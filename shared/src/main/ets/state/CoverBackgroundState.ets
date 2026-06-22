import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive cover-background preference (eros_fe ehSettingService.blurringOfCoverBackground). Controls how an
 * off-aspect (Contain-fitted) gallery cover fills its letterbox gaps in the list / grid / waterfall:
 *   - false (default) → a vertical gradient from the cover's extracted dominant color, fading to transparent
 *     so it blends into the card surface (cheap: a one-time color extraction + a GPU gradient fill)
 *   - true            → a blurred Cover copy of the same cover image (heavier real-time blur, opt-in)
 *
 * Restored from preferences by CoverBackgroundSettings at startup (SettingsBootstrap); the settings page is
 * the only writer. Only the close-vs-far fit decision is unconditional — this preference just picks the fill.
 */
@ObservedV2
export class CoverBackgroundState {
  @Trace blurringOfCoverBackground: boolean = false
}

const COVER_BACKGROUND_KEY: string = 'v2:coverBackground'

export function connectCoverBackground(): CoverBackgroundState {
  return AppStorageV2.connect(
    CoverBackgroundState,
    COVER_BACKGROUND_KEY,
    () => new CoverBackgroundState(),
  )!
}
