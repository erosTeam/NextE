import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhConstants } from '../constants/EhConstants'
import { CookieJarSettings } from './CookieJarSettings'
import { SiteModeSettings } from './SiteModeSettings'
import { ListModeSettings } from './ListModeSettings'
import { GalleryTitleSettings } from './GalleryTitleSettings'
import { ReadModeSettings } from './ReadModeSettings'
import { ThumbnailModeSettings } from './ThumbnailModeSettings'
import { CoverBackgroundSettings } from './CoverBackgroundSettings'
import { ActionAlignmentSettings } from './ActionAlignmentSettings'
import { ReadButtonStyleSettings } from './ReadButtonStyleSettings'
import { SearchHistorySettings } from './SearchHistorySettings'
import { SearchFilterSettings } from './SearchFilterSettings'
import { FavcatListSettings } from './FavcatListSettings'
import { LocalFavSettings } from './LocalFavSettings'
import { ViewedHistorySettings } from './ViewedHistorySettings'
import { GalleryReadProgressSettings } from './GalleryReadProgressSettings'
import { DownloadSettings } from './DownloadSettings'
import { DownloadQueueSettings } from './DownloadQueueSettings'
import { SecuritySettings } from './SecuritySettings'
import { UserTagLoader } from '../services/UserTagLoader'
import { SubtabSelectionSettings } from './SubtabSelectionSettings'
import { CustomProfilesSettings } from './CustomProfilesSettings'
import { AppColorFavoritesSettings } from './AppColorFavoritesSettings'
import { HomeTabSettings } from './HomeTabSettings'
import { ToplistFilterSettings } from './ToplistFilterSettings'
import { WebLoginStyleSettings } from './WebLoginStyleSettings'
import { ImageBlockSettings } from './ImageBlockSettings'
import { TagTranslationSettings } from './TagTranslationSettings'
import { CommentTranslationSettings } from './CommentTranslationSettings'
import { LocalBlockSettings } from './LocalBlockSettings'
import { DiagnosticsSettings } from './DiagnosticsSettings'
import { SyncSettings } from './SyncSettings'
import { ThemeSettings } from './ThemeSettings'
import { ThemeColorSettings } from './ThemeColorSettings'
import { ImmersiveMaterialSettings } from './ImmersiveMaterialSettings'
import { LanguageSettings } from './LanguageSettings'
import { SafeModeSettings } from './SafeModeSettings'
import { ReaderImageCacheSettings } from './ReaderImageCacheSettings'
import { EhPageCacheService } from '../services/EhPageCacheService'
import { ImagePipelineService } from '../services/ImagePipelineService'
import { connectSiteMode } from '../state/SiteModeState'
import { connectHomeSource } from '../state/HomeSourceState'
import { connectFavSelection } from '../state/FavSelectionState'
import { connectCustomProfiles } from '../state/CustomProfilesState'
import { CustomProfile, PROFILE_TYPE_FAVORITE } from '../model/CustomProfile'

const MAX_PAGE_CACHE_PRELOAD_CONCURRENCY: number = 2

/**
 * Restores every persisted setting from the preferences store into its AppStorageV2
 * mirror ONCE at startup, before the first page mounts (called from
 * EntryAbility.onWindowStageCreate). Each *Settings class registers its restore here so
 * the UI renders with the user's theme / site-mode / list-mode / reading prefs already
 * applied — no flash, no post-mount re-layout. Must never reject (best-effort).
 *
 * M3: restores the persisted auth cookie bundle (CookieJarSettings) so a logged-in user
 * stays logged in across restarts. Later milestones wire SiteModeSettings / ListModeSettings /
 * ThemeSettings / ReadingSettings / DownloadSettings here too.
 */
export class SettingsBootstrap {
  static async loadAll(context: common.UIAbilityContext): Promise<void> {
    try {
      // Theme + language first so the very first paint uses the user's appearance choice (no flash).
      await ThemeSettings.restore(context)
      await ThemeColorSettings.restore(context)
      await ImmersiveMaterialSettings.restore(context)
      await LanguageSettings.restore(context)
      await SafeModeSettings.restore(context)
      await CookieJarSettings.restore(context)
      await SiteModeSettings.restore(context)
      await ListModeSettings.restore(context)
      await GalleryTitleSettings.restore(context)
      await ReadModeSettings.restore(context)
      await ReaderImageCacheSettings.restore(context)
      ImagePipelineService.pruneReaderFileCache(context).catch((error: Error) => {
        DiagnosticLogger.warn('image-cache', 'reader_disk_startup_prune_failed', error.message)
      })
      ImagePipelineService.pruneImageBlockThumbnailFallbackCache(context).catch((error: Error) => {
        DiagnosticLogger.warn('image-cache', 'fallback_disk_startup_prune_failed', error.message)
      })
      await ThumbnailModeSettings.restore(context)
      await CoverBackgroundSettings.restore(context)
      await ActionAlignmentSettings.restore(context)
      await ReadButtonStyleSettings.restore(context)
      await SearchHistorySettings.restore(context)
      await SearchFilterSettings.restore(context)
      await FavcatListSettings.restore(context)
      await LocalFavSettings.restore(context)
      await ViewedHistorySettings.restore(context)
      await GalleryReadProgressSettings.restore(context)
      await SubtabSelectionSettings.restore(context)
      // Seed/restore the custom home sub-tab profiles (Phase 1: holder only; the bar still reads
      // HomeSourceState until Phase 2 wires it to profiles). Migrates the legacy HOME_SOURCE selection.
      await CustomProfilesSettings.restore(context)
      await AppColorFavoritesSettings.restore(context)
      await HomeTabSettings.restore(context)
      await ToplistFilterSettings.restore(context)
      await WebLoginStyleSettings.restore(context)
      await ImageBlockSettings.restore(context)
      await TagTranslationSettings.restore(context)
      await CommentTranslationSettings.restore(context)
      await LocalBlockSettings.restore(context)
      await SyncSettings.restore(context)
      await DiagnosticsSettings.restore(context)
      await DownloadSettings.restore(context)
      await DownloadQueueSettings.restore(context)
      await SecuritySettings.restore(context)
      // Cache warming is optional: active Home/Favorites VMs fall back to the same RDB load when it
      // has not completed. Keep durable settings on the startup path, but let windowStage begin mounting first.
      SettingsBootstrap.schedulePageCachePreload(context)
      DiagnosticLogger.info('settings', 'bootstrap_loaded', 'cookie jar restored')
      // Fire-and-forget (NOT awaited): load the user's My Tags for per-tag list colors. It's a network
      // round-trip and login-gated, so it must never block the first paint; logged-out users skip it.
      UserTagLoader.loadIfLoggedIn()
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('settings', 'bootstrap_failed', e.message)
    }
  }

  private static schedulePageCachePreload(context: common.UIAbilityContext): void {
    setTimeout((): void => {
      SettingsBootstrap.preloadPageCaches(context)
    }, 0)
  }

  private static async preloadPageCaches(context: common.UIAbilityContext): Promise<void> {
    try {
      const isEx: boolean = connectSiteMode().isEx
      const home = connectHomeSource()
      const fav = connectFavSelection()
      const favOrder: string = fav.orderByPosted ? EhConstants.FAV_ORDER_POSTED : EhConstants.FAV_ORDER_FAV
      const keys: string[] = []
      // Home tabs are custom profiles now; warm each non-hidden, non-favorite profile's uuid-scoped
      // cache (favorite-type profiles use the favorites cache key — handled with the favorites preload).
      const profiles: CustomProfile[] = connectCustomProfiles().profiles
      const selectedProfile: CustomProfile | null = connectCustomProfiles().findByUuid(
        connectCustomProfiles().selectedUuid,
      )
      if (selectedProfile !== null && !selectedProfile.hidden) {
        if (selectedProfile.listType === PROFILE_TYPE_FAVORITE) {
          if (selectedProfile.favcat !== 'l') {
            SettingsBootstrap.appendPreloadKey(
              keys,
              EhPageCacheService.favoritesListKey(isEx, selectedProfile.favcat, favOrder),
            )
          }
        } else {
          SettingsBootstrap.appendPreloadKey(
            keys,
            EhPageCacheService.homeProfileKey(isEx, selectedProfile.uuid),
          )
        }
      }
      SettingsBootstrap.appendPreloadKey(
        keys,
        EhPageCacheService.homeListKey(isEx, 'toplist', home.toplistTl),
      )
      if (fav.selectedFavcat !== 'l') {
        SettingsBootstrap.appendPreloadKey(
          keys,
          EhPageCacheService.favoritesListKey(isEx, fav.selectedFavcat, favOrder),
        )
      }
      for (let i = 0; i < profiles.length; i++) {
        const p: CustomProfile = profiles[i]
        if (!p.hidden && p.listType !== PROFILE_TYPE_FAVORITE) {
          SettingsBootstrap.appendPreloadKey(keys, EhPageCacheService.homeProfileKey(isEx, p.uuid))
        }
      }
      const toplistTls: number[] = [11, 12, 13, 15]
      for (let i = 0; i < toplistTls.length; i++) {
        SettingsBootstrap.appendPreloadKey(
          keys,
          EhPageCacheService.homeListKey(isEx, 'toplist', toplistTls[i]),
        )
      }
      const favcats: string[] = ['a', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
      for (let i = 0; i < favcats.length; i++) {
        SettingsBootstrap.appendPreloadKey(
          keys,
          EhPageCacheService.favoritesListKey(isEx, favcats[i], favOrder),
        )
      }
      const workers: number = await SettingsBootstrap.preloadGalleryListsBounded(context, keys)
      DiagnosticLogger.info(
        'page-cache',
        'preload_done',
        `jobs=${keys.length} workers=${workers} selected=${connectCustomProfiles().selectedUuid}/${home.toplistTl}/${fav.selectedFavcat}`,
      )
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'preload_failed', (error as Error).message)
    }
  }

  private static appendPreloadKey(keys: string[], key: string): void {
    if (key.length > 0 && keys.indexOf(key) < 0) {
      keys.push(key)
    }
  }

  /** Deferred warming is optional, so constrain it instead of multiplying RDB reads for every custom tab. */
  private static async preloadGalleryListsBounded(
    context: common.UIAbilityContext,
    keys: string[],
  ): Promise<number> {
    const workerCount: number = Math.min(MAX_PAGE_CACHE_PRELOAD_CONCURRENCY, keys.length)
    if (workerCount <= 0) {
      return 0
    }
    const workers: Promise<void>[] = []
    for (let i: number = 0; i < workerCount; i++) {
      workers.push(SettingsBootstrap.preloadGalleryListWorker(context, keys, i, workerCount))
    }
    await Promise.all(workers)
    return workerCount
  }

  private static async preloadGalleryListWorker(
    context: common.UIAbilityContext,
    keys: string[],
    workerIndex: number,
    workerCount: number,
  ): Promise<void> {
    for (let i: number = workerIndex; i < keys.length; i = i + workerCount) {
      await EhPageCacheService.preloadGalleryList(context, keys[i])
    }
  }
}
