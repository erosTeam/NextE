import { AppStorageV2 } from '@kit.ArkUI'

/** Gallery-list render modes (eros_fe ListModeEnum). */
export enum ListMode {
  LIST = 'list',           // medium rows
  SIMPLE_LIST = 'simpleList', // compact rows
  GRID = 'grid',
  WATERFALL = 'waterfall',
}

/**
 * Reactive gallery-list view mode. Restored from preferences (ListModeSettings) at startup;
 * the list scaffold reads it to switch between List / Grid / WaterFlow renderers.
 */
@ObservedV2
export class ListModeState {
  @Trace mode: string = ListMode.LIST
}

const LIST_MODE_KEY: string = 'v2:listMode'

export function connectListMode(): ListModeState {
  return AppStorageV2.connect(ListModeState, LIST_MODE_KEY, () => new ListModeState())!
}
