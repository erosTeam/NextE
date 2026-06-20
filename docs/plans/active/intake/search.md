# Search Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Search Filter Sheet Edits Commit Before Apply

Type: bug / search workflow

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- Implementation review while validating tag-to-search and Search filter behavior.

Observed behavior:

- Opening the Search filter sheet and tapping filter controls could write directly into the shared
  `SearchFilterState` before the user pressed Apply.
- Closing the sheet without applying could leave active filters changed silently, so a later search or
  apply action could use filter state the user never committed.

Original expected behavior:

- Filter sheet edits are draft-only until Apply.
- Closing/backing out of the sheet discards uncommitted changes.
- Reset is an explicit commit of the empty filter: it closes the sheet and reapplies the current
  query with defaults.

Superseded behavior:

- Later user feedback and Android FE comparison changed the product requirement: Search filters should
  live-apply with immediate visual feedback, no primary Apply button, and Reset as the only explicit
  action. Keep the old evidence as history only; do not restore this Apply/draft model unless a new
  product decision reverses the live-apply lane.

Implementation:

- `e704771 fix(search): draft filter changes before apply` adds local draft fields to
  `SearchFilterSheet`, syncs them from the active filter on each sheet open, and confines active
  `SearchFilterState` writes to `commitDraft()`.
- `GallerySearchPage` now passes an `openSeq` signal so each new sheet open re-syncs the draft from
  the current committed filter.
- `05a9fe8 fix(search): keep filter actions reachable` moves Apply/Reset out of the scroll content
  into a fixed sheet action bar, so the default medium detent exposes commit actions without requiring
  users to expand the sheet.

Evidence:

- Deterministic contracts/gates: `scripts/test_search_filter_draft_contract.mjs`,
  `scripts/test_search_filter_action_bar_contract.mjs`,
  `scripts/test_search_input_contract.mjs`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `bash scripts/setup-local-build-profile.sh` and
  `bash scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened Search via detail tag query `other:"rough translation"`, selected `Manga` in the filter
  sheet, closed with Back, reopened and confirmed the list remained unfiltered; selected `Manga` again
  and tapped Apply, sheet closed and visible results became Manga; reopened and tapped Reset, sheet
  closed and visible results returned to unfiltered/Doujinshi. Evidence directory:
  `/private/tmp/nexte_search_filter_draft_evidence/`, especially
  `search_filter_draft_selected.png`, `search_filter_reopen_after_cancel.png`,
  `search_filter_after_apply.png`, `search_filter_before_reset.png`, and
  `search_filter_after_reset.png`.
- Follow-up Mate X7 emulator pass for the fixed action bar: default medium sheet detent shows
  `重置` and `应用` at bounds `[50,2268][1030,2393]`, no sheet expansion required; tapping `Manga`
  and then Apply from the medium detent closes the sheet and applies Manga results; reopening and
  tapping Reset from the same detent closes the sheet. Evidence directory:
  `/private/tmp/nexte_search_filter_action_bar_evidence/`, especially
  `search_action_bar_sheet_initial.png`, `search_action_bar_sheet_initial.json`,
  `search_action_bar_after_apply.png`, `search_action_bar_after_apply.json`,
  `search_action_bar_before_reset.json`, and `search_action_bar_after_reset.png`.

Remaining acceptance:

- Needs controller/user review of the current evidence. No further device validation is required
  unless Search filter sheet state ownership, apply sequencing, or Search filter persistence changes.

### Search Filter Sheet UX Quality And Interaction Model Are Not Acceptable

Type: UX / interaction bug

Priority suggestion: P0

Status: implemented / needs controller acceptance

Source:

- User-reported current device behavior: search scope, category, and rating controls looked clickable
  but did not visibly update until another scope change forced the sheet to rebuild; the search filter
  entry was also hidden from favorite search and some action-seeded search states.
- Follow-up user feedback: the sheet is still visually low quality; category chips lack color
  semantics; FE likely supports long-press category inverse/solo behavior; rating should be a formal
  segmented/radio-like control; and the interaction model should apply filters live instead of using
  same-weight Apply and Reset actions.

Grounding:

- Required FE comparison target before more NextE product code: Android `eros_fe` search / gallery
  advanced filter surface, especially category color semantics, long-press category behavior, rating
  control shape, live-vs-Apply model, Reset placement/weight, and search-scope expression. FE is the
  product-semantics reference only; NextE should use HarmonyOS/HDS-native controls and not copy pixels.
- Primary information: selected search scope, selected category mask, selected minimum rating, and
  major active toggles should be visually scannable at first glance.
- Primary action: changing scope/category/rating/toggles should immediately update both visual state and
  the active search filter/requery. Secondary action: Reset clears filters explicitly.
- Usable loop: open Search from normal/tag/favorite paths, open filters, tap category/rating/scope,
  see immediate visual feedback and live reapplication, long-press a category for quick solo/invert,
  then Reset if needed. This lane does not change query parser correctness or favorite backend
  semantics unless FE comparison proves a search-scope behavior gap.
- HarmonyOS expression: native segmented controls for scope and rating, category-colored V2 buttons
  with long-press affordance, reset as the only explicit action, and stable title/page-level filter
  entry.

Android FE comparison evidence:

- Device: `fa967a75` (`model:22061218C`, `device:zizhan`) over ADB.
- Package: `com.honjow.fehviewer` (`eros_fe`), version `1.9.2`, foreground activity
  `com.honjow.fehviewer/.MainActivity`.
- Input method: ordinary `adb shell input` was rejected by Android `INJECT_EVENTS`; after user
  authorization, navigation used `adb -s fa967a75 shell su -c ...`.
- Evidence directory: `/private/tmp/nexte_search_filter_fe_comparison`.
- Key screenshots/layout dumps:
  `fe_home.png` / `.xml`, `fe_search.png` / `.xml`, `fe_filter_initial.png` / `.xml`,
  `fe_filter_open.png` / `.xml`, `fe_filter_after_manga_tap.png` / `.xml`,
  `fe_filter_after_doujinshi_long.png` / `.xml`, `fe_filter_rating_segment.png` / `.xml`,
  `fe_filter_rating_4_selected.png` / `.xml`, `fe_filter_favorite_scope.png` / `.xml`, and
  `fe_filter_restored.png` / `.xml`.
- Observed FE scope: a formal three-way segmented control (`Gallery`, `Watched`, `Favorite`).
- Observed FE categories: two-column, strong semantic-colored category buttons; all categories start
  selected/colored. Tapping `Manga` immediately turns it grey/off without changing scope.
- Observed FE long press: long-pressing `Doujinshi` while it is selected leaves `Doujinshi` selected
  and turns the other categories grey/off, matching the quick solo/invert mental model.
- Observed FE rating: an advanced minimum-rating switch reveals a segmented `2/3/4/5` star control;
  tapping `4` immediately selects that segment.
- Observed FE model: no primary Apply button in the filter view; state changes are immediate. Reset is
  a secondary icon action near the advanced-options switch. Favorite scope hides gallery category and
  advanced options.

Current NextE repair scope:

- Replace the old draft/Apply model with live filter edits: scope, category, rating, page range, and
  toggles update `SearchFilterState` immediately and bump `applySeq` for persist/requery.
- Use HarmonyOS `TabSegmentButtonV2` for scope and rating instead of fake Row/Text segmented controls
  or chip text blocks.
- Use a V2 category button component with `EhConstants.categoryColor(...)` semantic category colors,
  immediate selected/off state, and long-press solo/invert behavior.
- Keep the filter trigger as a native title-bar action across normal, tag/action-seeded, loading,
  error, result, and favorite search states.
- Remove the primary Apply button; keep Reset as the only explicit low-weight action.
- Queue a pending filter reapply when the user changes live filters during an in-flight search, and
  clear stale filter-only results when Reset leaves no query and no active filter.

Superseded FE/ADB preflight before the Android device was connected:

- Installed Android platform-tools through Homebrew on macOS; `adb` is available at
  `/opt/homebrew/bin/adb`.
- `adb version` reports Android Debug Bridge `1.0.41`, version `37.0.0-14910828`.
- `adb devices -l` started the ADB daemon but returned no connected Android devices:
  `List of devices attached` with no targets.
- This preflight blocker is now superseded for the Search filter lane by the connected-device evidence
  above. Keep it only as environment history, not as an active blocker for this item.
- Because no Android device is visible, NextE cannot yet run:
  `adb shell pm list packages | grep -i -E "eros|eh|hentai"`, launch `eros_fe`, capture screenshots,
  or verify FE category colors, long-press behavior, rating control shape, live-apply behavior, Reset
  weight, or search-scope expression.
- Follow-up preflight after pushing the branch briefly reported `emulator-5554 offline`; `adb reconnect
  offline` returned to no targets, so the Android target is still unavailable.
- Local Android SDK/emulator setup is also absent: no `emulator`, no `sdkmanager`, no
  `~/Library/Android`, and no existing `~/.android/avd`.
- The `emulator-5554 offline` target is not a usable Android target. Process/port inspection shows it
  comes from the running DevEco HarmonyOS Mate X7 emulator process
  `/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator ... -hvd Mate X7`, listening on
  `127.0.0.1:5555`; ADB sees that port as an offline Android emulator, while HDC is the correct tool
  for that HarmonyOS target.
- Local build/run prerequisites for installing `eros_fe` onto an Android emulator are also absent:
  `flutter` is not on `PATH`, no Java Runtime is installed, and no Android Studio app is present in
  `/Applications`. Installing the full Android/Flutter/JDK/emulator stack is a separate environment
  provisioning task and still would not replace the required connected Android FE screenshot evidence
  until an Android target and `eros_fe` install are available.

Source-only FE grounding already collected:

- `eros_fe/lib/pages/filter/gallery_filter_view.dart` uses `CupertinoSlidingSegmentedControl<SearchType>`
  for search scope (`normal`, `watched`, `favorite`).
- The same FE view hides gallery category and advanced options while `SearchType.favorite` is selected.
- `eros_fe/lib/pages/filter/filter.dart` implements `GalleryCatFilter` as a grid of
  `GalleryCatButton`s. Each button receives `ThemeColors.catColor[catName]` as the enabled category
  color, grey off state, and separate text colors.
- `GalleryCatButton` wraps the button in `GestureDetector(onLongPress: ...)`; normal press toggles the
  category and calls `onChanged`, while long press vibrates and runs the supplied `onLongPress`.
- FE long-press behavior in `GalleryCatFilter` keeps the pressed category unchanged and flips every
  other category to the inverse of the pressed category's current selected state. This provides the
  quick solo/invert mental model the NextE repair must preserve in a HarmonyOS-native way.
- FE minimum rating is not a chip row: `gallery_filter_view.dart` shows an advanced-option switch for
  minimum rating, then a `CupertinoSlidingSegmentedControl<int>` for `2`, `3`, `4`, and `5` stars.
- FE advanced options are persisted through `AdvanceSearchController.advanceSearch` and category state
  through `EhSettingService.catFilter`; `showFilterSetting()` has no dialog actions, so the filter view
  itself is not built around an Apply button. A separate clear/reset control appears only when advanced
  search is enabled.
- This source grounding does not satisfy the mandatory Android/ADB screenshot gate. It only narrows the
  FE observation checklist once a connected Android device is available.

Implementation:

- `886a38f fix(search): repair filter controls` replaces the hand-rolled scope `Row + Text` control
  with `TabSegmentButtonV2`, backed by localized `SegmentButtonV2Items`.
- The category/rating chips are now independent `@ComponentV2` controls with `@Param selected`, so
  tapping a chip updates its visual state immediately instead of relying on a sheet rebuild.
- `GallerySearchPage` now keeps the filter trigger as a native title-bar action with the correct
  `sys.symbol.funnel` icon across history, loading, error, empty, grid, list, simple-list, normal
  search, tag/action search, and favorite search states instead of hiding it when favorite scope is
  active.
- `GallerySearchPage` now uses the title bar for the current scope title and pins the search field in
  the HDS `bottomBuilder`, leaving the title action area available for filter and future actions.
- Favorite scope now keeps the sheet reachable and shows an explicit scope limitation hint for
  gallery-only filters.
- `cd798eb` superseded the earlier candidate for this item by adding category color semantics,
  long-press solo/invert, rating segmented control, and live filter application with no Apply button.
- `cd798eb fix(search): live-apply filter controls` implements the live-apply follow-up described
  above.
- `d0d09f6 fix(search): repair search chrome and clear flow` supersedes the temporary page-overlay
  trigger with title action + bottomBuilder search chrome, moves Reset beside Close in a low-weight
  sheet header, top-aligns the sheet content, fixes the SearchActionState monitor wiring for IME /
  search-button submit, and clears stale results/errors when the user clears the search field.
- Current correction branch: removes the mistakenly added funnel/filter action from
  `SearchPageField.ets`, keeps the bottomBuilder search row input-only, restores the filter entry to
  `GallerySearchPage`'s title/menu action, and disables Search title auto-hide for now so the menu
  action is not made unreachable by the previous layout workaround.
- Current correction branch also improves filter-sheet readability without shrinking text: scope/rating
  segmented controls now use explicit body-size text and bold selected state; category chips keep their
  current two-column semantic-color shape because that region was not the main visual problem; the
  sheet is now a flatter continuous filter form instead of a stack of section headers; `高级选项` is a
  normal switch row that reveals advanced fields; page range inputs are no-border pill fields with
  placeholder and bounded dimensions; advanced option rows use larger readable labels, unified row
  height, and a bounded form width so switches stay visually attached to their labels. The filter sheet
  now opens directly at the large detent instead of offering medium/large sheet stops.

Evidence:

- Deterministic contracts/gates: `scripts/test_search_filter_ux_contract.mjs`,
  `scripts/test_search_filter_draft_contract.mjs`, `scripts/test_search_filter_action_bar_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, `scripts/test_search_input_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`, and
  `git diff --check`.
- Official signed build passed with `scripts/setup-local-build-profile.sh` and
  `scripts/build_hvigor_signed.sh` on macOS; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP
  installed from `entry/build/default/outputs/default/entry-default-signed.hap`.
- NextE evidence directory: `/private/tmp/nexte_search_filter_live_apply_evidence`.
- Follow-up NextE evidence directory for `d0d09f6`:
  `/private/tmp/nexte_search_title_bottom_builder_evidence` (`search_funnel_title.png`,
  `search_funnel_sheet.png`, `search_keyboard_submit.png`, `search_clear_history.png`,
  `search_filter_sheet_topaligned.png`).
- Device observations for `d0d09f6`: title shows the active scope, search input is below the title in
  the bottomBuilder, the right action renders as a funnel and opens the filter sheet, sheet content is
  top-aligned below the header, keyboard Search submits into the search/error/results state, and
  tapping the Search clear button returns to the search-history state.
- Current correction acceptance: the filter action must stay in the title/menu/action area and must not
  be placed inside the search input row. SearchFilterSheet typography acceptance is readable 16-level
  form text and balanced control proportions, not tiny labels or mechanical section headings.
- Key NextE screenshots/layout dumps:
  `nexte_filter_sheet_open.png` / `.json` shows scope as a formal segmented control, two-column
  semantic-colored categories, fixed low-weight Reset, and no Apply button.
- `nexte_filter_manga_off.png` / `.json`: tapping `Manga` immediately changes its background to
  off/grey (`#0C000000` in layout) and the result list behind the sheet refreshes under the live
  filter.
- `nexte_filter_doujinshi_solo.png` / `.json`: long-pressing `Doujinshi` keeps only `Doujinshi`
  colored and turns other categories grey/off; the list behind refreshes to Doujinshi results.
- `nexte_filter_rating_visible.png` / `.json` and `nexte_filter_rating_4.png` / `.json`: rating is a
  segmented control, and tapping `4★` moves selected state immediately.
- `nexte_filter_after_reset.png` / `.json` and `nexte_filter_top_after_reset.png` / `.json`: Reset
  returns rating to `不限` and restores all categories colored/selected without an Apply button.
- `nexte_filter_favorite_scope.png` / `.json`: switching scope to `收藏` selects that segment and hides
  gallery-only category/rating controls behind an explicit limitation hint while the page-level filter
  entry remains visible.

Remaining acceptance:

- Needs controller/user review of the current correction evidence. FE ADB comparison for this filter
  lane is present; further Search UI/interaction work still needs a fresh FE comparison scoped to the
  changed surface.
- Required NextE correction evidence: filter icon is in title/menu/action, not in the search field row;
  category chips and rating segmented shape are preserved; page range inputs read as no-border pill
  range fields rather than blank blocks; SearchFilterSheet no longer adds section headers for every
  control type; advanced options appear as a continuous settings/form list under the ordinary
  `高级选项` switch; option rows read as compact settings rows with switch/label relationship intact;
  `f_sh` copy says `仅搜索已删除` / `Only expunged`, not "show expunged"; Reset remains low-weight next
  to Close.
- Historical NextE evidence before the current correction remains in
  `/private/tmp/nexte_search_filter_ux_repair_evidence/` and
  `/private/tmp/nexte_search_title_bottom_builder_evidence`. Current correction evidence is in
  `/private/tmp/nexte_search_filter_correction_evidence/`, especially
  `nexte_filter_sheet_final.png` and `nexte_filter_final_radius.png`.

### Search No Results Should Render Empty State, Not Parse Error

Type: bug / UX correctness

Priority suggestion: P1

Status: accepted

Implementation:

- `a7e7478 fix(search): render no-result searches as empty` treats EH list no-hit pages as valid
  empty list responses instead of `ParseFailure`, and changes Search empty results to the
  search-specific `没有搜索结果` / `No search results` copy.
- Scope: normal gallery search zero-result handling. Login, Cloudflare, rate-limit, removed/unavailable,
  empty body, and malformed pages still route through the existing typed error classifier.

Evidence:

- eros_fe source comparison: `lib/pages/tab/controller/search_page_controller.dart` initializes search
  with `RxStatus.empty()`, and `lib/pages/tab/view/search_page.dart` renders a non-error empty sliver
  when status is neither loading/error/success.
- Android FE ADB attempt: device `fa967a75`, package `com.honjow.fehviewer`; evidence in
  `/private/tmp/nexte_search_no_results_fe_evidence/`. The app stayed on the gallery list during the
  automated URL/search attempt, so this is recorded as a FE operation attempt, not acceptance proof.
- Deterministic contracts: `scripts/test_search_no_results_contract.mjs`,
  `scripts/test_error_classification_contract.mjs`, `scripts/test_search_input_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `scripts/test_v1_decorator_inventory_contract.mjs`.
- Official macOS DevEco/Hvigor signed build: `scripts/build_hvigor_signed.sh`, installed
  `entry/build/default/outputs/default/entry-default-signed.hap` on Mate X7 target
  `127.0.0.1:5555`.
- Device evidence: `/private/tmp/nexte_search_no_results_evidence/result.png` and `result.json` show
  query `nexte_no_results_probe_zzzzzzzzzzzzzzzzzzzz` rendering `没有搜索结果`, with no
  `无法解析此页面,应用可能需要更新。` parse-error copy.
- Current-main acceptance, 2026-06-19: contracts still pass on main, and HarmonyOS Mate X7 emulator
  target `127.0.0.1:5555` submitted `nexte_no_results_probe_zzzzzzzzzzzzzzzzzzzz`. The final layout
  shows that query in `appSearchField-2` and the empty-state copy `没有搜索结果`; it does not show
  `无法解析此页面` or `应用可能需要更新`. Evidence directory:
  `/private/tmp/nexte_search_no_results_current_acceptance`, especially `result.png` and `result.json`.

Closure:

- Accepted for the zero-result search empty-state bug. A successful Android FE no-results screenshot
  remains optional reference material, but this lane is closed because the eros_fe source behavior,
  deterministic classifier contracts, and current NextE runtime behavior are aligned. No product code
  changed in this acceptance update.

Source:

- User-reported current behavior.

Observed behavior:

- When a search has no results, the page can show a parse/update-style error instead of a normal
  no-results state.

Expected behavior:

- A normal zero-result search should leave the result area empty or show a centered no-results icon/message.
- It should not show copy like "unable to parse this page" / "app may need an update" unless the fetched page
  is actually an unexpected or unsupported page structure.
- The empty state should be search-specific, for example "没有搜索结果", rather than a generic fatal error.

Why this matters:

- No-result searches are normal user behavior, especially with exact tag queries or restrictive filters.
- Showing a parser/update error makes users think the app or EH integration is broken when the query simply
  matched nothing.

Likely failure mode:

- `GallerySearchPage` currently renders `PageErrorState` when `vm.itemCount === 0 && vm.errorMessage.length > 0`,
  and only falls through to `CardEmptyState` when there is no error.
- If the search request/classifier turns EH's zero-result HTML into `ParseFailure`, the UI shows the parser
  error instead of a no-results empty state.
- `EhGalleryListParser.parse()` can represent an empty list, but the network/classifier path may reject some
  zero-result pages before the parser result reaches `SearchViewModel`.

Likely modules to inspect:

- `feature/search/src/main/ets/pages/GallerySearchPage.ets`
- `feature/search/src/main/ets/viewmodel/SearchViewModel.ets`
- `shared/src/main/ets/network/EhApiService.ets`
- `shared/src/main/ets/network/EhErrorClassifier.ets`
- `shared/src/main/ets/parser/EhGalleryListParser.ets`
- `scripts/test_search_input_contract.mjs`
- `scripts/test_error_classification_contract.mjs`

Implementation direction to evaluate:

- Capture or fixture a real EH search response for a valid zero-result query.
- Teach the list/search fetch path to classify that response as a valid empty `GalleryList`, not a parse failure.
- Keep real malformed pages, login/auth gates, Cloudflare/rate-limit pages, and unsupported layout variants classified as errors.
- Add a search-specific empty state copy/icon for `hasSearched && itemCount === 0 && no fatal error`.
- Add deterministic coverage that zero-result search HTML produces an empty list and Search UI uses empty state, while true parse failures still show error.

Acceptance shape:

- Search a query that validly returns zero results.
- The page shows blank/history-free empty result area or a centered no-results icon/message.
- No parser/update error copy is shown for the zero-result case.
- A true malformed/error page still renders a recoverable error state.

### Search Tag Autocomplete / Tagsuggest Missing

Type: search UX / parity gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- eros_fe exposes live tag suggestions while composing a search query. This is a high-frequency search
  assist path because EH exact tag syntax is easy to mistype and namespace prefixes matter.

Implementation:

- Added `EhApiPhpService.tagSuggest()` for EH `api.php` `method=tagsuggest` responses, with typed
  `EhTagSuggestion` parsing from `ns` / `tn` entries.
- Added debounced Search page suggestions for the current last token. Completed exact namespaced tokens
  such as `f:futanari$` no longer reopen suggestions.
- Tapping a suggestion inserts exact EH tag query syntax into the page-local search field, for example
  `f:futanari$` or `p:"futari wa precure$"`, without moving the filter action out of the title/menu area.
- Scope intentionally excludes local translation DB lookup, FE-style blue substring highlighting, and
  QuickSearch expansion.

FE comparison evidence:

- Android device `fa967a75`, package `com.honjow.fehviewer`.
- `/private/tmp/nexte_fe_tagsuggest_search.png` / `.xml`: FE Search page with title actions and separate
  search field.
- `/private/tmp/nexte_fe_tagsuggest_fut.png` / `.xml`: typing `fut` shows a vertical suggestions list
  under the search field with namespaced tag rows.

NextE evidence:

- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`.
- `/private/tmp/nexte_tagsuggest_accept2_before.jpeg` / `_layout.json`: typing `fut` shows left-aligned
  live suggestions in the Search page body.
- `/private/tmp/nexte_tagsuggest_accept2_after.jpeg` / `_layout.json`: tapping the first suggestion fills
  `f:futanari$`, clears the suggestion list, and returns to Search history/blank composition state.

Contracts / gates:

- `scripts/test_search_tagsuggest_contract.mjs`
- `scripts/test_search_input_contract.mjs`
- `scripts/test_search_filter_action_bar_contract.mjs`
- `scripts/test_search_scope_contract.mjs`
- `scripts/test_v1_decorator_inventory_contract.mjs`
- `scripts/check_i18n_duplicates.py`
- `scripts/build_hvigor_signed.sh`

Acceptance shape:

- Open Search, type a partial tag token such as `fut`, and see suggestions without submitting the query.
- Tap a suggestion; the input should contain the exact EH namespaced tag query and suggestions should close.
- Pressing Search still owns actual query submission.
- The filter entry remains in the title/menu/action area, not beside the search input field.

Follow-up direction / research note, 2026-06-21:

- ArkUI `Search` appears to be only the input/control surface and does not provide a built-in
  autocomplete result container. `Select`, `Menu`, `MenuItem`, and `bindMenu` can cover dropdown or
  action-menu use cases, but they are a poor default fit for EH-style search candidates because they
  introduce floating/menu semantics instead of a normal search-results region.
- The lower search-page content region is the preferred place to present candidate matches. This
  matches the current NextE `SearchSuggestionView()` shape and eros_fe's body `SliverList` approach,
  and also stays close to official-app style patterns where suggestions occupy the content below the
  search field rather than a popover.
- Treat the interaction split as guidance, not a hard contract: the main row can be evaluated as
  "search this candidate now", while a trailing diagonal-arrow affordance can mean "put/append this
  candidate into the search box and keep composing". eros_fe currently fills the query on row tap, so
  device comparison and user acceptance should decide the final split.
- If the local tag-translation database is ported later, translated local matches and EH `tagsuggest`
  network matches can feed the same in-page candidate list. Prefer main/subtitle text treatment over
  a separate floating component unless a later native-control investigation proves a better fit.
- Keep this note loose: it is meant to steer the next UX pass away from hand-rolled popovers, not to
  require a specific visual layout, icon size, row height, or exact submit/fill behavior before the
  next screenshot/device review.

### Search Action Routes Can Lose The Second Tag Query

Type: routing / state ownership bug

Priority suggestion: P0

Status: accepted

Source:

- User-reported route-stack scenario: open Search from detail tag A, enter another gallery detail from
  the results, then tap tag B. One run crashed; later repeats opened the second Search page without a
  query.
- Root risk: `SearchActionState` was an AppStorageV2 singleton that held live keyword, submit, seed,
  focus, and pending-query state. Multiple Search page instances could coexist, and old/non-top Search
  pages could monitor and clear `pendingQuery` before the newly pushed Search page consumed tag B.

Expected behavior:

- Action-seeded searches from tags/uploader/similar should target a concrete Search session.
- If the current stack top is not Search, push a new Search route with route/session params instead of
  relying on a shared pending keyword bus as the page source of truth.
- Multiple Search pages may coexist; Search(A) must not overwrite, consume, or clear Search(B).

Implementation:

- Pending action state is now a narrow app-wide open/search signal only. `Index.onPendingQuery()`
  consumes it, pushes `SearchPageParams(initialQuery, focusOnAppear=false, sessionId)`, then clears it.
- `GallerySearchPage` owns page-local `SearchPageFieldState` for keyword, submit, seed, filter-open,
  and focus state. It no longer imports or monitors `SearchActionState.pendingQuery`.
- Action-seeded route params seed the page-local search field and immediately run the query on the new
  Search page, so older Search instances cannot consume tag B.
- The Search filter entry belongs in the title/menu/action area so tag search, normal search, favorite
  search, loading, error, and results states keep a stable page-level filter entry without polluting the
  search input row.
- Empty ordinary search no longer implicitly re-runs a network request when filters change; live filter
  reapply requires a non-empty query or explicit favorite scope.
- Advanced options now have a master switch; disabled advanced filters do not emit `advsearch=1` or
  advanced URL params.

Evidence:

- Deterministic contract added: `scripts/test_search_route_session_contract.mjs` covers stacked
  Search(A) -> Detail -> tag B session seeding and asserts `GallerySearchPage` no longer consumes the
  global pending query.
- Related contracts updated: `scripts/test_search_input_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, `scripts/test_search_filter_draft_contract.mjs`,
  `scripts/test_search_filter_settings_contract.mjs`, `scripts/test_search_filter_ux_contract.mjs`,
  and `scripts/test_home_source_routing_contract.mjs`.
- Gates passed: all above contracts, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build passed with `scripts/build_hvigor_signed.sh`; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside the sandbox, official signed HAP
  installed. Evidence directory: `/private/tmp/nexte_search_behavior_model_evidence`.
- Device route-stack check: from Search result detail, tapping the `chinese` tag opened a new Search
  page with `language:chinese` visible in the pinned search field and showed matching results; no crash
  or empty second Search query occurred. Key artifacts: `search_detail_a.png`,
  `search_tag_b.png`, and `search_tag_b.json`.
- Current-main acceptance, 2026-06-19, HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside
  the sandbox: `Search(character:roll)` -> result detail -> tag `artbook` opened a second Search page
  with `other:artbook` visible in `appSearchField-2` and matching `artbook` results. It did not show an
  empty query, reuse `character:roll`, or crash. Evidence directory:
  `/private/tmp/nexte_search_route_stack_acceptance`; key artifacts: `search_a.png`,
  `search_a.json`, `detail_from_search.png`, `detail_from_search.json`, `search_b.png`,
  `search_b.json`.
- Android FE reference, 2026-06-19: ADB target `fa967a75` opened eros_fe detail with `su`; screenshots
  captured under `/private/tmp/nexte_search_route_stack_fe`. The tap automation did not complete FE
  navigation, so product semantics were cross-checked from
  `/Users/honjow/git/eros_fe/lib/pages/gallery/view/gallery_widget.dart`, where detail tag tap routes to
  search via `NavigatorUtil.goSearchPageWithParam(simpleSearch: '${tag.type}:${tag.title.trim()}')`.

Closure:

- Accepted for the route-stack bug. No product code changed in this acceptance update.
- Implementation commit: `30ae664 fix(search): isolate action route state`.
- SearchFilter visual/control acceptance belongs to the separate Search Filter UX lane and must not keep
  this route-stack bug active.

### Search Submit During In-Flight Request Can Drop The Latest Query

Type: search reliability bug

Priority suggestion: P1

Status: accepted

Source:

- Implementation review of the current search input path after the SearchFilter lane was closed.

Current baseline:

- SearchFilter visual shape, filter action placement, and Search title/header auto-hide behavior are not
  part of this item and must remain unchanged.

Observed behavior:

- `GallerySearchPage.onSubmit()` sends the current field text to `SearchViewModel.search()`.
- Before this fix, `SearchViewModel.search()` returned immediately whenever `isLoading` was true.
- If a user submitted one search, quickly changed the keyword, then submitted again before the first
  request completed, the latest query could be silently dropped.

Expected behavior:

- Empty ordinary searches still return to history/blank.
- Favorite-scope empty browse still works.
- While a search is in flight, the latest non-empty submitted query should be queued and run after the
  current request completes, so the UI eventually reflects the user's final submitted keyword.

Implementation:

- `SearchViewModel` now stores a `pendingSearchQuery` while `isLoading` is true.
- When the current request completes, the VM runs the latest queued query if it differs from the
  completed query.
- Clearing the search state also clears any pending submitted query.
- If both a filter reapply and a new submitted query are pending, the new query wins because it will
  fetch with the latest filter state.

Evidence:

- Deterministic contract: `scripts/test_search_input_contract.mjs` now covers in-flight submit queuing.
- Regression contracts: `scripts/test_search_route_session_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, `scripts/test_search_filter_ux_contract.mjs`.
- Gates: `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  `git diff --check`.
- Official signed build passed with `scripts/build_hvigor_signed.sh`; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP
  installed from `entry/build/default/outputs/default/entry-default-signed.hap`: opened Search,
  submitted `test`, and verified the results page loaded normally with the query still visible.
  Evidence directory: `/private/tmp/nexte_search_pending_submit_evidence/`, especially
  `search_result.png` and `search_result.json`.
- Current-main acceptance, 2026-06-19: contracts still pass on main, and HarmonyOS Mate X7 emulator
  target `127.0.0.1:5555` accepted a new `gundam` search submission from the current Search page. The
  final layout shows `gundam` in `appSearchField-2` and gundam-related results, replacing the prior
  `other:artbook` results. Evidence directory:
  `/private/tmp/nexte_search_pending_submit_current_acceptance`, especially `before.png`,
  `before.json`, `after.png`, and `after.json`.
- Android FE reference, 2026-06-19: ADB target `fa967a75` was brought to foreground with
  `adb shell su -c 'am start -n com.honjow.fehviewer/.MainActivity'`; foreground confirmed as
  `com.honjow.fehviewer/.MainActivity`. Current FE screenshot:
  `/private/tmp/nexte_search_pending_submit_fe_reference/fe_foreground.png`.

Closure:

- Accepted for the search submission reliability bug. The exact in-flight race is locked by
  `scripts/test_search_input_contract.mjs`; the device pass covers the running signed app's search
  submission path. No product code changed in this acceptance update.

### Search History Cannot Delete One Entry

Type: search UX gap

Priority suggestion: P2

Status: implemented / needs controller acceptance

Source:

- `eros_fe/lib/pages/tab/view/search_page.dart` wires search-history chips with a long-press delete
  affordance.
- `eros_fe/lib/pages/tab/controller/search_page_controller.dart` persists `removeHistory()` and caps
  search history at 100 entries.

Current baseline:

- SearchFilter visual shape, filter action placement, and Search title/header auto-hide behavior are
  not part of this item and must remain unchanged.

Observed behavior:

- Before this fix, NextE search history chips could only be searched or cleared as a whole list.
- History retention was capped below eros_fe's 100-entry behavior.

Expected behavior:

- Tapping a history chip still runs that query.
- Long-pressing one history chip removes only that entry, persists the remaining list, and gives
  lightweight feedback.
- The retained history cap is 100 entries.

Implementation:

- `e35d181 fix(search): delete individual history entries`.
- `SearchHistorySettings` now caps at 100, exposes `remove(context, query)`, filters only the exact
  target query, and persists the remaining ordered list.
- `GallerySearchPage` adds a long-press gesture on each history chip and shows the localized
  `search_history_deleted` toast after removal.
- Scope is deliberately limited to retention and single-entry deletion. Translated-history subtitles
  and eros_fe's append-to-field chip behavior remain parity backlog items.

Evidence:

- FE ADB reference: Android device `fa967a75`, eros_fe package `com.honjow.fehviewer`, screenshot
  `/private/tmp/nexte_search_history_evidence/fe_search_history.png`.
- NextE HarmonyOS evidence: target `127.0.0.1:5555`, signed HAP installed, screenshots/layout dumps
  under `/private/tmp/nexte_search_history_evidence/`; `search_before_layout.json` includes `webtoon`
  as the first history chip, and `after_delete_layout.json` shows that `webtoon` was removed while
  following chips remain.
- Deterministic contract: `scripts/test_search_history_contract.mjs`.

Remaining acceptance:

- Needs controller/user acceptance of the long-press delete behavior and before/after device evidence.

Follow-up implementation:

- `fix(search): confirm clearing search history` extends the same Search history surface so the
  all-history `清除` action on the Search landing page no longer deletes immediately. It now opens a
  native confirmation dialog with cancel and destructive clear actions; cancelling keeps the visible
  history chips intact.
- This is separate from Search settings history clear safety. The Settings path was already gated,
  while the main Search page still had a direct `SearchHistorySettings.clear(this.ctx())` click target.

Follow-up evidence:

- FE source grounding: `eros_fe/lib/pages/tab/controller/search_page_controller.dart` still treats
  `clearHistory()` as a persisted clear-all action; NextE keeps that data semantic but adds a native
  confirmation gate for accidental-tap safety.
- Android FE reference: ADB target `fa967a75`, package `com.honjow.fehviewer`, source/UI reference
  captures under `.hvigor/outputs/search-history-clear-confirm-fe/`.
- NextE HarmonyOS evidence: target `127.0.0.1:5555`, signed HAP installed, captures under
  `.hvigor/outputs/search-history-clear-confirm-nexte/`. `search_clear_confirm.png` shows the native
  confirmation dialog; `search_after_cancel.png` shows history chips still present after cancel.
- Deterministic contract: `scripts/test_search_history_contract.mjs` now asserts clear-all is gated
  by `showAlertDialog`, uses localized confirmation text, keeps a separate clear helper, and the
  Search page clear text no longer directly calls `SearchHistorySettings.clear(...)`.

### Settings Root Missing Search Settings Entry

Type: feature gap / settings reachability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- System comparison against `eros_fe` settings showed Search as a first-level Settings child page while
  NextE only exposed search history/filter management from inside the Search page.

Grounding:

- `eros_fe` settings root exposes `Search` as a first-level row in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`, routing to
  `EHRoutes.searchSetting`.
- The FE child page lives at `/Users/honjow/git/eros_fe/lib/pages/setting/search_setting_page.dart`
  and currently presents a grouped Search settings page with `快速搜索`.
- NextE intentionally did not expand QuickSearch in this lane; the user-visible loop is Settings root
  -> Search settings -> manage existing persisted search data/profile.

Implementation:

- `8e897cc feat(settings): add search data settings` adds `SearchSettingsPage`, exports/registers the
  `SearchSettings` route, and adds a Settings root `搜索` row.
- The page uses the existing HDS Settings child-page pattern and exposes persisted search history count,
  clear-history action, saved filter profile state, and reset-filter action.
- `SearchFilterSettings.reset()` resets the saved filter profile to the clean default, bumps `applySeq`,
  and persists the profile through the existing single-writer settings path.
- Scope is limited to Settings reachability and data management. It does not change QuickSearch,
  SearchFilter visual baseline, search input layout, tag parsing, image search, or search algorithms.

Evidence:

- Android FE comparison, 2026-06-19: ADB target `fa967a75`, launched
  `com.honjow.fehviewer/.MainActivity` with `su`; Settings root showed `搜索`, tapping it opened FE
  Search settings with `快速搜索`.
  Evidence directory: `.hvigor/outputs/search-settings-fe-comparison/`, especially
  `fe_settings_root.png`, `fe_settings_root_window.xml`, `fe_search_settings.png`, and
  `fe_search_settings_window.xml`.
- Deterministic contracts/gates:
  `scripts/test_settings_search_entry_contract.mjs`,
  `scripts/test_search_filter_settings_contract.mjs`,
  `scripts/test_search_history_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- HarmonyOS emulator evidence, 2026-06-19: target `127.0.0.1:5555`, hdc outside sandbox, official
  signed HAP installed. Settings root showed the new `搜索` row; tapping it opened Search settings with
  `搜索历史`, `清除`, `筛选配置`, and `重置筛选`.
  Evidence directory: `.hvigor/outputs/search-settings-nexte-evidence/`, especially
  `nexte_settings_root.png`, `nexte_settings_root_layout.json`, `nexte_search_settings_page.png`, and
  `nexte_search_settings_page_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings root placement and Search settings data-management
  scope. No further FE/device validation is required unless Settings root or Search settings routing
  changes again.
