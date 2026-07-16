import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadQueueSettings,
} from 'shared'

/**
 * Projects the queue's quality-specific tasks into the two slots used by Gallery Detail.
 * Storage identity stays untouched: Gallery uses preferOriginal, while Archiver uses org/res tags.
 */
export class GalleryDownloadTaskProjection {
  static galleryTask(
    tasks: DownloadGalleryTask[],
    gid: string,
    token: string,
    preferOriginal: boolean,
  ): DownloadGalleryTask | null {
    let exact: DownloadGalleryTask | null = null
    let fallback: DownloadGalleryTask | null = null
    for (let i: number = 0; i < tasks.length; i++) {
      const task: DownloadGalleryTask = tasks[i]
      if (task.gid !== gid || task.preferOriginal !== preferOriginal) {
        continue
      }
      if (token.length === 0 || task.token === token) {
        if (exact === null || task.queuedAt > exact.queuedAt) {
          exact = task
        }
      } else if (fallback === null || task.queuedAt > fallback.queuedAt) {
        fallback = task
      }
    }
    return exact !== null ? exact : fallback
  }

  static galleryTasks(
    tasks: DownloadGalleryTask[],
    gid: string,
    token: string,
  ): DownloadGalleryTask[] {
    const out: DownloadGalleryTask[] = []
    const resampled: DownloadGalleryTask | null = GalleryDownloadTaskProjection.galleryTask(
      tasks,
      gid,
      token,
      false,
    )
    const original: DownloadGalleryTask | null = GalleryDownloadTaskProjection.galleryTask(
      tasks,
      gid,
      token,
      true,
    )
    if (resampled !== null) {
      out.push(resampled)
    }
    if (original !== null) {
      out.push(original)
    }
    return out
  }

  static archiverTask(
    tasks: DownloadArchiverTask[],
    gid: string,
    dltype: string,
  ): DownloadArchiverTask | null {
    const expectedTag: string = `${gid}:${dltype}`
    let fallback: DownloadArchiverTask | null = null
    for (let i: number = 0; i < tasks.length; i++) {
      const task: DownloadArchiverTask = tasks[i]
      if (task.tag === expectedTag) {
        return task
      }
      if (task.gid === gid && task.dltype === dltype &&
        (fallback === null || task.queuedAt > fallback.queuedAt)) {
        fallback = task
      }
    }
    return fallback
  }

  static archiverTasks(tasks: DownloadArchiverTask[], gid: string): DownloadArchiverTask[] {
    const out: DownloadArchiverTask[] = []
    const resampled: DownloadArchiverTask | null = GalleryDownloadTaskProjection.archiverTask(tasks, gid, 'res')
    const original: DownloadArchiverTask | null = GalleryDownloadTaskProjection.archiverTask(tasks, gid, 'org')
    if (resampled !== null) {
      out.push(resampled)
    }
    if (original !== null) {
      out.push(original)
    }
    return out
  }

  static effectiveGalleryStatus(task: DownloadGalleryTask): string {
    if (task.isDownloadComplete()) {
      return DownloadGalleryTaskStatus.COMPLETE
    }
    if (task.status === DownloadGalleryTaskStatus.COMPLETE) {
      return DownloadGalleryTaskStatus.PARTIAL
    }
    return task.status
  }

  static effectiveArchiverStatus(task: DownloadArchiverTask): string {
    if (DownloadQueueSettings.isArchiverTaskComplete(task)) {
      return DownloadGalleryTaskStatus.COMPLETE
    }
    if (task.status === DownloadGalleryTaskStatus.COMPLETE) {
      return DownloadGalleryTaskStatus.ERROR
    }
    return task.status
  }

  static aggregateGalleryStatus(tasks: DownloadGalleryTask[]): string {
    const statuses: string[] = []
    for (let i: number = 0; i < tasks.length; i++) {
      statuses.push(GalleryDownloadTaskProjection.effectiveGalleryStatus(tasks[i]))
    }
    return GalleryDownloadTaskProjection.aggregateStatus(statuses)
  }

  static aggregateArchiverStatus(tasks: DownloadArchiverTask[]): string {
    const statuses: string[] = []
    for (let i: number = 0; i < tasks.length; i++) {
      statuses.push(GalleryDownloadTaskProjection.effectiveArchiverStatus(tasks[i]))
    }
    return GalleryDownloadTaskProjection.aggregateStatus(statuses)
  }

  private static aggregateStatus(statuses: string[]): string {
    let best: string = DownloadGalleryTaskStatus.QUEUED
    let bestPriority: number = -1
    for (let i: number = 0; i < statuses.length; i++) {
      const priority: number = GalleryDownloadTaskProjection.statusPriority(statuses[i])
      if (priority > bestPriority) {
        best = statuses[i]
        bestPriority = priority
      }
    }
    return best
  }

  private static statusPriority(status: string): number {
    // The collapsed chip should first reflect work that is currently moving.
    // Any mixed state remains inspectable in the per-quality rows.
    if (status === DownloadGalleryTaskStatus.DOWNLOADING) {
      return 80
    }
    if (status === DownloadGalleryTaskStatus.PREPARING) {
      return 70
    }
    if (status === DownloadGalleryTaskStatus.READY) {
      return 60
    }
    if (status === DownloadGalleryTaskStatus.QUEUED) {
      return 50
    }
    if (status === DownloadGalleryTaskStatus.ERROR) {
      return 40
    }
    if (status === DownloadGalleryTaskStatus.PARTIAL) {
      return 30
    }
    if (status === DownloadGalleryTaskStatus.PAUSED) {
      return 20
    }
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return 10
    }
    return 0
  }
}
