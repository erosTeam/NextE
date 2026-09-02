import { ThemeConstants } from '../theme/ThemeConstants'

/** Standard inset divider between rows inside a grouped list section. */
@ComponentV2
export struct ListRowDivider {
  @Param insetStart: Length = ThemeConstants.SPACE_MD;

  build() {
    Divider()
      .strokeWidth(0.5)
      .color(ThemeConstants.DIVIDER)
      .margin({ left: this.insetStart })
  }
}
