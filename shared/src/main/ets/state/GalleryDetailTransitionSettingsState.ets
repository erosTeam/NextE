import { AppStorageV2 } from '@kit.ArkUI'

export enum GalleryDetailTransitionMode {
  SYSTEM = 'system',
  SEAMLESS = 'seamless',
  COVER_EXPAND = 'coverExpand',
}

/** Persisted preference that selects the card -> GalleryDetail transition. */
@ObservedV2
export class GalleryDetailTransitionSettingsState {
  @Trace mode: string = GalleryDetailTransitionMode.SEAMLESS
}

const GALLERY_DETAIL_TRANSITION_SETTINGS_KEY: string = 'v2_galleryDetailTransitionSettings'

export function connectGalleryDetailTransitionSettings(): GalleryDetailTransitionSettingsState {
  return AppStorageV2.connect(
    GalleryDetailTransitionSettingsState,
    GALLERY_DETAIL_TRANSITION_SETTINGS_KEY,
    () => new GalleryDetailTransitionSettingsState(),
  )!
}
