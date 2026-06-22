import { ThemeConstants } from '../theme/ThemeConstants'
import { SELECTOR_BAR_HEIGHT } from '../state/HomeSourceState'
import { TabItem } from '../model/TabItem'
import {
  connectThemeDisplay,
  ThemeDisplayState,
  connectLanguageState,
  LanguageState,
} from '../state/AppearanceState'

const INDICATOR_W: number = 18
const TAB_GAP: number = ThemeConstants.SPACE_XS
const BAR_PAD: number = ThemeConstants.SPACE_SM
// Underline baseline (V2Next FeedPills: indicator at TAB_BAR_HEIGHT - 14): the tab labels are TOP-aligned
// with a small top padding, and the 3px indicator sits just under them — so the bar fills its height
// tightly instead of floating a centred label with empty space above/below (which read as a tall bar).
const INDICATOR_Y: number = SELECTOR_BAR_HEIGHT - 14

/**
 * Shared selector sub-tab bar with a V2Next-style SLIDING indicator (FeedPills / IndexTitleBarComponents
 * pattern). The retained Swiper publishes an interpolated `visualIndex` (a float) as the user swipes;
 * this bar positions a single underline by interpolating between the measured tab CENTERS, so the bar
 * animation tracks the finger/page transition instead of jumping after the page settles. The discrete
 * highlight (brand colour + Medium weight) follows round(visualIndex). Reused by HomeSourceBar /
 * ToplistPeriodBar / FavcatBar so the indicator math is not hand-rolled per bar.
 *
 * `scrollable` (favcat case): many tabs overflow the bar, so the tab strip + its indicator live inside a
 * horizontal Scroll (the indicator is a child of the scrolled content, so it scrolls WITH the tabs), and
 * the active tab is auto-centred when the selection settles.
 */
@ComponentV2
export struct SubTabBar {
  @Require @Param tabs: TabItem[];
  // Interpolated active index (float) from the Swiper — the source of the indicator position + highlight.
  @Param visualIndex: number = 0;
  // When true the tab strip scrolls horizontally (favcat overflow) and the active tab auto-centres.
  @Param scrollable: boolean = false;
  @Event onSelect: (index: number) => void = (_i: number) => {};
  // Per-tab measured widths (onAreaChange) so the indicator tracks real tab centres, not a uniform guess.
  @Local tabWidths: number[] = [];
  // Reading this signal in the color helper makes this bar (hosted in a CACHED ComponentContent) repaint on
  // a system dark/light flip — without it the unselected $r('sys.color.*') tokens stay stale.
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  // Same idea for language: reading effectiveLocale in selectedIndex() (called for every tab) + folding it
  // into the ForEach key makes a language switch rebuild + re-key the cached bar, so even the SELECTED tab's
  // $r label re-resolves (otherwise only the unselected pills, which read a signal, refresh).
  @Local language: LanguageState = connectLanguageState();
  private scroller: Scroller = new Scroller();
  private viewportWidth: number = 0;
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

  private selectedIndex(): number {
    // Touch the locale signal so the whole bar depends on it (length is never < 0; this only registers the
    // @Trace read). selectedIndex() runs in every tab's fontColor/fontWeight, so the bar rebuilds on switch.
    if (this.language.effectiveLocale.length < 0) {
      return 0
    }
    const n: number = this.tabs.length
    if (n <= 0) {
      return 0
    }
    return Math.max(0, Math.min(n - 1, Math.round(this.visualIndex)))
  }

  // Left edge of tab i: bar padding + cumulative prior tab widths + inter-tab gaps.
  private tabLeft(i: number): number {
    let left: number = BAR_PAD
    for (let k = 0; k < i; k++) {
      const w: number = k < this.tabWidths.length ? this.tabWidths[k] : 0
      left += w + TAB_GAP
    }
    return left
  }

  private tabCenter(i: number): number {
    const wi: number = i < this.tabWidths.length ? this.tabWidths[i] : 0
    return this.tabLeft(i) + wi / 2
  }

  // Interpolated indicator left edge: lerp between the from/to tab centres by the fractional visual index.
  private indicatorLeft(): number {
    const n: number = this.tabs.length
    if (n <= 0) {
      return 0
    }
    const vi: number = Math.max(0, Math.min(n - 1, this.visualIndex))
    const from: number = Math.floor(vi)
    const to: number = Math.min(from + 1, n - 1)
    const frac: number = vi - from
    const center: number = this.tabCenter(from) + (this.tabCenter(to) - this.tabCenter(from)) * frac
    return center - INDICATOR_W / 2
  }

  private setTabWidth(i: number, w: number): void {
    const next: number[] = this.tabWidths.slice()
    while (next.length <= i) {
      next.push(0)
    }
    next[i] = w
    this.tabWidths = next
  }

  private tabAccentColor(i: number): ResourceColor {
    if (i >= 0 && i < this.tabs.length && this.tabs[i].selectedColor.length > 0) {
      return this.tabs[i].selectedColor
    }
    return ThemeConstants.BRAND_PRIMARY
  }

  private indicatorColor(): ResourceColor {
    const n: number = this.tabs.length
    if (n <= 0) {
      return ThemeConstants.BRAND_PRIMARY
    }
    const vi: number = Math.max(0, Math.min(n - 1, this.visualIndex))
    const from: number = Math.floor(vi)
    const to: number = Math.min(from + 1, n - 1)
    const frac: number = vi - from
    const fromColor: string = this.normalizedHex(this.tabs[from].selectedColor)
    const toColor: string = this.normalizedHex(this.tabs[to].selectedColor)
    if (fromColor.length > 0 && toColor.length > 0) {
      return this.lerpHexColor(fromColor, toColor, frac)
    }
    if (fromColor.length > 0) {
      return fromColor
    }
    if (toColor.length > 0) {
      return toColor
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

  private lerpHexColor(fromColor: string, toColor: string, frac: number): string {
    const a: number = Number.parseInt(fromColor.substring(1), 16)
    const b: number = Number.parseInt(toColor.substring(1), 16)
    const r: number = Math.round(((a >> 16) & 255) + (((b >> 16) & 255) - ((a >> 16) & 255)) * frac)
    const g: number = Math.round(((a >> 8) & 255) + (((b >> 8) & 255) - ((a >> 8) & 255)) * frac)
    const bl: number = Math.round((a & 255) + ((b & 255) - (a & 255)) * frac)
    return `#${this.hex2(r)}${this.hex2(g)}${this.hex2(bl)}`
  }

  private hex2(value: number): string {
    const s: string = Math.max(0, Math.min(255, value)).toString(16).toUpperCase()
    return s.length === 1 ? `0${s}` : s
  }

  // Keep the active tab visible (favcat strip can overflow). Centres on the discrete selected tab.
  @Monitor('visualIndex')
  onVisualIndexChange(): void {
    this.centerSelectedTab(true, false)
  }

  private centerSelectedTab(smooth: boolean, force: boolean): void {
    if (!this.scrollable) {
      return
    }
    const i: number = this.selectedIndex()
    if (!force && i === this.centeredTarget && this.pendingCenterIndex !== i) {
      return
    }
    this.centeredTarget = i
    this.centerTab(i, smooth)
  }

  private centerTab(i: number, smooth: boolean): void {
    if (!this.scrollable || i < 0 || i >= this.tabs.length) {
      return
    }
    const wi: number = i < this.tabWidths.length ? this.tabWidths[i] : 0
    if (this.viewportWidth <= 0 || wi <= 0) {
      this.pendingCenterIndex = i
      this.pendingCenterSmooth = smooth
      return
    }
    this.pendingCenterIndex = -1
    const target: number = this.tabLeft(i) - this.viewportWidth / 2 + wi / 2
    this.scroller.scrollTo({ xOffset: Math.max(0, target), yOffset: 0, animation: smooth })
  }

  @Builder
  tabRow() {
    Row({ space: TAB_GAP }) {
      ForEach(
        this.tabs,
        (tab: TabItem, index: number) => {
          Row({ space: 3 }) {
            Text(tab.label)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor(
                this.selectedIndex() === index
                  ? this.tabAccentColor(index)
                  : this.themeTracked($r('sys.color.font_secondary')),
              )
              .fontWeight(this.selectedIndex() === index ? FontWeight.Medium : FontWeight.Regular)
              .maxLines(1)
            if (tab.count >= 0) {
              Text(`${tab.count}`)
                .fontSize(ThemeConstants.FONT_SIZE_TINY)
                .fontColor(
                  this.selectedIndex() === index
                    ? this.tabAccentColor(index)
                    : this.themeTracked($r('sys.color.font_tertiary')),
                )
            }
          }
          .padding({
            left: ThemeConstants.SPACE_MD,
            right: ThemeConstants.SPACE_MD,
            top: ThemeConstants.SPACE_XS,
          })
          .onClick(() => {
            this.onSelect(index)
          })
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.setTabWidth(index, newValue.width as number)
            if (this.pendingCenterIndex === index) {
              this.centerTab(index, this.pendingCenterSmooth)
            }
          })
        },
        // Key MUST include the label + count, not just the stable key: dynamic tabs (favcat) reuse a key
        // (favId 0-9) across a seed→real update, so keying on the key alone makes ForEach reuse the frozen
        // seed chips (label/count are @Builder params, captured at create) — the bar stays "Favorites N / 0"
        // after the parse lands. A string label (favcat name) joins the key so a name/count change rebuilds
        // the chip; Resource labels (Home/Toplist) fold in effectiveLocale so a language switch re-keys them
        // and the $r re-resolves (a stable '' left the SELECTED tab's label frozen after a switch).
        (tab: TabItem) =>
          `${tab.key}:${typeof tab.label === 'string' ? tab.label : this.language.effectiveLocale}:${tab.count}:${tab.selectedColor}`,
      )
    }
    .padding({ left: BAR_PAD, right: BAR_PAD })
    // Top-align (V2Next FeedPills) so the label sits near the bar top with the indicator just under it,
    // filling the bar height tightly rather than centring the label with empty space above and below.
    .alignItems(VerticalAlign.Top)
  }

  // The single sliding indicator (interpolated), a child of the tab strip so it scrolls with the tabs.
  @Builder
  indicatorBar() {
    Row()
      .width(INDICATOR_W)
      .height(3)
      .borderRadius(1.5)
      .backgroundColor(this.indicatorColor())
      .position({ x: this.indicatorLeft(), y: INDICATOR_Y })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    if (this.scrollable) {
      Scroll(this.scroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.tabRow()
          this.indicatorBar()
        }.height(SELECTOR_BAR_HEIGHT)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .height(SELECTOR_BAR_HEIGHT)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.viewportWidth = newValue.width as number
        if (this.pendingCenterIndex >= 0) {
          this.centerTab(this.pendingCenterIndex, this.pendingCenterSmooth)
        } else {
          this.centerSelectedTab(false, true)
        }
      })
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.tabRow()
        this.indicatorBar()
      }
      .width('100%')
      .height(SELECTOR_BAR_HEIGHT)
    }
  }
}
