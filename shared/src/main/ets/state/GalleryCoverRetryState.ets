import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Explicit retry signal for gallery covers whose URL did not change across a list refresh.
 * Successful covers ignore the signal; failed or still-pending EhThumbnail instances restart
 * their ImageKnife request without changing the URL, cache signature, or LazyForEach key.
 */
@ObservedV2
export class GalleryCoverRetryState {
  @Trace epoch: number = 0
}

// EhThumbnail connects this state for every visible cover; AppStorageV2 keys cannot contain colons.
const GALLERY_COVER_RETRY_KEY: string = 'v2_galleryCoverRetry'

export function connectGalleryCoverRetry(): GalleryCoverRetryState {
  return AppStorageV2.connect(
    GalleryCoverRetryState,
    GALLERY_COVER_RETRY_KEY,
    () => new GalleryCoverRetryState(),
  )!
}

export function requestGalleryCoverRetry(): void {
  const state: GalleryCoverRetryState = connectGalleryCoverRetry()
  state.epoch += 1
}
