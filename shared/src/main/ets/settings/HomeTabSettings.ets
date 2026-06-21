import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { connectHomeTabAutoHide } from '../state/HomeTabAutoHideState'

export class HomeTabSettings {
  static readonly DEFAULT_AUTO_HIDE: boolean = true

  static apply(autoHide: boolean): void {
    connectHomeTabAutoHide().autoHide = autoHide
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const autoHide: boolean = store.getSync(StorageKeys.HOME_TAB_AUTO_HIDE, HomeTabSettings.DEFAULT_AUTO_HIDE) as boolean
      HomeTabSettings.apply(autoHide)
    } catch (_error) {
      HomeTabSettings.apply(HomeTabSettings.DEFAULT_AUTO_HIDE)
    }
  }

  static async save(context: common.UIAbilityContext, autoHide: boolean): Promise<void> {
    HomeTabSettings.apply(autoHide)
    const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
    store.putSync(StorageKeys.HOME_TAB_AUTO_HIDE, autoHide)
    store.flushSync()
  }
}
