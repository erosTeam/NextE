import { AppStorageV2 } from '@kit.ArkUI'

/**
 * App-wide window safe-area / keyboard layout metrics, owned by `AppStorageV2`.
 *
 * `EntryAbility` is the single writer: it observes the main-window size, window avoid areas, and the
 * soft-keyboard height and publishes them through `LayoutSafeAreaBridge`. `@ComponentV2` consumers
 * read these `@Trace` fields via `connectLayoutSafeArea()`, so any change re-renders the subscribed
 * components.
 *
 * History: these metrics used to be dual-written into the legacy V1 `AppStorage`
 * (`topAvoidHeight` / `bottomAvoidHeight` / `keyboardHeight`) for `@StorageProp` readers.
 * Every reader has since moved to V2, so the V1 `AppStorage` half was retired and this
 * object is now the sole source of truth. Do not reintroduce the `AppStorage` writes.
 */
@ObservedV2
export class LayoutSafeAreaState {
  // Main-window snapshot/event dimensions in px. These are used only for aspect comparisons; 0 = unknown.
  @Trace mainWindowWidthPx: number = 0
  @Trace mainWindowHeightPx: number = 0
  @Trace topAvoidHeight: number = 0
  @Trace bottomAvoidHeight: number = 0
  @Trace keyboardHeight: number = 0
  // Last measured gallery list content width (vp), cached so a remounting WaterFlow can compute its column
  // count on the FIRST frame instead of falling back to a fixed default. Written by the list scaffolds
  // (onAreaChange) and invalidated to 0 by EntryAbility on window-size change (fold/unfold, rotation,
  // split-screen) so a stale pre-fold width never sticks. 0 = unknown.
  @Trace galleryContentWidth: number = 0
  // A GalleryDetail destination is recreated after pop/push, but its available width does not become
  // unknown merely because the page instance is new. Keep the last resolved destination width for each
  // root Navigation mode so repeat opens can select the correct compact/split detail layout immediately.
  // EntryAbility invalidates both values only when the real window size changes.
  @Trace galleryDetailStackContentWidth: number = 0
  @Trace galleryDetailSplitContentWidth: number = 0

  rememberedGalleryDetailContentWidth(rootNavigationSplit: boolean): number {
    return rootNavigationSplit
      ? this.galleryDetailSplitContentWidth
      : this.galleryDetailStackContentWidth
  }
}

// Single app-wide AppStorageV2 key for the shared safe-area state object.
const LAYOUT_SAFE_AREA_V2_KEY: string = 'v2_layoutSafeArea'

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
  static publishMainWindowSizePx(widthPx: number, heightPx: number): void {
    const state = connectLayoutSafeArea()
    const normalizedWidth: number = Math.max(0, widthPx)
    const normalizedHeight: number = Math.max(0, heightPx)
    if (state.mainWindowWidthPx !== normalizedWidth) {
      state.mainWindowWidthPx = normalizedWidth
    }
    if (state.mainWindowHeightPx !== normalizedHeight) {
      state.mainWindowHeightPx = normalizedHeight
    }
  }

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

  // Cache the last measured gallery content width (or pass 0 to invalidate on window-size change).
  static publishGalleryContentWidth(width: number): void {
    const state = connectLayoutSafeArea()
    if (state.galleryContentWidth !== width) {
      state.galleryContentWidth = width
    }
  }

  static publishGalleryDetailContentWidth(width: number, rootNavigationSplit: boolean): void {
    const state = connectLayoutSafeArea()
    const normalizedWidth: number = Math.max(0, width)
    if (rootNavigationSplit) {
      if (state.galleryDetailSplitContentWidth !== normalizedWidth) {
        state.galleryDetailSplitContentWidth = normalizedWidth
      }
      return
    }
    if (state.galleryDetailStackContentWidth !== normalizedWidth) {
      state.galleryDetailStackContentWidth = normalizedWidth
    }
  }

  static invalidateGalleryDetailContentWidths(): void {
    const state = connectLayoutSafeArea()
    if (state.galleryDetailStackContentWidth !== 0) {
      state.galleryDetailStackContentWidth = 0
    }
    if (state.galleryDetailSplitContentWidth !== 0) {
      state.galleryDetailSplitContentWidth = 0
    }
  }
}
