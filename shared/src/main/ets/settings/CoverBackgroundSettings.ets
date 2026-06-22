import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { connectCoverBackground } from '../state/CoverBackgroundState'

export class CoverBackgroundSettings {
  static apply(value: boolean): void {
    connectCoverBackground().blurringOfCoverBackground = value
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      CoverBackgroundSettings.apply(store.getSync(StorageKeys.BLURRING_OF_COVER_BACKGROUND, false) as boolean)
    } catch (_error) {
      CoverBackgroundSettings.apply(false)
    }
  }

  static async setBlurringOfCoverBackground(context: common.UIAbilityContext, value: boolean): Promise<void> {
    CoverBackgroundSettings.apply(value)
    const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
    store.putSync(StorageKeys.BLURRING_OF_COVER_BACKGROUND, value)
    store.flushSync()
  }
}
