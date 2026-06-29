import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class ImageBlockSettingsState {
  @Trace enabled: boolean = false
}

const IMAGE_BLOCK_SETTINGS_KEY: string = 'v2:imageBlockSettings'

export function connectImageBlockSettings(): ImageBlockSettingsState {
  return AppStorageV2.connect(
    ImageBlockSettingsState,
    IMAGE_BLOCK_SETTINGS_KEY,
    () => new ImageBlockSettingsState(),
  )!
}
