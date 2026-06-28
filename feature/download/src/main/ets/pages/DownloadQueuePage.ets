import {
  ThemeConstants,
  SecondaryListScaffold,
  CardEmptyState,
  AppStrings,
  CachedImageFileService,
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
  EhGalleryImage,
  EhThumbnail,
  ReaderParams,
  DownloadQueueSettings,
  DownloadQueueState,
  DownloadViewType,
  DownloadViewState,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  connectDownloadQueue,
  connectDownloadView,
  connectNavStack,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Downloads (下载) bottom tab — plain tab content hosted under Index's shared HDS title bar (no
 * NavDestination wrapper). Mirrors eros_fe's first-level split: Gallery downloads and Archiver
 * downloads are separate retained queues. Gallery tasks show seed preparation and sandbox image
 * download progress here; completed Gallery tasks enter the normal Reader with local file:// images.
 */
@ComponentV2
export struct DownloadQueuePage {
  // Accepted for the Index tab-scroller handoff (this placeholder doesn't scroll, so it's unused).
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local downloadView: DownloadViewState = connectDownloadView();
  @Local downloadQueue: DownloadQueueState = connectDownloadQueue();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private selectedEmptyText(): Resource {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? $r('app.string.download_archiver_empty')
      : $r('app.string.download_gallery_empty')
  }

  private selectedNextStep(): Resource {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? $r('app.string.download_archiver_next_step')
      : $r('app.string.download_gallery_next_step')
  }

  private taskStatusText(task: DownloadGalleryTask): string {
    return this.statusText(task.status)
  }

  private statusText(status: string): string {
    if (status === DownloadGalleryTaskStatus.PREPARING) {
      return AppStrings.get('download_status_preparing')
    }
    if (status === DownloadGalleryTaskStatus.READY) {
      return AppStrings.get('download_status_ready')
    }
    if (status === DownloadGalleryTaskStatus.DOWNLOADING) {
      return AppStrings.get('download_status_downloading')
    }
    if (status === DownloadGalleryTaskStatus.PARTIAL) {
      return AppStrings.get('download_status_partial')
    }
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return AppStrings.get('download_status_complete')
    }
    if (status === DownloadGalleryTaskStatus.ERROR) {
      return AppStrings.get('download_status_error')
    }
    return AppStrings.get('download_status_queued')
  }

  private taskMetaText(task: DownloadGalleryTask): string {
    const parts: string[] = []
    if (task.pageCountText().length > 0) {
      parts.push(task.pageCountText())
    }
    if (task.category.length > 0) {
      parts.push(task.category)
    }
    if (task.uploader.length > 0) {
      parts.push(task.uploader)
    }
    return parts.join(' · ')
  }

  private taskProgressLabel(task: DownloadGalleryTask): string {
    const parts: string[] = []
    if (task.status === DownloadGalleryTaskStatus.ERROR) {
      return this.taskStatusText(task)
    }
    if (task.downloadProgressText().length > 0) {
      parts.push(this.taskStatusText(task))
      parts.push(AppStrings.get('download_file_progress').replace('%s', task.downloadProgressText()))
      return parts.join(' · ')
    }
    if (task.seedProgressText().length > 0) {
      if (task.status === DownloadGalleryTaskStatus.PREPARING || task.status === DownloadGalleryTaskStatus.READY) {
        parts.push(this.taskStatusText(task))
      }
      parts.push(AppStrings.get('download_seed_progress').replace('%s', task.seedProgressText()))
      return parts.join(' · ')
    }
    return this.taskStatusText(task)
  }

  private taskProgressRatio(task: DownloadGalleryTask): number {
    if (task.status === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (task.pageCount <= 0) {
      return 0
    }
    if (task.downloadedCount() > 0) {
      return Math.max(0, Math.min(1, task.downloadedCount() / task.pageCount))
    }
    if (task.seededCount() > 0) {
      return Math.max(0, Math.min(1, task.seededCount() / task.pageCount))
    }
    return 0
  }

  private async removeTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.removeGallery(this.ctx(), task.gid, task.token)
  }

  private async removeArchiverTask(task: DownloadArchiverTask): Promise<void> {
    await DownloadQueueSettings.removeArchiver(this.ctx(), task.tag)
  }

  private async resumeTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.downloadGalleryImages(this.ctx(), task.gid, task.token)
  }

  private async resumeArchiverTask(task: DownloadArchiverTask): Promise<void> {
    await DownloadQueueSettings.downloadArchiver(this.ctx(), task.tag)
  }

  private canResumeTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.ERROR ||
      task.status === DownloadGalleryTaskStatus.PARTIAL ||
      task.status === DownloadGalleryTaskStatus.READY
  }

  private canReadTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.COMPLETE && task.downloadedCount() > 0
  }

  private canResumeArchiverTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.ERROR || task.status === DownloadGalleryTaskStatus.QUEUED
  }

  private archiverProgressRatio(task: DownloadArchiverTask): number {
    if (task.status === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (task.bytesTotal > 0) {
      return Math.max(0, Math.min(1, task.bytesWritten / task.bytesTotal))
    }
    return Math.max(0, Math.min(1, task.progress / 100))
  }

  private archiverProgressLabel(task: DownloadArchiverTask): string {
    if (task.status === DownloadGalleryTaskStatus.ERROR) {
      return this.statusText(task.status)
    }
    const progress: string = task.progressText()
    if (progress.length > 0) {
      return `${this.statusText(task.status)} · ${progress}`
    }
    return this.statusText(task.status)
  }

  private openDownloadedTask(task: DownloadGalleryTask): void {
    const images: EhGalleryImage[] = this.downloadedSeedImages(task)
    if (images.length === 0) {
      return
    }
    const fileCount: number = task.pageCount > 0 ? task.pageCount : images.length
    const loadedPages: number = task.previewPageCount > 0 ? task.previewPageCount : 1
    const perPage: number = task.firstPageCount > 0 ? task.firstPageCount : images.length
    this.stack.pushPathByName(
      'Reader',
      new ReaderParams(task.gid, task.token, 0, fileCount, task.displayTitle(), images, loadedPages, perPage),
    )
  }

  private downloadedSeedImages(task: DownloadGalleryTask): EhGalleryImage[] {
    const images: EhGalleryImage[] = []
    for (let i: number = 0; i < task.imageSeeds.length; i++) {
      const seed: DownloadImageSeed = task.imageSeeds[i]
      if (seed.filePath.length === 0 || seed.bytesWritten <= 0) {
        continue
      }
      const image: EhGalleryImage = new EhGalleryImage(seed.page)
      image.imgkey = seed.imgkey
      image.sUrl = seed.imagePageUrl
      image.thumbUrl = seed.thumbUrl
      image.imageUrl = CachedImageFileService.displayUri(seed.filePath)
      image.originImageUrl = seed.originImageUrl
      image.showKey = seed.showKey
      image.reloadKey = seed.reloadKey
      images.push(image)
    }
    return images
  }

  @Builder
  private EmptyQueueSection() {
    Column() {
      CardEmptyState({ message: this.selectedEmptyText(), expand: false })
      Text(this.selectedNextStep())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({
          left: ThemeConstants.SPACE_LG,
          right: ThemeConstants.SPACE_LG,
          bottom: ThemeConstants.SPACE_LG,
        })
    }
    .width('100%')
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private GalleryTaskSection() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.downloadQueue.galleryTasks,
        (task: DownloadGalleryTask) => {
          this.DownloadGalleryTaskCard(task)
        },
        (task: DownloadGalleryTask) => `${task.gid}:${task.token}`,
      )
    }
    .width('100%')
  }

  @Builder
  private ArchiverTaskSection() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.downloadQueue.archiverTasks,
        (task: DownloadArchiverTask) => {
          this.DownloadArchiverTaskCard(task)
        },
        (task: DownloadArchiverTask) => task.tag,
      )
    }
    .width('100%')
  }

  @Builder
  private DownloadGalleryTaskCard(task: DownloadGalleryTask) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      EhThumbnail({
        url: task.thumbUrl,
        thumbWidth: ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH,
        thumbHeight: ThemeConstants.DOWNLOAD_TASK_CARD_HEIGHT - ThemeConstants.SPACE_LG,
         radius: ThemeConstants.THUMB_RADIUS,
      })
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(task.displayTitle())
          .fontSize(ThemeConstants.FONT_SIZE_META)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.taskMetaText(task))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Blank()
        this.TaskProgressBar(task)
        Text(this.taskProgressLabel(task))
          .fontSize(ThemeConstants.FONT_SIZE_META)
          .fontColor(task.status === DownloadGalleryTaskStatus.ERROR
            ? Color.Red
            : $r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Start)
      this.TaskActions(task)
    }
    .width('100%')
    .height(ThemeConstants.DOWNLOAD_TASK_CARD_HEIGHT)
    .padding(ThemeConstants.SPACE_SM)
    .alignItems(VerticalAlign.Center)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private DownloadArchiverTaskCard(task: DownloadArchiverTask) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      Column() {
        SymbolGlyph($r('sys.symbol.arrow_down_to_line_circle_fill'))
          .fontSize(ThemeConstants.FONT_SIZE_H1)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
      }
      .width(ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH)
      .height(ThemeConstants.DOWNLOAD_TASK_CARD_HEIGHT - ThemeConstants.SPACE_LG)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(ThemeConstants.THUMB_RADIUS)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(task.displayTitle())
          .fontSize(ThemeConstants.FONT_SIZE_META)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(task.resolution.length > 0 ? task.resolution : task.dltype)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Blank()
        this.ArchiverProgressBar(task)
        Text(this.archiverProgressLabel(task))
          .fontSize(ThemeConstants.FONT_SIZE_META)
          .fontColor(task.status === DownloadGalleryTaskStatus.ERROR
            ? Color.Red
            : $r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Start)
      this.ArchiverTaskActions(task)
    }
    .width('100%')
    .height(ThemeConstants.DOWNLOAD_TASK_CARD_HEIGHT)
    .padding(ThemeConstants.SPACE_SM)
    .alignItems(VerticalAlign.Center)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private TaskProgressBar(task: DownloadGalleryTask) {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.taskProgressRatio(task) * 100))}%`)
        .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .backgroundColor(task.status === DownloadGalleryTaskStatus.ERROR
          ? Color.Red
          : ThemeConstants.BRAND_PRIMARY)
    }
    .width('100%')
    .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
    .borderRadius(ThemeConstants.RADIUS_SM)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .clip(true)
  }

  @Builder
  private ArchiverProgressBar(task: DownloadArchiverTask) {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.archiverProgressRatio(task) * 100))}%`)
        .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .backgroundColor(task.status === DownloadGalleryTaskStatus.ERROR
          ? Color.Red
          : ThemeConstants.BRAND_PRIMARY)
    }
    .width('100%')
    .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
    .borderRadius(ThemeConstants.RADIUS_SM)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .clip(true)
  }

  @Builder
  private TaskActions(task: DownloadGalleryTask) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      if (this.canReadTask(task)) {
        this.ReadTaskButton(task)
      } else if (this.canResumeTask(task)) {
        this.ResumeTaskButton(task)
      }
      this.RemoveTaskButton(task)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }

  @Builder
  private ArchiverTaskActions(task: DownloadArchiverTask) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      if (this.canResumeArchiverTask(task)) {
        this.ResumeArchiverTaskButton(task)
      }
      this.RemoveArchiverTaskButton(task)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }

  @Builder
  private ReadTaskButton(task: DownloadGalleryTask) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([ThemeConstants.BRAND_PRIMARY])
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .accessibilityText($r('app.string.detail_read'))
    .onClick(() => {
      this.openDownloadedTask(task)
    })
  }

  @Builder
  private ResumeTaskButton(task: DownloadGalleryTask) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([ThemeConstants.BRAND_PRIMARY])
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .accessibilityText($r('app.string.common_retry'))
    .onClick(() => {
      this.resumeTask(task)
    })
  }

  @Builder
  private ResumeArchiverTaskButton(task: DownloadArchiverTask) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([ThemeConstants.BRAND_PRIMARY])
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .accessibilityText($r('app.string.common_retry'))
    .onClick(() => {
      this.resumeArchiverTask(task)
    })
  }

  @Builder
  private RemoveTaskButton(task: DownloadGalleryTask) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .accessibilityText($r('app.string.common_remove'))
    .onClick(() => {
      this.removeTask(task)
    })
  }

  @Builder
  private RemoveArchiverTaskButton(task: DownloadArchiverTask) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .accessibilityText($r('app.string.common_remove'))
    .onClick(() => {
      this.removeArchiverTask(task)
    })
  }

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
        onDidScroll: (offset: number, state: ScrollState) => {
          if (this.onDidScroll) {
            this.onDidScroll(offset, state)
          }
        },
      }) {
        ListItem() {
          Column() {
            Blank()
          }
          .height(DOWNLOAD_SELECTOR_BAR_HEIGHT)
        }
        if (this.downloadView.viewType === DownloadViewType.GALLERY && this.downloadQueue.galleryTasks.length > 0) {
          ListItem() {
            this.GalleryTaskSection()
          }
        } else if (this.downloadView.viewType === DownloadViewType.ARCHIVER && this.downloadQueue.archiverTasks.length > 0) {
          ListItem() {
            this.ArchiverTaskSection()
          }
        } else {
          ListItem() {
            this.EmptyQueueSection()
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
