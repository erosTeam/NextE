import { DownloadArchiverTask, DownloadGalleryTask, DownloadImageSeed } from '../model/DownloadGalleryTask'

/** Compares only durable queue fields so a normal cold restore does not rewrite every task and seed. */
export class DownloadQueueRestoreReconciler {
  static galleryNeedsRdbReconcile(
    stored: DownloadGalleryTask[],
    restored: DownloadGalleryTask[],
  ): boolean {
    if (stored.length !== restored.length) {
      return true
    }
    for (let i: number = 0; i < restored.length; i++) {
      const next: DownloadGalleryTask = restored[i]
      const previous: DownloadGalleryTask | undefined = stored.find((item: DownloadGalleryTask) => {
        return item.gid === next.gid && item.token === next.token && item.preferOriginal === next.preferOriginal
      })
      if (previous === undefined || !DownloadQueueRestoreReconciler.sameGalleryTask(previous, next)) {
        return true
      }
    }
    return false
  }

  static archiverNeedsRdbReconcile(
    stored: DownloadArchiverTask[],
    restored: DownloadArchiverTask[],
  ): boolean {
    if (stored.length !== restored.length) {
      return true
    }
    for (let i: number = 0; i < restored.length; i++) {
      const next: DownloadArchiverTask = restored[i]
      const previous: DownloadArchiverTask | undefined = stored.find((item: DownloadArchiverTask) => item.tag === next.tag)
      if (previous === undefined || !DownloadQueueRestoreReconciler.sameArchiverTask(previous, next)) {
        return true
      }
    }
    return false
  }

  private static sameGalleryTask(a: DownloadGalleryTask, b: DownloadGalleryTask): boolean {
    if (
      a.gid !== b.gid ||
      a.token !== b.token ||
      a.title !== b.title ||
      a.titleJp !== b.titleJp ||
      a.thumbUrl !== b.thumbUrl ||
      a.imgWidth !== b.imgWidth ||
      a.imgHeight !== b.imgHeight ||
      a.pageCount !== b.pageCount ||
      a.category !== b.category ||
      a.uploader !== b.uploader ||
      a.upgradeFromGid !== b.upgradeFromGid ||
      a.queuedAt !== b.queuedAt ||
      a.preparedAt !== b.preparedAt ||
      a.firstPageCount !== b.firstPageCount ||
      a.previewPageCount !== b.previewPageCount ||
      a.prepareError !== b.prepareError ||
      a.preferOriginal !== b.preferOriginal ||
      a.status !== b.status ||
      a.imageSeeds.length !== b.imageSeeds.length
    ) {
      return false
    }
    for (let i: number = 0; i < a.imageSeeds.length; i++) {
      if (!DownloadQueueRestoreReconciler.sameSeed(a.imageSeeds[i], b.imageSeeds[i])) {
        return false
      }
    }
    return true
  }

  private static sameSeed(a: DownloadImageSeed, b: DownloadImageSeed): boolean {
    return a.page === b.page &&
      a.imgkey === b.imgkey &&
      a.imagePageUrl === b.imagePageUrl &&
      a.thumbUrl === b.thumbUrl &&
      a.imageUrl === b.imageUrl &&
      a.originImageUrl === b.originImageUrl &&
      a.showKey === b.showKey &&
      a.reloadKey === b.reloadKey &&
      a.filePath === b.filePath &&
      a.bytesWritten === b.bytesWritten &&
      a.downloadedAt === b.downloadedAt &&
      a.downloadError === b.downloadError
  }

  private static sameArchiverTask(a: DownloadArchiverTask, b: DownloadArchiverTask): boolean {
    return a.tag === b.tag &&
      a.gid === b.gid &&
      a.token === b.token &&
      a.title === b.title &&
      a.thumbUrl === b.thumbUrl &&
      a.imgWidth === b.imgWidth &&
      a.imgHeight === b.imgHeight &&
      a.dltype === b.dltype &&
      a.resolution === b.resolution &&
      a.parseSource === b.parseSource &&
      a.url === b.url &&
      a.fileName === b.fileName &&
      a.filePath === b.filePath &&
      a.queuedAt === b.queuedAt &&
      a.downloadedAt === b.downloadedAt &&
      a.bytesWritten === b.bytesWritten &&
      a.bytesTotal === b.bytesTotal &&
      a.progress === b.progress &&
      a.error === b.error &&
      a.status === b.status
  }
}
