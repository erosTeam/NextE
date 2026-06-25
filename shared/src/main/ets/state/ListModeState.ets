import { AppStorageV2 } from '@kit.ArkUI'

/** Gallery-list render modes (eros_fe ListModeEnum). */
export enum ListMode {
  LIST = 'list', // medium rows
  SIMPLE_LIST = 'simpleList', // compact rows
  GRID = 'grid',
  WATERFALL = 'waterfall',
  COVER_WALL = 'coverWall',
}

/**
 * Reactive gallery-list view mode. Restored from preferences (ListModeSettings) at startup;
 * the list scaffold reads it to switch between List / Grid / WaterFlow renderers.
 *
 * `fixedHeight` is the orthogonal eros_fe `fixedHeightOfListItems` axis (only meaningful in LIST mode):
 * true → every list row is pinned to one portrait-cover height (uniform rhythm; title/tags clip to fit
 * above a foot-anchored meta block); false → the row grows with its content (adaptive). Default TRUE to
 * match eros_fe, whose `_fixedHeightOfListItems` defaults to true (fixed rows are the out-of-box look).
 */
@ObservedV2
export class ListModeState {
  @Trace mode: string = ListMode.LIST
  @Trace fixedHeight: boolean = true
  // Per-mode minimum column width (vp) override for the three grid-like modes, set by the pinch
  // gesture / settings slider. 0 = use the built-in base width (ThemeConstants.GALLERY_*_MIN_W).
  // Width (not column count) is stored so column count stays a derived value — auto-adapts to
  // foldable / orientation width changes instead of fixing a count that would crowd or strand cells.
  @Trace gridColW: number = 0
  @Trace waterfallColW: number = 0
  @Trace coverWallColW: number = 0

  /** Override width for a grid-like mode, or 0 when none is set. */
  overrideWidthFor(mode: string): number {
    if (mode === ListMode.GRID) {
      return this.gridColW
    }
    if (mode === ListMode.WATERFALL) {
      return this.waterfallColW
    }
    if (mode === ListMode.COVER_WALL) {
      return this.coverWallColW
    }
    return 0
  }

  /** Live (in-memory) width set used during a pinch drag; ListModeSettings persists on release. */
  setWidthFor(mode: string, width: number): void {
    if (mode === ListMode.GRID) {
      this.gridColW = width
    } else if (mode === ListMode.WATERFALL) {
      this.waterfallColW = width
    } else if (mode === ListMode.COVER_WALL) {
      this.coverWallColW = width
    }
  }
}

const LIST_MODE_KEY: string = 'v2:listMode'

export function connectListMode(): ListModeState {
  return AppStorageV2.connect(ListModeState, LIST_MODE_KEY, () => new ListModeState())!
}
