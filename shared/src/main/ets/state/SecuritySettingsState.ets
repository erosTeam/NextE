import { AppStorageV2 } from '@kit.ArkUI'

export enum AutoLockTimeout {
  DISABLED = -1,
  INSTANT = 0,
  SECONDS_30 = 30,
  MINUTES_1 = 60,
  MINUTES_5 = 300,
  MINUTES_10 = 600,
  MINUTES_30 = 1800,
  HOURS_1 = 3600,
  HOURS_5 = 18000,
}

/**
 * Security preferences mirror eros_fe's SecuritySettingPage shape. This state currently persists
 * the user's auto-lock preference only; actual lock enforcement and biometric authentication are a
 * separate feature lane because they require platform capability and lifecycle validation.
 */
@ObservedV2
export class SecuritySettingsState {
  @Trace autoLockSeconds: number = AutoLockTimeout.DISABLED
}

const SECURITY_SETTINGS_KEY: string = 'v2:securitySettings'

export function connectSecuritySettings(): SecuritySettingsState {
  return AppStorageV2.connect(
    SecuritySettingsState,
    SECURITY_SETTINGS_KEY,
    () => new SecuritySettingsState(),
  )!
}
