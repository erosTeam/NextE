import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * Shared RETAINED-SUBTAB HOST (retained-subtab-framework-contract.md). The one place the retained-subtab
 * mechanics live, so Home source / Toplist period / Favorites favcat / future custom subtabs all share it
 * instead of re-implementing a Swiper per surface. It owns:
 *   - the SwiperController + the per-key Scroller map (stable identity → retained scroll per key),
 *   - cachedCount = key count (retain ALL keys → switching away/back keeps each key's list + scroll),
 *   - the visual-index publishing from onGestureSwipe / onAnimationStart / onAnimationEnd (the bar's
 *     sliding indicator tracks the finger/page),
 *   - onChange selected-key publication back to the surface bus,
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
  // Renders the retained page for one key. GLOBAL @Builder (params only, no `this`).
  @BuilderParam pageBuilder: (key: string, isActive: boolean, scroller: Scroller) => void;
  // Publish the new selected key back to the surface bus (onChange / settle).
  @Event onSelectKey: (key: string) => void = (_k: string) => {};
  // Publish the per-frame interpolated visual index to the surface's visual-index bus (bar indicator).
  @Event onVisualIndex: (value: number) => void = (_v: number) => {};
  // Hand the active key's Scroller up so the HDS title auto-hide binds the right list.
  @Event onScrollerReady?: (scroller: Scroller) => void;
  private swiperController: SwiperController = new SwiperController();
  private scrollers: Map<string, Scroller> = new Map<string, Scroller>();
  private swiperWidth: number = 0;

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

  aboutToAppear(): void {
    this.onVisualIndex(this.activeIndex())
    this.notifyActiveScroller()
  }

  // Selection bus changed (a bar tap, a login-gated key removal, etc.) → swipe to that retained page.
  @Monitor('selectedKey')
  onSelectedKeyChange(): void {
    this.swiperController.changeIndex(this.activeIndex(), true)
    this.notifyActiveScroller()
  }

  build() {
    Swiper(this.swiperController) {
      ForEach(
        this.keys,
        (key: string) => {
          this.pageBuilder(key, key === this.selectedKey, this.scrollerForKey(key))
        },
        (key: string) => key,
      )
    }
    .index(this.activeIndex())
    // Retain ALL keys (bounded per surface) so any away/back switch keeps that key's list + scroll.
    .cachedCount(this.keys.length)
    .nestedScroll(SwiperNestedScrollMode.SELF_ONLY)
    .indicator(false)
    .loop(false)
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
      this.onVisualIndex(index)
    })
    .onChange((i: number) => {
      if (i < 0 || i >= this.keys.length) {
        return
      }
      this.onVisualIndex(i)
      const key: string = this.keys[i]
      if (key !== this.selectedKey) {
        this.onSelectKey(key)
      }
      this.notifyActiveScroller()
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.swiperWidth = newValue.width as number
    })
    .width('100%')
    .height('100%')
  }
}
