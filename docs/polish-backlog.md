# Polish Backlog — table-site experience alignment

Durable worklist for the `/loop` table-site polish pass. Doctrine: native HDS first; read the
V2Next equivalent before writing; reuse the shared framework; any hand-rolling becomes a shared
`@ComponentV2`/holder. Each item is verified on device `192.168.50.237:12345` before it is checked
off. Source: 8-agent audit workflow `wg156753f`.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done (device-verified).

## P0

- [x] **Rank 1 — ReaderPage HDS destination + safe-area counter.** Bare `NavDestination()` →
  `HdsNavDestination()` (keep `.hideTitleBar(true)`, V2Next ImagePreviewPage pattern). Add
  `private layout: LayoutSafeAreaState = connectLayoutSafeArea()`. Page counter
  `.margin({ bottom: 36 })` → `.margin({ bottom: this.layout.bottomAvoidHeight + SPACE_MD })` so it
  clears the gesture bar on every device.

## P1

- [x] **Rank 9 — Reader counter scrim token.** Counter `backgroundColor('#99000000')` magic literal →
  shared `ThemeConstants.OVERLAY_SCRIM` (V2Next hardcodes per-page; a shared token is the
  doctrine-correct version). Done alongside Rank 1, same file.
- [x] **Rank 2 — Shared list scaffolds (prereq for 3–6).** Copied `SecondaryListScaffold`,
  `GroupedListSection`, `ConciseListRow`, `SectionHeader` from V2Next into NextE `shared/.../components/`;
  added `ThemeConstants.LIST_SECTION_INSET/LIST_ROW_RADIUS/LIST_ROW_TEXT_INDENT/FONT_SIZE_LIST_ITEM`;
  exported all four from `shared/Index.ets`. Adaptations: dropped the no-op `LanguageState` passthrough
  (NextE has no in-app locale override) and inlined the leading-image normalizer (no `ImageUtils`).
  Verified end-to-end via the Settings rewrite (Rank 3).
- [x] **Rank 3 — Settings → `SecondaryListScaffold` + grouped rows.** SettingsPage now renders one
  `GroupedListSection` of two `ConciseListRow`s (站点 / 关于) on `SecondaryListScaffold`; custom
  `@Builder row()` + manual safe-area padding deleted. Device-verified. **Favorites intentionally NOT
  moved to `SecondaryListScaffold`**: favorites is a *gallery* list → when login (M3) lands it belongs
  on `PullRefreshListScaffold` + `GalleryCard` like Home/Search, not the settings-style row scaffold.
  Kept as the honest login-gated empty state for now.
- [x] **Rank 4 — GalleryDetailPage → `SecondaryListScaffold`.** Extracted header/tags/preview into
  `GalleryHeaderCard` / `GalleryTagsCard` / `GalleryPreviewGrid` `@ComponentV2` structs under
  `feature/gallery/components/`, each wrapping its content in `GroupedListSection` (triplicated
  `.padding/.borderRadius/.backgroundColor` chrome gone). Page now lays them out as `ListItem`s on
  `SecondaryListScaffold` (scaffold owns the title-bar + gesture-bar insets). Children re-render on
  the VM's `@Trace gallery/images` reference swap. Device-verified — no visual regression.
- [x] **Rank 5 — Title-bar search → HDS field + `SearchActionState`.** Ported `AppSearchField` (HDS
  immersive ULTRA_THIN material + built-in 搜索 button; reads `fieldText` not keyword to avoid IME flap)
  and `SearchActionState` (keyword + submitSeq + seedSeq + pendingQuery) into `shared/`. `SearchTitleField`
  now hosts `AppSearchField` and writes keyword/submitSeq; `GallerySearchPage` reacts via
  `@Monitor('actionState.submitSeq')`. Retired `SearchQueryState` + its `Date.now()`-string hack.
  Adaptations: inlined the material (no `ImmersiveMaterialSettings` user-setting layer); `autoFocus: false`
  (persistent tab, not a pushed page). Device-verified: typing "naruto" + 搜索 loads real results.
- [~] **Rank 6 — GalleryCard chrome → `GroupedListSection`. SKIP (forced churn).** GalleryCard is a
  *content* card (like V2Next's TopicCard), which self-applies chrome and is never wrapped in
  `GroupedListSection` (that's for grouping multiple settings-style rows under one outer card). Wrapping
  conflicts padding semantics (12dp interior vs 4dp inset) for zero dedup. Revisit only if a broader
  list-card refactor across all content types is ever planned. *(5-agent eval `wg3r5vhu5`.)*
- [~] **Rank 7 — Extract `ZoomableImageView`. SKIP (premature).** Single consumer (the reader); the
  gesture logic is carefully tuned (vertical-only pan so horizontal swipe reaches the Swiper, `zoomScale`
  reserved-word avoidance, unconditional gesture binding). Extracting now is premature abstraction that
  risks that tuning. Revisit when a 2nd zoomable-image surface appears.
- [~] **Rank 8 — Descriptor-driven `routerMap`. SKIP (over-engineering at this scale).** 3 routes
  (GalleryDetail/Reader/Download) vs V2Next's 30+. A coordinator/descriptor indirection adds boilerplate
  without dedup. Revisit at ~7+ routes with varied title-bar/transition behavior.

## P2

- [x] **Rank 10 — Floating-bar polish (the genuine half).** `barFloatingStyle.barBottomMargin`
  SPACE_LG→SPACE_XL + `adaptToHandedness: true` in `Index.ets` — visible breathing room + native
  left/right-hand support (matches V2Next `Index.ets:620`). Device-verified. **`badgeCount`/`onSelectedClick`
  on MainTabIcon SKIPPED as speculative**: no unread/notification data source and no re-select-scroll-to-top
  UX exist yet — would be dead code. Add alongside the feature that needs them.
- [~] **Rank 11 — SettingsPage SectionHeader grouping. DEFER.** One 2-row group → a header is visual
  noise (V2Next uses headers for 3+ distinct groups). Worth it once the full settings tree (reading /
  layout / download / network / uconfig) lands and there are multiple groups to separate.

---

## Extended polish — round 2 (deep audit `wjb4w7z7z`, 2026-06-14)

User opted to broaden scope past the 11-item audit. A 4-agent deep audit (dark-mode / state-handling /
pagination / visual-polish) drove this round.

- [x] **Dark mode — page-by-page, device-verified.** `app.color.*` tokens all carry genuine dark overrides
  (card #FFFFFF→#191919, bg #F5F5F5→#121212, text #1A1A1A→#EDEDED, …) and pages otherwise use
  auto-adapting `sys.color.*`. Confirmed visually in dark on home/list/detail/settings/search (incl. the HDS
  immersive search material + floating bar) via a temporary `setColorMode(DARK)` pass that was reverted.
- [x] **Loading/empty/error state gaps.** HomePage → shared `PageLoadingState`/`PageErrorState`/`CardEmptyState`
  (was: spinner forever on an empty feed). GalleryDetailPage renders `vm.error` + retry on load failure
  (keeps the seeded header). ReaderPage shows white error+retry on the black canvas when all preview pages
  fail. `ReaderViewModel` clears stale `error` on each `loadMore`.
- [x] **Pagination races.** `GalleryListViewModel.refresh()` + `SearchViewModel.refresh()` now guard
  `isLoading/isLoadingMore` and flag `isLoading` so a concurrent `loadMore` can't interleave `appendData`
  with `setData`.
- [x] **i18n hardcoded strings — DONE, device-verified.** Added `nav_gallery`, `gallery_preview`,
  `detail_read`/`detail_read_with_count` (`%s`), `image_load_failed`, `settings_site`, `settings_about`,
  `gallery_meta` (`%s页 · %s · 收藏 %s` zh / `%sP · %s · Favorited %s` en/ja) to base+zh_CN+en_US+ja_JP;
  replaced every user-facing literal in GalleryDetailPage / GalleryPreviewGrid / GalleryHeaderCard /
  ReaderPage / SettingsPage; reader retry reuses `common_retry`. i18n parity gate green; zh render unchanged
  ("49页 · 23.02 MiB · 收藏 5 times"). `gallery_meta` keeps EH's own favcount string ("N times"/"Never"/"Once")
  as the last `%s` — wrapper labels localize, no parser change / pluralization needed.
- [~] **SKIP (audit findings rejected on review):** the claimed `ReaderViewModel.ensureLoadedUpTo` off-by-one
  (verified `<=` is *correct* — `<` under-loads at exact batch boundaries); padding→token nitpicks (invisible
  churn, and 2px→SPACE_XS=4px would change spacing); `refresh()` `hasMore`-on-error reset (changes pagination
  semantics for speculative benefit).

## Status: backlog resolved (2026-06-14)

Every audit item is now either **done + device-verified** (Ranks 1, 9, 2, 3, 4, 5, 10-margins) or
**deliberately not done** with a documented "revisit when X" condition (Ranks 6, 7, 8, 11, 10-badge) —
the latter validated by an independent 5-agent evaluation (`wg3r5vhu5`) specifically to avoid churning
working UI. The table-site core flow (home → detail → reader → search → settings) runs end-to-end on the
shared V2Next framework with correct safe-area insets, no title/status-bar overlaps, and real EH data.
Next natural scope is a new milestone (login / ExHentai / real favorites — M3), not more table-site polish.
