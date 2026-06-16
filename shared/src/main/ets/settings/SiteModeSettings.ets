import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectSiteMode } from '../state/SiteModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Persists the site mode (表站 e-hentai / 里站 exhentai) and is the single writer of the
 * reactive SiteModeState mirror. ExHentai requires login + igneous — the SettingsPage toggle
 * enforces that gate before calling setEx(true). Restored at bootstrap so the chosen site
 * survives a restart.
 */
export class SiteModeSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const isEx: boolean = store.getSync(StorageKeys.SITE_MODE_EX, false) as boolean
      connectSiteMode().isEx = isEx
    } catch (error) {
      DiagnosticLogger.warn('settings', 'sitemode_restore_failed', (error as Error).message)
    }
  }

  static async setEx(context: common.UIAbilityContext, isEx: boolean): Promise<void> {
    connectSiteMode().isEx = isEx
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.SITE_MODE_EX, isEx)
      store.flushSync()
      DiagnosticLogger.info('settings', 'sitemode_set', `isEx=${isEx}`)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'sitemode_save_failed', (error as Error).message)
    }
  }
}
