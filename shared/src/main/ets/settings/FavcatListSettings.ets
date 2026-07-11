import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { Favcat } from '../model/Favcat'
import { connectFavSelection, FavSelectionState } from '../state/FavSelectionState'
import { connectRemoteFavoriteSlotCache } from '../state/RemoteFavoriteSlotCacheState'
import { EhCookieStore } from '../network/EhCookieStore'

/** Persisted snapshot of the remote 0-9 favorite categories. */
class FavcatSnapshot {
  favId: string = ''
  favTitle: string = ''
  totNum: number = 0
}

class FavcatSnapshotEnvelope {
  memberId: string = ''
  favcats: FavcatSnapshot[] = []

  constructor(memberId: string = '', favcats: FavcatSnapshot[] = []) {
    this.memberId = memberId
    this.favcats = favcats
  }
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
      const memberId: string = FavcatListSettings.activeMemberId()
      const key: string = FavcatListSettings.storageKey(memberId)
      const raw: string = store.getSync(key, '') as string
      const restored: Favcat[] = FavcatListSettings.parse(raw, memberId)
      if (restored.length > 0) {
        connectFavSelection().favList = restored
        connectRemoteFavoriteSlotCache().update(restored)
      } else {
        const fallback: Favcat[] = FavcatListSettings.defaultRemoteSlots()
        connectFavSelection().favList = fallback
        connectRemoteFavoriteSlotCache().update([])
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'favcat_restore_failed', (error as Error).message)
    }
  }

  static async persist(context: common.UIAbilityContext, favcats: Favcat[]): Promise<void> {
    // The parsed list belongs to the account that initiated this persistence. Capture its identity
    // before Preferences yields so an A → B switch cannot write A's metadata under B's key.
    const memberId: string = FavcatListSettings.activeMemberId()
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const key: string = FavcatListSettings.storageKey(memberId)
      const previousRaw: string = store.getSync(key, '[]') as string
      const previous: Favcat[] = FavcatListSettings.parse(previousRaw, memberId)
      const snap: FavcatSnapshot[] = FavcatListSettings.snapshot(
        FavcatListSettings.mergeWithPreviousCounts(previous, favcats),
      )
      if (snap.length === 0) {
        return
      }
      const payload: Object =
        memberId.length > 0 ? new FavcatSnapshotEnvelope(memberId, snap) : snap
      store.putSync(key, JSON.stringify(payload))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'favcat_save_failed', (error as Error).message)
    }
  }

  private static activeMemberId(): string {
    return EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
  }

  private static storageKey(memberId: string): string {
    if (memberId.length === 0) {
      return StorageKeys.FAVORITES_FAVCATS
    }
    return `${StorageKeys.FAVORITES_FAVCATS}.${memberId}`
  }

  private static defaultRemoteSlots(): Favcat[] {
    const out: Favcat[] = []
    for (let i: number = 0; i < 10; i++) {
      out.push(new Favcat(`${i}`, `Favorites ${i}`, 0, true))
    }
    return out
  }

  private static snapshot(favcats: Favcat[]): FavcatSnapshot[] {
    const out: FavcatSnapshot[] = []
    favcats.forEach((f: Favcat) => {
      if (FavcatListSettings.isRemoteSlot(f.favId) && !FavSelectionState.isPlaceholderFavcat(f)) {
        const s: FavcatSnapshot = new FavcatSnapshot()
        s.favId = f.favId
        s.favTitle = f.favTitle
        s.totNum = f.totNum >= 0 ? f.totNum : 0
        out.push(s)
      }
    })
    return out
  }

  private static mergeWithPreviousCounts(previous: Favcat[], incoming: Favcat[]): Favcat[] {
    const byId: Map<string, Favcat> = new Map<string, Favcat>()
    previous.forEach((f: Favcat) => {
      byId.set(f.favId, f)
    })
    const out: Favcat[] = []
    incoming.forEach((f: Favcat) => {
      const next: Favcat = new Favcat(f.favId, f.favTitle, f.totNum, f.isPlaceholder)
      const old: Favcat | undefined = byId.get(f.favId)
      if (
        old !== undefined &&
        next.totNum === 0 &&
        old.totNum > 0 &&
        next.favTitle === old.favTitle
      ) {
        next.totNum = old.totNum
      }
      out.push(next)
    })
    return out
  }

  private static parse(raw: string, memberId: string): Favcat[] {
    if (raw.length === 0) {
      return []
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object
      if (memberId.length === 0 && Array.isArray(parsed)) {
        return FavcatListSettings.parseSnapshots(parsed as FavcatSnapshot[])
      }
      const envelope: FavcatSnapshotEnvelope = parsed as FavcatSnapshotEnvelope
      if (envelope.memberId !== memberId || !Array.isArray(envelope.favcats)) {
        return []
      }
      return FavcatListSettings.parseSnapshots(envelope.favcats)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'favcat_parse_failed', (error as Error).message)
      return []
    }
  }

  private static parseSnapshots(parsed: FavcatSnapshot[]): Favcat[] {
    const out: Favcat[] = []
    const seen: Set<string> = new Set<string>()
    parsed.forEach((s: FavcatSnapshot) => {
      const favId: string = typeof s.favId === 'string' ? s.favId : ''
      if (!FavcatListSettings.isRemoteSlot(favId) || seen.has(favId)) {
        return
      }
      seen.add(favId)
      const title: string = typeof s.favTitle === 'string' ? s.favTitle : ''
      const count: number = typeof s.totNum === 'number' && s.totNum >= 0 ? s.totNum : 0
      const restored: Favcat = new Favcat(favId, title, count)
      if (!FavSelectionState.isPlaceholderFavcat(restored)) {
        out.push(restored)
      }
    })
    out.sort((a: Favcat, b: Favcat) => Number.parseInt(a.favId, 10) - Number.parseInt(b.favId, 10))
    return out
  }

  private static isRemoteSlot(favId: string): boolean {
    const n: number = Number.parseInt(favId, 10)
    return `${n}` === favId && n >= 0 && n <= 9
  }
}
