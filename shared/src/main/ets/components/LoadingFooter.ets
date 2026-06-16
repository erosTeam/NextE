import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * List footer for infinite scroll (V2Next LoadingFooter): spinner while loading, a
 * tap-to-retry on error, or a "no more" terminus. Sits as the last ListItem.
 */
@ComponentV2
export struct LoadingFooter {
  @Param isLoading: boolean = false
  @Param hasMore: boolean = true
  @Param isError: boolean = false
  @Param errorMessage: ResourceStr = $r('app.string.common_load_failed_tap_retry')
  @Event onRetry?: () => void

  build() {
    Row() {
      if (this.isLoading) {
        LoadingProgress()
          .width(ThemeConstants.LOADING_SIZE_SMALL)
          .height(ThemeConstants.LOADING_SIZE_SMALL)
          .color($r('sys.color.font_secondary'))
        Text($r('app.string.common_loading'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ left: ThemeConstants.SPACE_SM })
      } else if (this.isError) {
        Text(this.errorMessage)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
      } else if (!this.hasMore) {
        Text($r('app.string.common_no_more'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(ThemeConstants.FOOTER_HEIGHT)
    .onClick(() => {
      if (this.isError && this.onRetry) {
        this.onRetry()
      }
    })
  }
}
