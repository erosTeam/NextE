import { EhGalleryImage } from 'shared'

/**
 * Immutable ownership token for one Reader image-source request.
 *
 * A page can change source while an older `/s/` resolve, disk load, or image-block decision is still
 * in flight. Snapshot the source inputs so that old work cannot borrow a newly selected cache key or
 * merge its metadata into the newer page state.
 */
export class ReaderImageSourceRequest {
  epoch: number
  image: EhGalleryImage
  imageKey: string
  fileCacheKey: string
  preferOriginal: boolean

  constructor(
    epoch: number,
    image: EhGalleryImage,
    imageKey: string,
    fileCacheKey: string,
    preferOriginal: boolean,
  ) {
    this.epoch = epoch
    this.image = image.copy()
    this.imageKey = imageKey
    this.fileCacheKey = fileCacheKey
    this.preferOriginal = preferOriginal
  }
}

/** Per-component generation fence for source resolution and the durable Reader file cache. */
export class ReaderImageSourceRequestGate {
  private epoch: number = 0

  begin(
    image: EhGalleryImage,
    imageKey: string,
    fileCacheKey: string,
    preferOriginal: boolean,
  ): ReaderImageSourceRequest {
    this.epoch = this.epoch + 1
    return new ReaderImageSourceRequest(
      this.epoch,
      image,
      imageKey,
      fileCacheKey,
      preferOriginal,
    )
  }

  invalidate(): void {
    this.epoch = this.epoch + 1
  }

  isCurrent(
    request: ReaderImageSourceRequest,
    imageKey: string,
    fileCacheKey: string,
    preferOriginal: boolean,
  ): boolean {
    return request.epoch === this.epoch &&
      request.imageKey === imageKey &&
      request.fileCacheKey === fileCacheKey &&
      request.preferOriginal === preferOriginal
  }

  /** Merge only resolver-owned fields after the request is still current. */
  commitResolvedImage(
    request: ReaderImageSourceRequest,
    target: EhGalleryImage,
    imageKey: string,
    fileCacheKey: string,
    preferOriginal: boolean,
  ): boolean {
    if (!this.isCurrent(request, imageKey, fileCacheKey, preferOriginal)) {
      return false
    }
    target.imageUrl = request.image.imageUrl
    target.originImageUrl = request.image.originImageUrl
    target.showKey = request.image.showKey
    target.reloadKey = request.image.reloadKey
    return true
  }
}
