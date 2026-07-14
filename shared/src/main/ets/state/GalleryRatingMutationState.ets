import { AppStorageV2 } from '@kit.ArkUI'

const GALLERY_RATING_MUTATION_KEY: string = 'v2_galleryRatingMutation'

/**
 * App-wide signal for one gallery's EH rating state after a protected write completes.
 * Retained home/search/favorites lists consume it to repaint already-rendered star rows without
 * waiting for a route reopen or full refetch.
 */
@ObservedV2
export class GalleryRatingMutationState {
  @Trace version: number = 0
  @Trace gid: string = ''
  @Trace userRating: number = 0
  @Trace averageRating: number = 0
  @Trace ratingCount: string = ''
  @Trace colorRating: string = ''

  publish(
    gid: string,
    userRating: number,
    averageRating: number,
    ratingCount: string,
    colorRating: string,
  ): void {
    this.gid = gid
    this.userRating = userRating
    this.averageRating = averageRating
    this.ratingCount = ratingCount
    this.colorRating = colorRating
    this.version = this.version + 1
  }
}

export function connectGalleryRatingMutation(): GalleryRatingMutationState {
  return AppStorageV2.connect(
    GalleryRatingMutationState,
    GALLERY_RATING_MUTATION_KEY,
    () => new GalleryRatingMutationState(),
  )!
}
