import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectClipboardLinkSettings } from '../state/ClipboardLinkSettingsState'

const READ_PASTEBOARD_PERMISSION: Permissions = 'ohos.permission.READ_PASTEBOARD'

/** Persists the opt-in clipboard-link detector and owns its runtime permission request. */
export class ClipboardLinkSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const state = connectClipboardLinkSettings()
      state.enabled = store.getSync(StorageKeys.CLIPBOARD_LINK_ENABLED, false) as boolean
      state.lastChangeCount = store.getSync(StorageKeys.CLIPBOARD_LINK_CHANGE_COUNT, -1) as number
    } catch (error) {
      DiagnosticLogger.warn('settings', 'clipboard_link_restore_failed', (error as Error).message)
      connectClipboardLinkSettings().enabled = false
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<boolean> {
    if (enabled && !await ClipboardLinkSettings.requestPermission(context)) {
      DiagnosticLogger.info('clipboard', 'permission_denied', 'source=settings')
      return false
    }
    const state = connectClipboardLinkSettings()
    state.enabled = enabled
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.CLIPBOARD_LINK_ENABLED, enabled)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'clipboard_link_save_failed', (error as Error).message)
    }
    return true
  }

  static async markChangeCount(context: common.UIAbilityContext, changeCount: number): Promise<void> {
    const state = connectClipboardLinkSettings()
    state.lastChangeCount = changeCount
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.CLIPBOARD_LINK_CHANGE_COUNT, changeCount)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'clipboard_change_count_save_failed', (error as Error).message)
    }
  }

  static async disableAfterPermissionFailure(context: common.UIAbilityContext): Promise<void> {
    if (!connectClipboardLinkSettings().enabled) {
      return
    }
    await ClipboardLinkSettings.setEnabled(context, false)
  }

  private static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const result = await at.requestPermissionsFromUser(context, [READ_PASTEBOARD_PERMISSION])
      return result.authResults.length > 0 && result.authResults[0] === 0
    } catch (error) {
      DiagnosticLogger.warn('clipboard', 'permission_request_failed', (error as Error).message)
      return false
    }
  }
}
