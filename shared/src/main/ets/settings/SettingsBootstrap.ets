import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhConstants } from '../constants/EhConstants'
import { CookieJarSettings } from './CookieJarSettings'
import { SiteModeSettings } from './SiteModeSettings'
import { ListModeSettings } from './ListModeSettings'
import { GalleryDetailTransitionSettings } from './GalleryDetailTransitionSettings'
import { GalleryTitleSettings } from './GalleryTitleSettings'
import { ReadModeSettings } from './ReadModeSettings'
import { ThumbnailModeSettings } from './ThumbnailModeSettings'
import { CoverBackgroundSettings } from './CoverBackgroundSettings'
import { ActionAlignmentSettings } from './ActionAlignmentSettings'
import { ReadButtonStyleSettings } from './ReadButtonStyleSettings'
import { ScreenOrientationSettings } from './ScreenOrientationSettings'
import { TabletLayoutSettings } from './TabletLayoutSettings'
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
import { ClipboardLinkSettings } from './ClipboardLinkSettings'
import { WebLoginStyleSettings } from './WebLoginStyleSettings'
import { ImageBlockSettings } from './ImageBlockSettings'
import { TagTranslationSettings } from './TagTranslationSettings'
import { CommentTranslationSettings } from './CommentTranslationSettings'
import { ComicTranslationProviderSettings } from './ComicTranslationProviderSettings'
import { LlmSourceProfileRepository } from './LlmSourceProfileRepository'
import { LlmSourceMigrationService } from '../services/LlmSourceMigrationService'
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
import { CustomProfile } from '../model/CustomProfile'

const MAX_PAGE_CACHE_PRELOAD_CONCURRENCY: number = 2

/**
 * Restores persisted settings from storage into their AppStorageV2 mirrors. Settings that can affect
 * the first mounted route are restored by loadForFirstContent; service-only state and maintenance are
 * restored by loadDeferred after content mounting. loadAll retains the complete explicit reload used by
 * backup restore. Each phase is best-effort and must never reject.
 *
 * M3: restores the persisted auth cookie bundle (CookieJarSettings) so a logged-in user
 * stays logged in across restarts. Later milestones wire SiteModeSettings / ListModeSettings /
 * ThemeSettings / ReadingSettings / DownloadSettings here too.
 */
export class SettingsBootstrap {
  /** Restore state that can affect the first mounted page. */
  static async loadForFirstContent(context: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now()
    try {
      // These settings read independent keys from one Preferences store. Start the native reads together,
      // then keep the first mount behind the completed group so appearance never flashes through defaults.
      await Promise.all([
        ThemeSettings.restore(context),
        ThemeColorSettings.restore(context),
        ImmersiveMaterialSettings.restore(context),
        LanguageSettings.restore(context),
        ScreenOrientationSettings.restore(context),
        TabletLayoutSettings.restore(context),
        SafeModeSettings.restore(context),
      ])

      // Auth must be ready before site mode, favorite slots, and persisted sub-tab selection are normalized.
      await CookieJarSettings.restore(context)

      await Promise.all([
        SiteModeSettings.restore(context),
        ListModeSettings.restore(context),
        GalleryDetailTransitionSettings.restore(context),
        GalleryTitleSettings.restore(context),
        ReadModeSettings.restore(context),
        ReaderImageCacheSettings.restore(context),
        ThumbnailModeSettings.restore(context),
        CoverBackgroundSettings.restore(context),
        ActionAlignmentSettings.restore(context),
        ReadButtonStyleSettings.restore(context),
        SearchFilterSettings.restore(context),
        FavcatListSettings.restore(context),
        SubtabSelectionSettings.restore(context),
        AppColorFavoritesSettings.restore(context),
        HomeTabSettings.restore(context),
        ToplistFilterSettings.restore(context),
        ClipboardLinkSettings.restore(context),
        WebLoginStyleSettings.restore(context),
        ImageBlockSettings.restore(context),
        TagTranslationSettings.restore(context),
        CommentTranslationSettings.restore(context),
        ComicTranslationProviderSettings.restore(context),
        DownloadSettings.restore(context),
        SecuritySettings.restore(context),
      ])

      // RDB-backed restores remain ordered: they share migrations/write schedulers and feed the initial
      // Home/Favorites/Watched state. Parallelizing those stores risks lock contention and stale snapshots.
      await SearchHistorySettings.restore(context)
      await LocalFavSettings.restore(context)
      await ViewedHistorySettings.restore(context)
      await GalleryReadProgressSettings.restore(context)
      // Seed/restore the custom home sub-tab profiles (Phase 1: holder only; the bar still reads
      // HomeSourceState until Phase 2 wires it to profiles). Migrates the legacy HOME_SOURCE selection.
      await CustomProfilesSettings.restore(context)
      await LocalBlockSettings.restore(context)
      DiagnosticLogger.info(
        'settings',
        'first_content_settings_loaded',
        `durationMs=${Date.now() - startedAt}`,
      )
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('settings', 'first_content_settings_failed', e.message)
    }
  }

  /** Restore startup services that do not affect the already mounted first page. */
  static async loadDeferred(context: common.UIAbilityContext): Promise<void> {
    const startedAt: number = Date.now()
    try {
      await LlmSourceMigrationService.migrateIfNeeded(context)
      await LlmSourceProfileRepository.restore(context)
      await SyncSettings.restore(context)
      await DiagnosticsSettings.restore(context)
      await DownloadQueueSettings.restore(context)
      ImagePipelineService.pruneReaderFileCache(context).catch((error: Error) => {
        DiagnosticLogger.warn('image-cache', 'reader_disk_startup_prune_failed', error.message)
      })
      ImagePipelineService.pruneImageBlockThumbnailFallbackCache(context).catch((error: Error) => {
        DiagnosticLogger.warn('image-cache', 'fallback_disk_startup_prune_failed', error.message)
      })
      ImagePipelineService.pruneImageBlockPreviewCache(context).catch((error: Error) => {
        DiagnosticLogger.warn('image-cache', 'image_block_preview_startup_prune_failed', error.message)
      })
      // Cache warming is optional: active Home/Favorites VMs fall back to the same RDB load when it
      // has not completed. Keep durable settings on the startup path, but let windowStage begin mounting first.
      SettingsBootstrap.schedulePageCachePreload(context)
      TagTranslationSettings.scheduleStatusRefresh(context)
      DiagnosticLogger.info(
        'settings',
        'bootstrap_loaded',
        `deferredDurationMs=${Date.now() - startedAt}`,
      )
      // Fire-and-forget (NOT awaited): reconcile My Tags after both cookies and site mode are restored.
      // It is login-gated and never blocks the first paint.
      UserTagLoader.reconcileActiveContext()
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('settings', 'bootstrap_failed', e.message)
    }
  }

  /** Full reload entrypoint retained for backup restore and other explicit in-process reapplication. */
  static async loadAll(context: common.UIAbilityContext): Promise<void> {
    await SettingsBootstrap.loadForFirstContent(context)
    await SettingsBootstrap.loadDeferred(context)
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
      // Home tabs are custom profiles now. Every profile, including favorite-type profiles, owns a
      // revisioned cache because its query can differ from the standalone Favorites page.
      const profiles: CustomProfile[] = connectCustomProfiles().profiles
      const selectedProfile: CustomProfile | null = connectCustomProfiles().findByUuid(
        connectCustomProfiles().selectedUuid,
      )
      if (selectedProfile !== null && !selectedProfile.hidden) {
        SettingsBootstrap.appendPreloadKey(
          keys,
          EhPageCacheService.homeProfileKey(
            isEx,
            selectedProfile.uuid,
            selectedProfile.contentRevision(),
          ),
        )
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
        if (!p.hidden) {
          SettingsBootstrap.appendPreloadKey(
            keys,
            EhPageCacheService.homeProfileKey(isEx, p.uuid, p.contentRevision()),
          )
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
