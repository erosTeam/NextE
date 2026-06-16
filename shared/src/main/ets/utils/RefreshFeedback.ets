import { promptAction } from '@kit.ArkUI'

/**
 * Centralized feedback for a failed pull-to-refresh (V2Next RefreshFeedback). The shared
 * `PullRefresh` calls this when its refresh callback REJECTS; initial loads keep their
 * inline error view, so an empty-list first-load failure is never double-reported here.
 */
export class RefreshFeedback {
  static notifyRefreshFailed(): void {
    try {
      promptAction.showToast({ message: $r('app.string.common_refresh_failed') })
    } catch (_error) {
    }
  }
}
