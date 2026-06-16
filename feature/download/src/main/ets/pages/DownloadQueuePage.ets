import { ThemeConstants } from 'shared'

/**
 * Downloads (下载) bottom tab — plain tab content hosted under Index's shared HDS title bar (no
 * NavDestination wrapper). M0 placeholder; M4 replaces this with the queue/concurrency/resume state
 * machine + archiver (DownloadViewModel + background DownloadAgentService) and offline-read source
 * resolution. eros_fe ships 下载 as a top-level tab (tabhome_controller.dart:31).
 */
@ComponentV2
export struct DownloadQueuePage {
  // Accepted for the Index tab-scroller handoff (this placeholder doesn't scroll, so it's unused).
  @Param scroller: Scroller = new Scroller();

  build() {
    Column() {
      Text('Downloads')
        .fontSize(ThemeConstants.FONT_SIZE_H2)
        .fontColor($r('sys.color.font_primary'))
      Text('queue · resume · archiver · offline read (M4)')
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: ThemeConstants.SPACE_SM })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
