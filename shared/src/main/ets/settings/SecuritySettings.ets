import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { userAuth } from '@kit.UserAuthenticationKit'
import {
  AutoLockTimeout,
  connectSecuritySettings,
  SecuritySettingsState,
} from '../state/SecuritySettingsState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { AppStrings } from '../i18n/AppStrings'

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
const BIOMETRIC_PERMISSION: Permissions = 'ohos.permission.ACCESS_BIOMETRIC'
const AUTH_UNAVAILABLE: number = -1

interface AuthCandidate {
  authTypes: userAuth.UserAuthType[]
  authTrustLevel: userAuth.AuthTrustLevel
}

const AUTH_CANDIDATES: AuthCandidate[] = [
  {
    authTypes: [userAuth.UserAuthType.FACE, userAuth.UserAuthType.PIN],
    authTrustLevel: userAuth.AuthTrustLevel.ATL3,
  },
  {
    authTypes: [userAuth.UserAuthType.FINGERPRINT],
    authTrustLevel: userAuth.AuthTrustLevel.ATL1,
  },
  {
    authTypes: [userAuth.UserAuthType.FACE],
    authTrustLevel: userAuth.AuthTrustLevel.ATL1,
  },
]

export enum SecurityAuthResult {
  SUCCESS,
  FAILED,
  UNAVAILABLE,
}

function normalizeAutoLockSeconds(value: number): number {
  for (let i = 0; i < AUTO_LOCK_VALUES.length; i++) {
    if (value === AUTO_LOCK_VALUES[i]) {
      return value
    }
  }
  return AutoLockTimeout.DISABLED
}

type WindowPrivacyApplier = (enabled: boolean) => void
let windowPrivacyApplier: WindowPrivacyApplier | null = null

/** Single writer for security preferences. */
export class SecuritySettings {
  static bindWindowPrivacyApplier(applier: WindowPrivacyApplier): void {
    windowPrivacyApplier = applier
    SecuritySettings.applyWindowPrivacy()
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const recentTasksProtection: boolean = store.getSync(
        StorageKeys.SECURITY_RECENT_TASKS_PROTECTION,
        false,
      ) as boolean
      const autoLockSeconds: number = store.getSync(
        StorageKeys.SECURITY_AUTO_LOCK_SEC,
        AutoLockTimeout.DISABLED,
      ) as number
      const lastBackgroundAt: number = store.getSync(
        StorageKeys.SECURITY_LAST_BACKGROUND_AT,
        0,
      ) as number
      const state: SecuritySettingsState = connectSecuritySettings()
      state.recentTasksProtectionEnabled = recentTasksProtection
      state.autoLockSeconds = normalizeAutoLockSeconds(autoLockSeconds)
      state.lastBackgroundAt = lastBackgroundAt
      SecuritySettings.applyWindowPrivacy()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'security_restore_failed', (error as Error).message)
    }
  }

  static async setRecentTasksProtection(
    context: common.UIAbilityContext,
    enabled: boolean,
  ): Promise<void> {
    connectSecuritySettings().recentTasksProtectionEnabled = enabled
    SecuritySettings.applyWindowPrivacy()
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SECURITY_RECENT_TASKS_PROTECTION, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'security_recent_tasks_save_failed', (error as Error).message)
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

  static async setAutoLockSecondsWithBoundaryAuth(
    context: common.UIAbilityContext,
    seconds: number,
  ): Promise<SecurityAuthResult> {
    const value: number = normalizeAutoLockSeconds(seconds)
    const current: number = connectSecuritySettings().autoLockSeconds
    if (current === value) {
      return SecurityAuthResult.SUCCESS
    }
    const crossesEnabledBoundary: boolean =
      (current === AutoLockTimeout.DISABLED) !== (value === AutoLockTimeout.DISABLED)
    if (crossesEnabledBoundary) {
      const authResult: SecurityAuthResult = await SecuritySettings.authenticate(context)
      if (authResult !== SecurityAuthResult.SUCCESS) {
        return authResult
      }
    }
    await SecuritySettings.setAutoLockSeconds(context, value)
    return SecurityAuthResult.SUCCESS
  }

  static async recordBackground(context: common.UIAbilityContext): Promise<void> {
    const state: SecuritySettingsState = connectSecuritySettings()
    if (state.locked) {
      return
    }
    const now: number = Date.now()
    state.lastBackgroundAt = now
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SECURITY_LAST_BACKGROUND_AT, now)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'security_background_save_failed', (error as Error).message)
    }
  }

  static async lockIfNeeded(context: common.UIAbilityContext, reason: string): Promise<void> {
    const state: SecuritySettingsState = connectSecuritySettings()
    if (!SecuritySettings.shouldLock(state)) {
      return
    }
    await SecuritySettings.unlockNow(context, reason)
  }

  static async unlockNow(context: common.UIAbilityContext, reason: string): Promise<void> {
    const state: SecuritySettingsState = connectSecuritySettings()
    if (state.autoLockSeconds === AutoLockTimeout.DISABLED || state.authenticating) {
      return
    }
    state.locked = true
    state.authenticating = true
    state.authError = ''
    SecuritySettings.applyWindowPrivacy()
    DiagnosticLogger.info('security', 'auth_start', reason)
    const result: SecurityAuthResult = await SecuritySettings.authenticate(context)
    state.authenticating = false
    if (result === SecurityAuthResult.SUCCESS) {
      state.locked = false
      state.authError = ''
      state.lastBackgroundAt = Date.now()
      SecuritySettings.applyWindowPrivacy()
      await SecuritySettings.persistLastBackgroundAt(context, state.lastBackgroundAt)
      DiagnosticLogger.info('security', 'auth_success', reason)
      return
    }
    if (result === SecurityAuthResult.UNAVAILABLE) {
      state.locked = false
      state.authError = ''
      state.autoLockSeconds = AutoLockTimeout.DISABLED
      SecuritySettings.applyWindowPrivacy()
      await SecuritySettings.setAutoLockSeconds(context, AutoLockTimeout.DISABLED)
      DiagnosticLogger.warn('security', 'auth_unavailable_unlock', reason)
      return
    }
    state.authError = AppStrings.get('security_unlock_failed')
    SecuritySettings.applyWindowPrivacy()
    DiagnosticLogger.warn('security', 'auth_failed', reason)
  }

  static autoLockValues(): number[] {
    return AUTO_LOCK_VALUES
  }

  private static shouldLock(state: SecuritySettingsState): boolean {
    if (state.autoLockSeconds === AutoLockTimeout.DISABLED || state.authenticating) {
      return false
    }
    if (state.locked) {
      return true
    }
    if (state.lastBackgroundAt <= 0) {
      return false
    }
    if (state.autoLockSeconds === AutoLockTimeout.INSTANT) {
      return true
    }
    const elapsedMs: number = Date.now() - state.lastBackgroundAt
    return elapsedMs >= state.autoLockSeconds * 1000
  }

  private static applyWindowPrivacy(): void {
    if (windowPrivacyApplier === null) {
      return
    }
    const state: SecuritySettingsState = connectSecuritySettings()
    windowPrivacyApplier(state.recentTasksProtectionEnabled || state.locked)
  }

  private static async persistLastBackgroundAt(
    context: common.UIAbilityContext,
    value: number,
  ): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.SECURITY_LAST_BACKGROUND_AT, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'security_unlock_save_failed', (error as Error).message)
    }
  }

  private static async ensureBiometricPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const result = await at.requestPermissionsFromUser(context, [BIOMETRIC_PERMISSION])
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0
      DiagnosticLogger.info('security', 'biometric_permission', `granted=${granted}`)
      return granted
    } catch (error) {
      DiagnosticLogger.warn('security', 'biometric_permission_failed', (error as Error).message)
      return false
    }
  }

  private static availableAuthCandidate(): AuthCandidate | null {
    for (let i = 0; i < AUTH_CANDIDATES.length; i++) {
      const candidate: AuthCandidate = AUTH_CANDIDATES[i]
      const types: userAuth.UserAuthType[] = []
      for (let j = 0; j < candidate.authTypes.length; j++) {
        SecuritySettings.pushAvailableAuthType(types, candidate.authTypes[j], candidate.authTrustLevel)
      }
      if (types.length > 0) {
        return {
          authTypes: types,
          authTrustLevel: candidate.authTrustLevel,
        }
      }
    }
    return null
  }

  private static pushAvailableAuthType(
    types: userAuth.UserAuthType[],
    type: userAuth.UserAuthType,
    trustLevel: userAuth.AuthTrustLevel,
  ): void {
    try {
      userAuth.getAvailableStatus(type, trustLevel)
      DiagnosticLogger.info('security', 'auth_type_available', `${type}@${trustLevel}`)
      types.push(type)
    } catch (error) {
      DiagnosticLogger.info('security', 'auth_type_unavailable', `${type}@${trustLevel}: ${(error as Error).message}`)
    }
  }

  private static async authenticate(context: common.UIAbilityContext): Promise<SecurityAuthResult> {
    if (!await SecuritySettings.ensureBiometricPermission(context)) {
      return SecurityAuthResult.UNAVAILABLE
    }
    const authCandidate: AuthCandidate | null = SecuritySettings.availableAuthCandidate()
    if (authCandidate === null) {
      DiagnosticLogger.warn('security', 'auth_unavailable', 'no enrolled auth type')
      return SecurityAuthResult.UNAVAILABLE
    }
    const result: number = await SecuritySettings.startAuthentication(authCandidate)
    if (result === AUTH_UNAVAILABLE) {
      return SecurityAuthResult.UNAVAILABLE
    }
    return result === userAuth.UserAuthResultCode.SUCCESS ? SecurityAuthResult.SUCCESS : SecurityAuthResult.FAILED
  }

  private static startAuthentication(authCandidate: AuthCandidate): Promise<number> {
    return new Promise<number>((resolve: (value: number) => void): void => {
      try {
        const random = cryptoFramework.createRandom()
        const authParam: userAuth.AuthParam = {
          challenge: random.generateRandomSync(16).data,
          authType: authCandidate.authTypes,
          authTrustLevel: authCandidate.authTrustLevel,
        }
        const widgetParam: userAuth.WidgetParam = {
          title: AppStrings.get('security_unlock_title'),
        }
        const userAuthInstance: userAuth.UserAuthInstance =
          userAuth.getUserAuthInstance(authParam, widgetParam)
        userAuthInstance.on('result', {
          onResult(result: userAuth.UserAuthResult): void {
            DiagnosticLogger.info('security', 'auth_result', `${result.result}`)
            resolve(result.result)
          },
        })
        userAuthInstance.start()
      } catch (error) {
        DiagnosticLogger.warn('security', 'auth_exception', (error as Error).message)
        resolve(AUTH_UNAVAILABLE)
      }
    })
  }
}
