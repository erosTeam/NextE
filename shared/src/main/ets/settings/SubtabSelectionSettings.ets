import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectAuth } from '../state/AuthState'
import { connectFavSelection } from '../state/FavSelectionState'
import { connectHomeSource } from '../state/HomeSourceState'

const HOME_DEFAULT: string = ''
const FAV_DEFAULT: string = 'a'
const FAV_LOCAL: string = 'l'
const TOPLIST_DEFAULT: number = 15

export class SubtabSelectionSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const auth = connectAuth()
      const homeSource = SubtabSelectionSettings.normalizeHomeSource(
        store.getSync(StorageKeys.HOME_SOURCE, HOME_DEFAULT) as string,
        auth.isLogin,
      )
      const favcat = SubtabSelectionSettings.normalizeFavcat(
        store.getSync(StorageKeys.FAVORITES_FAVCAT, FAV_DEFAULT) as string,
        auth.isLogin,
      )
      const toplistTl = SubtabSelectionSettings.normalizeToplistTl(
        store.getSync(StorageKeys.TOPLIST_TL, TOPLIST_DEFAULT) as number,
      )
      const home = connectHomeSource()
      home.source = homeSource
      home.toplistTl = toplistTl
      connectFavSelection().selectedFavcat = favcat
    } catch (error) {
      DiagnosticLogger.warn('settings', 'subtab_selection_restore_failed', (error as Error).message)
    }
  }

  static async setHomeSource(
    context: common.UIAbilityContext,
    source: string,
    isLogin: boolean,
  ): Promise<void> {
    const normalized: string = SubtabSelectionSettings.normalizeHomeSource(source, isLogin)
    connectHomeSource().source = normalized
    await SubtabSelectionSettings.saveString(context, StorageKeys.HOME_SOURCE, normalized)
  }

  static async setFavoritesFavcat(
    context: common.UIAbilityContext,
    favcat: string,
    isLogin: boolean,
  ): Promise<void> {
    const normalized: string = SubtabSelectionSettings.normalizeFavcat(favcat, isLogin)
    connectFavSelection().selectedFavcat = normalized
    await SubtabSelectionSettings.saveString(context, StorageKeys.FAVORITES_FAVCAT, normalized)
  }

  static async setToplistTl(context: common.UIAbilityContext, tl: number): Promise<void> {
    const normalized: number = SubtabSelectionSettings.normalizeToplistTl(tl)
    connectHomeSource().toplistTl = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.TOPLIST_TL, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'subtab_selection_save_toplist_failed', (error as Error).message)
    }
  }

  private static normalizeHomeSource(source: string, isLogin: boolean): string {
    if (source === 'popular') {
      return source
    }
    if (source === 'watched' && isLogin) {
      return source
    }
    return HOME_DEFAULT
  }

  private static normalizeFavcat(favcat: string, isLogin: boolean): string {
    if (!isLogin) {
      return FAV_LOCAL
    }
    if (favcat === FAV_DEFAULT || favcat === FAV_LOCAL) {
      return favcat
    }
    const n: number = Number.parseInt(favcat, 10)
    if (`${n}` === favcat && n >= 0 && n <= 9) {
      return favcat
    }
    return FAV_DEFAULT
  }

  private static normalizeToplistTl(tl: number): number {
    if (tl === 11 || tl === 12 || tl === 13 || tl === 15) {
      return tl
    }
    return TOPLIST_DEFAULT
  }

  private static async saveString(
    context: common.UIAbilityContext,
    key: string,
    value: string,
  ): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(key, value)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'subtab_selection_save_failed', (error as Error).message)
    }
  }
}
