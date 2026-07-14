import { AppStorageV2 } from '@kit.ArkUI'

export const TABLET_LAYOUT_AUTO: string = 'auto'
export const TABLET_LAYOUT_OFF: string = 'off'
export const TABLET_LAYOUT_LANDSCAPE_ONLY: string = 'landscapeOnly'

/** Persisted user intent for adaptive large-screen layout; actual split state stays with HDS. */
@ObservedV2
export class TabletLayoutState {
  @Trace mode: string = TABLET_LAYOUT_AUTO
}

const TABLET_LAYOUT_KEY: string = 'v2_tabletLayout'

export function connectTabletLayout(): TabletLayoutState {
  return AppStorageV2.connect(
    TabletLayoutState,
    TABLET_LAYOUT_KEY,
    () => new TabletLayoutState(),
  )!
}
