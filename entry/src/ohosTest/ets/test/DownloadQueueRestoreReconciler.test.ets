import { describe, expect, it } from '@ohos/hypium'
import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
  DownloadQueueRestoreReconciler,
} from 'shared'

function gallery(status: string): DownloadGalleryTask {
  const task: DownloadGalleryTask = new DownloadGalleryTask()
  task.gid = '100'
  task.token = 'token'
  task.title = 'Gallery'
  task.queuedAt = 10
  task.status = status
  const seed: DownloadImageSeed = new DownloadImageSeed()
  seed.page = 1
  seed.imagePageUrl = 'https://example.test/s/100-1'
  task.imageSeeds = [seed]
  task.syncProgressCounts()
  return task
}

function archiver(status: string): DownloadArchiverTask {
  const task: DownloadArchiverTask = new DownloadArchiverTask()
  task.tag = 'archive-100'
  task.gid = '100'
  task.queuedAt = 10
  task.status = status
  return task
}

export default function downloadQueueRestoreReconcilerTest(): void {
  describe('Download queue restore reconciler', () => {
    it('skips full RDB replacement when a restored queue has no durable changes', 0, (done: Function) => {
      const storedGallery: DownloadGalleryTask = gallery(DownloadGalleryTaskStatus.READY)
      const storedArchiver: DownloadArchiverTask = archiver(DownloadGalleryTaskStatus.QUEUED)
      expect(DownloadQueueRestoreReconciler.galleryNeedsRdbReconcile([storedGallery], [storedGallery.copy()])).assertEqual(false)
      expect(DownloadQueueRestoreReconciler.archiverNeedsRdbReconcile([storedArchiver], [storedArchiver.copy()])).assertEqual(false)
      done()
    })

    it('rebuilds only when cold-start normalization or metadata recovery changes durable data', 0, (done: Function) => {
      const storedGallery: DownloadGalleryTask = gallery(DownloadGalleryTaskStatus.DOWNLOADING)
      const normalizedGallery: DownloadGalleryTask = storedGallery.copy()
      normalizedGallery.status = DownloadGalleryTaskStatus.READY
      expect(DownloadQueueRestoreReconciler.galleryNeedsRdbReconcile([storedGallery], [normalizedGallery])).assertEqual(true)
      expect(DownloadQueueRestoreReconciler.galleryNeedsRdbReconcile([], [normalizedGallery])).assertEqual(true)

      const storedArchiver: DownloadArchiverTask = archiver(DownloadGalleryTaskStatus.DOWNLOADING)
      const normalizedArchiver: DownloadArchiverTask = storedArchiver.copy()
      normalizedArchiver.status = DownloadGalleryTaskStatus.QUEUED
      expect(DownloadQueueRestoreReconciler.archiverNeedsRdbReconcile([storedArchiver], [normalizedArchiver])).assertEqual(true)
      done()
    })
  })
}
