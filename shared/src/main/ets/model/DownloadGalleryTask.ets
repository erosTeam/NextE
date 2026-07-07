import { EhGallery } from './EhGallery'
import { EhGalleryImage } from './EhGalleryImage'

export class DownloadImageSeed {
  page: number = 0
  imgkey: string = ''
  imagePageUrl: string = ''
  thumbUrl: string = ''
  imageUrl: string = ''
  originImageUrl: string = ''
  showKey: string = ''
  reloadKey: string = ''
  filePath: string = ''
  bytesWritten: number = 0
  downloadedAt: number = 0
  downloadError: string = ''

  static fromGalleryImage(image: EhGalleryImage): DownloadImageSeed {
    const seed: DownloadImageSeed = new DownloadImageSeed()
    seed.page = image.page
    seed.imgkey = image.imgkey
    seed.imagePageUrl = image.sUrl
    seed.thumbUrl = image.thumbUrl
    seed.imageUrl = image.imageUrl
    seed.originImageUrl = image.originImageUrl
    seed.showKey = image.showKey
    seed.reloadKey = image.reloadKey
    return seed
  }

  copy(): DownloadImageSeed {
    const seed: DownloadImageSeed = new DownloadImageSeed()
    seed.page = this.page
    seed.imgkey = this.imgkey
    seed.imagePageUrl = this.imagePageUrl
    seed.thumbUrl = this.thumbUrl
    seed.imageUrl = this.imageUrl
    seed.originImageUrl = this.originImageUrl
    seed.showKey = this.showKey
    seed.reloadKey = this.reloadKey
    seed.filePath = this.filePath
    seed.bytesWritten = this.bytesWritten
    seed.downloadedAt = this.downloadedAt
    seed.downloadError = this.downloadError
    return seed
  }
}

@ObservedV2
export class DownloadGalleryTask {
  @Trace gid: string = ''
  @Trace token: string = ''
  @Trace title: string = ''
  @Trace titleJp: string = ''
  @Trace thumbUrl: string = ''
  @Trace imgWidth: number = 0
  @Trace imgHeight: number = 0
  @Trace pageCount: number = 0
  @Trace category: string = ''
  @Trace uploader: string = ''
  @Trace upgradeFromGid: string = ''
  @Trace queuedAt: number = 0
  @Trace preparedAt: number = 0
  @Trace firstPageCount: number = 0
  @Trace previewPageCount: number = 0
  @Trace imageSeeds: DownloadImageSeed[] = []
  @Trace seededFiles: number = 0
  @Trace downloadedFiles: number = 0
  @Trace activeDownloadPage: number = 0
  @Trace activeBytesWritten: number = 0
  @Trace activeBytesTotal: number = 0
  @Trace prepareError: string = ''
  @Trace preferOriginal: boolean = false
  @Trace status: string = DownloadGalleryTaskStatus.QUEUED

  static fromGallery(gallery: EhGallery, fallbackGid: string, fallbackToken: string): DownloadGalleryTask {
    const task: DownloadGalleryTask = new DownloadGalleryTask()
    task.gid = gallery.gid.length > 0 ? gallery.gid : fallbackGid
    task.token = gallery.token.length > 0 ? gallery.token : fallbackToken
    task.title = gallery.title()
    task.titleJp = gallery.japaneseTitle
    task.thumbUrl = gallery.thumbUrl.length > 0 ? gallery.thumbUrl : gallery.thumbUrlL
    task.imgWidth = gallery.imgWidth
    task.imgHeight = gallery.imgHeight
    task.pageCount = gallery.fileCountNumber()
    task.category = gallery.category
    task.uploader = gallery.uploader
    task.upgradeFromGid = gallery.parentGid !== task.gid ? gallery.parentGid : ''
    task.queuedAt = Date.now()
    task.status = DownloadGalleryTaskStatus.QUEUED
    return task
  }

  applySeedImages(images: EhGalleryImage[], previewPageCount: number): void {
    this.imageSeeds = DownloadGalleryTask.toSeeds(images)
    this.firstPageCount = this.imageSeeds.length
    this.previewPageCount = previewPageCount
    this.syncProgressCounts()
  }

  copy(): DownloadGalleryTask {
    const task: DownloadGalleryTask = new DownloadGalleryTask()
    task.gid = this.gid
    task.token = this.token
    task.title = this.title
    task.titleJp = this.titleJp
    task.thumbUrl = this.thumbUrl
    task.imgWidth = this.imgWidth
    task.imgHeight = this.imgHeight
    task.pageCount = this.pageCount
    task.category = this.category
    task.uploader = this.uploader
    task.upgradeFromGid = this.upgradeFromGid
    task.queuedAt = this.queuedAt
    task.preparedAt = this.preparedAt
    task.firstPageCount = this.firstPageCount
    task.previewPageCount = this.previewPageCount
    task.imageSeeds = this.imageSeeds.map((seed: DownloadImageSeed) => seed.copy())
    task.seededFiles = this.seededFiles
    task.downloadedFiles = this.downloadedFiles
    task.activeDownloadPage = this.activeDownloadPage
    task.activeBytesWritten = this.activeBytesWritten
    task.activeBytesTotal = this.activeBytesTotal
    task.prepareError = this.prepareError
    task.preferOriginal = this.preferOriginal
    task.status = this.status
    task.syncProgressCounts()
    return task
  }

  assignFrom(source: DownloadGalleryTask): void {
    this.gid = source.gid
    this.token = source.token
    this.title = source.title
    this.titleJp = source.titleJp
    this.thumbUrl = source.thumbUrl
    this.imgWidth = source.imgWidth
    this.imgHeight = source.imgHeight
    this.pageCount = source.pageCount
    this.category = source.category
    this.uploader = source.uploader
    this.upgradeFromGid = source.upgradeFromGid
    this.queuedAt = source.queuedAt
    this.preparedAt = source.preparedAt
    this.firstPageCount = source.firstPageCount
    this.previewPageCount = source.previewPageCount
    this.imageSeeds = source.imageSeeds.map((seed: DownloadImageSeed) => seed.copy())
    this.seededFiles = source.seededFiles
    this.downloadedFiles = source.downloadedFiles
    this.activeDownloadPage = source.activeDownloadPage
    this.activeBytesWritten = source.activeBytesWritten
    this.activeBytesTotal = source.activeBytesTotal
    this.prepareError = source.prepareError
    this.preferOriginal = source.preferOriginal
    this.status = source.status
    this.syncProgressCounts()
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
    if (this.imageSeeds.length > 0) {
      return this.imageSeeds.length
    }
    return this.seededFiles
  }

  expectedFileCount(): number {
    return Math.max(this.pageCount, this.seededCount(), this.downloadedCount())
  }

  seedProgressText(): string {
    if (this.seededCount() === 0) {
      return ''
    }
    const total: number = this.expectedFileCount()
    if (total > 0) {
      return `${this.seededCount()}/${total}`
    }
    return `${this.seededCount()}`
  }

  downloadedCount(): number {
    if (this.imageSeeds.length > 0) {
      if (this.downloadedFiles > 0) {
        return Math.max(0, Math.min(this.downloadedFiles, this.imageSeeds.length))
      }
      return DownloadGalleryTask.countDownloadedSeeds(this.imageSeeds)
    }
    return this.downloadedFiles
  }

  isDownloadComplete(): boolean {
    const downloaded: number = this.downloadedCount()
    const total: number = this.expectedFileCount()
    if (total > 0) {
      return this.seededCount() >= total && downloaded >= total
    }
    return this.imageSeeds.length > 0 && this.pendingDownloadCount() === 0
  }

  pendingDownloadCount(): number {
    if (this.imageSeeds.length > 0 && this.downloadedFiles > 0) {
      return Math.max(0, this.seededCount() - this.downloadedFiles)
    }
    return this.imageSeeds.filter((seed: DownloadImageSeed) => {
      return seed.filePath.length === 0 && seed.imagePageUrl.length > 0
    }).length
  }

  downloadProgressText(): string {
    if (this.downloadedCount() === 0) {
      return ''
    }
    const total: number = this.expectedFileCount()
    if (total > 0) {
      return `${this.downloadedCount()}/${total}`
    }
    return `${this.downloadedCount()}`
  }

  activeDownloadRatio(): number {
    if (this.activeBytesWritten <= 0 || this.activeBytesTotal <= 0) {
      return 0
    }
    return Math.max(0, Math.min(1, this.activeBytesWritten / this.activeBytesTotal))
  }

  clearActiveDownloadProgress(): void {
    this.activeDownloadPage = 0
    this.activeBytesWritten = 0
    this.activeBytesTotal = 0
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

  syncProgressCounts(): void {
    this.seededFiles = this.imageSeeds.length
    this.downloadedFiles = DownloadGalleryTask.countDownloadedSeeds(this.imageSeeds)
  }

  private static countDownloadedSeeds(seeds: DownloadImageSeed[]): number {
    let count: number = 0
    seeds.forEach((seed: DownloadImageSeed) => {
      if (seed.filePath.length > 0 && seed.bytesWritten > 0) {
        count++
      }
    })
    return count
  }
}

export class DownloadGalleryTaskStatus {
  static readonly QUEUED: string = 'queued'
  static readonly PREPARING: string = 'preparing'
  static readonly READY: string = 'ready'
  static readonly DOWNLOADING: string = 'downloading'
  static readonly PAUSED: string = 'paused'
  static readonly PARTIAL: string = 'partial'
  static readonly COMPLETE: string = 'complete'
  static readonly ERROR: string = 'error'
}

export class DownloadArchiverParseSource {
  static readonly OFFICIAL: string = 'official'
  static readonly BOT: string = 'bot'
}

@ObservedV2
export class DownloadArchiverTask {
  @Trace tag: string = ''
  @Trace gid: string = ''
  @Trace token: string = ''
  @Trace title: string = ''
  @Trace thumbUrl: string = ''
  @Trace imgWidth: number = 0
  @Trace imgHeight: number = 0
  @Trace dltype: string = ''
  @Trace resolution: string = ''
  @Trace parseSource: string = DownloadArchiverParseSource.OFFICIAL
  @Trace url: string = ''
  @Trace fileName: string = ''
  @Trace filePath: string = ''
  @Trace queuedAt: number = 0
  @Trace downloadedAt: number = 0
  @Trace bytesWritten: number = 0
  @Trace bytesTotal: number = 0
  @Trace progress: number = 0
  @Trace error: string = ''
  @Trace status: string = DownloadGalleryTaskStatus.QUEUED

  copy(): DownloadArchiverTask {
    const task: DownloadArchiverTask = new DownloadArchiverTask()
    task.tag = this.tag
    task.gid = this.gid
    task.token = this.token
    task.title = this.title
    task.thumbUrl = this.thumbUrl
    task.imgWidth = this.imgWidth
    task.imgHeight = this.imgHeight
    task.dltype = this.dltype
    task.resolution = this.resolution
    task.parseSource = this.parseSource
    task.url = this.url
    task.fileName = this.fileName
    task.filePath = this.filePath
    task.queuedAt = this.queuedAt
    task.downloadedAt = this.downloadedAt
    task.bytesWritten = this.bytesWritten
    task.bytesTotal = this.bytesTotal
    task.progress = this.progress
    task.error = this.error
    task.status = this.status
    return task
  }

  assignFrom(source: DownloadArchiverTask): void {
    this.tag = source.tag
    this.gid = source.gid
    this.token = source.token
    this.title = source.title
    this.thumbUrl = source.thumbUrl
    this.imgWidth = source.imgWidth
    this.imgHeight = source.imgHeight
    this.dltype = source.dltype
    this.resolution = source.resolution
    this.parseSource = source.parseSource
    this.url = source.url
    this.fileName = source.fileName
    this.filePath = source.filePath
    this.queuedAt = source.queuedAt
    this.downloadedAt = source.downloadedAt
    this.bytesWritten = source.bytesWritten
    this.bytesTotal = source.bytesTotal
    this.progress = source.progress
    this.error = source.error
    this.status = source.status
  }

  displayTitle(): string {
    return this.title.length > 0 ? this.title : `#${this.gid}`
  }

  progressText(): string {
    if (this.bytesWritten <= 0) {
      return ''
    }
    if (this.bytesTotal > 0) {
      return `${this.progress}%`
    }
    return `${this.bytesWritten} B`
  }
}
