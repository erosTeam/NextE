import { ThemeConstants } from '../theme/ThemeConstants'
import { SELECTOR_BAR_HEIGHT } from '../state/HomeSourceState'
import { TabItem } from '../model/TabItem'

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
  private scroller: Scroller = new Scroller();
  private viewportWidth: number = 0;
  private lastCentered: number = -1;

  private selectedIndex(): number {
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

  // Keep the active tab visible (favcat strip can overflow). Centres on the discrete selected tab.
  @Monitor('visualIndex')
  onVisualIndexChange(): void {
    if (!this.scrollable) {
      return
    }
    const i: number = this.selectedIndex()
    if (i === this.lastCentered) {
      return
    }
    this.lastCentered = i
    const wi: number = i < this.tabWidths.length ? this.tabWidths[i] : 0
    const target: number = this.tabLeft(i) - this.viewportWidth / 2 + wi / 2
    this.scroller.scrollTo({ xOffset: Math.max(0, target), yOffset: 0, animation: true })
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
                  ? ThemeConstants.BRAND_PRIMARY
                  : $r('sys.color.font_secondary'),
              )
              .fontWeight(this.selectedIndex() === index ? FontWeight.Medium : FontWeight.Regular)
              .maxLines(1)
            if (tab.count >= 0) {
              Text(`${tab.count}`)
                .fontSize(ThemeConstants.FONT_SIZE_TINY)
                .fontColor(
                  this.selectedIndex() === index
                    ? ThemeConstants.BRAND_PRIMARY
                    : $r('sys.color.font_tertiary'),
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
          })
        },
        // Key MUST include the label + count, not just the stable key: dynamic tabs (favcat) reuse a key
        // (favId 0-9) across a seed→real update, so keying on the key alone makes ForEach reuse the frozen
        // seed chips (label/count are @Builder params, captured at create) — the bar stays "Favorites N / 0"
        // after the parse lands. A string label (favcat name) joins the key so a name/count change rebuilds
        // the chip; Resource labels (Home/Toplist, static) contribute '' and stay stable.
        (tab: TabItem) => `${tab.key}:${typeof tab.label === 'string' ? tab.label : ''}:${tab.count}`,
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
      .backgroundColor(ThemeConstants.BRAND_PRIMARY)
      .position({ x: this.indicatorLeft(), y: INDICATOR_Y })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    if (this.scrollable) {
      Scroll(this.scroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.tabRow()
          this.indicatorBar()
        }
        .height(SELECTOR_BAR_HEIGHT)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .height(SELECTOR_BAR_HEIGHT)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.viewportWidth = newValue.width as number
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
