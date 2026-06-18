import { EhGallery } from './EhGallery'

export class DownloadGalleryTask {
  gid: string = ''
  token: string = ''
  title: string = ''
  titleJp: string = ''
  thumbUrl: string = ''
  pageCount: number = 0
  category: string = ''
  uploader: string = ''
  queuedAt: number = 0
  status: string = DownloadGalleryTaskStatus.QUEUED

  static fromGallery(gallery: EhGallery, fallbackGid: string, fallbackToken: string): DownloadGalleryTask {
    const task: DownloadGalleryTask = new DownloadGalleryTask()
    task.gid = gallery.gid.length > 0 ? gallery.gid : fallbackGid
    task.token = gallery.token.length > 0 ? gallery.token : fallbackToken
    task.title = gallery.title()
    task.titleJp = gallery.japaneseTitle
    task.thumbUrl = gallery.thumbUrl.length > 0 ? gallery.thumbUrl : gallery.thumbUrlL
    task.pageCount = Number.parseInt(gallery.fileCount.length > 0 ? gallery.fileCount : '0', 10)
    task.category = gallery.category
    task.uploader = gallery.uploader
    task.queuedAt = Date.now()
    task.status = DownloadGalleryTaskStatus.QUEUED
    return task
  }

  copy(): DownloadGalleryTask {
    const task: DownloadGalleryTask = new DownloadGalleryTask()
    task.gid = this.gid
    task.token = this.token
    task.title = this.title
    task.titleJp = this.titleJp
    task.thumbUrl = this.thumbUrl
    task.pageCount = this.pageCount
    task.category = this.category
    task.uploader = this.uploader
    task.queuedAt = this.queuedAt
    task.status = this.status
    return task
  }

  displayTitle(): string {
    if (this.title.length > 0) {
      return this.title
    }
    if (this.titleJp.length > 0) {
      return this.titleJp
    }
    return `#${this.gid}`
  }

  pageCountText(): string {
    return this.pageCount > 0 ? `${this.pageCount}P` : ''
  }
}

export class DownloadGalleryTaskStatus {
  static readonly QUEUED: string = 'queued'
}
