import { UIContext } from '@kit.ArkUI'

/**
 * Centralized feedback for a failed pull-to-refresh (V2Next RefreshFeedback). The shared
 * `PullRefresh` calls this when its refresh callback REJECTS; initial loads keep their
 * inline error view, so an empty-list first-load failure is never double-reported here.
 *
 * The caller passes its own UIContext: the context-free `promptAction.showToast` is deprecated,
 * and its replacement (`getUIContext().getPromptAction()`) may throw, so the call stays wrapped.
 */
export class RefreshFeedback {
  static notifyRefreshFailed(ui: UIContext): void {
    try {
      ui.getPromptAction().showToast({ message: $r('app.string.common_refresh_failed') })
    } catch (_error) {
    }
  }
}
