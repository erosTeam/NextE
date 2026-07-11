import { describe, expect, it } from '@ohos/hypium'
import { DownloadQueueTaskProjection } from 'download'
import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadSortMode,
} from 'shared'

function galleryTask(
  gid: string,
  title: string,
  status: string,
  queuedAt: number,
): DownloadGalleryTask {
  const task: DownloadGalleryTask = new DownloadGalleryTask()
  task.gid = gid
  task.token = `token-${gid}`
  task.title = title
  task.status = status
  task.queuedAt = queuedAt
  return task
}

function archiverTask(
  tag: string,
  title: string,
  status: string,
  queuedAt: number,
): DownloadArchiverTask {
  const task: DownloadArchiverTask = new DownloadArchiverTask()
  task.tag = tag
  task.gid = `gid-${tag}`
  task.title = title
  task.status = status
  task.queuedAt = queuedAt
  return task
}

export default function downloadQueueTaskProjectionTest(): void {
  describe('DownloadQueueTaskProjection', () => {
    it('keeps the existing status groups and live task references while ordering each group once', 0, (done: Function) => {
      const alpha: DownloadGalleryTask = galleryTask('alpha', 'Alpha', DownloadGalleryTaskStatus.QUEUED, 20)
      const zulu: DownloadGalleryTask = galleryTask('zulu', 'Zulu', DownloadGalleryTaskStatus.DOWNLOADING, 30)
      const partial: DownloadGalleryTask = galleryTask('partial', 'Half', DownloadGalleryTaskStatus.COMPLETE, 25)
      partial.pageCount = 4
      partial.downloadedFiles = 2
      const paused: DownloadGalleryTask = galleryTask('paused', 'Paused', DownloadGalleryTaskStatus.PAUSED, 15)
      const failed: DownloadGalleryTask = galleryTask('failed', 'Failed', DownloadGalleryTaskStatus.ERROR, 10)
      const complete: DownloadGalleryTask = galleryTask('complete', 'Done', DownloadGalleryTaskStatus.COMPLETE, 5)
      complete.pageCount = 2
      complete.downloadedFiles = 2

      const archiverActive: DownloadArchiverTask = archiverTask('active', 'Archive Active', DownloadGalleryTaskStatus.QUEUED, 20)
      const archiverPaused: DownloadArchiverTask = archiverTask('paused', 'Archive Paused', DownloadGalleryTaskStatus.PAUSED, 15)
      const archiverFailed: DownloadArchiverTask = archiverTask('failed', 'Archive Failed', DownloadGalleryTaskStatus.ERROR, 10)
      const archiverComplete: DownloadArchiverTask = archiverTask('complete', 'Archive Done', DownloadGalleryTaskStatus.COMPLETE, 5)

      const projection: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [zulu, paused, partial, complete, alpha, failed],
        [archiverComplete, archiverFailed, archiverPaused, archiverActive],
        '',
        DownloadSortMode.TITLE_ASC,
      )

      expect(projection.galleryVisibleCount).assertEqual(6)
      expect(projection.archiverVisibleCount).assertEqual(4)
      expect(projection.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('alpha,partial,zulu')
      expect(projection.galleryTasksForGroup(1)[0].gid).assertEqual('paused')
      expect(projection.galleryTasksForGroup(2)[0].gid).assertEqual('failed')
      expect(projection.galleryTasksForGroup(3)[0].gid).assertEqual('complete')
      expect(projection.archiverTasksForGroup(0)[0].tag).assertEqual('active')
      expect(projection.archiverTasksForGroup(1)[0].tag).assertEqual('paused')
      expect(projection.archiverTasksForGroup(2)[0].tag).assertEqual('failed')
      expect(projection.archiverTasksForGroup(3)[0].tag).assertEqual('complete')

      alpha.activeBytesWritten = 1024
      expect(projection.galleryTasksForGroup(0)[0].activeBytesWritten).assertEqual(1024)
      expect(projection.galleryTasksForGroup(-1).length).assertEqual(0)
      expect(projection.archiverTasksForGroup(4).length).assertEqual(0)
      done()
    })

    it('preserves every sort mode and the existing searchable fields', 0, (done: Function) => {
      const alpha: DownloadGalleryTask = galleryTask('alpha', 'Zulu', DownloadGalleryTaskStatus.QUEUED, 10)
      alpha.category = 'Category Needle'
      const beta: DownloadGalleryTask = galleryTask('beta', 'Alpha', DownloadGalleryTaskStatus.QUEUED, 20)
      const archiver: DownloadArchiverTask = archiverTask('archive', 'Archive', DownloadGalleryTaskStatus.QUEUED, 30)
      archiver.fileName = 'target-file.cbz'

      const addedAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [beta, alpha],
        [],
        '',
        DownloadSortMode.ADDED_ASC,
      )
      const addedDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [beta, alpha],
        [],
        '',
        DownloadSortMode.ADDED_DESC,
      )
      const titleAsc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [],
        '',
        DownloadSortMode.TITLE_ASC,
      )
      const titleDesc: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [],
        '',
        DownloadSortMode.TITLE_DESC,
      )
      const gallerySearch: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [archiver],
        '  category needle  ',
        DownloadSortMode.ADDED_DESC,
      )
      const archiverSearch: DownloadQueueTaskProjection = DownloadQueueTaskProjection.build(
        [alpha, beta],
        [archiver],
        'TARGET-FILE',
        DownloadSortMode.ADDED_DESC,
      )

      expect(addedAsc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('alpha,beta')
      expect(addedDesc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('beta,alpha')
      expect(titleAsc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('beta,alpha')
      expect(titleDesc.galleryTasksForGroup(0).map((task: DownloadGalleryTask): string => task.gid).join(','))
        .assertEqual('alpha,beta')
      expect(gallerySearch.galleryVisibleCount).assertEqual(1)
      expect(gallerySearch.galleryTasksForGroup(0)[0].gid).assertEqual('alpha')
      expect(gallerySearch.archiverVisibleCount).assertEqual(0)
      expect(archiverSearch.galleryVisibleCount).assertEqual(0)
      expect(archiverSearch.archiverVisibleCount).assertEqual(1)
      expect(archiverSearch.archiverTasksForGroup(0)[0].tag).assertEqual('archive')
      done()
    })
  })
}
