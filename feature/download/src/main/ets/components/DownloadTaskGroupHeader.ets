import {
  DownloadQueueSignalState,
  DownloadQueueState,
  DownloadViewState,
  DownloadViewType,
  ThemeConstants,
  connectDownloadQueue,
  connectDownloadQueueSignal,
  connectDownloadView,
} from 'shared'
import { DownloadQueueTaskProjection } from '../model/DownloadQueueTaskProjection'

export const DOWNLOAD_PINNED_TASK_GROUP_HEADER_HEIGHT: number =
  ThemeConstants.FONT_SIZE_BODY + ThemeConstants.SPACE_XS * 2

export function downloadTaskGroupTitle(group: number): Resource {
  if (group === 1) {
    return $r('app.string.download_group_paused')
  }
  if (group === 2) {
    return $r('app.string.download_group_failed')
  }
  if (group === 3) {
    return $r('app.string.download_group_completed')
  }
  return $r('app.string.download_group_active')
}

/** Shared text/badge content. Its parent chooses the surface because List and HDS have different layers. */
@ComponentV2
export struct DownloadTaskGroupHeaderContent {
  @Param group: number = -1
  @Param count: number = 0

  build() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text(downloadTaskGroupTitle(this.group))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(ThemeConstants.BRAND_PRIMARY)
        .fontWeight(FontWeight.Bold)
      Text(`${this.count}`)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontColor(ThemeConstants.TEXT_ON_BRAND)
        .fontWeight(FontWeight.Medium)
        .padding({
          left: ThemeConstants.SPACE_XS,
          right: ThemeConstants.SPACE_XS,
          top: ThemeConstants.SPACE_XS / 2,
          bottom: ThemeConstants.SPACE_XS / 2,
        })
        .borderRadius(ThemeConstants.RADIUS_ROUND)
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
    }
    .alignItems(VerticalAlign.Center)
  }
}

/** Ordinary list header: its surrounding List already supplies the page surface. */
@ComponentV2
export struct DownloadTaskGroupHeader {
  @Param group: number = -1
  @Param count: number = 0

  build() {
    Row() {
      DownloadTaskGroupHeaderContent({ group: this.group, count: this.count })
    }
    .width('100%')
    .height(DOWNLOAD_PINNED_TASK_GROUP_HEADER_HEIGHT)
    .padding({
      left: ThemeConstants.SPACE_SM,
      right: ThemeConstants.SPACE_SM,
    })
  }
}

/**
 * HDS-side mirror. `DownloadViewState` carries only the task-group enum; this component calculates
 * title and count from the current queue projection so searches, sort changes, and task transitions
 * cannot leave a stale label or badge in the title bar.
 */
@ComponentV2
export struct DownloadPinnedTaskGroupHeader {
  @Local private downloadView: DownloadViewState = connectDownloadView()
  @Local private downloadQueue: DownloadQueueState = connectDownloadQueue()
  @Local private downloadQueueSignal: DownloadQueueSignalState = connectDownloadQueueSignal()

  private currentCount(): number {
    // Read the signal explicitly: queue task fields are mutable models and this is the same update
    // boundary the queue page uses before rebuilding its visible groups.
    if (this.downloadQueueSignal.version < 0 || this.downloadView.pinnedGroup < 0) {
      return 0
    }
    const projection: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
      this.downloadQueue.galleryTasks,
      this.downloadQueue.archiverTasks,
      this.downloadView.searchText,
      this.downloadView.sortMode,
    )
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? projection.archiverTasksForGroup(this.downloadView.pinnedGroup).length
      : projection.galleryTasksForGroup(this.downloadView.pinnedGroup).length
  }

  build() {
    if (this.downloadView.pinnedGroupVisible && this.downloadView.pinnedGroup >= 0) {
      Row() {
        DownloadTaskGroupHeaderContent({
          group: this.downloadView.pinnedGroup,
          count: this.currentCount(),
        })
      }
      .width('100%')
      .height(DOWNLOAD_PINNED_TASK_GROUP_HEADER_HEIGHT)
      .padding({
        left: ThemeConstants.SPACE_MD + ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_MD + ThemeConstants.SPACE_SM,
      })
      .alignItems(VerticalAlign.Center)
    }
  }
}
