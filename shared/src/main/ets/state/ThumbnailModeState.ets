import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive gallery detail-preview display prefs (eros_fe ehSettingService.hideGalleryThumbnails /
 * horizontalThumbnails). Both default FALSE → the out-of-box detail preview is the inline GRID peek.
 * Restored from preferences by ThumbnailModeSettings at startup; the settings page is the only writer.
 *
 * Modes (mirrors eros_fe ThumbTile dispatch):
 *   - hideGalleryThumbnails=false, horizontalThumbnails=false → inline GRID peek + "more previews" entry
 *   - hideGalleryThumbnails=false, horizontalThumbnails=true  → horizontal row + tappable header entry
 *   - hideGalleryThumbnails=true                              → no inline previews, just the entry button
 */
@ObservedV2
export class ThumbnailModeState {
  @Trace hideGalleryThumbnails: boolean = false
  @Trace horizontalThumbnails: boolean = false
}

const THUMBNAIL_MODE_KEY: string = 'v2:thumbnailMode'

export function connectThumbnailMode(): ThumbnailModeState {
  return AppStorageV2.connect(
    ThumbnailModeState,
    THUMBNAIL_MODE_KEY,
    () => new ThumbnailModeState(),
  )!
}
