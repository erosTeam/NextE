import { deviceInfo } from '@kit.BasicServicesKit'
import { uiMaterial } from '@kit.ArkUI'
import { ThemeConstants } from '../theme/ThemeConstants'
import { SELECTOR_BAR_HEIGHT } from '../state/HomeSourceState'
import { TabItem } from '../model/TabItem'
import {
  connectThemeDisplay,
  ThemeDisplayState,
  connectLanguageState,
  LanguageState,
} from '../state/AppearanceState'

const TAB_GAP: number = ThemeConstants.SPACE_SM
// Breathing room between the bar's edges and the first/last capsule. SPACE_MD is what the project already
// uses for its sibling chip surfaces (DownloadTypeBar's HDS selector bar and its segmented button,
// CategorySelector), so the capsules line up with them instead of running flush to the screen edge.
const BAR_INSET: number = ThemeConstants.SPACE_MD
// Capsule height inside the fixed SELECTOR_BAR_HEIGHT bar: 30 leaves room above and below, so each pill reads
// as a separate floating button rather than a full-height block.
const PILL_HEIGHT: number = 30

/**
 * Shared selector sub-tab bar — one capsule per sub-tab, in the shape the design guide's 子页签 / 胶囊样式
 * (single-select) prescribes. This replaces the previous V2Next FeedPills look (a flat bar with a single
 * sliding underline): with a filled pill as the selection target, a sliding underline reads as stray
 * decoration, so the capsule itself carries the state instead.
 *
 * The guide's rule for this control is explicit — 「建议使用品牌色对激活的子页签进行色彩填充」 — so the ACTIVE
 * capsule is a solid accent fill with text that contrasts against it, exactly like CategorySelector, the
 * project's other chip group. The INACTIVE capsules are the frosted (沉浸光感) surface instead — see
 * inactiveMaterial(); on API < 26 they fall back to the platform's neutral chip fill, so the capsules still
 * read as capsules instead of bare text.
 *
 * Every surface uses the same native horizontal List. When its content fits it remains visually static; when
 * it overflows the List scrolls naturally and recentres the selected tab. Reused by HomeSourceBar /
 * ToplistPeriodBar / FavcatBar, so all three sub-tab surfaces change together; 下载 uses TabSegmentButtonV2
 * and is unaffected.
 *
 * Non-negotiable SDK contract: systemMaterial() owns backgroundColor / borderColor / borderWidth / shadow on
 * the node it decorates. That is why the two states never mix — the active capsule sets a real backgroundColor
 * and NO material, the inactive one sets the material and an explicit transparent backgroundColor.
 */
@ComponentV2
export struct SubTabBar {
  @Require @Param tabs: TabItem[];
  // Interpolated active index (float) from the Swiper — drives the discrete capsule highlight while swiping.
  @Param visualIndex: number = 0;
  // Discrete selected index from the selection bus. Scrolling listens to this, not visualIndex.
  @Param selectedIndex: number = -1;
  @Event onSelect: (index: number) => void = (_i: number) => {};
  // Reading this signal in the color helper makes this bar (hosted in a CACHED ComponentContent) repaint on
  // a system dark/light flip — without it the unselected $r('sys.color.*') tokens stay stale.
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  // Same idea for language: reading effectiveLocale in visualSelectedIndex() (called for every capsule) +
  // folding it into the ForEach key makes a language switch rebuild + re-key the cached bar, so even the
  // SELECTED capsule's $r label re-resolves (otherwise only the unselected pills, which read a signal, refresh).
  @Local language: LanguageState = connectLanguageState();
  private scroller: Scroller = new Scroller();
  private containerReady: boolean = false;
  private pendingCenterIndex: number = -1;
  private pendingCenterSmooth: boolean = false;
  private centeredTarget: number = -1;

  aboutToAppear(): void {
    this.centerSelectedTab(false, true)
  }

  // Returns `color` unchanged; the point is the effectiveDark read, which registers a rebuild dependency so
  // this cached pill subtree recolors the instant the system (or manual) theme flips.
  private themeTracked(color: ResourceColor): ResourceColor {
    return this.themeDisplay.effectiveDark ? color : color
  }

  /**
   * An INACTIVE capsule's 沉浸光感 system material, or undefined on API < 26 (and where the component-level
   * system material is unavailable) — there inactive capsules take the platform's neutral chip fill instead,
   * so the geometry never regresses to invisible bare text.
   *
   * The grade is FIXED at the thinnest one rather than taken from 「沉浸光感材质」 on purpose: that setting
   * maps its top grade to REGULAR/THICK, and a 30vp capsule at THICK turns into an opaque grey blob. The bar
   * also sits ON the title-bar surface that the setting grades, so the user's choice still reaches these
   * capsules through the surface behind them. applyShadow is off: up to 12 frosted capsules scrolling
   * horizontally would otherwise pay the material's shadow draw cost for a cue nobody reads.
   */
  private inactiveMaterial(): uiMaterial.Material | undefined {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return undefined
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      // Complementary text adaptation, same as the title bar's material.
      colorInvert: true,
      applyShadow: false,
      // No press deformation — a tap switches the whole page underneath.
      interactive: false,
    })
  }

  // The ACTIVE capsule's grid fill (the guide's 「品牌色填充」 rule). Per-tab accents are honoured — the
  // favourites slots carry their own colours and the shared brand colour is the default for every other bar.
  private activeFill(i: number): ResourceColor {
    return this.tabAccentColor(i)
  }

  // Text/icon colour ON that fill. The accent is not always saturated — the synthetic favcat capsules are
  // pastel (#B5A4A4 all / #A99E68 local) where white washes out — so pick white or near-black from the
  // accent's relative luminance rather than assuming white like a fixed brand fill would.
  private onFillTextColor(i: number): ResourceColor {
    const hex: string = this.accentHex(i)
    if (hex.length === 0) {
      return ThemeConstants.TEXT_ON_BRAND
    }
    const r: number = Number.parseInt(hex.substring(1, 3), 16)
    const g: number = Number.parseInt(hex.substring(3, 5), 16)
    const b: number = Number.parseInt(hex.substring(5, 7), 16)
    const luminance: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return luminance > 0.6 ? ThemeConstants.TEXT_ON_LIGHT_ACCENT : ThemeConstants.TEXT_ON_BRAND
  }

  // The INACTIVE capsule's fill. With the system material available the material owns the paint, and the SDK
  // says not to combine it with a real backgroundColor — so the only value that belongs there is transparent.
  private inactiveFill(): ResourceColor {
    return deviceInfo.apiAvailable('26.0.0')
      ? Color.Transparent
      : $r('sys.color.ohos_id_color_button_normal')
  }

  // The tab's accent as #RRGGBB, or '' when it is not a literal hex (then the capsule keeps the untinted
  // grade). tabAccentColor() already resolves the shared brand colour to a hex string for every surface.
  private accentHex(i: number): string {
    const color: ResourceColor = this.tabAccentColor(i)
    return typeof color === 'string' ? this.normalizedHex(color) : ''
  }

  private visualSelectedIndex(): number {
    // Touch the locale signal so the whole bar depends on it (length is never < 0; this only registers the
    // @Trace read). selectedIndex() runs in every capsule's fontColor/fontWeight, so the bar rebuilds on switch.
    if (this.language.effectiveLocale.length < 0) {
      return 0
    }
    const n: number = this.tabs.length
    if (n <= 0) {
      return 0
    }
    return Math.max(0, Math.min(n - 1, Math.round(this.visualIndex)))
  }

  private safeKeyPart(value: string): string {
    const out: string = value.replace(/[^A-Za-z0-9_]/g, '_')
    return out.length > 0 ? out : '_'
  }

  private tabRenderKey(tab: TabItem, index: number): string {
    const label: string = typeof tab.label === 'string' ? tab.label : this.language.effectiveLocale
    return `tab_${index}_${this.safeKeyPart(tab.key)}_${this.safeKeyPart(label)}_${this.safeKeyPart(`${tab.count}`)}_${this.safeKeyPart(tab.selectedColor)}`
  }

  private tabAccentColor(i: number): ResourceColor {
    if (i >= 0 && i < this.tabs.length && this.tabs[i].selectedColor.length > 0) {
      return this.tabs[i].selectedColor
    }
    return ThemeConstants.BRAND_PRIMARY
  }

  private normalizedHex(color: string): string {
    let c: string = color.trim()
    if (c.length === 0) {
      return ''
    }
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (/^[0-9a-fA-F]{3}$/.test(c)) {
      c = `${c[0]}${c[0]}${c[1]}${c[1]}${c[2]}${c[2]}`
    }
    return /^[0-9a-fA-F]{6}$/.test(c) ? `#${c.toUpperCase()}` : ''
  }

  // Keep the active tab visible whenever natural content overflow makes that necessary. This follows the
  // discrete selection bus, matching V2Next FeedPills; visualIndex is high-frequency highlight state only.
  @Monitor('selectedIndex')
  onSelectedIndexChange(): void {
    this.centerSelectedTab(true, false)
  }

  private centerSelectedTab(smooth: boolean, force: boolean): void {
    const i: number = this.centerIndex()
    if (!force && i === this.centeredTarget && this.pendingCenterIndex !== i) {
      return
    }
    this.centeredTarget = i
    this.centerTab(i, smooth)
  }

  private centerTab(i: number, smooth: boolean): void {
    if (i < 0 || i >= this.tabs.length) {
      return
    }
    if (!this.containerReady) {
      this.pendingCenterIndex = i
      this.pendingCenterSmooth = smooth
      return
    }
    this.pendingCenterIndex = -1
    this.scroller.scrollToIndex(i, smooth, ScrollAlign.CENTER)
  }

  private centerIndex(): number {
    const n: number = this.tabs.length
    if (n <= 0) {
      return 0
    }
    const raw: number = this.selectedIndex >= 0 ? this.selectedIndex : this.visualSelectedIndex()
    return Math.max(0, Math.min(n - 1, raw))
  }

  // A capsule can only be scrolled to once it has been laid out, so the first centring pass is deferred to the
  // target item's onAreaChange (the bar itself measures before any item does).
  private updateTabLayout(i: number, area: Area): void {
    if ((area.width as number) <= 0) {
      return
    }
    if (this.pendingCenterIndex === i) {
      this.centerTab(i, this.pendingCenterSmooth)
    }
  }

  build() {
    List({ space: TAB_GAP, scroller: this.scroller }) {
      ForEach(
        this.tabs,
        (tab: TabItem, index: number) => {
          ListItem() {
            Row({ space: 3 }) {
              Text(tab.label)
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontColor(
                  this.visualSelectedIndex() === index
                    ? this.onFillTextColor(index)
                    : this.themeTracked($r('sys.color.font_secondary')),
                )
                .fontWeight(this.visualSelectedIndex() === index ? FontWeight.Bold : FontWeight.Regular)
                .maxLines(1)
              if (tab.count >= 0) {
                Text(`${tab.count}`)
                  .fontSize(ThemeConstants.FONT_SIZE_TINY)
                  .fontColor(
                    this.visualSelectedIndex() === index
                      ? this.onFillTextColor(index)
                      : this.themeTracked($r('sys.color.font_tertiary')),
                  )
              }
            }
            .height(PILL_HEIGHT)
            .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
            .borderRadius(ThemeConstants.RADIUS_ROUND)
            .clip(true)
            // The two states never share an attribute: the filled capsule has no material (the fill is its
            // paint), the frosted one has no real background (see the struct doc).
            .systemMaterial(this.visualSelectedIndex() === index ? undefined : this.inactiveMaterial())
            .backgroundColor(
              this.visualSelectedIndex() === index ? this.activeFill(index) : this.inactiveFill(),
            )
            .onClick(() => {
              this.onSelect(index)
            })
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              this.updateTabLayout(index, newValue)
            })
          }
        },
        (tab: TabItem, index: number) => this.tabRenderKey(tab, index),
      )
    }
    .listDirection(Axis.Horizontal)
    // Capsules are shorter than the bar, so the cross axis must centre them explicitly (the default Start
    // alignment would sink the row to the top and leave a gap under it).
    .alignListItem(ListItemAlign.Center)
    .scrollBar(BarState.Off)
    // Applied as CONTENT offsets, not padding. List padding is a CLIP boundary: the capsules would vanish
    // BAR_INSET short of the edge while scrolling, as if an invisible wall sat at each end. These only
    // displace the resting position — the row still scrolls flush to the screen edge, which is what makes it
    // read as content sliding under a floating bar. (The platform resets both to 0 if their sum exceeds the
    // content length; 24vp never comes close on a sub-tab row.)
    .contentStartOffset(BAR_INSET)
    .contentEndOffset(BAR_INSET)
    .width('100%')
    .height(SELECTOR_BAR_HEIGHT)
    .onAreaChange((_oldValue: Area, _newValue: Area) => {
      this.containerReady = true
      if (this.pendingCenterIndex >= 0) {
        this.centerTab(this.pendingCenterIndex, this.pendingCenterSmooth)
      } else {
        this.centerSelectedTab(false, true)
      }
    })
  }
}
