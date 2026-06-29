import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class ImageBlockRuntimeState {
  @Trace signal: string = ''
}

const IMAGE_BLOCK_RUNTIME_KEY: string = 'v2:imageBlockRuntime'

export function connectImageBlockRuntime(): ImageBlockRuntimeState {
  return AppStorageV2.connect(ImageBlockRuntimeState, IMAGE_BLOCK_RUNTIME_KEY, () => new ImageBlockRuntimeState())!
}

export function publishImageBlockRulesChanged(reason: string): void {
  connectImageBlockRuntime().signal = `${Date.now()}:${reason}`
}
