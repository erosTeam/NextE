import { ThemeConstants } from '../theme/ThemeConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * The active-key signal the host shares with EVERY retained page. Passed by reference (once) to each
 * page's @Param, so its @Trace propagates to ALL pages — including cached/off-screen ones — when the host
 * updates it. This is why first activation is reliable: a per-render `isActive` @Param does NOT update on
 * cached pages (ForEach with stable keys + Swiper cachedCount does not re-run the item builder for them),
 * so @Monitor('isActive') never fired and an unvisited subtab never auto-loaded. A page instead watches
 * `active.activeKey === itsKey` and loads exactly once on its first activation.
 */
@ObservedV2
export class ActiveKeyState {
  @Trace activeKey: string = ''
}

/**
 * Shared RETAINED-SUBTAB HOST (retained-subtab-framework-contract.md). The one place the retained-subtab
 * mechanics live, so Home source / Toplist period / Favorites favcat / future custom subtabs all share it
 * instead of re-implementing a Swiper per surface. It owns:
 *   - the SwiperController + the per-key Scroller map (stable identity → retained scroll per key),
 *   - cachedCount = key count (retain ALL keys → switching away/back keeps each key's list + scroll),
 *   - the visual-index publishing from onGestureSwipe / onAnimationStart / onAnimationEnd (the bar's
 *     sliding indicator tracks the finger/page),
 *   - settled selected-key publication back to the surface bus,
 *   - the active page's Scroller handoff up (for the HDS title auto-hide binding).
 *
 * The host owns NO content VM/datasource: each key's page (rendered by `pageBuilder`) owns its own VM +
 * datasource + first-load/cursor/scroll. `pageBuilder` is a GLOBAL @Builder (no `this`) so passing it to
 * this @BuilderParam under @ComponentV2 can't hit the instance-@Builder `this`-loss crash.
 */
@ComponentV2
export struct RetainedSubtabHost {
  // Stable ordered key list (the surface's TabItem keys). The Swiper renders one retained page per key.
  @Param keys: string[] = [];
  // Currently selected key (from the surface's selection bus). Drives the active page + the swipe target.
  @Param selectedKey: string = '';
  // Renders the retained page for one key. GLOBAL @Builder (params only, no `this`). It receives the
  // SHARED ActiveKeyState (not a per-render isActive) so every page — cached too — sees activation.
  @BuilderParam pageBuilder:
    (key: string, active: ActiveKeyState, scroller: Scroller, onDidScroll: (offset: number, state: ScrollState) => void) => void;
  // Publish the new selected key back to the surface bus after the Swiper settles.
  @Event onSelectKey: (key: string) => void = (_k: string) => {};
  // Publish the per-frame interpolated visual index to the surface's visual-index bus (bar indicator).
  @Event onVisualIndex: (value: number) => void = (_v: number) => {};
  // Hand the active key's Scroller up so the HDS title auto-hide binds the right list.
  @Event onScrollerReady?: (scroller: Scroller) => void;
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local swiperIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();
  private scrollers: Map<string, Scroller> = new Map<string, Scroller>();
  private swiperWidth: number = 0;
  private ignoreStartupSelectionChange: boolean = false;
  // Shared active-key signal handed to every page; updated whenever the active key changes (bar tap or
  // swipe settle). Its @Trace reaches cached pages, so each key's first activation triggers exactly one load.
  private active: ActiveKeyState = new ActiveKeyState();

  private scrollerForKey(key: string): Scroller {
    const existing: Scroller | undefined = this.scrollers.get(key)
    if (existing !== undefined) {
      return existing
    }
    const scroller: Scroller = new Scroller()
    this.scrollers.set(key, scroller)
    return scroller
  }

  private activeIndex(): number {
    const idx: number = this.keys.indexOf(this.selectedKey)
    return idx < 0 ? 0 : idx
  }

  private effectiveActiveKey(): string {
    if (this.keys.length <= 0) {
      return ''
    }
    return this.keys[this.activeIndex()]
  }

  // Interpolate the visual index from the mid-swipe offset so the bar indicator tracks the finger.
  private visualFromOffset(index: number, extraInfo: SwiperAnimationEvent): number {
    if (this.swiperWidth <= 0) {
      return index
    }
    return index + -extraInfo.currentOffset / this.swiperWidth
  }

  private notifyActiveScroller(): void {
    if (this.onScrollerReady) {
      this.onScrollerReady(this.scrollerForKey(this.selectedKey))
    }
  }

  private notifyDidScroll(offset: number, state: ScrollState): void {
    if (this.onDidScroll) {
      this.onDidScroll(offset, state)
    }
  }

  aboutToAppear(): void {
    // Seed the active-key signal BEFORE the pages build, so the initially-active page's aboutToAppear sees
    // active.activeKey === itsKey and loads.
    this.active.activeKey = this.selectedKey
    const restoredIndex: number = this.activeIndex()
    this.swiperIndex = restoredIndex
    this.ignoreStartupSelectionChange = true
    this.onVisualIndex(restoredIndex)
    this.notifyActiveScroller()
    DiagnosticLogger.info(
      'home-list-anchor',
      'host_appear',
      `selected=${this.selectedKey} keys=${this.keys.join(',')} index=${restoredIndex}`,
    )
  }

  // Selection bus changed (a bar tap, a login-gated key removal, etc.) → swipe to that retained page AND
  // publish the active key so that page (cached or not) loads on its first activation.
  @Monitor('selectedKey')
  onSelectedKeyChange(): void {
    DiagnosticLogger.info(
      'home-list-anchor',
      'host_selected_change',
      `selected=${this.selectedKey} keys=${this.keys.join(',')} swiperIndex=${this.swiperIndex}`,
    )
    this.syncSelectedIndex(true)
  }

  @Monitor('keys')
  onKeysChange(): void {
    DiagnosticLogger.info(
      'home-list-anchor',
      'host_keys_change',
      `selected=${this.selectedKey} keys=${this.keys.join(',')} swiperIndex=${this.swiperIndex}`,
    )
    this.syncSelectedIndex(false)
  }

  private syncSelectedIndex(animated: boolean): void {
    if (this.keys.length <= 0) {
      this.swiperIndex = 0
      this.active.activeKey = ''
      this.onVisualIndex(0)
      return
    }
    const from: number = Math.max(0, Math.min(this.keys.length - 1, this.swiperIndex))
    const target: number = this.activeIndex()
    const activeKey: string = this.effectiveActiveKey()
    if (from === target) {
      this.swiperIndex = target
      this.active.activeKey = activeKey
      this.onVisualIndex(target)
      this.notifyActiveScroller()
      return
    }
    this.swiperIndex = from
    this.active.activeKey = activeKey
    if (animated) {
      this.swiperController.changeIndex(target, true)
    } else {
      this.swiperIndex = target
      this.swiperController.changeIndex(target, false)
      this.onVisualIndex(target)
    }
    this.notifyActiveScroller()
  }

  build() {
    Swiper(this.swiperController) {
      ForEach(
        this.keys,
        (key: string) => {
          this.pageBuilder(key, this.active, this.scrollerForKey(key), (offset: number, state: ScrollState) => {
            if (key === this.selectedKey) {
              this.notifyDidScroll(offset, state)
            }
          })
        },
        (key: string) => key,
      )
    }
    .index(this.swiperIndex)
    // Retain ALL keys (bounded per surface) so any away/back switch keeps that key's list + scroll.
    .cachedCount(this.keys.length)
    .nestedScroll(SwiperNestedScrollMode.SELF_ONLY)
    .indicator(false)
    .loop(false)
    .duration(ThemeConstants.ANIM_DURATION)
    .curve(Curve.EaseOut)
    .onGestureSwipe((index: number, extraInfo: SwiperAnimationEvent) => {
      this.onVisualIndex(this.visualFromOffset(index, extraInfo))
    })
    .onAnimationStart((index: number, targetIndex: number, extraInfo: SwiperAnimationEvent) => {
      this.onVisualIndex(this.visualFromOffset(index, extraInfo))
      this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
        this.onVisualIndex(targetIndex)
      })
    })
    .onAnimationEnd((index: number, _extraInfo: SwiperAnimationEvent) => {
      this.swiperIndex = index
      this.onVisualIndex(index)
      const key: string = this.keys[index]
      this.active.activeKey = key
      DiagnosticLogger.info(
        'home-list-anchor',
        'host_animation_end',
        `index=${index} key=${key} selected=${this.selectedKey} keys=${this.keys.join(',')}`,
      )
      if (key !== this.selectedKey) {
        this.onSelectKey(key)
      }
      this.notifyActiveScroller()
    })
    .onChange((i: number) => {
      if (this.ignoreStartupSelectionChange) {
        this.ignoreStartupSelectionChange = false
        const expectedIndex: number = this.activeIndex()
        if (i !== expectedIndex) {
          this.onVisualIndex(expectedIndex)
          return
        }
      }
      if (i < 0 || i >= this.keys.length) {
        return
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.swiperWidth = newValue.width as number
    })
    .width('100%')
    .height('100%')
  }
}
