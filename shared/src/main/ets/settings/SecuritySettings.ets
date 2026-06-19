import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import {
  AutoLockTimeout,
  connectSecuritySettings,
  SecuritySettingsState,
} from '../state/SecuritySettingsState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const AUTO_LOCK_VALUES: number[] = [
  AutoLockTimeout.DISABLED,
  AutoLockTimeout.INSTANT,
  AutoLockTimeout.SECONDS_30,
  AutoLockTimeout.MINUTES_1,
  AutoLockTimeout.MINUTES_5,
  AutoLockTimeout.MINUTES_10,
  AutoLockTimeout.MINUTES_30,
  AutoLockTimeout.HOURS_1,
  AutoLockTimeout.HOURS_5,
]

function normalizeAutoLockSeconds(value: number): number {
  for (let i = 0; i < AUTO_LOCK_VALUES.length; i++) {
    if (value === AUTO_LOCK_VALUES[i]) {
      return value
    }
  }
  return AutoLockTimeout.DISABLED
}

/** Single writer for security preferences. */
export class SecuritySettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const autoLockSeconds: number = store.getSync(
        StorageKeys.SECURITY_AUTO_LOCK_SEC,
        AutoLockTimeout.DISABLED,
      ) as number
      const state: SecuritySettingsState = connectSecuritySettings()
      state.autoLockSeconds = normalizeAutoLockSeconds(autoLockSeconds)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'security_restore_failed', (error as Error).message)
    }
  }

  static async setAutoLockSeconds(
    context: common.UIAbilityContext,
    seconds: number,
  ): Promise<void> {
    const value: number = normalizeAutoLockSeconds(seconds)
    connectSecuritySettings().autoLockSeconds = value
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SECURITY_AUTO_LOCK_SEC, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'security_auto_lock_save_failed', (error as Error).message)
    }
  }

  static autoLockValues(): number[] {
    return AUTO_LOCK_VALUES
  }
}
