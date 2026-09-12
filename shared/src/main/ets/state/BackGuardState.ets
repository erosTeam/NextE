import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Home back-guard (eros_fe tabhome_controller.doubleClickBack): on the gallery tab with an empty
 * nav stack, the first back press shows a toast and the second within one second exits the app.
 * Defaults ON. Restored from preferences at startup by BackGuardSettings (SettingsBootstrap);
 * the advanced settings page is the only writer.
 */
@ObservedV2
export class BackGuardState {
  @Trace enabled: boolean = true
}

const BACK_GUARD_STATE_V2_KEY: string = 'v2_backGuard'

export function connectBackGuard(): BackGuardState {
  return AppStorageV2.connect(BackGuardState, BACK_GUARD_STATE_V2_KEY, () => new BackGuardState())!
}
