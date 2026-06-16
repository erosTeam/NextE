import { AppStorageV2 } from '@kit.ArkUI'

/**
 * App-wide window safe-area / keyboard layout metrics, owned by `AppStorageV2`.
 *
 * `EntryAbility` is the single writer: it observes the window avoid areas and the
 * soft-keyboard height and publishes them through `LayoutSafeAreaBridge`. `@ComponentV2`
 * consumers read these `@Trace` fields via `connectLayoutSafeArea()`, so any change
 * re-renders the subscribed components.
 *
 * History: these metrics used to be dual-written into the legacy V1 `AppStorage`
 * (`topAvoidHeight` / `bottomAvoidHeight` / `keyboardHeight`) for `@StorageProp` readers.
 * Every reader has since moved to V2, so the V1 `AppStorage` half was retired and this
 * object is now the sole source of truth. Do not reintroduce the `AppStorage` writes.
 */
@ObservedV2
export class LayoutSafeAreaState {
  @Trace topAvoidHeight: number = 0
  @Trace bottomAvoidHeight: number = 0
  @Trace keyboardHeight: number = 0
}

// Single app-wide AppStorageV2 key for the shared safe-area state object.
const LAYOUT_SAFE_AREA_V2_KEY: string = 'v2:layoutSafeArea'

/**
 * Returns the app-wide `LayoutSafeAreaState` singleton from `AppStorageV2`, creating
 * it (zeroed) on first access. Reading its `@Trace` fields inside a `@ComponentV2`
 * `build()` subscribes that component to safe-area / keyboard changes.
 */
export function connectLayoutSafeArea(): LayoutSafeAreaState {
  return AppStorageV2.connect(
    LayoutSafeAreaState,
    LAYOUT_SAFE_AREA_V2_KEY,
    () => new LayoutSafeAreaState(),
  )!
}

/**
 * The single publish point for layout metrics. `EntryAbility` calls these to push the
 * latest window insets / keyboard height into the shared `LayoutSafeAreaState`, which
 * fans the change out to every `@ComponentV2` consumer. (Formerly a V1->V2 dual-write
 * bridge; the V1 `AppStorage` half was retired, so it now publishes to V2 only.)
 */
export class LayoutSafeAreaBridge {
  static publishInsets(topAvoidHeight: number, bottomAvoidHeight: number): void {
    const state = connectLayoutSafeArea()
    if (state.topAvoidHeight !== topAvoidHeight) {
      state.topAvoidHeight = topAvoidHeight
    }
    if (state.bottomAvoidHeight !== bottomAvoidHeight) {
      state.bottomAvoidHeight = bottomAvoidHeight
    }
  }

  static publishKeyboardHeight(keyboardHeight: number): void {
    const state = connectLayoutSafeArea()
    if (state.keyboardHeight !== keyboardHeight) {
      state.keyboardHeight = keyboardHeight
    }
  }
}
