import {
  ThemeConstants,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  CardEmptyState,
  AppStrings,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  EhThumbnail,
  DownloadQueueSettings,
  DownloadQueueState,
  DownloadViewType,
  DownloadViewState,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  connectDownloadQueue,
  connectDownloadView,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Downloads (下载) bottom tab — plain tab content hosted under Index's shared HDS title bar (no
 * NavDestination wrapper). Mirrors eros_fe's first-level split: Gallery downloads and Archiver
 * downloads are separate retained queues. This lane intentionally stops at the non-destructive
 * workbench surface; the background download service, archive submit, and offline-reader source
 * resolver land in later lanes.
 */
@ComponentV2
export struct DownloadQueuePage {
  // Accepted for the Index tab-scroller handoff (this placeholder doesn't scroll, so it's unused).
  @Param scroller: Scroller = new Scroller();
  @Local downloadView: DownloadViewState = connectDownloadView();
  @Local downloadQueue: DownloadQueueState = connectDownloadQueue();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private selectedTitle(): Resource {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? $r('app.string.download_archiver_queue')
      : $r('app.string.download_gallery_queue')
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

  private selectedActiveCount(): number {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? 0
      : this.downloadQueue.galleryTasks.length
  }

  private selectedStatus(): Resource {
    return this.selectedActiveCount() > 0
      ? $r('app.string.download_status_active')
      : $r('app.string.download_status_empty')
  }

  private taskStatusText(task: DownloadGalleryTask): string {
    if (task.status === DownloadGalleryTaskStatus.PREPARING) {
      return AppStrings.get('download_status_preparing')
    }
    if (task.status === DownloadGalleryTaskStatus.READY) {
      return AppStrings.get('download_status_ready')
    }
    if (task.status === DownloadGalleryTaskStatus.DOWNLOADING) {
      return AppStrings.get('download_status_downloading')
    }
    if (task.status === DownloadGalleryTaskStatus.PARTIAL) {
      return AppStrings.get('download_status_partial')
    }
    if (task.status === DownloadGalleryTaskStatus.ERROR) {
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

  @Builder
  private SummarySection() {
    GroupedListSection() {
      ConciseListRow({
        title: this.selectedTitle(),
        leadingIcon: this.downloadView.viewType === DownloadViewType.ARCHIVER
          ? $r('sys.symbol.square_grid_2x2')
          : $r('sys.symbol.picture'),
        trailingText: this.selectedStatus(),
        showChevron: false,
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.download_active_tasks'),
        leadingIcon: $r('sys.symbol.arrow_down_to_line_circle_fill'),
        trailingText: `${this.selectedActiveCount()}`,
        showChevron: false,
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.download_finished_tasks'),
        leadingIcon: $r('sys.symbol.checkmark'),
        trailingText: '0',
        showChevron: false,
      })
    }
  }

  @Builder
  private EmptyQueueSection() {
    GroupedListSection() {
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
      this.RemoveTaskButton(task)
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
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
      }) {
        ListItem() {
          Column() {
            Blank()
          }
          .height(DOWNLOAD_SELECTOR_BAR_HEIGHT)
        }
        ListItem() {
          this.SummarySection()
        }
        if (this.downloadView.viewType === DownloadViewType.GALLERY && this.downloadQueue.galleryTasks.length > 0) {
          ListItem() {
            this.GalleryTaskSection()
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
