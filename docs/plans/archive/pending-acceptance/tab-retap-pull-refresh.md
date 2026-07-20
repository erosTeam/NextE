# Re-tap bottom tab → scroll-to-top + pull-refresh (连点 tab 刷新)

Status: implemented, pending build + device acceptance. Ported from V2Next MainTabIcon.onSelectedClick /
triggerRootRefresh / rootRefreshAction.

## What

Re-tapping the icon of the ALREADY-ACTIVE bottom tab refreshes whatever list is on screen — it scrolls the
active list to the top and runs its pull-to-refresh (exactly the V2Next behaviour). Tapping a different tab
still just switches tabs. Applies to the three gallery-list tabs (Gallery / Favorites / Toplist); Downloads
and Settings have no pull-refresh list, so re-tap is a no-op there.

## How (NextE port)

V2Next threads a `rootRefreshAction` up from each page. NextE's nav shell already tracks each tab's ACTIVE
sub-tab Scroller (the `onScrollerReady` chain), so instead of new plumbing through the retained-subtab
framework we route by Scroller:

- `RootRefreshRegistry` (shared, new): `Map<Scroller, () => void>`. Each list body registers
  `(its Scroller → () => its PullRefreshController.triggerTopRefresh())`.
- `GalleryListBody` (Gallery + Toplist sub-tabs) and `FavcatPage` (Favorites sub-tabs) register on
  `aboutToAppear`, unregister on `aboutToDisappear` (keyed by their passed-in Scroller; each retained
  sub-tab owns a distinct one).
- `MainTabIcon`: gains `@Event onSelectedClick`; its `.onClick` fires it only when `currentIndex === idx`
  (the re-tap case — a different tab leaves the index unchanged so HdsTabs handles the switch).
- `Index.tabIcon` passes `onSelectedClick: (i) => this.triggerRootRefresh(i)`; `triggerRootRefresh(i)` calls
  `RootRefreshRegistry.trigger(this.homeTabScrollers[i])` (the active sub-tab's Scroller it already tracks).

`PullRefreshController.triggerTopRefresh()` already does scroll-to-top + the pull animation + the onRefresh
callback (→ `vm.refresh()`), with guards against double-firing — so the registry action is a one-liner.

## Files

New: `shared/.../utils/RootRefreshRegistry.ets` (+ Index export).
Edited: `feature/home/.../components/GalleryListBody.ets`, `feature/user/.../components/FavcatPage.ets`,
`entry/.../components/MainTabIcon.ets`, `entry/.../pages/Index.ets`.

## Notes

- No new permissions / i18n / state. Registry keyed by Scroller identity; only the active sub-tab's Scroller
  is ever triggered, even though all retained sub-tabs register.
- Downloads/Settings: re-tap is a no-op (no pull-refresh list). Scroll-to-top there is a possible follow-up
  (Index already has `scrollActiveTabToTop()`).
