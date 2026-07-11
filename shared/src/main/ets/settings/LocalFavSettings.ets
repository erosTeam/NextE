import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGallery } from '../model/EhGallery'
import { connectLocalFav } from '../state/LocalFavState'
import { LocalFavoriteRepository } from '../storage/LocalFavoriteRepository'
import { SyncScheduler } from '../sync/SyncScheduler'

class LocalFavGallerySnapshot {
  gid: string = ''
  token: string = ''
  url: string = ''
  thumbUrl: string = ''
  thumbUrlL: string = ''
  imgWidth: number = 0
  imgHeight: number = 0
  englishTitle: string = ''
  japaneseTitle: string = ''
  category: string = ''
  uploader: string = ''
  postTime: string = ''
  fileCount: string = ''
  rating: number = 0
  ratingFallBack: number = 0
  colorRating: string = ''
  favNote: string = ''
  favTitle: string = ''
  expunged: boolean = false
  lastViewTime: number = 0
}

/** Persists the local-only Favorites slot (`favcat=l`). */
export class LocalFavSettings {
  // Keep add/remove, backup restore, and provider drains in their call order. A rapid toggle must
  // never let its earlier RDB write finish after its later tombstone.
  private static rdbWriteTail: Promise<void> = Promise.resolve()
  private static mutationRevision: number = 0

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await LocalFavSettings.migrateLegacyPreferences(context)
      await LocalFavSettings.refreshFromStorage(context)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_restore_failed', (error as Error).message)
    }
  }

  static async persist(context: common.UIAbilityContext, items: EhGallery[]): Promise<void> {
    try {
      await LocalFavSettings.enqueueRdbWrite(
        (): Promise<void> => LocalFavoriteRepository.replaceAll(
          context,
          LocalFavSettings.snapshotGalleries(items),
        ),
      )
      SyncScheduler.requestAfterLocalWrite(context, 'local_favorites')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_save_failed', (error as Error).message)
    }
  }

  static async add(context: common.UIAbilityContext, gallery: EhGallery): Promise<boolean> {
    if (gallery.gid.length === 0) {
      return false
    }
    const state = connectLocalFav()
    const prepared: EhGallery = LocalFavSettings.prepare(gallery)
    prepared.lastViewTime = LocalFavSettings.nextMutationTime(state.items, prepared.lastViewTime)
    const next: EhGallery[] = [prepared]
    state.items.forEach((item: EhGallery) => {
      if (item.gid !== gallery.gid) {
        next.push(item.copy())
      }
    })
    const inserted: boolean = next.length !== state.items.length || state.items.length === 0 || state.items[0].gid !== gallery.gid
    state.items = next
    LocalFavSettings.mutationRevision = LocalFavSettings.mutationRevision + 1
    await LocalFavSettings.persistAdd(context, prepared)
    return inserted
  }

  static async removeByGid(context: common.UIAbilityContext, gid: string): Promise<boolean> {
    if (gid.length === 0) {
      return false
    }
    const state = connectLocalFav()
    const next: EhGallery[] = []
    let removed: boolean = false
    state.items.forEach((item: EhGallery) => {
      if (item.gid === gid) {
        removed = true
      } else {
        next.push(item.copy())
      }
    })
    if (!removed) {
      return false
    }
    state.items = next
    LocalFavSettings.mutationRevision = LocalFavSettings.mutationRevision + 1
    await LocalFavSettings.persistRemoval(context, gid)
    return true
  }

  static contains(gid: string): boolean {
    if (gid.length === 0) {
      return false
    }
    return connectLocalFav().items.some((item: EhGallery) => item.gid === gid)
  }

  static async exportForBackup(context: common.UIAbilityContext): Promise<EhGallery[]> {
    await LocalFavSettings.migrateLegacyPreferences(context)
    await LocalFavSettings.flushForSync(context)
    return LocalFavoriteRepository.load(context)
  }

  static async restoreBackup(context: common.UIAbilityContext, items: EhGallery[]): Promise<void> {
    LocalFavSettings.mutationRevision = LocalFavSettings.mutationRevision + 1
    await LocalFavSettings.enqueueRdbWrite(
      (): Promise<void> => LocalFavoriteRepository.replaceAll(
        context,
        LocalFavSettings.snapshotGalleries(items),
      ),
    )
    await LocalFavSettings.deleteLegacyPreference(context)
    await LocalFavSettings.refreshFromStorage(context)
    SyncScheduler.requestAfterLocalWrite(context, 'local_favorites_restore_backup')
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.LOCAL_FAVORITES, '') as string
    if (raw.length === 0) {
      return
    }
    const items: EhGallery[] = LocalFavSettings.parse(raw)
    if (items.length > 0) {
      await LocalFavSettings.enqueueRdbWrite(
        (): Promise<void> => LocalFavoriteRepository.replaceAll(context, items),
      )
    }
    store.deleteSync(StorageKeys.LOCAL_FAVORITES)
    store.flushSync()
  }

  /** Drain current local-favorite writes before WebDAV/Huawei Cloud reads the durable table. */
  static async flushForSync(_context: common.UIAbilityContext): Promise<void> {
    await LocalFavSettings.rdbWriteTail
  }

  private static async persistAdd(context: common.UIAbilityContext, item: EhGallery): Promise<void> {
    try {
      await LocalFavSettings.enqueueRdbWrite(async (): Promise<void> => {
        item.lastViewTime = await LocalFavoriteRepository.upsert(context, item)
      })
      SyncScheduler.requestAfterLocalWrite(context, 'local_favorites')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_add_failed', (error as Error).message)
    }
  }

  private static async persistRemoval(context: common.UIAbilityContext, gid: string): Promise<void> {
    try {
      await LocalFavSettings.enqueueRdbWrite(async (): Promise<void> => {
        await LocalFavoriteRepository.tombstone(context, gid)
      })
      SyncScheduler.requestAfterLocalWrite(context, 'local_favorites')
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_remove_failed', (error as Error).message)
    }
  }

  /** Keep later writes runnable after a failed database operation. */
  private static enqueueRdbWrite(work: () => Promise<void>): Promise<void> {
    const next: Promise<void> = LocalFavSettings.rdbWriteTail.then(
      (): Promise<void> => work(),
      (): Promise<void> => work(),
    )
    LocalFavSettings.rdbWriteTail = next
    return next
  }

  /** The live list mirrors the durable newest-first order while the repository handles old tombstones. */
  private static nextMutationTime(items: EhGallery[], requestedTime: number): number {
    let latest: number = 0
    items.forEach((item: EhGallery) => {
      latest = Math.max(latest, Math.floor(item.lastViewTime))
    })
    return Math.max(Date.now(), Math.max(0, Math.floor(requestedTime)), latest + 1)
  }

  /** Do not replace an add/remove that arrived while an RDB snapshot was loading. */
  private static async refreshFromStorage(context: common.UIAbilityContext): Promise<void> {
    for (let attempt: number = 0; attempt < 2; attempt++) {
      await LocalFavSettings.rdbWriteTail
      const revision: number = LocalFavSettings.mutationRevision
      const items: EhGallery[] = await LocalFavoriteRepository.load(context)
      if (revision === LocalFavSettings.mutationRevision) {
        connectLocalFav().items = items
        return
      }
    }
  }

  private static prepare(gallery: EhGallery): EhGallery {
    const g: EhGallery = gallery.copy()
    g.favcat = 'l'
    g.favTitle = 'Local'
    g.lastViewTime = Date.now()
    return g
  }

  private static snapshot(items: EhGallery[]): LocalFavGallerySnapshot[] {
    const out: LocalFavGallerySnapshot[] = []
    const seen: Set<string> = new Set<string>()
    items.forEach((g: EhGallery) => {
      if (g.gid.length === 0 || seen.has(g.gid)) {
        return
      }
      seen.add(g.gid)
      const s: LocalFavGallerySnapshot = new LocalFavGallerySnapshot()
      s.gid = g.gid
      s.token = g.token
      s.url = g.url
      s.thumbUrl = g.thumbUrl
      s.thumbUrlL = g.thumbUrlL
      s.imgWidth = g.imgWidth
      s.imgHeight = g.imgHeight
      s.englishTitle = g.englishTitle
      s.japaneseTitle = g.japaneseTitle
      s.category = g.category
      s.uploader = g.uploader
      s.postTime = g.postTime
      s.fileCount = g.fileCount
      s.rating = g.rating
      s.ratingFallBack = g.ratingFallBack
      s.colorRating = g.colorRating
      s.favNote = g.favNote
      s.favTitle = g.favTitle.length > 0 ? g.favTitle : 'Local'
      s.expunged = g.expunged
      s.lastViewTime = g.lastViewTime
      out.push(s)
    })
    return out
  }

  private static snapshotGalleries(items: EhGallery[]): EhGallery[] {
    const snapshots: LocalFavGallerySnapshot[] = LocalFavSettings.snapshot(items)
    const out: EhGallery[] = []
    snapshots.forEach((s: LocalFavGallerySnapshot) => {
      const gallery: EhGallery = LocalFavSettings.fromSnapshot(s)
      if (gallery.gid.length > 0) {
        out.push(gallery)
      }
    })
    return out
  }

  private static async deleteLegacyPreference(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.deleteSync(StorageKeys.LOCAL_FAVORITES)
    store.flushSync()
  }

  private static parse(raw: string): EhGallery[] {
    try {
      const parsed: Object = JSON.parse(raw) as Object
      if (!Array.isArray(parsed)) {
        return []
      }
      const out: EhGallery[] = []
      const seen: Set<string> = new Set<string>()
      ;(parsed as LocalFavGallerySnapshot[]).forEach((s: LocalFavGallerySnapshot) => {
        const g: EhGallery = LocalFavSettings.fromSnapshot(s)
        if (g.gid.length === 0 || seen.has(g.gid)) {
          return
        }
        seen.add(g.gid)
        out.push(g)
      })
      return out
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_parse_failed', (error as Error).message)
      return []
    }
  }

  private static fromSnapshot(s: LocalFavGallerySnapshot): EhGallery {
    const gid: string = typeof s.gid === 'string' ? s.gid : ''
    const g: EhGallery = new EhGallery(gid, typeof s.token === 'string' ? s.token : '')
    g.url = typeof s.url === 'string' ? s.url : ''
    g.thumbUrl = typeof s.thumbUrl === 'string' ? s.thumbUrl : ''
    g.thumbUrlL = typeof s.thumbUrlL === 'string' ? s.thumbUrlL : ''
    g.imgWidth = typeof s.imgWidth === 'number' ? s.imgWidth : 0
    g.imgHeight = typeof s.imgHeight === 'number' ? s.imgHeight : 0
    g.englishTitle = typeof s.englishTitle === 'string' ? s.englishTitle : ''
    g.japaneseTitle = typeof s.japaneseTitle === 'string' ? s.japaneseTitle : ''
    g.category = typeof s.category === 'string' ? s.category : ''
    g.uploader = typeof s.uploader === 'string' ? s.uploader : ''
    g.postTime = typeof s.postTime === 'string' ? s.postTime : ''
    g.fileCount = typeof s.fileCount === 'string' ? s.fileCount : ''
    g.rating = typeof s.rating === 'number' ? s.rating : 0
    g.ratingFallBack = typeof s.ratingFallBack === 'number' ? s.ratingFallBack : 0
    g.colorRating = typeof s.colorRating === 'string' ? s.colorRating : ''
    g.favNote = typeof s.favNote === 'string' ? s.favNote : ''
    g.favcat = 'l'
    g.favTitle = typeof s.favTitle === 'string' && s.favTitle.length > 0 ? s.favTitle : 'Local'
    g.expunged = typeof s.expunged === 'boolean' ? s.expunged : false
    g.lastViewTime = typeof s.lastViewTime === 'number' ? s.lastViewTime : 0
    return g
  }
}
