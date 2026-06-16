import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * Group header above a GroupedListSection (ported from V2Next). V2Next routed the title
 * through a LanguageState read to re-render on in-app locale override; NextE has no such
 * override yet, so the title renders directly ($r resources already track the system locale).
 */
@ComponentV2
export struct SectionHeader {
  @Param title: ResourceStr = ''

  build() {
    Text(this.title)
      .fontSize(ThemeConstants.FONT_SIZE_LIST_ITEM)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
        top: ThemeConstants.SPACE_XS,
        bottom: ThemeConstants.SPACE_XS,
      })
      .width('100%')
  }
}
