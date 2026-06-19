import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { Favcat } from '../model/Favcat'
import { connectFavSelection } from '../state/FavSelectionState'

/** Persisted snapshot of the remote 0-9 favorite categories. */
class FavcatSnapshot {
  favId: string = ''
  favTitle: string = ''
  totNum: number = 0
}

/**
 * Restores and persists the favorites category selector metadata.
 *
 * eros_fe keeps the parsed favcat list in the user's profile and falls back to EHConst.favList only when
 * nothing has been parsed yet. NextE already seeds the 10 slots for first paint; this setting lets later
 * launches reuse the last real names/counts immediately, then the next favorites.php response refreshes
 * the snapshot. Synthetic entries such as 'a' (all) and future 'l' (local) are not written here.
 */
export class FavcatListSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.FAVORITES_FAVCATS, '[]') as string
      const restored: Favcat[] = FavcatListSettings.parse(raw)
      if (restored.length > 0) {
        connectFavSelection().favList = restored
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'favcat_restore_failed', (error as Error).message)
    }
  }

  static async persist(context: common.UIAbilityContext, favcats: Favcat[]): Promise<void> {
    try {
      const snap: FavcatSnapshot[] = FavcatListSettings.snapshot(favcats)
      if (snap.length === 0) {
        return
      }
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.FAVORITES_FAVCATS, JSON.stringify(snap))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'favcat_save_failed', (error as Error).message)
    }
  }

  private static snapshot(favcats: Favcat[]): FavcatSnapshot[] {
    const out: FavcatSnapshot[] = []
    favcats.forEach((f: Favcat) => {
      if (FavcatListSettings.isRemoteSlot(f.favId)) {
        const s: FavcatSnapshot = new FavcatSnapshot()
        s.favId = f.favId
        s.favTitle = f.favTitle.length > 0 ? f.favTitle : `Favorites ${f.favId}`
        s.totNum = f.totNum >= 0 ? f.totNum : 0
        out.push(s)
      }
    })
    return out
  }

  private static parse(raw: string): Favcat[] {
    try {
      const parsed: Object = JSON.parse(raw) as Object
      if (!Array.isArray(parsed)) {
        return []
      }
      const out: Favcat[] = []
      const seen: Set<string> = new Set<string>()
      ;(parsed as FavcatSnapshot[]).forEach((s: FavcatSnapshot) => {
        const favId: string = typeof s.favId === 'string' ? s.favId : ''
        if (!FavcatListSettings.isRemoteSlot(favId) || seen.has(favId)) {
          return
        }
        seen.add(favId)
        const title: string =
          typeof s.favTitle === 'string' && s.favTitle.length > 0
            ? s.favTitle
            : `Favorites ${favId}`
        const count: number = typeof s.totNum === 'number' && s.totNum >= 0 ? s.totNum : 0
        out.push(new Favcat(favId, title, count))
      })
      out.sort((a: Favcat, b: Favcat) => Number.parseInt(a.favId, 10) - Number.parseInt(b.favId, 10))
      return out
    } catch (error) {
      DiagnosticLogger.warn('settings', 'favcat_parse_failed', (error as Error).message)
      return []
    }
  }

  private static isRemoteSlot(favId: string): boolean {
    const n: number = Number.parseInt(favId, 10)
    return `${n}` === favId && n >= 0 && n <= 9
  }
}
