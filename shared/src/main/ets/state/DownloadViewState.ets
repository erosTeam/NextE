import { AppStorageV2 } from '@kit.ArkUI'

export enum DownloadViewType {
  GALLERY = 'gallery',
  ARCHIVER = 'archiver',
}

export class DownloadSortMode {
  static readonly ADDED_DESC: string = 'added_desc'
  static readonly ADDED_ASC: string = 'added_asc'
  static readonly TITLE_ASC: string = 'title_asc'
  static readonly TITLE_DESC: string = 'title_desc'
}

/**
 * Downloads tab queue selector. The segmented control is pinned in Index's HDS title-bar
 * bottomBuilder, while DownloadQueuePage renders the queue body in a separate component tree.
 * This V2 holder is the single channel between them.
 */
@ObservedV2
export class DownloadViewState {
  @Trace viewType: string = DownloadViewType.GALLERY
  @Trace searchActive: boolean = false
  @Trace searchText: string = ''
  @Trace sortMode: string = DownloadSortMode.ADDED_DESC
}

const DOWNLOAD_VIEW_KEY: string = 'v2:downloadView'

export function connectDownloadView(): DownloadViewState {
  return AppStorageV2.connect(DownloadViewState, DOWNLOAD_VIEW_KEY, () => new DownloadViewState())!
}

export const DOWNLOAD_SELECTOR_BAR_HEIGHT: number = 52
