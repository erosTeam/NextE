import { AppStorageV2 } from '@kit.ArkUI'

export const SCREEN_ORIENTATION_UNSPECIFIED: string = 'unspecified'
export const SCREEN_ORIENTATION_AUTO_ROTATION_UNSPECIFIED: string = 'autoRotationUnspecified'

/** Reactive preference for the main window's system-managed orientation policy. */
@ObservedV2
export class ScreenOrientationState {
  @Trace mode: string = SCREEN_ORIENTATION_UNSPECIFIED
}

const SCREEN_ORIENTATION_KEY: string = 'v2_screenOrientation'

export function connectScreenOrientation(): ScreenOrientationState {
  return AppStorageV2.connect(
    ScreenOrientationState,
    SCREEN_ORIENTATION_KEY,
    () => new ScreenOrientationState(),
  )!
}
