import { EhMytags } from '../model/EhMytags'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'
import { connectSiteMode } from '../state/SiteModeState'
import { EhCookieStore } from '../network/EhCookieStore'
import { EhApiService } from '../network/EhApiService'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Loads the user's My Tags into the global usertag store once, in the background. eros_fe defers this a
 * few seconds after startup; we fire it from bootstrap (after cookies are restored) WITHOUT blocking the
 * first paint — getMyTags is a network round-trip. Gated on login: logged-out users keep neutral tags.
 */
export class UserTagLoader {
  static async loadIfLoggedIn(): Promise<void> {
    if (!EhCookieStore.getInstance().isLogin()) {
      return
    }
    try {
      const mytags: EhMytags = await EhApiService.getInstance().getMyTags(connectSiteMode().isEx, '')
      UserTagStore.getInstance().setTags(mytags.tags)
      // Bump the reactive signal so any already-rendered list cards re-color (cold-start race fix).
      const sig: UserTagSignal = connectUserTagSignal()
      sig.version = sig.version + 1
      DiagnosticLogger.info('usertag', 'loaded', `${mytags.tags.length} tags`)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('usertag', 'load_failed', e.message)
    }
  }
}
