import { AppStorageV2 } from '@kit.ArkUI'
import { EhGallery } from '../model/EhGallery'
import { EhGalleryComment } from '../model/EhGalleryComment'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { GalleryDetailResult } from '../network/EhApiService'
import { EhPageCacheService } from '../services/EhPageCacheService'

const GALLERY_DETAIL_REFRESH_MUTATION_KEY: string = 'v2_galleryDetailRefreshMutation'

/**
 * Carries one authoritative full-detail response from a child surface back to the retained detail page.
 * The payload is copied before publication and version is written last, so consumers never observe a
 * gallery header paired with stale previews/comments from the previous refresh.
 */
@ObservedV2
export class GalleryDetailRefreshMutationState {
  @Trace version: number = 0
  @Trace gid: string = ''
  @Trace token: string = ''
  @Trace isEx: boolean = false
  @Trace gallery: EhGallery = new EhGallery()
  @Trace images: EhGalleryImage[] = []
  @Trace comments: EhGalleryComment[] = []
  @Trace previewPageCount: number = 1

  publish(gid: string, token: string, isEx: boolean, detail: GalleryDetailResult): void {
    const snapshot: GalleryDetailResult = EhPageCacheService.copyGalleryDetail(detail)
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.gallery = snapshot.gallery
    this.images = snapshot.images
    this.comments = snapshot.comments
    this.previewPageCount = snapshot.previewPageCount
    this.version = this.version + 1
  }

  snapshot(): GalleryDetailResult {
    return EhPageCacheService.copyGalleryDetail(new GalleryDetailResult(
      this.gallery,
      this.images,
      this.comments,
      this.previewPageCount,
    ))
  }
}

export function connectGalleryDetailRefreshMutation(): GalleryDetailRefreshMutationState {
  return AppStorageV2.connect(
    GalleryDetailRefreshMutationState,
    GALLERY_DETAIL_REFRESH_MUTATION_KEY,
    () => new GalleryDetailRefreshMutationState(),
  )!
}
