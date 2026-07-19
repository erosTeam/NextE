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
  // HDS title-bar mirror state. It intentionally carries only a stable task-group id, never a
  // rendered label or count: those derive from the live queue projection in the title builder.
  @Trace pinnedGroup: number = -1
  @Trace pinnedGroupVisible: boolean = false
  // Measured lower edge of the always-visible download selector in window coordinates. This changes
  // with HDS title-area collapse and replaces static title-bar-height assumptions in the queue.
  @Trace hdsSelectorBottomY: number = -1
  // Title-bar action bus. The title bar cannot anchor a native Menu, so DownloadQueuePage owns it.
  @Trace cmdKind: string = ''
  @Trace cmdSeq: number = 0
}

const DOWNLOAD_VIEW_KEY: string = 'v2_downloadView'

export function connectDownloadView(): DownloadViewState {
  return AppStorageV2.connect(DownloadViewState, DOWNLOAD_VIEW_KEY, () => new DownloadViewState())!
}

export const DOWNLOAD_SELECTOR_BAR_HEIGHT: number = 52
