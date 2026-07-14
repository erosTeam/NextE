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
 * Security preferences mirror eros_fe's SecuritySettingPage shape. Runtime lock fields live here too
 * so the root shell can cover content while native user authentication is pending.
 */
@ObservedV2
export class SecuritySettingsState {
  @Trace recentTasksProtectionEnabled: boolean = false
  @Trace autoLockSeconds: number = AutoLockTimeout.DISABLED
  @Trace lastBackgroundAt: number = 0
  @Trace locked: boolean = false
  @Trace authenticating: boolean = false
  @Trace authError: string = ''
}

const SECURITY_SETTINGS_KEY: string = 'v2_securitySettings'

export function connectSecuritySettings(): SecuritySettingsState {
  return AppStorageV2.connect(
    SecuritySettingsState,
    SECURITY_SETTINGS_KEY,
    () => new SecuritySettingsState(),
  )!
}
