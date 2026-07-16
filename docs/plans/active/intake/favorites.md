# Favorites Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- This file is an evidence ledger, not a priority queue. Start from the user's latest request and use `../product-bug-intake.md` for intake writing rules.
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

- Current durable gates: `node scripts/test_search_history_rdb_contract.mjs`,
  `node scripts/test_local_favorites_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`,
  `python3 scripts/check_i18n_duplicates.py`, and `git diff --check`.
- The former Search UI/source-shape contracts are retired and no longer exist in `scripts/`; device
  layout/screenshots and the real user path below are the acceptance evidence for this UI behavior.
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

Follow-up implementation candidate, 2026-07-16:

- User report: favorites-origin Search could return no matches because it silently inherited the
  Favorites tab's current `favcat`; selecting local favorites produced the invalid remote scope
  `favcat=l`. The filter sheet also appeared unable to switch back to Gallery or Watched because the
  route-owned `isFavoriteScope` overrode the persisted filter scope in both the title and request path.
- FE/source grounding: `../eros_fe/lib/pages/tab/view/search_page.dart` switches a Search request to
  favorite list type without inheriting the active Favorites folder. EH `favorites.php` accepts one
  `favcat`, so folder filtering is single-select rather than multi-select.
- Current working change makes scope and favorite folder page-session state, defaults the Favorites
  entry to `favorite + all`, and removes search scope from the persisted advanced-filter snapshot.
  Gallery / Watched / Favorite now drive one request-target value, so switching the segment can change
  the endpoint instead of being overridden by the entry route.
- The Favorite filter surface reuses `FavoriteSelectorPage` row hierarchy: colored heart + folder
  title, with the trailing count/current badge replaced by the native ArkUI `Radio`. It lists `全部`
  plus remote slots `0..9`; local `l` stays out because it is not a `favorites.php` category.
- The Search title shows `收藏` for all folders and `收藏 · <folder>` for a specific folder, making the
  active server scope visible outside the sheet.
- Static evidence: V1 decorator inventory reports `0 file(s)`; i18n parity and `git diff --check`
  pass; `scripts/build_hvigor_signed.sh` completes with `BUILD SUCCESSFUL`.
- HarmonyOS device evidence, 2026-07-16, user-selected device shorthand `237` resolved live to
  `192.168.50.237:12345`: installed the current signed HAP and ran the complete Favorites -> Search
  path. Search opened in Favorite scope with history/compose content and no inherited folder title.
- Filter evidence confirms Favorite is the initially selected segment, `全部` is the only checked native
  `Radio`, and the folder rows mirror the Favorites category page. Selecting `本子` flips `a=false` /
  `1=true`; closing the sheet changes the title to `收藏 · 本子`.
- Scope-switch evidence confirms the same sheet can select Gallery (`画廊=true`) and Watched
  (`订阅=true`); Gallery restores gallery-only advanced filter content instead of remaining pinned to
  the route's Favorite type. Switching back to Favorite retains the session folder choice.
- Positive result evidence: after selecting `全部`, submitting `Yor` in Favorite scope returned multiple
  real favorites, including `[Raiti] Yor helps Anya make friends (Spy X Family)` and
  `[アヘ丸] 浮浪者につかまるヨルさん①-② [中国翻訳]`; the original empty-result path is no longer
  reproduced.
- Evidence root: `.hvigor/outputs/favorites-search-237-20260716/`, especially `05-filter-sheet/`,
  `06-folder-selected/`, `07-gallery-scope/`, `08-watched-scope/`, `09-folder-title/`, and
  `10-search-results/`. The Gallery/Watched request-target mapping is source-backed; this device pass
  verifies their selectable UI/session state but did not capture raw remote request URLs.

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

- Late favcat metadata arrival and datasource replacement are validated through the signed build and
  device path; the former source-shape contract is retired.
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

### Search Result Favorite Heart Color Can Disagree With Favorites Page

Type: favorites metadata / cross-list visual-state consistency bug

Priority suggestion: P1/P2

Status: implemented / pending device acceptance

Implementation:

- Current implementation commit: `FavcatSlotResolver` is now shared by Favorites and Search. It builds
  a non-placeholder `favTitle -> favId` map and can either mutate fresh fetched rows before render or
  return copied rows for already-rendered datasources.
- `SearchViewModel` resolves `list.gallerys` from `list.favList` on initial search, refresh, and
  loadMore before rendering/appending.
- `GallerySearchPage` observes account-level `favSel.favList` and re-resolves visible Search rows when
  real favcat metadata arrives after the current page has already rendered.
- `FavoritesViewModel` now reuses the same resolver, so Favorites and Search cannot drift into two
  separate `favTitle -> slot` policies.

Verification:

- Deterministic: `node scripts/test_search_favorite_slot_resolver_contract.mjs`,
  `node scripts/test_favorites_search_contract.mjs`, `node scripts/test_favcat_color_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`, and `git diff --check`.
- Build: `scripts/build_hvigor_signed.sh` passed.
- Simulator smoke: installed the signed HAP on local target `127.0.0.1:5555`, cold-started NextE, and
  captured evidence at `.hvigor/outputs/search-favorite-slot-resolver/screen.jpeg` and
  `.hvigor/outputs/search-favorite-slot-resolver/layout.json`.

Still pending:

- Controller/device acceptance should reproduce the original mismatching Search result and confirm the
  heart color updates to match Favorites after real favcat metadata is available in the same process.

Follow-up, 2026-06-22:

- User feedback: entering `热门` / normal Home list directly can still show every favorited gallery with
  the default red favorite icon instead of the real favorite-folder color. This is a common metadata
  resolution problem, not a per-page color tweak.
- Current code inspection shows `shared/src/main/ets/utils/FavcatSlotResolver.ets` is already the shared
  non-placeholder `favTitle -> favcat` resolver, but it is only wired through Favorites and Search.
  `feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets` does not currently consume the resolver
  or re-resolve visible Home/Popular rows when `favSel.favList` metadata arrives.
- Card components still color from `gallery.favcat`; if a row only has `favTitle`, the heart falls back
  to the generic favorite color. Fixing only one entry page will leave the same bug on another list
  surface.
- Next repair should route all gallery-list-producing surfaces through the same resolver path: Home,
  Popular, Watched/retained Home sub-tabs, Toplist if it carries favorite state, Search, Favorites, and
  their List/Simple/Grid/Waterfall card presentations. Prefer wiring the existing shared resolver into
  fetch/refresh/loadMore and late account-metadata-change paths rather than copying page-local fixes.
- Acceptance should include a favorited gallery visible from `热门` whose `favTitle` is known but whose
  `favcat` slot is initially empty; once real favcat metadata exists in-process, the Home/Popular heart
  color must match Favorites without restart.

Status, 2026-06-22: implemented / pending controller acceptance.

- Scope: `GalleryListViewModel` now applies the shared non-placeholder `FavcatSlotResolver` to Home
  gallery-list fetch, refresh, load-more, and toplist load-more results, and exposes a late
  `resolveVisibleFavoriteSlotsFrom(...)` path for already-rendered rows.
- `GalleryListBody` monitors shared account favcat metadata and asks the VM to re-resolve visible rows
  when real favcat names/slots arrive after the list has rendered.
- Verified: `node scripts/test_v1_decorator_inventory_contract.mjs`, `git diff --check`, official signed build,
  and local emulator Home render smoke at `.hvigor/outputs/common-favcat-color/`.
- Still pending: controller/device acceptance with a real Home/Popular row that initially has
  `favTitle` but empty `favcat`, proving the heart color updates in-process after real favcat metadata
  arrives.

Source:

- User feedback, 2026-06-20: in some list results obtained through Search, the favorite heart icon color
  for already-favorited galleries does not match the gallery's actual favorite category. Opening the same
  gallery/list through Favorites shows the correct color.

Observed behavior:

- The mismatch is not universal; it appears in certain searched-result lists.
- Favorites pages can show the same favorite state correctly, so the favcat color table and Favorites
  list rendering are not globally broken.
- This suggests a Search/list metadata propagation issue rather than a pure color-token issue.

Likely cause to verify:

- `EhGalleryListParser` can derive `gallery.favcat` from list-row favorite border color when present.
  On `favorites.php`, it often gets only `favTitle`, and `FavoritesViewModel` resolves `favTitle ->
  favcat` against parsed favcat metadata before rendering or after late metadata arrival.
- `SearchViewModel` currently renders both normal search results and favorite-scope search results, but
  it does not have an equivalent late `favTitle -> favcat` re-resolve path for visible rows.
- A search result row may therefore carry `favTitle` without the matching numeric slot, or carry a stale
  / fallback slot, causing `GalleryCard`, `GalleryGridCard`, `GallerySimpleCard`, and Waterfall cards to
  paint the heart with the wrong or default color.

Expected behavior:

- Any visible gallery card surface that indicates "already favorited" should use the same account-level
  favcat slot mapping as Favorites.
- Search results, favorite-scope search, Home/list browsing, Grid, Simple, and Waterfall cards should
  agree on the heart color for the same gallery once real favcat metadata is available.
- If the current page only knows `favTitle`, it should resolve that name to the remote slot using the
  same non-placeholder favcat metadata as Favorites. If it cannot resolve, it should use the neutral
  fallback intentionally, not a wrong category color.

Implementation direction:

- Extract the Favorites `favTitle -> favcat` resolution into a shared helper or shared account-level
  favorite metadata service instead of keeping it private to `FavoritesViewModel`.
- Let `SearchViewModel` re-resolve visible rows when favorite metadata changes, mirroring
  `FavoritesViewModel.resolveVisibleFavoriteSlotsFrom(...)`.
- Consider the same helper for Home/Search/Favorites retained-list mutation paths so a remote favorite
  write or late favcat metadata parse updates all already-rendered lists consistently.
- Keep placeholder favcats (`Favorites N / 0`) excluded from the mapping, matching the existing
  Favorites safeguard.

Acceptance shape:

- Reproduce with a favorited gallery visible in Search results whose heart color currently disagrees
  with the Favorites page.
- After real favcat metadata is loaded, Search result heart color matches the Favorites page without
  requiring app restart.
- Favorite-scope search through `favorites.php f_search` also matches the selected/actual favorite
  slot.
- Contracts should cover Search visible-row late resolution, placeholder exclusion, and card surfaces
  using `gallery.favcat` only after a real slot is resolved.
