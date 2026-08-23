import { AppStorageV2 } from '@kit.ArkUI'

/** Persisted preference that controls the card -> GalleryDetail shared-window transition. */
@ObservedV2
export class GalleryDetailTransitionSettingsState {
  @Trace enabled: boolean = true
}

const GALLERY_DETAIL_TRANSITION_SETTINGS_KEY: string = 'v2_galleryDetailTransitionSettings'

export function connectGalleryDetailTransitionSettings(): GalleryDetailTransitionSettingsState {
  return AppStorageV2.connect(
    GalleryDetailTransitionSettingsState,
    GALLERY_DETAIL_TRANSITION_SETTINGS_KEY,
    () => new GalleryDetailTransitionSettingsState(),
  )!
}
