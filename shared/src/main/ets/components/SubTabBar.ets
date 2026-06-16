import { ThemeConstants } from '../theme/ThemeConstants'
import { SELECTOR_BAR_HEIGHT } from '../state/HomeSourceState'

/** One sub-tab: a stable key (must match the retained Swiper's page key) + its label. */
export class SubTabItem {
  key: string = ''
  label: ResourceStr = ''

  constructor(key: string, label: ResourceStr) {
    this.key = key
    this.label = label
  }
}

const INDICATOR_W: number = 18
const TAB_GAP: number = ThemeConstants.SPACE_XS
const BAR_PAD: number = ThemeConstants.SPACE_SM
// Underline baseline: a 3px indicator sitting just under the vertically-centred label in the bar row.
const INDICATOR_Y: number = SELECTOR_BAR_HEIGHT - 10

/**
 * Shared selector sub-tab bar with a V2Next-style SLIDING indicator (FeedPills / IndexTitleBarComponents
 * pattern). The retained Swiper publishes an interpolated `visualIndex` (a float) as the user swipes;
 * this bar positions a single underline by interpolating between the measured tab CENTERS, so the bar
 * animation tracks the finger/page transition instead of jumping after the page settles. The discrete
 * highlight (brand colour + Medium weight) follows round(visualIndex). Reused by HomeSourceBar /
 * ToplistPeriodBar / FavcatBar so the indicator math is not hand-rolled per bar.
 */
@ComponentV2
export struct SubTabBar {
  @Require @Param tabs: SubTabItem[];
  // Interpolated active index (float) from the Swiper — the source of the indicator position + highlight.
  @Param visualIndex: number = 0;
  @Event onSelect: (index: number) => void = (_i: number) => {};
  // Per-tab measured widths (onAreaChange) so the indicator tracks real tab centres, not a uniform guess.
  @Local tabWidths: number[] = [];

  private selectedIndex(): number {
    const n: number = this.tabs.length
    if (n <= 0) {
      return 0
    }
    return Math.max(0, Math.min(n - 1, Math.round(this.visualIndex)))
  }

  // Center x of tab i: bar padding + cumulative prior tab widths + inter-tab gaps + half this tab.
  private tabCenter(i: number): number {
    let left: number = BAR_PAD
    for (let k = 0; k < i; k++) {
      const w: number = k < this.tabWidths.length ? this.tabWidths[k] : 0
      left += w + TAB_GAP
    }
    const wi: number = i < this.tabWidths.length ? this.tabWidths[i] : 0
    return left + wi / 2
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: TAB_GAP }) {
        ForEach(
          this.tabs,
          (tab: SubTabItem, index: number) => {
            Text(tab.label)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor(
                this.selectedIndex() === index
                  ? ThemeConstants.BRAND_PRIMARY
                  : $r('sys.color.font_secondary'),
              )
              .fontWeight(this.selectedIndex() === index ? FontWeight.Medium : FontWeight.Regular)
              .padding({
                left: ThemeConstants.SPACE_MD,
                right: ThemeConstants.SPACE_MD,
                top: ThemeConstants.SPACE_XS,
              })
              .maxLines(1)
              .onClick(() => {
                this.onSelect(index)
              })
              .onAreaChange((_oldValue: Area, newValue: Area) => {
                this.setTabWidth(index, newValue.width as number)
              })
          },
          (tab: SubTabItem) => tab.key,
        )
      }
      .padding({ left: BAR_PAD, right: BAR_PAD })
      .alignItems(VerticalAlign.Center)

      // The single sliding indicator (interpolated), drawn over the tabs.
      Row()
        .width(INDICATOR_W)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
        .position({ x: this.indicatorLeft(), y: INDICATOR_Y })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(SELECTOR_BAR_HEIGHT)
  }
}
