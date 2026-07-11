import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectSiteMode } from '../state/SiteModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhConstants } from '../constants/EhConstants'
import { UserTagLoader } from '../services/UserTagLoader'

/**
 * Persists the site mode (表站 e-hentai / 里站 exhentai) and is the single writer of the
 * reactive SiteModeState mirror. ExHentai requires login + igneous — the SettingsPage toggle
 * enforces that gate before calling setEx(true). Restored at bootstrap so the chosen site
 * survives a restart.
 */
export class SiteModeSettings {
  // Preferences acquisition is asynchronous. Only the newest selection may persist after it returns.
  private static writeEpoch: number = 0

  static shouldUseEx(requestedIsEx: boolean, isLogin: boolean, igneous: string): boolean {
    return requestedIsEx && isLogin && igneous.length > 0 && igneous !== 'mystery'
  }

  private static activeJarCanUseEx(): boolean {
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    return SiteModeSettings.shouldUseEx(
      true,
      cookieStore.isLogin(),
      cookieStore.get(EhConstants.COOKIE_IGNEOUS),
    )
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    SiteModeSettings.writeEpoch = SiteModeSettings.writeEpoch + 1
    const epoch: number = SiteModeSettings.writeEpoch
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const requestedIsEx: boolean = store.getSync(StorageKeys.SITE_MODE_EX, false) as boolean
      const isEx: boolean = SiteModeSettings.shouldUseEx(
        requestedIsEx,
        EhCookieStore.getInstance().isLogin(),
        EhCookieStore.getInstance().get(EhConstants.COOKIE_IGNEOUS),
      )
      if (epoch !== SiteModeSettings.writeEpoch) {
        return
      }
      connectSiteMode().isEx = isEx
      if (requestedIsEx && !isEx) {
        store.putSync(StorageKeys.SITE_MODE_EX, false)
        store.flushSync()
        DiagnosticLogger.info('settings', 'sitemode_reconciled', 'reason=missing_ex_access')
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'sitemode_restore_failed', (error as Error).message)
    }
  }

  static async setEx(context: common.UIAbilityContext, requestedIsEx: boolean): Promise<void> {
    SiteModeSettings.writeEpoch = SiteModeSettings.writeEpoch + 1
    const epoch: number = SiteModeSettings.writeEpoch
    const isEx: boolean = SiteModeSettings.shouldUseEx(
      requestedIsEx,
      EhCookieStore.getInstance().isLogin(),
      EhCookieStore.getInstance().get(EhConstants.COOKIE_IGNEOUS),
    )
    const previousIsEx: boolean = connectSiteMode().isEx
    connectSiteMode().isEx = isEx
    if (previousIsEx !== isEx) {
      UserTagLoader.reconcileActiveContext()
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      if (epoch !== SiteModeSettings.writeEpoch) {
        return
      }
      store.putSync(StorageKeys.SITE_MODE_EX, isEx)
      store.flushSync()
      DiagnosticLogger.info('settings', 'sitemode_set', `isEx=${isEx}`)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'sitemode_save_failed', (error as Error).message)
    }
  }

  static async reconcileActiveJar(context: common.UIAbilityContext): Promise<void> {
    if (!connectSiteMode().isEx || SiteModeSettings.activeJarCanUseEx()) {
      return
    }
    await SiteModeSettings.setEx(context, false)
  }
}
