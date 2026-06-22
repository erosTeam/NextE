/**
 * Process-wide map from a list's Scroller to its "scroll-to-top + pull-refresh" action, so re-tapping the
 * already-active bottom tab can refresh whatever list is on screen WITHOUT threading a refresh callback
 * through every retained-subtab level (V2Next "连点 tab 刷新").
 *
 * Each list body registers (its Scroller → () => its PullRefreshController.triggerTopRefresh()). The nav
 * shell already tracks each tab's ACTIVE sub-tab Scroller (the onScrollerReady chain), so on a re-tap it
 * looks the action up by that Scroller and fires it. Keyed by Scroller identity because every retained
 * sub-tab owns a distinct Scroller, and only the active one is ever triggered. Bodies unregister on
 * disappear so a recycled list never fires a stale controller.
 */
export class RootRefreshRegistry {
  private static actions: Map<Scroller, () => void> = new Map<Scroller, () => void>()

  static register(scroller: Scroller, action: () => void): void {
    RootRefreshRegistry.actions.set(scroller, action)
  }

  static unregister(scroller: Scroller): void {
    RootRefreshRegistry.actions.delete(scroller)
  }

  // Fire the registered refresh for this Scroller's list, if any (no-op for tabs without a pull-refresh
  // list, e.g. downloads/settings).
  static trigger(scroller: Scroller): void {
    const action: (() => void) | undefined = RootRefreshRegistry.actions.get(scroller)
    if (action !== undefined) {
      action()
    }
  }
}
