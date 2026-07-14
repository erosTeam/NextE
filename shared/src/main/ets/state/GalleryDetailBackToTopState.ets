import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Owners that can receive the system status-bar back-to-top action while a wide
 * gallery-detail workspace shows all three scrollable panes.
 */
export const GALLERY_DETAIL_BACK_TO_TOP_PRIMARY: string = 'primary'
export const GALLERY_DETAIL_BACK_TO_TOP_METADATA: string = 'metadata'
export const GALLERY_DETAIL_BACK_TO_TOP_THUMBNAILS: string = 'thumbnails'

/**
 * Runtime-only coordinator for the wide gallery-detail workspace.
 *
 * ArkUI dispatches a status-bar tap to every eligible vertical scrollable. The
 * workspace instead grants that native behavior to one pane at a time. A
 * NavDestination id is the session token: an outgoing detail can never clear a
 * replacement detail that has already become active.
 */
@ObservedV2
export class GalleryDetailBackToTopState {
  @Trace activeDestinationId: string = ''
  @Trace activeOwner: string = ''

  begin(destinationId: string): void {
    if (destinationId.length === 0 || this.activeDestinationId === destinationId) {
      return
    }
    this.activeDestinationId = destinationId
    // Do not invent a target before the user scrolls one of the visible panes.
    // This protects the primary list's retained position on first entry.
    this.activeOwner = ''
  }

  end(destinationId: string): void {
    if (destinationId.length === 0 || this.activeDestinationId !== destinationId) {
      return
    }
    this.activeDestinationId = ''
    this.activeOwner = ''
  }

  selectPrimary(): void {
    if (this.activeDestinationId.length === 0 || this.activeOwner === GALLERY_DETAIL_BACK_TO_TOP_PRIMARY) {
      return
    }
    this.activeOwner = GALLERY_DETAIL_BACK_TO_TOP_PRIMARY
  }

  selectDetailOwner(destinationId: string, owner: string): void {
    if (
      destinationId.length === 0 ||
      this.activeDestinationId !== destinationId ||
      (owner !== GALLERY_DETAIL_BACK_TO_TOP_METADATA && owner !== GALLERY_DETAIL_BACK_TO_TOP_THUMBNAILS) ||
      this.activeOwner === owner
    ) {
      return
    }
    this.activeOwner = owner
  }

  primaryEnabled(): boolean {
    if (this.activeDestinationId.length === 0) {
      return true
    }
    return this.activeOwner === GALLERY_DETAIL_BACK_TO_TOP_PRIMARY
  }

  detailEnabled(destinationId: string, owner: string): boolean {
    if (this.activeDestinationId.length === 0) {
      return true
    }
    return this.activeDestinationId === destinationId && this.activeOwner === owner
  }
}

const GALLERY_DETAIL_BACK_TO_TOP_KEY: string = 'v2_galleryDetailBackToTop'

/** Returns the app-wide, non-persistent wide-detail back-to-top coordinator. */
export function connectGalleryDetailBackToTop(): GalleryDetailBackToTopState {
  return AppStorageV2.connect(
    GalleryDetailBackToTopState,
    GALLERY_DETAIL_BACK_TO_TOP_KEY,
    () => new GalleryDetailBackToTopState(),
  )!
}
