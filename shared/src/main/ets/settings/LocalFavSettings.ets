import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGallery } from '../model/EhGallery'
import { connectLocalFav } from '../state/LocalFavState'
import { LocalFavoriteRepository } from '../storage/LocalFavoriteRepository'

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
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await LocalFavSettings.migrateLegacyPreferences(context)
      connectLocalFav().items = await LocalFavoriteRepository.load(context)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_restore_failed', (error as Error).message)
    }
  }

  static async persist(context: common.UIAbilityContext, items: EhGallery[]): Promise<void> {
    try {
      await LocalFavoriteRepository.replaceAll(context, LocalFavSettings.snapshotGalleries(items))
    } catch (error) {
      DiagnosticLogger.warn('settings', 'localfav_save_failed', (error as Error).message)
    }
  }

  static async add(context: common.UIAbilityContext, gallery: EhGallery): Promise<boolean> {
    if (gallery.gid.length === 0) {
      return false
    }
    const state = connectLocalFav()
    const next: EhGallery[] = [LocalFavSettings.prepare(gallery)]
    state.items.forEach((item: EhGallery) => {
      if (item.gid !== gallery.gid) {
        next.push(item.copy())
      }
    })
    const inserted: boolean = next.length !== state.items.length || state.items.length === 0 || state.items[0].gid !== gallery.gid
    state.items = next
    await LocalFavSettings.persist(context, next)
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
    await LocalFavSettings.persist(context, next)
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
    return LocalFavoriteRepository.load(context)
  }

  static async restoreBackup(context: common.UIAbilityContext, items: EhGallery[]): Promise<void> {
    await LocalFavoriteRepository.replaceAll(context, LocalFavSettings.snapshotGalleries(items))
    await LocalFavSettings.deleteLegacyPreference(context)
    connectLocalFav().items = await LocalFavoriteRepository.load(context)
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
      await LocalFavoriteRepository.replaceAll(context, items)
    }
    store.deleteSync(StorageKeys.LOCAL_FAVORITES)
    store.flushSync()
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
