import { AppStorageV2 } from '@kit.ArkUI'

/** Gallery-list render modes (eros_fe ListModeEnum). */
export enum ListMode {
  LIST = 'list', // medium rows
  SIMPLE_LIST = 'simpleList', // compact rows
  GRID = 'grid',
  WATERFALL = 'waterfall',
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
}

const LIST_MODE_KEY: string = 'v2:listMode'

export function connectListMode(): ListModeState {
  return AppStorageV2.connect(ListModeState, LIST_MODE_KEY, () => new ListModeState())!
}
