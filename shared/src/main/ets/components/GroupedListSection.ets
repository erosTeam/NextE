import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * A rounded, inset card that groups a run of ConciseListRow children (ported from V2Next).
 * Settings groups, detail-page cards, etc. wrap their rows in one of these so the chrome
 * (radius + card background + inset) lives in one shared place instead of every page.
 */
@ComponentV2
export struct GroupedListSection {
  @BuilderParam content: () => void
  @Param inset: number = ThemeConstants.LIST_SECTION_INSET
  @Param radius: number = ThemeConstants.RADIUS_CARD

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(this.radius)
    .clip(true)
    .padding(this.inset)
    .backgroundColor($r('app.color.card_background'))
  }
}
