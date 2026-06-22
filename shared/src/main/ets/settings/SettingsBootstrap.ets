import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { CookieJarSettings } from './CookieJarSettings'
import { SiteModeSettings } from './SiteModeSettings'
import { ListModeSettings } from './ListModeSettings'
import { GalleryTitleSettings } from './GalleryTitleSettings'
import { ReadModeSettings } from './ReadModeSettings'
import { ThumbnailModeSettings } from './ThumbnailModeSettings'
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
import { AppColorFavoritesSettings } from './AppColorFavoritesSettings'
import { HomeTabSettings } from './HomeTabSettings'
import { TagTranslationSettings } from './TagTranslationSettings'

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
      await CookieJarSettings.restore(context)
      await SiteModeSettings.restore(context)
      await ListModeSettings.restore(context)
      await GalleryTitleSettings.restore(context)
      await ReadModeSettings.restore(context)
      await ThumbnailModeSettings.restore(context)
      await SearchHistorySettings.restore(context)
      await SearchFilterSettings.restore(context)
      await FavcatListSettings.restore(context)
      await LocalFavSettings.restore(context)
      await ViewedHistorySettings.restore(context)
      await GalleryReadProgressSettings.restore(context)
      await SubtabSelectionSettings.restore(context)
      await AppColorFavoritesSettings.restore(context)
      await HomeTabSettings.restore(context)
      await TagTranslationSettings.restore(context)
      await DownloadSettings.restore(context)
      await DownloadQueueSettings.restore(context)
      await SecuritySettings.restore(context)
      DiagnosticLogger.info('settings', 'bootstrap_loaded', 'cookie jar restored')
      // Fire-and-forget (NOT awaited): load the user's My Tags for per-tag list colors. It's a network
      // round-trip and login-gated, so it must never block the first paint; logged-out users skip it.
      UserTagLoader.loadIfLoggedIn()
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('settings', 'bootstrap_failed', e.message)
    }
  }
}
