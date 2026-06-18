import { AppStorageV2 } from '@kit.ArkUI'
import { DownloadGalleryTask } from '../model/DownloadGalleryTask'

/**
 * Local gallery download queue. This is intentionally only queue state: the background image
 * downloader and archive submitter are separate lanes, so detail-page enqueue stays non-destructive.
 */
@ObservedV2
export class DownloadQueueState {
  @Trace galleryTasks: DownloadGalleryTask[] = []
}

const DOWNLOAD_QUEUE_KEY: string = 'v2:downloadQueue'

export function connectDownloadQueue(): DownloadQueueState {
  return AppStorageV2.connect(DownloadQueueState, DOWNLOAD_QUEUE_KEY, () => new DownloadQueueState())!
}
