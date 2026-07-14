import { AppStorageV2 } from '@kit.ArkUI'

export const READ_BUTTON_STYLE_FILLED: string = 'filled'
export const READ_BUTTON_STYLE_HDS: string = 'hds'

/** Reactive style for the gallery-detail floating Read button. */
@ObservedV2
export class ReadButtonStyleState {
  @Trace style: string = READ_BUTTON_STYLE_FILLED
}

const READ_BUTTON_STYLE_KEY: string = 'v2_readButtonStyle'

export function connectReadButtonStyle(): ReadButtonStyleState {
  return AppStorageV2.connect(
    ReadButtonStyleState,
    READ_BUTTON_STYLE_KEY,
    () => new ReadButtonStyleState(),
  )!
}
