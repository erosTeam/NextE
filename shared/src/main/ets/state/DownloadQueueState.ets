import { AppStorageV2 } from '@kit.ArkUI'
import { DownloadArchiverTask, DownloadGalleryTask } from '../model/DownloadGalleryTask'

/**
 * Local gallery download queue. This is intentionally only queue state: the background image
 * downloader and archive submitter are separate lanes, so detail-page enqueue stays non-destructive.
 */
@ObservedV2
export class DownloadQueueState {
  @Trace revision: number = 0
  @Trace galleryTasks: DownloadGalleryTask[] = []
  @Trace archiverTasks: DownloadArchiverTask[] = []

  replaceGalleryTasks(tasks: DownloadGalleryTask[]): void {
    this.galleryTasks = tasks
    this.bumpRevision()
  }

  replaceArchiverTasks(tasks: DownloadArchiverTask[]): void {
    this.archiverTasks = tasks
    this.bumpRevision()
  }

  bumpRevision(): void {
    this.revision = this.revision + 1
    publishDownloadQueueChanged()
  }
}

@ObservedV2
export class DownloadQueueSignalState {
  @Trace version: number = 0
}

const DOWNLOAD_QUEUE_KEY: string = 'v2_downloadQueue'
const DOWNLOAD_QUEUE_SIGNAL_KEY: string = 'v2_downloadQueueSignal'
let sharedDownloadQueueState: DownloadQueueState | null = null
let downloadQueuePageActive: boolean = false

export function connectDownloadQueue(): DownloadQueueState {
  if (sharedDownloadQueueState === null) {
    sharedDownloadQueueState = AppStorageV2.connect(
      DownloadQueueState,
      DOWNLOAD_QUEUE_KEY,
      () => new DownloadQueueState(),
    )!
  }
  return sharedDownloadQueueState
}

export function connectDownloadQueueSignal(): DownloadQueueSignalState {
  return AppStorageV2.connect(
    DownloadQueueSignalState,
    DOWNLOAD_QUEUE_SIGNAL_KEY,
    () => new DownloadQueueSignalState(),
  )!
}

export function publishDownloadQueueChanged(): void {
  const signal: DownloadQueueSignalState = connectDownloadQueueSignal()
  signal.version = signal.version + 1
}

export function setDownloadQueuePageActive(active: boolean): void {
  if (downloadQueuePageActive === active) {
    return
  }
  downloadQueuePageActive = active
  if (active) {
    publishDownloadQueueChanged()
  }
}

export function isDownloadQueuePageActive(): boolean {
  return downloadQueuePageActive
}
