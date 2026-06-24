import { ThemeConstants } from '../theme/ThemeConstants'

/** Centered full-pane loading spinner (V2Next PageLoadingState). */
@ComponentV2
export struct PageLoadingState {
  @Param expand: boolean = true

  build() {
    Column() {
      LoadingProgress()
        .width(ThemeConstants.LOADING_SIZE)
        .height(ThemeConstants.LOADING_SIZE)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .layoutWeight(this.expand ? 1 : 0)
  }
}

/** Centered error message + capsule retry (V2Next PageErrorState). */
@ComponentV2
export struct PageErrorState {
  @Param message: ResourceStr = $r('app.string.common_load_failed')
  @Param retryLabel: ResourceStr = $r('app.string.common_retry')
  @Param expand: boolean = true
  @Event retryAction?: () => void

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(this.message)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button(this.retryLabel)
        .type(ButtonType.Capsule)
        .fontColor(ThemeConstants.TEXT_ON_BRAND)
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .onClick(() => {
          if (this.retryAction) {
            this.retryAction()
          }
        })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding(ThemeConstants.SPACE_XL)
    .layoutWeight(this.expand ? 1 : 0)
  }
}

/** Centered empty-content message (V2Next CardEmptyState). */
@ComponentV2
export struct CardEmptyState {
  @Param message: ResourceStr = $r('app.string.common_no_content')
  @Param expand: boolean = true

  build() {
    Column() {
      Text(this.message)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding(ThemeConstants.SPACE_LG)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .layoutWeight(this.expand ? 1 : 0)
  }
}
