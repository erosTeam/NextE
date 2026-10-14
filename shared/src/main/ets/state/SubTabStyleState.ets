import { AppStorageV2 } from '@kit.ArkUI'

export const SUBTAB_STYLE_UNDERLINE: string = 'underline'
export const SUBTAB_STYLE_CAPSULE: string = 'capsule'

@ObservedV2
export class SubTabStyleState {
  @Trace style: string = SUBTAB_STYLE_UNDERLINE
}

export function connectSubTabStyle(): SubTabStyleState {
  return AppStorageV2.connect(
    SubTabStyleState,
    'v2_subTabStyle',
    () => new SubTabStyleState(),
  )!
}
