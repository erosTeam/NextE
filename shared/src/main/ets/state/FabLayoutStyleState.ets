import { AppStorageV2 } from '@kit.ArkUI'

export const FAB_LAYOUT_BOTTOM: string = 'bottom'
export const FAB_LAYOUT_CENTERED: string = 'centered'
export const FAB_LAYOUT_DEFAULT: string = FAB_LAYOUT_BOTTOM

/** Gallery-detail floating action rail layout: bottom rail vs centered vertical capsule. */
@ObservedV2
export class FabLayoutStyleState {
  @Trace style: string = FAB_LAYOUT_DEFAULT
}

export function connectFabLayoutStyle(): FabLayoutStyleState {
  return AppStorageV2.connect(
    FabLayoutStyleState,
    'v2_fabLayoutStyle',
    () => new FabLayoutStyleState(),
  )!
}
