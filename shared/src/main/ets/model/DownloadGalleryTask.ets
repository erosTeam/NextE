import { EhGallery } from './EhGallery'
import { EhGalleryImage } from './EhGalleryImage'

export class DownloadImageSeed {
  page: number = 0
  imgkey: string = ''
  imagePageUrl: string = ''
  thumbUrl: string = ''

  static fromGalleryImage(image: EhGalleryImage): DownloadImageSeed {
    const seed: DownloadImageSeed = new DownloadImageSeed()
    seed.page = image.page
    seed.imgkey = image.imgkey
    seed.imagePageUrl = image.sUrl
    seed.thumbUrl = image.thumbUrl
    return seed
  }

  copy(): DownloadImageSeed {
    const seed: DownloadImageSeed = new DownloadImageSeed()
    seed.page = this.page
    seed.imgkey = this.imgkey
    seed.imagePageUrl = this.imagePageUrl
    seed.thumbUrl = this.thumbUrl
    return seed
  }
}

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
  preparedAt: number = 0
  firstPageCount: number = 0
  previewPageCount: number = 0
  imageSeeds: DownloadImageSeed[] = []
  prepareError: string = ''
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

  applySeedImages(images: EhGalleryImage[], previewPageCount: number): void {
    this.imageSeeds = DownloadGalleryTask.toSeeds(images)
    this.firstPageCount = this.imageSeeds.length
    this.previewPageCount = previewPageCount
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
    task.preparedAt = this.preparedAt
    task.firstPageCount = this.firstPageCount
    task.previewPageCount = this.previewPageCount
    task.imageSeeds = this.imageSeeds.map((seed: DownloadImageSeed) => seed.copy())
    task.prepareError = this.prepareError
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

  seededCount(): number {
    return this.imageSeeds.length
  }

  seedProgressText(): string {
    if (this.seededCount() === 0) {
      return ''
    }
    if (this.pageCount > 0) {
      return `${this.seededCount()}/${this.pageCount}`
    }
    return `${this.seededCount()}`
  }

  private static toSeeds(images: EhGalleryImage[]): DownloadImageSeed[] {
    const seeds: DownloadImageSeed[] = []
    images.forEach((image: EhGalleryImage) => {
      if (image.sUrl.length > 0) {
        seeds.push(DownloadImageSeed.fromGalleryImage(image))
      }
    })
    return seeds
  }
}

export class DownloadGalleryTaskStatus {
  static readonly QUEUED: string = 'queued'
  static readonly PREPARING: string = 'preparing'
  static readonly READY: string = 'ready'
  static readonly ERROR: string = 'error'
}
