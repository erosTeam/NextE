import { ThemeConstants } from '../theme/ThemeConstants'

/** Shared trailing action for swipe-to-delete rows. */
@ComponentV2
export struct SwipeDeleteAction {
  @Param label: Resource = $r('app.string.common_delete');
  @Event action?: () => void;

  build() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.White])
      }
      .width(48)
      .height(40)
      .backgroundColor(Color.Red)
      .accessibilityText(this.label)
      .onClick(() => {
        if (this.action) {
          this.action()
        }
      })
    }
    .height('100%')
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    .justifyContent(FlexAlign.Center)
  }
}
