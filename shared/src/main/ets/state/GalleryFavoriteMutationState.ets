import { AppStorageV2 } from '@kit.ArkUI'

const GALLERY_FAVORITE_MUTATION_KEY: string = 'v2_galleryFavoriteMutation'

/**
 * App-wide signal for one gallery's EH favorite state after a protected write completes.
 * Detail owns the write, retained list/search/favorites pages consume this to update their
 * already-rendered data sources without waiting for a route reopen or full refetch.
 */
@ObservedV2
export class GalleryFavoriteMutationState {
  @Trace version: number = 0
  @Trace gid: string = ''
  @Trace favcat: string = ''
  @Trace favTitle: string = ''
  @Trace favNote: string = ''

  publish(gid: string, favcat: string, favTitle: string, favNote: string): void {
    this.gid = gid
    this.favcat = favcat
    this.favTitle = favTitle
    this.favNote = favNote
    this.version = this.version + 1
  }
}

export function connectGalleryFavoriteMutation(): GalleryFavoriteMutationState {
  return AppStorageV2.connect(
    GalleryFavoriteMutationState,
    GALLERY_FAVORITE_MUTATION_KEY,
    () => new GalleryFavoriteMutationState(),
  )!
}
