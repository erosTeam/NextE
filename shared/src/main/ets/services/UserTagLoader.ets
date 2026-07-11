import { EhMytags } from '../model/EhMytags'
import { EhApiService } from '../network/EhApiService'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  UserTagContextService,
  UserTagRequestContext,
  UserTagRequestFence,
} from './UserTagContextService'

/**
 * Reconciles the user's My Tags with the active account/site in the background. The mutable lookup cache
 * is deliberately plain, so every request snapshots credentials + site and must pass the context fence
 * before it can update colors or hide rules.
 */
export class UserTagLoader {
  private static activeRequest: UserTagRequestContext | null = null

  /** Compatibility entry point for bootstrap; reconciliation is intentionally fire-and-forget. */
  static loadIfLoggedIn(): void {
    UserTagLoader.reconcileActiveContext()
  }

  /** Clear old cache data synchronously before a caller replaces the active cookie jar. */
  static invalidateActiveContext(): void {
    UserTagLoader.activeRequest = null
    UserTagContextService.reset()
  }

  /** Start one load per authenticated account/site scope; unchanged scopes are a no-op. */
  static reconcileActiveContext(): void {
    const active: UserTagRequestContext = UserTagContextService.captureActiveRequest()
    if (!UserTagRequestFence.matchesAuthenticated(active, active)) {
      UserTagLoader.invalidateActiveContext()
      return
    }
    const previous: UserTagRequestContext | null = UserTagLoader.activeRequest
    if (
      previous !== null &&
      UserTagRequestFence.sameScope(previous, active) &&
      UserTagContextService.isCurrentAuthenticated(previous)
    ) {
      return
    }
    UserTagLoader.invalidateActiveContext()
    const request: UserTagRequestContext = UserTagContextService.captureActiveRequest()
    UserTagLoader.activeRequest = request
    UserTagLoader.load(request).catch((error: Error) => {
      DiagnosticLogger.warn('usertag', 'load_failed', error.message)
    })
  }

  private static async load(request: UserTagRequestContext): Promise<void> {
    try {
      const mytags: EhMytags = await EhApiService.getInstance().getMyTags(request.isEx, '')
      if (
        UserTagLoader.activeRequest !== request ||
        !UserTagContextService.publishMyTags(request, mytags.tags)
      ) {
        return
      }
      DiagnosticLogger.info('usertag', 'loaded', `${mytags.tags.length} tags`)
    } catch (error) {
      if (UserTagLoader.activeRequest === request && UserTagContextService.isCurrentAuthenticated(request)) {
        throw error as Error
      }
    }
  }
}
