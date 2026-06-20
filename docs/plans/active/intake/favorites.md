# Favorites Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Favorites Favcat Selector Page

Type: parity / UX gap

Priority suggestion: P1/P2

Status: implemented / needs controller acceptance

Implementation:

- `7322126 feat(favorites): add favcat selector` adds a Favorites title action that opens a
  full-screen `FavoriteSelectorPage`.
- Scope: native HDS list overview of `全部` plus server favcats, colored heart leading icon per
  favcat, trailing counts, current selection marker, and tap-to-select returning to Favorites.
- `ceaa966 feat(favorites): show local slot in selector` closes the local-slot gap: logged-out selector
  rows are local-only, logged-in selector rows are `全部` plus remote favcats plus local `l`, and the
  logged-out Favorites title action still opens the selector instead of hiding the entry.
- Explicit non-scope: favorite write/move/rename/delete, per-favcat keep-alive architecture, and
  jump/seek navigation.

Evidence:

- FE source grounding: `../eros_fe/lib/pages/tab/view/favorite_sel_page.dart` and
  `../eros_fe/lib/pages/tab/view/tabbar/favorite_tabbar_page.dart`.
- Deterministic contract: `scripts/test_favorites_selector_contract.mjs`.
- Static gates: `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  `git diff --check`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- HarmonyOS device evidence on `192.168.50.197:12345`: installed signed HAP, opened Favorites,
  confirmed the third title action, opened `收藏分类`, saw rows for `全部/F0/本子/漫画/3D/高分/...`
  with counts, selected `本子`, and returned to Favorites with the `本子` list loaded.
  Evidence directory: `/private/tmp/nexte_favorites_selector_evidence/`, especially
  `nexte_fav_after_fix.jpeg`, `layout_fav_after_fix.json`, `nexte_selector_after_fix.jpeg`,
  `layout_selector_after_fix.json`, `nexte_fav_after_select.jpeg`, and
  `layout_fav_after_select.json`.
- Android FE comparison, 2026-06-19: ADB target `fa967a75`, `su` launched
  `com.honjow.fehviewer/.MainActivity`; from the FE main gallery tab, tapped bottom `收藏`, then tapped
  the Favorite tab bars selector. FE selector evidence shows title `收藏夹` and rows for `所有收藏`,
  remote favcats, and final `本地收藏 0`. Evidence directory:
  `/Users/honjow/git/NextE/.hvigor/outputs/reader-save-fe-comparison/`, especially
  `fe-favorites-tab.png/xml` and `fe-favorites-selector.png/xml`.

Remaining acceptance:

- Needs controller/user acceptance of the NextE selector visual placement and local-slot behavior. No
  further FE comparison is required unless Favorites selector structure changes again.

### Favorites Search Entry Auto-Browses Empty Query Instead Of Showing Search History

Type: Search UX / route initialization bug

Priority suggestion: P1

Status: implemented / pending controller acceptance

Implementation:

- Current working change removes the `GallerySearchPage.onReady()` `vm.search('')` call from the
  favorite route seed path, syncs `SearchPageField` submitted text into the page-owned field state
  before bumping `submitSeq`, and makes `SearchViewModel.search()` / `refresh()` block empty queries in
  every scope.
- Live filter edits now persist but only reapply when the current page field has a non-empty query; empty
  favorite scope remains a compose/history state until the user submits.
- Deterministic contracts updated:
  `scripts/test_search_input_contract.mjs`, `scripts/test_favorites_search_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, and `scripts/test_search_filter_draft_contract.mjs`.

Validation:

- Contracts:
  `node scripts/test_search_input_contract.mjs`,
  `node scripts/test_favorites_search_contract.mjs`,
  `node scripts/test_search_scope_contract.mjs`,
  `node scripts/test_search_filter_draft_contract.mjs`,
  `node scripts/test_search_filter_action_bar_contract.mjs`,
  `node scripts/test_search_filter_ux_contract.mjs`,
  `node scripts/test_search_history_contract.mjs`,
  `node scripts/test_search_tagsuggest_contract.mjs`,
  `node scripts/test_search_route_session_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`,
  `python3 scripts/check_i18n_duplicates.py`,
  `git diff --check`.
- Build: `scripts/build_hvigor_signed.sh` on macOS signing path.
- Device evidence on local HarmonyOS simulator `127.0.0.1:5555`:
  `.hvigor/outputs/search-entry-behavior/after_fav_search.jpeg` /
  `after_fav_search_layout.json` show Favorites title-bar Search opens the favorite-scope Search page
  with the pinned field and search history, not an empty favorite results page.
- Device evidence:
  `.hvigor/outputs/search-entry-behavior/submitted.jpeg` / `submitted_layout.json` show typing
  `nexteprobe` and pressing the field search button enters the search result state (`没有搜索结果` for
  this probe query), proving submit no longer only dismisses input.
- Device evidence:
  `.hvigor/outputs/search-entry-behavior/cleared.jpeg` / `cleared_layout.json` show clearing the field
  returns to the search history/blank compose state and removes the old no-results state.

Source:

- User feedback, 2026-06-20: tapping the Favorites page search button opens the Search page and
  immediately performs an empty favorite search, so the search history / blank compose state is hidden.
  The user has to type anything and clear it before the expected history screen appears.

Observed behavior:

- `Index.openFavoriteSearch()` pushes `SearchPageParams('favorite', favcat)`.
- `GallerySearchPage.onReady()` treats `searchType === 'favorite'` as an instruction to seed favorite
  scope and immediately call `vm.search('')`.
- Prior docs described this as "Favorite-scope empty browse still works", but that conflates a favorite
  browse mode with the title-bar search entry.

Expected behavior:

- The Favorites title-bar search action should open the shared Search page in favorite scope, but remain
  in the search compose state when there is no initial query.
- The pinned search field should be available, and the page should show search history / blank history
  composition just like ordinary Search.
- Only an explicit user submit should run `favorites.php` with `f_search`.
- If NextE still needs an empty favorite browse mode, it must be a separate explicit route flag or entry,
  not the default behavior of the search button.

Implementation direction:

- Add an explicit route/session semantic such as `autoBrowseOnOpen` / `initialBrowse` to
  `SearchPageParams`, defaulting to false for search-entry routes.
- `Index.openFavoriteSearch()` should pass favorite scope and favcat, but should not cause
  `GallerySearchPage` to call `vm.search('')` when `initialQuery === ''`.
- Preserve any existing favorite-scope result search after the user enters a keyword and submits.
- Keep tag/action-seeded searches separate: they still pass `initialQuery` and `focusOnAppear=false`,
  run immediately, and must not show the keyboard.

Acceptance shape:

- From Favorites, tap Search: Search opens in favorite scope, search field is visible, no network search
  for an empty query runs, and search history / blank state is visible.
- Type a keyword and press the IME Search button: favorite search executes against the selected favcat.
- Clear the keyword: the page returns to history / blank compose state.
- Tag/uploader action-seeded searches still open results-first without keyboard focus.
- Deterministic contract covers that favorite-scope route without `initialQuery` does not call
  `vm.search('')`, while an explicit user submit still does.

### Favorites List Favcat Colors Require Restart After First Login

Type: favorites metadata / visual-state refresh bug

Priority suggestion: P1

Status: implemented / pending device acceptance

Implementation:

- Commit pending in current lane: `FavoritesViewModel.resolveVisibleFavoriteSlotsFrom(favcats)` builds a
  non-placeholder `favTitle -> favId` map, scans already-rendered datasource rows with `favTitle` and
  empty `favcat`, replaces changed rows with copied rows carrying the resolved slot, and calls
  `dataSource.setData(...)` only when changed.
- `FavcatPage` now calls the resolver when shared `favSel.favList` changes and immediately after
  publishing merged parsed favcat metadata.
- Existing explicit remote favorite mutation remains authoritative; the late resolver only fills missing
  slots for rows that still have `favcat == ''`.

Verification:

- Deterministic: `node scripts/test_favcat_snapshot_contract.mjs` covers late favcat metadata arrival,
  placeholder exclusion, and datasource replacement after slot resolution.
- Related contracts also passed in this lane: favorites selector, remote favorite sheet, favcat color,
  local favorite toggle, retained subtab framework, V1 decorator inventory, i18n parity, and
  `git diff --check`.
- Simulator: installed signed HAP on local HarmonyOS target `127.0.0.1:5555`; Favorites page evidence
  saved at `.hvigor/outputs/favorite-late-resolve/favorites.jpeg` and
  `.hvigor/outputs/favorite-late-resolve/favorites_layout.json`. The visible Favorites strip retained
  real names/counts (`全部 4396`, `F0`, `本子`, `漫画`, `3D`, `高分`) and the screenshot shows varied
  favcat heart colors rather than one fallback color.

Still pending:

- Fresh-login / cleared-favcat-cache acceptance should still be checked by controller or a dedicated
  device pass because the current simulator already had real account favcat metadata available.

Source:

- User feedback, 2026-06-20: in the Favorites gallery list, all favorite heart icons can initially show
  the same fallback color instead of each gallery's actual favorite category color. After exiting and
  reopening the app, the colors become correct.

Observed behavior:

- The issue appears most likely after first login or first Favorites load in a fresh process.
- Restarting the app makes colors correct, which suggests the persisted favcat metadata restores early
  enough on the second launch, while the first-run in-memory update does not refresh already-rendered
  gallery rows.

Likely cause:

- Favorites list rows often carry `favTitle` but not the numeric `favcat` slot.
- `GalleryCard`, `GalleryGridCard`, and `GallerySimpleCard` color hearts from `gallery.favcat`.
  If `favcat` is empty, even with `favTitle`, they fall back to the generic favorite color.
- `FavoritesViewModel.resolveFavcatSlots()` can map `favTitle -> favcat`, but if real favcat metadata
  arrives after rows are already loaded, the visible datasource may not be re-resolved and replaced.
- Placeholder favcats such as `Favorites N / 0` must not participate in this mapping.

Expected behavior:

- Once real favcat metadata arrives in the current process, already-loaded Favorites rows with
  `favTitle` and empty `favcat` should be re-resolved and the datasource should update.
- Users should not need to restart the app for favorite category colors to become correct.
- Placeholder/default favcat metadata must never overwrite or drive the visible color mapping.

Implementation direction:

- Add a deterministic method on `FavoritesViewModel` to re-resolve visible rows from a real favcat list:
  scan `dataSource.getAll()`, map non-placeholder `favTitle -> favId`, write missing `favcat`, and
  replace the datasource only when changed.
- Trigger that method when shared favcat metadata changes or after a real `favorites.php`/popup favcat
  parse updates `FavSelectionState.favList`.
- Keep explicit favorite mutations authoritative; this re-resolve path should only fill missing slots
  for rows that have `favTitle` but no `favcat`.

Acceptance shape:

- Fresh login/fresh favcat cache: open Favorites, load rows, then load/parse real favcat metadata; visible
  row heart colors update in the same app process without restart.
- Placeholder `Favorites N / 0` entries do not map real rows or overwrite real metadata.
- Restarting the app is not required for correct favcat colors.
- Deterministic contract covers late favcat metadata arrival, placeholder exclusion, and datasource
  replacement after slot resolution.
