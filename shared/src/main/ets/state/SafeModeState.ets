import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class SafeModeState {
  @Trace buildEnabled: boolean = false
  @Trace unlocked: boolean = false

  restricted(): boolean {
    return this.buildEnabled && !this.unlocked
  }
}

const SAFE_MODE_STATE_KEY: string = 'v2_safeMode'

export function connectSafeMode(): SafeModeState {
  return AppStorageV2.connect(
    SafeModeState,
    SAFE_MODE_STATE_KEY,
    () => new SafeModeState(),
  )!
}
