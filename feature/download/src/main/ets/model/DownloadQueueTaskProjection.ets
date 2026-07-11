import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadSortMode,
} from 'shared'

const DOWNLOAD_TASK_GROUP_COUNT: number = 4

/**
 * Immutable-at-the-container-level projection used by the download queue page. It groups and orders
 * the current queue once per state change while deliberately retaining the live task instances, so
 * progress fields keep flowing to cards without a per-card queue lookup.
 */
export class DownloadQueueTaskProjection {
  galleryGroups: DownloadGalleryTask[][] = [[], [], [], []]
  archiverGroups: DownloadArchiverTask[][] = [[], [], [], []]
  galleryVisibleCount: number = 0
  archiverVisibleCount: number = 0

  static build(
    galleryTasks: DownloadGalleryTask[],
    archiverTasks: DownloadArchiverTask[],
    searchText: string,
    sortMode: string,
  ): DownloadQueueTaskProjection {
    const projection: DownloadQueueTaskProjection = new DownloadQueueTaskProjection()
    const query: string = searchText.trim().toLowerCase()

    for (let i: number = 0; i < galleryTasks.length; i++) {
      const task: DownloadGalleryTask = galleryTasks[i]
      if (!DownloadQueueTaskProjection.galleryMatchesSearch(task, query)) {
        continue
      }
      const group: number = DownloadQueueTaskProjection.galleryGroup(task)
      projection.galleryGroups[group].push(task)
      projection.galleryVisibleCount = projection.galleryVisibleCount + 1
    }
    for (let group: number = 0; group < DOWNLOAD_TASK_GROUP_COUNT; group++) {
      projection.galleryGroups[group].sort((a: DownloadGalleryTask, b: DownloadGalleryTask): number => {
        return DownloadQueueTaskProjection.compareGalleryTasks(a, b, sortMode)
      })
    }

    for (let i: number = 0; i < archiverTasks.length; i++) {
      const task: DownloadArchiverTask = archiverTasks[i]
      if (!DownloadQueueTaskProjection.archiverMatchesSearch(task, query)) {
        continue
      }
      const group: number = DownloadQueueTaskProjection.archiverGroup(task)
      projection.archiverGroups[group].push(task)
      projection.archiverVisibleCount = projection.archiverVisibleCount + 1
    }
    for (let group: number = 0; group < DOWNLOAD_TASK_GROUP_COUNT; group++) {
      projection.archiverGroups[group].sort((a: DownloadArchiverTask, b: DownloadArchiverTask): number => {
        return DownloadQueueTaskProjection.compareArchiverTasks(a, b, sortMode)
      })
    }
    return projection
  }

  galleryTasksForGroup(group: number): DownloadGalleryTask[] {
    return group >= 0 && group < DOWNLOAD_TASK_GROUP_COUNT ? this.galleryGroups[group] : []
  }

  archiverTasksForGroup(group: number): DownloadArchiverTask[] {
    return group >= 0 && group < DOWNLOAD_TASK_GROUP_COUNT ? this.archiverGroups[group] : []
  }

  private static galleryMatchesSearch(task: DownloadGalleryTask, query: string): boolean {
    if (query.length === 0) {
      return true
    }
    return DownloadQueueTaskProjection.containsLower(task.displayTitle(), query) ||
      DownloadQueueTaskProjection.containsLower(task.titleJp, query) ||
      DownloadQueueTaskProjection.containsLower(task.gid, query) ||
      DownloadQueueTaskProjection.containsLower(task.category, query)
  }

  private static archiverMatchesSearch(task: DownloadArchiverTask, query: string): boolean {
    if (query.length === 0) {
      return true
    }
    return DownloadQueueTaskProjection.containsLower(task.displayTitle(), query) ||
      DownloadQueueTaskProjection.containsLower(task.gid, query) ||
      DownloadQueueTaskProjection.containsLower(task.resolution, query) ||
      DownloadQueueTaskProjection.containsLower(task.dltype, query) ||
      DownloadQueueTaskProjection.containsLower(task.fileName, query)
  }

  private static containsLower(value: string, query: string): boolean {
    return value.toLowerCase().includes(query)
  }

  private static galleryGroup(task: DownloadGalleryTask): number {
    const downloaded: number = task.downloadedCount()
    const total: number = Math.max(task.pageCount, downloaded, task.seededCount())
    const status: string = task.status === DownloadGalleryTaskStatus.COMPLETE && total > 0 && downloaded < total
      ? DownloadGalleryTaskStatus.PARTIAL
      : task.status
    return DownloadQueueTaskProjection.statusGroup(status)
  }

  private static archiverGroup(task: DownloadArchiverTask): number {
    return DownloadQueueTaskProjection.statusGroup(task.status)
  }

  private static statusGroup(status: string): number {
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return 3
    }
    if (status === DownloadGalleryTaskStatus.ERROR) {
      return 2
    }
    if (status === DownloadGalleryTaskStatus.PAUSED) {
      return 1
    }
    return 0
  }

  private static compareGalleryTasks(a: DownloadGalleryTask, b: DownloadGalleryTask, sortMode: string): number {
    if (sortMode === DownloadSortMode.ADDED_ASC) {
      return DownloadQueueTaskProjection.compareNumberThenKey(
        a.queuedAt,
        b.queuedAt,
        DownloadQueueTaskProjection.galleryTaskKey(a),
        DownloadQueueTaskProjection.galleryTaskKey(b),
        true,
      )
    }
    if (sortMode === DownloadSortMode.TITLE_ASC) {
      return DownloadQueueTaskProjection.compareTextThenTime(a.displayTitle(), b.displayTitle(), a.queuedAt, b.queuedAt, true)
    }
    if (sortMode === DownloadSortMode.TITLE_DESC) {
      return DownloadQueueTaskProjection.compareTextThenTime(a.displayTitle(), b.displayTitle(), a.queuedAt, b.queuedAt, false)
    }
    return DownloadQueueTaskProjection.compareNumberThenKey(
      a.queuedAt,
      b.queuedAt,
      DownloadQueueTaskProjection.galleryTaskKey(a),
      DownloadQueueTaskProjection.galleryTaskKey(b),
      false,
    )
  }

  private static compareArchiverTasks(a: DownloadArchiverTask, b: DownloadArchiverTask, sortMode: string): number {
    if (sortMode === DownloadSortMode.ADDED_ASC) {
      return DownloadQueueTaskProjection.compareNumberThenKey(a.queuedAt, b.queuedAt, a.tag, b.tag, true)
    }
    if (sortMode === DownloadSortMode.TITLE_ASC) {
      return DownloadQueueTaskProjection.compareTextThenTime(a.displayTitle(), b.displayTitle(), a.queuedAt, b.queuedAt, true)
    }
    if (sortMode === DownloadSortMode.TITLE_DESC) {
      return DownloadQueueTaskProjection.compareTextThenTime(a.displayTitle(), b.displayTitle(), a.queuedAt, b.queuedAt, false)
    }
    return DownloadQueueTaskProjection.compareNumberThenKey(a.queuedAt, b.queuedAt, a.tag, b.tag, false)
  }

  private static compareTextThenTime(aText: string, bText: string, aTime: number, bTime: number, asc: boolean): number {
    const a: string = aText.toLowerCase()
    const b: string = bText.toLowerCase()
    if (a < b) {
      return asc ? -1 : 1
    }
    if (a > b) {
      return asc ? 1 : -1
    }
    return DownloadQueueTaskProjection.compareNumberThenKey(aTime, bTime, aText, bText, false)
  }

  private static compareNumberThenKey(
    aValue: number,
    bValue: number,
    aKey: string,
    bKey: string,
    asc: boolean,
  ): number {
    if (aValue !== bValue) {
      return asc ? aValue - bValue : bValue - aValue
    }
    if (aKey < bKey) {
      return -1
    }
    if (aKey > bKey) {
      return 1
    }
    return 0
  }

  private static galleryTaskKey(task: DownloadGalleryTask): string {
    return task.gid + ':' + task.token + ':' + (task.preferOriginal ? 'original' : 'resample')
  }
}
