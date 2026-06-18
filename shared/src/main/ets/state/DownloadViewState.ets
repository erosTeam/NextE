import { AppStorageV2 } from '@kit.ArkUI'

export enum DownloadViewType {
  GALLERY = 'gallery',
  ARCHIVER = 'archiver',
}

/**
 * Downloads tab queue selector. The segmented control is pinned in Index's HDS title-bar
 * bottomBuilder, while DownloadQueuePage renders the queue body in a separate component tree.
 * This V2 holder is the single channel between them.
 */
@ObservedV2
export class DownloadViewState {
  @Trace viewType: string = DownloadViewType.GALLERY
}

const DOWNLOAD_VIEW_KEY: string = 'v2:downloadView'

export function connectDownloadView(): DownloadViewState {
  return AppStorageV2.connect(DownloadViewState, DOWNLOAD_VIEW_KEY, () => new DownloadViewState())!
}

export const DOWNLOAD_SELECTOR_BAR_HEIGHT: number = 52
