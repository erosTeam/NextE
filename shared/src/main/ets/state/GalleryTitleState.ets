import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Detail title display preference, mirroring eros_fe `jpnTitleInGalleryPage`.
 * false: English/Romanized title is primary, Japanese title is secondary.
 * true: Japanese title is primary when present, English/Romanized title is secondary.
 */
@ObservedV2
export class GalleryTitleState {
  @Trace japaneseTitleInGalleryPage: boolean = false
}

const GALLERY_TITLE_KEY: string = 'v2:galleryTitle'

export function connectGalleryTitle(): GalleryTitleState {
  return AppStorageV2.connect(GalleryTitleState, GALLERY_TITLE_KEY, () => new GalleryTitleState())!
}
