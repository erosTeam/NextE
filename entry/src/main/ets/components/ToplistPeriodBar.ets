import { ThemeConstants, HomeSourceState, connectHomeSource, SELECTOR_BAR_HEIGHT } from 'shared'

/**
 * Toplist-tab period switcher, PINNED in the HDS title bar via a `bottomBuilder`. eros_fe's toplist
 * is its own page with a period selector (ToplistType all/year/month/yesterday = tl 11/12/13/15,
 * toplist_controller.dart:8-20) presented as a nav-bar action; NextE pins it as a substantial
 * single-row segmented control. Reads/writes the shared HomeSourceState.toplistTl that ToplistPage's
 * ViewModel reacts to.
 */
@ComponentV2
export struct ToplistPeriodBar {
  @Local home: HomeSourceState = connectHomeSource();

  build() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      this.Tab(11, $r('app.string.toplist_all'))
      this.Tab(12, $r('app.string.toplist_year'))
      this.Tab(13, $r('app.string.toplist_month'))
      this.Tab(15, $r('app.string.toplist_yesterday'))
    }
    .width('100%')
    .height(SELECTOR_BAR_HEIGHT)
    .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
    .alignItems(VerticalAlign.Center)
  }

  // V2Next FeedPills text-tab + underline (mirrors HomeSourceBar). No capsule background.
  @Builder
  Tab(tl: number, label: ResourceStr) {
    Column({ space: 1 }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(
          this.home.toplistTl === tl
            ? ThemeConstants.BRAND_PRIMARY
            : $r('sys.color.font_secondary'),
        )
        .fontWeight(this.home.toplistTl === tl ? FontWeight.Medium : FontWeight.Regular)
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          top: ThemeConstants.SPACE_XS,
        })
        .maxLines(1)
      Row()
        .height(3)
        .width(18)
        .borderRadius(1.5)
        .backgroundColor(
          this.home.toplistTl === tl ? ThemeConstants.BRAND_PRIMARY : Color.Transparent,
        )
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.home.toplistTl = tl
    })
  }
}
@Builder
export function ToplistPeriodBarCCBuilder(_arg: Object) {
  ToplistPeriodBar()
}
