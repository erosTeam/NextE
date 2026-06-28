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
import { EhPageCacheService } from '../services/EhPageCacheService'
import { connectSiteMode } from '../state/SiteModeState'
import { connectHomeSource } from '../state/HomeSourceState'
import { connectFavSelection } from '../state/FavSelectionState'
import { connectCustomProfiles } from '../state/CustomProfilesState'
import { CustomProfile, PROFILE_TYPE_FAVORITE } from '../model/CustomProfile'

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
      await TagTranslationSettings.restore(context)
      await CommentTranslationSettings.restore(context)
      await LocalBlockSettings.restore(context)
      await SyncSettings.restore(context)
      await DiagnosticsSettings.restore(context)
      await DownloadSettings.restore(context)
      await DownloadQueueSettings.restore(context)
      DownloadQueueSettings.resumePendingDownloads(context)
      await SecuritySettings.restore(context)
      await SettingsBootstrap.preloadPageCaches(context)
      DiagnosticLogger.info('settings', 'bootstrap_loaded', 'cookie jar restored')
      // Fire-and-forget (NOT awaited): load the user's My Tags for per-tag list colors. It's a network
      // round-trip and login-gated, so it must never block the first paint; logged-out users skip it.
      UserTagLoader.loadIfLoggedIn()
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('settings', 'bootstrap_failed', e.message)
    }
  }

  private static async preloadPageCaches(context: common.UIAbilityContext): Promise<void> {
    try {
      const isEx: boolean = connectSiteMode().isEx
      const home = connectHomeSource()
      const fav = connectFavSelection()
      const favOrder: string = fav.orderByPosted ? EhConstants.FAV_ORDER_POSTED : EhConstants.FAV_ORDER_FAV
      const jobs: Promise<void>[] = []
      // Home tabs are custom profiles now; warm each non-hidden, non-favorite profile's uuid-scoped
      // cache (favorite-type profiles use the favorites cache key — handled with the favorites preload).
      const profiles: CustomProfile[] = connectCustomProfiles().profiles
      for (let i = 0; i < profiles.length; i++) {
        const p: CustomProfile = profiles[i]
        if (!p.hidden && p.listType !== PROFILE_TYPE_FAVORITE) {
          jobs.push(EhPageCacheService.preloadGalleryList(
            context,
            EhPageCacheService.homeProfileKey(isEx, p.uuid),
          ))
        }
      }
      const toplistTls: number[] = [11, 12, 13, 15]
      for (let i = 0; i < toplistTls.length; i++) {
        jobs.push(EhPageCacheService.preloadGalleryList(
          context,
          EhPageCacheService.homeListKey(isEx, 'toplist', toplistTls[i]),
        ))
      }
      const favcats: string[] = ['a', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
      for (let i = 0; i < favcats.length; i++) {
        jobs.push(EhPageCacheService.preloadGalleryList(
          context,
          EhPageCacheService.favoritesListKey(isEx, favcats[i], favOrder),
        ))
      }
      await Promise.all(jobs)
      DiagnosticLogger.info('page-cache', 'preload_done', `jobs=${jobs.length} selected=${connectCustomProfiles().selectedUuid}/${home.toplistTl}/${fav.selectedFavcat}`)
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'preload_failed', (error as Error).message)
    }
  }
}
