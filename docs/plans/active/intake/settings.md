# Settings And History Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- This file is an evidence ledger, not a priority queue. Start from the user's latest request and use `../product-bug-intake.md` for intake writing rules.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Viewed History Day Sections And Pinned Group Headers

Type: list organization / navigation context

Status: implemented / device-verified on 197

Grounding:

1. `../eros_n_ohos/lib/pages/nav/history/history_view.dart` groups history by local calendar day and pins each day header while its rows scroll.
2. History remains a single chronological feed; day sections expose its time context without changing storage, ordering, or deletion behavior.
3. Recent labels use only `Today`, `Yesterday`, and `The day before yesterday`; older sections use their calendar date to avoid a hard-to-scan numeric relative range.
4. History and download both retain only stable group identity in scroll state (local day start / task-group enum). Their header label and count derive from the current date and current queue projection; neither may cache display text. Because HDS overlays native sticky headers in this immersive layout, each page mirrors the crossed group through its HDS owner using both real scroll offset and the list-group index.
5. ArkUI `List.sticky(StickyStyle.Header)` is available for `ListItemGroup` headers. Device QA must confirm the pinned-header geometry below the app title and download selector overlays.

Candidate pseudo-sticky route, 2026-07-19:

1. `../eros_n_ohos/lib/pages/nav/history/history_view.dart` uses each date's `SliverPinnedHeader`; `../eros_fe/lib/pages/tab/view/history_page.dart` confirms the current history page's title/clear-action hierarchy.
2. The first-screen priority remains history rows; the date is contextual metadata, not a new title-level navigation control.
3. The clear-history action remains in the title menu; the date mirror is passive and has no tap action.
4. This lane tests only a title-bar `bottomBuilder` date mirror driven by the list's real visible section. It does not change storage, pagination, deletion, or row layout.
5. HDS expression: cache one `ComponentContent` in `bottomBuilder`, update its V2 state from the list scroll callback, and retain the list's immersive under-title viewport.

QA feedback, 2026-07-19, target `192.168.50.197:12345`:

- Baseline: the immersive `TitleBar` occupies `y=124..305`, while the `List` deliberately occupies `y=124..2720`; after scroll, the native group header is pinned beneath that higher-z title layer and is not readable. This is the reported failure.
- A/B 1, history page only: `enableComponentSafeArea: true` changes the `List` viewport to `y=305..2720` and pins `今天` to `y=305..390`, but it removes the list's intended extension under the immersive title and combines with the existing content reserve to create extra initial blank space. Rejected and reverted.
- A/B 2, history page only: `dynamicHideTitleBar(...).bindToScrollable([scroller])` does hide HDS `TitleBar` (`[0,0]` after scroll) without changing the List viewport, but the native pinned day header still is not readable. Rejected and reverted.
- The current SDK type contract exposes only `List.sticky(StickyStyle)` and no sticky-header offset or title-bar-below overlay API. On the same device, a forced content-layer label was either covered by HDS (`position` at title height), positioned far below its requested boundary after unit conversion, or caused HDS composition artifacts when given a full-height sibling. These are rejected probes, not shippable behavior.
- `bottomBuilder` can instead act as a deliberately limited date-context mirror: it is cached as one V2 `ComponentContent`, hidden while the first in-flow day header is visible, and updated from the visible `ListItemGroup` index after scrolling. The list keeps its under-title immersive viewport and native sticky headers are disabled to avoid a duplicate hidden header.
- On target `192.168.50.197:12345`, the bottomBuilder mirror was visually verified absent at the top, readable as `今天` immediately below the title after scrolling, and absent again after returning to the top. This device currently had only `今天` data, so a real `今天 → 昨天` transition remains pending device acceptance; no synthetic history rows were written.
- Final device verification, 2026-07-20: the target contained one real 07-20 history row and multiple 07-19 rows. First entry and return/re-entry each rendered exactly one `今天` and one `昨天`; no stale duplicate remained. After crossing the real day boundary, `昨天` was visibly mirrored below the HDS title while rows continued under the immersive title. Artifact screenshots: `.hvigor/outputs/history-download-pinned-197-20260720/history-top.jpeg` and `history-scrolled.jpeg`.
- Final download verification, 2026-07-20: the gallery queue had only two completed rows and could not scroll, so no synthetic tasks were created. The archive queue had eight real completed rows; after scrolling, its live `已完成 8` header was visibly mirrored below the HDS Gallery/Archive selector. Artifact: `.hvigor/outputs/history-download-pinned-197-20260720/download-archiver-scrolled.jpeg`.
- The stored `viewed_at` value is already mapped to `EhGallery.lastViewTime` and to the generic card's unlabelled `postTime` slot. The history item must render it explicitly as the viewing time (normally `HH:mm` under an already-day-grouped list), rather than relying on the generic publication-time slot.

### Hidden System Symbol Reference Page

Type: developer reference / system symbol discovery

Priority suggestion: P2 / bounded developer utility

Status: implemented / needs controller acceptance

Source:

- User request, 2026-07-10: the HarmonyOS API website does not show every available system icon,
  while the SDK resource table lists names without a visual preview. Provide a hidden in-app reference
  page that shows every compile-SDK system symbol and copies its resource name when tapped.

Grounding:

- `eros_fe` reference: `/Users/honjow/git/eros_fe/lib/pages/setting/about_page.dart` is the concrete
  About/version surface used for the hidden entry; eros_fe has no HarmonyOS system-symbol browser, so
  the catalog itself is target-platform developer tooling rather than an EH product-parity feature.
- Primary information: a searchable visual grid of every `sys.symbol.*` entry accepted by the current
  DevEco compile SDK; the glyph and exact resource name are peers on each card.
- Primary action: tap a symbol card to copy `sys.symbol.<name>`; secondary action is filtering by any
  name fragment. Neither action changes app settings or user data.
- Scope: generate and check in the catalog from DevEco `sysResource.js`, open it by rapidly tapping the
  About `Platform / HarmonyOS NEXT` row five times, search, preview, and copy. The existing version-tap
  safe-mode unlock remains independent. No online icon source, favorites, categories,
  or runtime SDK scraping.
- HarmonyOS expression: routed `HdsNavDestination`, native `Search`, responsive lazy `Grid`,
  `SymbolGlyph`, system pasteboard, and the existing immersive title bar.

User path and negative states:

- Settings -> About -> rapidly tap `Platform / HarmonyOS NEXT` five times -> symbol reference page -> type a name
  fragment -> tap a card -> copied resource-name toast.
- Empty search results show a terminal no-results state rather than an empty grid with stale count.
- Narrow/folded panes reduce the responsive grid column count; wide panes add columns without changing
  card density.
- The full 4,000+ entry catalog is rendered through `LazyForEach`; filtering reloads the stable data
  source instead of mounting every icon at once.

Acceptance:

- Re-running `scripts/generate_system_symbol_catalog.mjs` against the active DevEco SDK produces the
  checked-in catalog deterministically.
- A signed build succeeds and the hidden entry, search, responsive layout, symbol rendering, and
  clipboard toast are verified on a connected emulator/device.

Handled update, 2026-07-10:

- Generated 4,027 compile-SDK symbols from DevEco `sysResource.js`. Catalog construction is deferred
  until the page opens, and the grid uses `LazyForEach`, so normal app startup does not allocate every
  catalog entry or mount every card.
- Final hidden entry is independent of the version/safe-mode gesture: Settings -> About -> tap
  `Platform / HarmonyOS NEXT` five times.
- Signed Hvigor build succeeded; V1 inventory reported `0 file(s)`; four-locale i18n parity,
  safe-mode contract, and `git diff --check` passed.
- Mate X7 emulator `127.0.0.1:5555`: verified the five-tap entry, all-symbol grid, search to the unique
  `square_and_square` result, copy toast/system pasteboard value `sys.symbol.square_and_square`, and
  the terminal no-results state. Expanded layout rendered five columns; folded layout rendered two,
  then the emulator was restored to expanded state. Evidence:
  `/private/tmp/nexte_system_symbol_evidence/`.

### Settings UI Must Extend Shared Primitives, Not Hand-Roll Local Rows

Type: implementation quality / settings UI baseline

Priority suggestion: mandatory baseline

Status: active guidance / applies before settings-like UI edits

Source:

- User feedback, 2026-06-20: settings and settings-like management screens keep drifting because
  pages hand-roll list rows, dividers, buttons, and modal chrome instead of reusing the existing HDS
  settings primitives. When a local issue is pointed out, agents tend to overreact by replacing the
  primitive or rewriting the page instead of fixing the shared pattern.

Baseline:

- Settings pages and settings-like management pages should default to the shared NextE/HDS primitives:
  `SecondaryListScaffold`, `GroupedListSection`, `ConciseListRow`, `SectionHeader`, `AppModalScaffold`,
  and existing title-bar/menu builders.
- Product pages that behave like settings or management lists, such as `MyTagsPage`, should follow this
  baseline even if they live outside the `feature/settings` module.
- Page-local hand-rolled `Row`/`Column` settings cells, divider magic numbers, fake title bars, and
  custom button chrome are not acceptable as first-choice implementations.

Implementation rule:

- If a shared primitive almost works but lacks a capability, extend it narrowly instead of replacing it.
  Examples: opt-in multiline subtitle, controlled row height, divider policy, prefix/suffix alignment,
  trailing badge slot, menu anchor wrapper, modal title action slot, close/confirm icon actions.
- New primitive parameters must be opt-in and must preserve existing settings pages by default.
- If the requested behavior is one-off and not semantically a settings row, create a small wrapper around
  the shared primitive rather than a page-local visual clone.
- Before changing a settings-like page after user visual feedback, inspect the shared primitive contract
  first. A screenshot problem in one page should not trigger a full page rewrite unless the user
  explicitly says the page direction is wrong.

Acceptance:

- The implementation report names the shared primitive used and, if extended, the exact opt-in parameter
  or wrapper added.
- Contracts should prevent reintroducing page-local magic divider indents or fake settings rows when a
  shared primitive can express the same UI.
- Screenshot validation should check row height consistency, divider ownership/indent, prefix/title/
  trailing vertical alignment, and modal chrome consistency with HDS.
- If a page intentionally does not use shared settings primitives, the implementation must explain why
  it is not settings-like and what existing HDS primitive is closer.

### ConciseListRow Subtitle Defaults Still Clip Useful Setting Explanations

Type: shared settings primitive / readability bug

Priority suggestion: P1 / bounded settings-quality lane

Status: implemented / pending controller acceptance

Source:

- User feedback, 2026-06-20: the previous Reader Settings subtitle work appears to have only added an
  optional parameter, not changed the default. Rows such as Layout Settings `详情页优先显示日文标题` still
  have long explanatory subtitles that are clipped to one line, hiding useful behavior details.

Read-only inspection:

- `shared/src/main/ets/components/ConciseListRow.ets` currently declares
  `@Param subtitleMaxLines: number = 1`.
- The secondary text modifier uses `.maxLines(this.subtitleMaxLines)`, so the parameter works only for
  callers that explicitly pass it.
- `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets` passes `subtitleMaxLines: 3` only for
  the volume-key row.
- `feature/settings/src/main/ets/pages/LayoutSettingsPage.ets` uses the Japanese-title preference row
  with `subtitle: settings_japanese_title_in_gallery_hint`, but does not pass `subtitleMaxLines`, so it
  remains one-line clipped.
- Current `ConciseListRow.cardHeight()` returns `84` whenever `subtitleMaxLines > 1`. Therefore simply
  changing the default to `2` or `3` would make every row with any subtitle jump to the tall-row height,
  even when the subtitle is naturally one line.
- SDK inspection: `/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/api/@hms.hds.hdsBaseComponent.d.ets`
  declares `HdsListItemCardOptions.cardHeight?: Dimension`. The height is optional in the HDS type
  contract. NextE currently passes `cardHeight: this.cardHeight()` from its shared wrapper, so the hard
  52/60/84 row heights are a NextE wrapper policy, not an HDS requirement.
- V2Next uses the older fixed `subtitle ? 60 : 52` row-height wrapper; NextE inherited that pattern and
  later added a one-off `84` branch for multiline subtitles. That inheritance explains the current
  behavior, but it should not be treated as a product requirement.

Expected behavior:

- Ordinary settings rows with explanatory subtitles should be readable by default, preferably with a
  2-line default.
- Longer explanatory rows can still opt into 3 lines.
- Rows without subtitles or with short subtitles should not become visually bloated just because the
  default max-lines increased.
- Existing settings pages should benefit from the shared primitive without each page adding one-off
  `subtitleMaxLines` parameters.

Implementation direction:

- Treat this as a shared primitive extension, not a Layout Settings one-off.
- Revisit `ConciseListRow` subtitle and height policy together. Required order:
  - first test whether omitting `cardHeight` lets HDS naturally size the row from primary/secondary text,
    prefix/suffix, and padding;
  - if natural HDS height works, remove the hard-coded row-height branching and use min-height/padding
    only where needed for baseline row rhythm;
  - if HDS runtime evidence shows fixed height is required, replace magic `52/60/84` branching with one
    shared formula or narrow policy based on text lines and vertical padding.
- Possible product shape:
  - default subtitle max lines becomes 2;
  - row height follows actual rendered content where possible, not merely the maximum allowed lines;
  - explicit `subtitleMaxLines: 3` remains available for rows such as volume-key behavior hints.
- Update deterministic contracts so they no longer prove only the Reader volume-key row opted in; they
  should lock that the shared row default or shared policy allows useful two-line subtitles.
- Verify at least Layout Settings `详情页优先显示日文标题` and Reader Settings volume-key rows on device or
  simulator screenshots/layout dumps.

Acceptance:

- `ConciseListRow` no longer has a one-line-only subtitle default for ordinary settings rows.
- Layout Settings Japanese-title row shows its explanatory subtitle readably without a page-local
  one-off fix.
- Reader Settings volume-key hint remains readable up to 3 lines.
- Row heights stay coherent across Settings pages; no broad row bloat or accidental clipped text.
- The implementation report cites the HDS `cardHeight?: Dimension` finding and states whether runtime
  validation used omitted `cardHeight`, min-height, or a formula fallback.
- No page-local hand-rolled settings row is introduced.

Handled update, 2026-06-20:

- Implemented as a shared `ConciseListRow` primitive change, not a Layout Settings one-off.
- `ConciseListRow.subtitleMaxLines` now defaults to `2`, while callers such as Reader Settings can still
  explicitly request `subtitleMaxLines: 3`.
- Removed NextE's fixed `cardHeight()` wrapper branch and stopped passing `cardHeight` into
  `HdsListItemCard`; runtime validation used HDS natural measurement based on the SDK finding that
  `HdsListItemCardOptions.cardHeight?: Dimension` is optional.
- FE grounding/evidence:
  - Android device: `fa967a75`, package `com.honjow.fehviewer`.
  - Screenshots: `.hvigor/outputs/settings-subtitle-row-fix/fe-settings-ref.png` and
    `.hvigor/outputs/settings-subtitle-row-fix/fe-mytags-ref.png`.
- NextE evidence:
  - HarmonyOS emulator target: `127.0.0.1:5555`.
  - Layout Settings screenshot/layout:
    `.hvigor/outputs/settings-subtitle-row-fix/nexte-layout-settings-natural.png`,
    `.hvigor/outputs/settings-subtitle-row-fix/nexte-layout-settings-natural-layout.json`.
  - Reader Settings screenshot/layout:
    `.hvigor/outputs/settings-subtitle-row-fix/nexte-reader-settings-natural.png`,
    `.hvigor/outputs/settings-subtitle-row-fix/nexte-reader-settings-natural-layout.json`.
- Validation:
  - `node scripts/test_settings_layout_entry_contract.mjs`
  - `node scripts/test_settings_reader_entry_contract.mjs`
  - `node scripts/test_settings_dropdown_anchor_contract.mjs`
  - `node scripts/test_reader_settings_readability_contract.mjs`
  - `node scripts/test_settings_search_entry_contract.mjs`
  - `node scripts/test_settings_eh_entry_contract.mjs`
  - `node scripts/test_settings_security_entry_contract.mjs`
  - `node scripts/test_settings_advanced_entry_contract.mjs`
  - `node scripts/test_v1_decorator_inventory_contract.mjs`
  - `python3 scripts/check_i18n_duplicates.py`
  - `git diff --check`
  - `scripts/build_hvigor_signed.sh`
- Remaining acceptance: controller visual acceptance only; reopen with a fresh Settings screenshot if
  subtitle rows clip useful text or natural HDS height causes row bloat.

### Reader Settings Row Separators And Subtitle Readability

Type: UI readability / settings form quality

Priority suggestion: P2 / medium

Status: implemented / pending controller acceptance

Source:

- User feedback, 2026-06-20: Reader Settings menu rows lack visible separators.
- User feedback, 2026-06-20: when some setting subtitles are long, the trailing content becomes
  unreadable or disappears; subtitles should be allowed to wrap, with a maximum of 3 lines.

Observed risk:

- Reader settings are already a high-frequency configuration surface. If rows are not separated, the
  page reads as a loose text stack instead of a settings list.
- Long explanatory subtitles are part of the setting's meaning. A one-line or clipped subtitle can
  hide important behavior details, especially for controls such as volume-key navigation or reading
  interaction settings.

Expected behavior:

- Reader Settings rows should have clear row separation consistent with HDS/settings-list style.
- Subtitles should be readable and wrap naturally up to 3 lines, then ellipsize cleanly if still too
  long.
- Row height should expand for multiline subtitles instead of clipping text or forcing only the first
  line to be visible.

Implementation direction:

- Inspect `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets` and the shared
  `ConciseListRow` subtitle path before implementation.
- Prefer a shared row-level subtitle policy if it improves the broader Settings shell: controlled
  subtitle `maxLines(3)`, overflow ellipsis, readable line height, and a row `minHeight` that can
  expand for multiline subtitles.
- Add separators either through the local Reader Settings row composition or through the shared
  settings-row/group pattern if that is the project-standard HDS expression.
- If changing shared `ConciseListRow`, verify EH/Layout/Search/History/About settings pages do not
  regress through unexpected row bloat or divider duplication.

Acceptance shape:

- Reader Settings screenshot shows clear separation between menu rows.
- A long Reader Settings subtitle is visible for up to 3 lines and truncates cleanly beyond that.
- Other Settings pages that use `ConciseListRow` remain visually stable.
- Deterministic contract should lock the subtitle policy to `maxLines(3)` plus overflow handling and
  should cover row separation in Reader Settings or the shared settings-row pattern.

Handled update, 2026-06-20:

- Implemented local Reader Settings row dividers and an opt-in `ConciseListRow.subtitleMaxLines` path.
  The shared row default remains one line, so other settings/list rows do not grow unless they opt in.
- FE grounding:
  - Source: `/Users/honjow/git/eros_fe/lib/pages/item/setting_item.dart` uses explicit dividers between
    settings rows.
  - Android ADB evidence: `.hvigor/outputs/reader-settings-row-fe/reader-settings.png` and
    `.hvigor/outputs/reader-settings-row-fe/reader-settings.xml` show `阅读设置` rows separated by
    thin dividers.
- NextE evidence:
  - HarmonyOS emulator target: `127.0.0.1:5555`.
  - Screenshot: `.hvigor/outputs/reader-settings-row-nexte/reader-settings-screen.jpeg`.
  - Layout: `.hvigor/outputs/reader-settings-row-nexte/reader-settings-layout.json`.
  - Layout verification found 3 Reader Settings `Divider` nodes and the volume-key subtitle
    `音量减/加对应下一页/上一页` rendered with bounds `[74,956][659,1007]`, not clipped to an invisible
    one-line trailing state.
- Validation:
  - `node scripts/test_reader_settings_readability_contract.mjs`
  - `node scripts/test_v1_decorator_inventory_contract.mjs`
  - `git diff --check`
  - `scripts/build_hvigor_signed.sh`
- Remaining acceptance: controller visual acceptance only; reopen with a fresh Reader Settings screenshot
  if row separation or subtitle readability regresses.

### Home Bottom Navigation Auto-Hide And Smart-Grip Action Alignment

Type: feature enhancement / platform UX

Priority suggestion: P2 / medium

Status: partially implemented / Home bottom-tab auto-hide pending controller acceptance; smart-grip parked

Source:

- User feedback, 2026-06-20: add automatic hiding for the Home bottom navigation bar.
- User feedback, 2026-06-20: introduce 智感握姿 / smart-grip support and let the gallery detail
  read/resume floating action follow the configured hand edge.
- User notes that both behaviors can be copied/adapted from Next2V rather than redesigned from scratch.

Product intent:

- Home browsing should gain vertical space while scrolling: the floating bottom tab bar hides on forward
  scroll and returns on reverse scroll or near-top interaction.
- The read/resume floating action should remain reachable for one-handed use. With smart grip enabled,
  it follows the detected holding hand; with smart grip unsupported/disabled, the ordinary fixed/follow
  fallback remains usable.
- This is not a Reader-core or Gallery Grid lane. It should be implemented after higher-priority layout
  and write-operation gaps unless the current bottom bar or read action becomes a concrete blocker.

Next2V implementation pointers:

- Home bottom-tab auto-hide:
  - `/Users/honjow/git/V2Next/shared/src/main/ets/state/HomeTabAutoHideState.ets`
  - `/Users/honjow/git/V2Next/entry/src/main/ets/pages/Index.ets`
    - `connectHomeTabAutoHide()`
    - `applyHomeTabAutoHide()`
    - `onHomeTabDidScroll(...)`
    - `HdsTabsController.bindScroller(...)`
    - `applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)`
    - `applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)`
  - `/Users/honjow/git/V2Next/feature/settings/src/main/ets/pages/SettingsPage.ets`
    - `home_tab_auto_hide` setting row and `updateHomeTabAutoHide(...)`.
- Smart-grip / action alignment:
  - `/Users/honjow/git/V2Next/shared/src/main/ets/services/MotionHandStateService.ets`
    uses `@kit.MultimodalAwarenessKit` `motion.on('holdingHandChanged', ...)` and falls back when
    subscription fails.
  - `/Users/honjow/git/V2Next/shared/src/main/ets/state/MotionHandEdgeState.ets`
  - `/Users/honjow/git/V2Next/shared/src/main/ets/state/MotionReplyAlignmentState.ets`
  - `/Users/honjow/git/V2Next/shared/src/main/ets/settings/ReplyActionAlignmentSettings.ets`
    supports `smartGrip`, `followOperation`, `fixedLeft`, and `fixedRight`.
  - `/Users/honjow/git/V2Next/feature/detail/src/main/ets/pages/TopicDetailPage.ets`
    computes continuous left/right X positions for floating reply/resume actions and updates them via
    `@Monitor('motion.edge')` instead of jumping discrete alignment.

Implementation direction:

- Home bottom-tab auto-hide has been implemented. Do not reopen that slice unless fresh evidence shows
  the floating bottom tab bar no longer hides on a normal forward scroll or no longer returns when
  expected.
- Add a capability-checked motion-hand service using `@kit.MultimodalAwarenessKit`, with a silent
  fallback to fixed/follow-operation alignment if smart grip is unsupported.
- Reuse the existing gallery detail read/resume FAB as the first consumer. It should slide between left
  and right edge based on the effective alignment setting without changing Reader launch semantics.
- Keep Settings copy honest: smart grip should only appear as an option if subscription/capability is
  available, otherwise expose fixed/follow-operation choices.

Acceptance shape:

- Home: scrolling down hides the floating bottom tab bar; scrolling up or returning near the top shows it.
  Switching tabs must not leave the bar permanently hidden.
- Settings: Home tab auto-hide has a visible toggle and persists across restart; action alignment offers
  smart grip only when supported, with fixed-left/fixed-right/follow-operation fallback.
- Gallery detail: read/resume FAB follows the selected edge; when smart grip reports a left/right hand,
  the FAB animates to the corresponding side; Reader opening/resume index remains unchanged.
- Device evidence should include at least one ordinary no-smart-grip/fallback run and one smart-grip-capable
  run if hardware support is available. If no compatible device is available, mark implementation
  `implemented / needs device acceptance`, not accepted.

Handled update, 2026-06-21:

- Implemented only the Home bottom-tab auto-hide slice. Smart-grip/action alignment remains parked.
- NextE now has:
  - `shared/src/main/ets/state/HomeTabAutoHideState.ets` as the V2 state holder.
  - `shared/src/main/ets/settings/HomeTabSettings.ets` persisted through `StorageKeys.HOME_TAB_AUTO_HIDE`.
  - `SettingsBootstrap` restore and a Settings root switch row.
  - `Index.ets` HDS active-scroller binding and Next2V-aligned `HOME_TAB_SCROLL_DELTA_PX = 6` /
    `HOME_TAB_ANIMATION_GUARD_MS = 180`.
  - Home/Favorites/Toplist retained sub-tabs and Download/Settings pages forwarding scroll events.
- Validation:
  - `scripts/build_hvigor_signed.sh` passed.
  - Local HarmonyOS emulator target: `127.0.0.1:5555`.
  - A slow/default `uitest` swipe was not treated as a failure because HDS bottom-bar hiding is
    gesture-speed sensitive.
  - Valid high-velocity `uitest uiInput swipe ... 40000` evidence:
    `.hvigor/outputs/home-tab-auto-hide/home_tab_auto_fast_start.png` shows bottom tabs visible before
    scroll; `.hvigor/outputs/home-tab-auto-hide/home_tab_auto_velocity_after.png` shows the bottom tabs
    hidden after scroll.
  - `node scripts/test_home_tab_auto_hide_contract.mjs`
- Remaining acceptance:
  - Controller visual acceptance on normal user scroll behavior.
  - Optional restart/toggle acceptance for the Settings switch.
  - Smart-grip-aware read/resume action alignment is not implemented in this update.

Follow-up, 2026-06-22:

- User feedback rejects placing the scroll/home-tab auto-hide switch directly on the Settings root. The
  behavior can remain, but the setting should live under an appropriate child settings surface such as
  Layout / browsing display settings, using existing Settings primitives.
- Current code evidence: `feature/settings/src/main/ets/pages/SettingsPage.ets` renders
  `settings_home_tab_auto_hide` in `MainSection()` and wires it directly to `HomeTabSettings`.
  `scripts/test_home_tab_auto_hide_contract.mjs` also currently locks the root-page placement by
  requiring `SettingsPage` to contain `connectHomeTabAutoHide`, `settings_home_tab_auto_hide`, and
  `HomeTabSettings.save(ctx, enabled)`.
- Next repair should move the visible row out of Settings root and update the contract to assert the new
  placement while keeping the same persisted `HomeTabSettings` behavior. Keep this separate from the
  parked smart-grip/action-alignment lane.
- Naming note: the current implementation/string refers to Home bottom-tab auto-hide. If a later lane
  separately introduces title-bar auto-hide configuration, do not conflate the two settings.

### Settings Shell Audit: Visible Rows Must Be Real Or Honest

Type: feature gap / settings trustworthiness

Priority suggestion: P1

Status: implemented / pending controller acceptance

Source:

- User feedback, 2026-06-20: some Settings options, including Reader settings, feel hard to open or
  unreliable, and several Settings rows look like feature shells without real behavior.
- User expectation: Settings should not imply completed functionality when the underlying feature is
  absent or not wired.
- Read-only NextE inspection:
  - Settings root exposed EH, Layout, Reader, Download, Search, History, Advanced, Security, and
    About routes; Security and Download settings entries were later hidden until their downstream
    behavior is real.
  - `ReaderSettingsPage` has direction, double-page, auto-page interval, and volume-key rows. The route
    exists, but runtime menu opening / behavior linkage needs current device verification.
  - `EhSettingsPage` previously contained disabled `网站设置` and `图片限制` rows; comments say website
    settings, cloud sync, link handlers, and favorite write behavior remain separate lanes. These
    disabled placeholder rows were later hidden so EH settings only presents the NextE-owned loops.
  - `AdvancedSettingsPage` currently provides only HiLog diagnostics and marker write, while FE Advanced
    contains cache/proxy/import/export/log-related maintenance rows.
  - `SearchSettingsPage` exposed destructive `清除` search-history and `重置筛选` rows that called
    `SearchHistorySettings.clear()` / `SearchFilterSettings.reset()` directly without confirmation.
  - `DownloadSettingsPage` is explicitly scoped to persisted policy controls, while the broader download
    executor remains incomplete; this was later corrected by hiding the Download settings entry from
    Settings root until those policies are consumed by the executor.
  - `SecuritySettingsPage` intentionally exposed recent-task blur as disabled and auto-lock preference
    foundation without full biometric/lifecycle enforcement; this was later corrected by hiding the
    Security entry from Settings root until real lock enforcement exists.

Observed risk:

- A route existing in Settings can make the app feel more complete than it is.
- Disabled placeholders and rows with partial behavior should be reviewed as product debt, not treated
  as finished parity.
- Destructive data-management actions in Settings should not execute on a single accidental tap.
- If a settings row opens a menu or page unreliably, the issue is a concrete usability bug even if the
  route/contract exists.

Expected behavior:

- Every visible Settings row falls into one of three honest states:
  1. Real and wired: changing it affects the app immediately or after a clear documented restart/scope.
  2. Not yet implemented: disabled or parked with concise copy that does not imply protection/action.
  3. Entry-only by design: opens a non-destructive preview/safety surface and clearly states the missing
     submit/executor path.
- High-frequency settings, especially Reader settings and EH account/site settings, should be verified
  before lower-value Settings parity rows are expanded.
- If a setting affects Reader, Search, Download, Security, or EH writes, acceptance must prove both the
  Settings UI and the downstream behavior.

Implementation direction:

- First audit Settings rows/pages and classify them as `real`, `partial`, `disabled honest`, or `shell`.
- Fix broken reachability or menu-open behavior before adding more settings rows.
- For partial rows, either finish the smallest useful loop or change copy/disabled state so users do not
  mistake the row for a completed feature.
- Keep this lane separate from broad UI redesign. The core deliverable is trustworthiness and behavior,
  not visual polish.

Acceptance shape:

- Settings root and child pages have an inventory table listing row, status, linked state/action, and
  missing downstream behavior.
- Reader Settings row opens reliably; each visible reader setting either affects Reader or is marked as
  partial with a follow-up lane.
- Disabled EH/Security/Advanced rows use honest text and do not masquerade as active actions.
- Contracts verify key rows are routable and partial/disabled rows cannot trigger accidental writes.

Handled update, 2026-06-20:

- Settings shell audit scheduling state: implemented / pending controller acceptance. Current visible
  Settings root scope is `EH`, `布局`, `阅读`, `搜索`, `历史`, `诊断`, and `关于`. Security and Download
  settings entries are hidden until their downstream enforcement/executor loops exist; EH disabled
  placeholders are hidden; Search/history destructive clears are confirmation-gated; row dropdowns use
  row-local anchors. A 2026-06-20 code audit found no remaining visible Settings row that is an unowned
  placeholder or immediate destructive action without confirmation. Reopen only with fresh Settings
  regression evidence.
- Security root exposure: implemented / pending controller acceptance. Settings root no longer shows
  the `安全` entry because the underlying recent-task privacy and auto-lock enforcement are not wired.
  The parked `SecuritySettingsPage` / V2 preference foundation remains in code for a future
  platform-validated lane, but it is no longer presented as a completed user-facing security feature.
- Contract updated: `scripts/test_settings_security_entry_contract.mjs` now locks that Settings root
  must not contain `settings_security` or `pushPathByName('SecuritySettings', null)` until the real
  protection lane exists.
- HarmonyOS emulator evidence: target `127.0.0.1:5555`, signed HAP installed. Settings root layout
  showed `EH`, `布局`, `阅读`, `下载`, `搜索`, `历史`, `高级`, and `关于`, with `contains 安全: false`.
  Evidence files: `.hvigor/outputs/settings-security-root-hidden/settings_root.png` and
  `.hvigor/outputs/settings-security-root-hidden/settings_root_layout.json`.
- Download settings root exposure: implemented / pending controller acceptance. Settings root no
  longer shows the settings-side `下载` row because the current download queue/workbench does not
  consume the parked concurrency/original-image policy preferences. The bottom-tab Download workbench
  remains available. The Settings entry is reviewed and device-validated with the workbench behavior;
  it is not locked by a page-source contract.
- HarmonyOS emulator evidence: target `127.0.0.1:5555`, signed HAP installed. Settings root main rows
  were `账号 / 我的标签 / 退出登录 / EH / 布局 / 阅读 / 搜索 / 历史 / 高级 / 关于`; `main contains 下载:
  false`, while bottom-tab `下载` remained visible. Evidence files:
  `.hvigor/outputs/settings-download-root-hidden/settings_root.png` and
  `.hvigor/outputs/settings-download-root-hidden/settings_root_layout.json`.
- EH disabled placeholder exposure: implemented / pending controller acceptance. EH settings no
  longer shows disabled `网站设置` / `图片限制` rows because NextE does not yet implement the protected
  website-settings profile flow or image-limit refresh surface. The EH settings page remains scoped to
  real, existing loops: site mode, login, cookie import, My Tags, and logout. The site row trailing
  value also uses compact `表站` / `里站` labels so the current state remains readable in the settings
  row. Contract updated: `scripts/test_settings_eh_entry_contract.mjs` now locks that
  `EhSettingsPage` must not expose those future rows as visible disabled settings, and that the site
  row uses compact trailing labels.
- HarmonyOS emulator evidence: target `127.0.0.1:5555`, signed HAP installed. Settings root still
  showed `EH / 布局 / 阅读 / 搜索 / 历史 / 高级 / 关于`; tapping `EH` opened EH settings with `站点`,
  account, `我的标签`, and `退出登录`. Layout search found `网站设置: 0` and `图片限制: 0`. Evidence files:
  `.hvigor/outputs/settings-eh-placeholders-hidden/settings_root.jpeg`,
  `.hvigor/outputs/settings-eh-placeholders-hidden/settings_root_layout.json`,
  `.hvigor/outputs/settings-eh-placeholders-hidden/eh_settings_final.jpeg`, and
  `.hvigor/outputs/settings-eh-placeholders-hidden/eh_settings_final_layout.json`.
- Search history clear safety: implemented / pending controller acceptance. The Search settings
  `清除` row now opens a native confirmation dialog; only the destructive confirmation button calls
  `SearchHistorySettings.clear()`, while cancel leaves history untouched. Contract updated:
  `scripts/test_settings_search_entry_contract.mjs` now locks that the row calls
  `confirmClearHistory()` and that the dialog contains cancel plus the destructive clear action.
  HarmonyOS emulator evidence: target `127.0.0.1:5555`, signed HAP installed. Search settings showed
  history count `11`; tapping `清除` opened `清除全部搜索历史？` with `取消` and `清除`; tapping `取消`
  dismissed the dialog and the page still showed history count `11`. Evidence files:
  `.hvigor/outputs/settings-search-clear-confirm/search_settings.jpeg`,
  `.hvigor/outputs/settings-search-clear-confirm/search_settings_layout.json`,
  `.hvigor/outputs/settings-search-clear-confirm/search_clear_dialog.jpeg`,
  `.hvigor/outputs/settings-search-clear-confirm/search_clear_dialog_layout.json`, and
  `.hvigor/outputs/settings-search-clear-confirm/search_after_cancel_layout.json`.
- Search filter reset safety: implemented / pending controller acceptance. The Search settings
  `重置筛选` row now opens a native confirmation dialog; only the destructive confirmation button calls
  `SearchFilterSettings.reset()`, while cancel leaves the saved filter profile untouched. Contract
  updated: `scripts/test_settings_search_entry_contract.mjs` now locks that the row calls
  `confirmResetFilters()` and that the dialog contains cancel plus the destructive reset action.
  HarmonyOS emulator evidence: target `127.0.0.1:5555`, signed HAP installed. Search settings showed
  filter state `未启用`; tapping `重置筛选` opened `重置已保存的筛选设置？` with `取消` and
  `重置筛选`; tapping `取消` dismissed the dialog and the page still showed filter state `未启用`.
  Evidence files:
  `.hvigor/outputs/settings-search-reset-confirm/search_settings.jpeg`,
  `.hvigor/outputs/settings-search-reset-confirm/search_settings_layout.json`,
  `.hvigor/outputs/settings-search-reset-confirm/search_reset_dialog.jpeg`,
  `.hvigor/outputs/settings-search-reset-confirm/search_reset_dialog_layout.json`, and
  `.hvigor/outputs/settings-search-reset-confirm/search_after_cancel_layout.json`.
- Viewed history clear safety: implemented / pending controller acceptance. The History page title-bar
  trash action now opens a native destructive confirmation dialog; only the red destructive confirmation
  button calls `ViewedHistoryStore.clear()`, while cancel leaves the viewed-history list untouched.
  Contract updated: `scripts/test_viewed_history_surface_contract.mjs` now locks that the title action
  calls `confirmClearHistory()`, the dialog contains cancel plus the destructive clear action, and
  `clearHistory()` is only reached from the confirmation path. HarmonyOS emulator evidence: target
  `127.0.0.1:5555`, signed HAP installed. History showed existing gallery rows; tapping the trash
  button opened `清空全部浏览历史？` with `取消` and red `清空`; tapping `取消` dismissed the dialog and
  the history list still contained the same rows. Evidence files:
  `.hvigor/outputs/history-clear-confirm/history_page.png`,
  `.hvigor/outputs/history-clear-confirm/history_page_layout.json`,
  `.hvigor/outputs/history-clear-confirm/history_confirm.png`,
  `.hvigor/outputs/history-clear-confirm/history_confirm_layout.json`,
  `.hvigor/outputs/history-clear-confirm/history_after_cancel.png`, and
  `.hvigor/outputs/history-clear-confirm/history_after_cancel_layout.json`.

### Settings Root Missing Layout Settings Page

Type: feature gap / settings reachability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- System comparison against `eros_fe` settings showed Layout as a first-level Settings child page, while
  NextE kept existing list/view and thumbnail-display controls scattered in Settings root.

Grounding:

- `eros_fe` settings root exposes `Layout` in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`, routing to
  `EHRoutes.layoutSetting`.
- The FE child page lives at `/Users/honjow/git/eros_fe/lib/pages/setting/layout_setting_page.dart`
  and contains theme/layout/display controls including thumbnail, list-style, and fixed-height related
  rows.
- NextE intentionally did not expand theme, locale, tag translation, tabbar customization, or blur-cover
  controls in this lane; the user-visible loop is Settings root -> Layout settings -> manage existing
  persisted NextE layout/display state.

Implementation:

- `4b942d6 feat(settings): add layout settings page` adds `LayoutSettingsPage`, exports/registers the
  `LayoutSettings` route, and replaces the root `列表视图` cycler plus scattered layout switches with a
  single Settings root `布局` row.
- `LayoutSettingsPage` exposes the existing persisted list view mode, fixed list row height, hide
  gallery thumbnails, and horizontal thumbnails controls through the existing HDS Settings child-page
  pattern.
- Existing list-height and thumbnail contracts now target `LayoutSettingsPage`, preserving the same
  single-writer settings paths while reflecting the new information architecture.
- Scope is limited to Settings reachability and IA cleanup. It does not change SearchFilter,
  auth-cookie-login, Reader behavior, thumbnail rendering, list sizing, theme, locale, tag translation,
  or tabbar customization.

Evidence:

- Android FE comparison, 2026-06-19: ADB target `fa967a75`, launched
  `com.honjow.fehviewer/.MainActivity` with `su`; FE Layout page title `样式` showed layout/display
  settings including `隐藏画廊缩略图`, `水平缩略图`, `列表样式`, and `固定列表项高度`.
  Evidence directory: `.hvigor/outputs/layout-settings-fe-comparison/`, especially
  `fe_layout_settings.png` and `fe_layout_settings_window.xml`.
- Deterministic contracts/gates:
  `scripts/test_settings_layout_entry_contract.mjs`,
  `scripts/test_list_height_mode_contract.mjs`,
  `scripts/test_thumbnail_mode_contract.mjs`,
  `scripts/test_settings_reader_entry_contract.mjs`,
  `scripts/test_settings_search_entry_contract.mjs`,
  `scripts/test_settings_about_entry_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- HarmonyOS emulator evidence, 2026-06-19: target `127.0.0.1:5555`, hdc outside sandbox, official
  signed HAP installed. Settings root showed `布局`; tapping it opened Layout settings with `列表视图`,
  `固定列表行高`, `隐藏画廊缩略图`, and `横向缩略图`; tapping `列表视图` opened a menu with `列表`,
  `简洁`, and `网格`.
  Evidence directory: `.hvigor/outputs/layout-settings-nexte-evidence/`, especially
  `nexte_settings_root.png`, `nexte_settings_root_layout.json`,
  `nexte_layout_settings_page.png`, `nexte_layout_settings_page_layout.json`,
  `nexte_layout_settings_menu.png`, and `nexte_layout_settings_menu_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings root placement and Layout settings page structure.
  No further FE/device validation is required unless Settings root or Layout settings routing changes
  again.

### Settings Row Dropdown Menus Use Wrong Anchor

Type: bug / settings interaction UX

Priority suggestion: P1

Status: implemented / needs controller acceptance

Implementation:

- This lane changes settings dropdown rows to bind the native `Menu` to a
  one-row `Column` wrapper instead of a broad section/page container.
- Covered pages: `LayoutSettingsPage`, `ReaderSettingsPage`, `DownloadSettingsPage`, and
  `SecuritySettingsPage`.
- Each row-local menu uses `Placement.BottomRight`, so the popup opens near the row's trailing current
  value / dropdown affordance.
- `ConciseListRow` remains a stable row primitive; the first attempted shared `BuilderParam` menu
  extension was rejected during device validation because tapping the menu path returned the app to the
  desktop.

Verification:

- FE grounding: eros_fe setting selector rows use row taps to open a selection surface, with the row
  retaining title/current-value semantics. Source files checked:
  `/Users/honjow/git/eros_fe/lib/pages/setting/setting_items/selector_Item.dart`,
  `/Users/honjow/git/eros_fe/lib/pages/setting/read_setting_page.dart`,
  `/Users/honjow/git/eros_fe/lib/pages/setting/download_setting_page.dart`, and
  `/Users/honjow/git/eros_fe/lib/pages/setting/security_setting_page.dart`.
- Android FE ADB availability / current foreground evidence:
  `/Users/honjow/git/NextE/.hvigor/outputs/settings-dropdown-anchor/eros_fe_current_pull.png`.
- Deterministic contract: `node scripts/test_settings_dropdown_anchor_contract.mjs` locks row-local
  `Column(){ ConciseListRow(...) }.bindMenu(... Placement.BottomRight ...)` anchors and prevents the
  outer-container binding from returning.
- Full deterministic contracts passed via
  `for f in scripts/test_*contract.mjs; do node "$f" || exit 1; done`.
- V2-only gate passed: `node scripts/test_v1_decorator_inventory_contract.mjs` reports `0 file(s)`.
- i18n parity and `git diff --check` passed.
- Signed macOS build passed: `scripts/build_hvigor_signed.sh`.
- HarmonyOS Mate X7 simulator, hdc outside sandbox, signed HAP installed on `127.0.0.1:5555`.
- Device evidence:
  - Layout settings view-mode menu anchored near the first row trailing value:
    `/Users/honjow/git/NextE/.hvigor/outputs/settings-dropdown-anchor/new_menu.png`.
  - Reader settings direction menu anchored near the first row trailing value:
    `/Users/honjow/git/NextE/.hvigor/outputs/settings-dropdown-anchor/reader_menu.png`.

Remaining acceptance:

- Controller/user should confirm menu placement feel on the relevant settings pages. No further work is
  planned unless placement still feels off on device.

Source:

- User-reported current behavior: tapping a settings row with a menu opens the options from the bottom
  or from an unexpected position, as if the popup is not bound to the clicked control.
- Read-only inspection:
  - `feature/settings/src/main/ets/pages/LayoutSettingsPage.ets` binds the view-mode menu to a parent
    `Column()` / section container with `placement: Placement.Bottom`, not to the clicked row or trailing
    dropdown affordance.
  - `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets`, `DownloadSettingsPage.ets`, and
    `SecuritySettingsPage.ets` use similar `bindMenu` patterns and should be checked for the same
    anchor problem.
  - `feature/user/src/main/ets/pages/FavoritesPage.ets` already documents a workaround for title-bar
    menus: the command opens a native menu through an owned invisible anchor because HDS title-bar icons
    cannot directly anchor a menu.

Observed behavior:

- Menu options may appear from the bottom edge or a broad parent area instead of near the row that the
  user tapped.
- This makes settings rows feel like they are opening a sheet or global action, not a contextual menu.

Expected behavior:

- Dropdown menu placement should be visually anchored to the actual settings row or trailing dropdown
  affordance that was tapped.
- The menu should feel local to the row, not attached to the whole section/page.
- If HDS title/action components cannot directly anchor a native `Menu`, use a deliberate small anchor
  at the intended visual position instead of binding to a large parent container.

Likely root cause:

- `bindMenu` calculates placement from the component it is bound to. Binding it to a container that wraps
  multiple rows gives the framework the wrong geometry.
- The current row abstraction (`ConciseListRow`) does not appear to expose a menu anchor slot, so callers
  bind the menu outside the actual tappable row.

Implementation direction:

- Audit settings rows that use `trailingDropdown` + `bindMenu`.
- Prefer binding the menu to the actual row/trailing affordance, or extend the row component with a
  supported menu-anchor pattern.
- Where direct binding is not possible, place a small owned anchor at the row's trailing edge, similar in
  spirit to the existing Favorites order-menu workaround, but scoped to each settings row.
- Keep this separate from changing the layout settings information architecture or adding new layout
  modes.

Acceptance shape:

- Tapping `设置 -> 布局 -> 列表视图` opens the list/simple/grid menu near that row, not from the bottom of
  the section/page.
- Reader direction/column/auto-page menus and download/security setting menus are checked for the same
  anchoring behavior.
- The selected row still updates through the existing persisted settings path.

### Settings Root Missing Advanced Settings Page

Type: feature gap / settings reachability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- System comparison against `eros_fe` settings showed Advanced as a first-level Settings child page, while
  NextE lacked an Advanced maintenance surface despite already using native `DiagnosticLogger` / HiLog.

Grounding:

- `eros_fe` settings root exposes `Advanced` in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`, routing to
  `EHRoutes.advancedSetting`.
- The FE child page lives at `/Users/honjow/git/eros_fe/lib/pages/setting/advanced_setting_page.dart`
  and includes low-frequency maintenance rows such as language, blockers, clear cache, proxy, data
  import/export, native HTTP client, `Log`, and `Log debugMode`.
- FE log browsing is implemented by `/Users/honjow/git/eros_fe/lib/pages/setting/log_page.dart`; NextE
  intentionally starts with native HiLog diagnostics instead of a file-log viewer.

Implementation:

- `8078f1b feat(settings): add advanced diagnostics page` adds `AdvancedSettingsPage`,
  exports/registers the `AdvancedSettings` route, and adds a Settings root `高级` row.
- The page exposes a native diagnostics description and a `写入测试标记` action that writes
  `[diagnostics] manual_marker | ts=...` through the existing `DiagnosticLogger` / system HiLog path.
- Scope is deliberately limited to the one maintenance loop NextE already owns. It does not implement
  proxy settings, cache clearing, import/export, language switching, blockers, WebDAV, native HTTP
  adapter switching, file-log browsing, SearchFilter, Reader, or auth-cookie-login changes.

Evidence:

- Android FE comparison, 2026-06-19: ADB target `fa967a75`, launched
  `com.honjow.fehviewer/.MainActivity` with `su`; FE Advanced page title `高级` showed maintenance rows
  including language, blockers, clear cache, proxy, import/export, native HTTP client, `Log`, and
  `Log debugMode`.
  Evidence directory: `.hvigor/outputs/advanced-settings-fe-comparison/`, especially
  `fe_advanced_settings.png` and `fe_advanced_settings_window.xml`.
- Deterministic contracts/gates:
  `scripts/test_settings_advanced_entry_contract.mjs`,
  `scripts/test_settings_layout_entry_contract.mjs`,
  `scripts/test_settings_search_entry_contract.mjs`,
  `scripts/test_settings_reader_entry_contract.mjs`,
  `scripts/test_settings_about_entry_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- HarmonyOS emulator evidence, 2026-06-19: target `127.0.0.1:5555`, hdc outside sandbox, official
  signed HAP installed. Settings root showed `高级`; tapping it opened Advanced settings with
  `诊断`, `HiLog`, and `写入测试标记`. Tapping the marker action emitted
  `A0e001/NextE: [diagnostics] manual_marker | ts=1781858500437` in native HiLog.
  Evidence directory: `.hvigor/outputs/advanced-settings-nexte-evidence/`, especially
  `nexte_settings_root.png`, `nexte_settings_root_layout.json`,
  `nexte_advanced_settings_page.png`, `nexte_advanced_settings_page_layout.json`,
  `nexte_advanced_marker_toast.png`, and `nexte_manual_marker_hilog.txt`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings root placement and minimal Advanced diagnostics scope.
  No further FE/device validation is required unless Settings root or Advanced settings routing changes
  again.

Follow-up correction:

- `fix(settings): label diagnostics scope honestly` keeps the existing native diagnostics route but
  changes the visible Settings root row and page title from `高级` / Advanced to `诊断` /
  Diagnostics. The prior label over-promised eros_fe's full Advanced maintenance page, which includes
  language, blockers, cache, proxy, WebDAV, import/export, native HTTP, and log rows. NextE currently
  implements only the HiLog diagnostics marker loop, so the visible label now matches the real scope.
- Contract updated: `scripts/test_settings_advanced_entry_contract.mjs` now locks that the Settings
  root pushes the diagnostics route through the `advanced_diagnostics` label and must not label that
  route as full `settings_advanced`.
- Android FE evidence refreshed on target `fa967a75`, package `com.honjow.fehviewer`, under
  `.hvigor/outputs/settings-diagnostics-label-fe/`: `fe_settings_root.png/xml` shows FE has a root
  `高级` entry, and `fe_advanced_page.png/xml` shows the broad maintenance rows that NextE does not
  yet implement.
- HarmonyOS emulator evidence refreshed on target `127.0.0.1:5555`, signed HAP installed, under
  `.hvigor/outputs/settings-diagnostics-label-nexte/`: `settings_root.png/json` shows the root row is
  `诊断` rather than `高级`, and `diagnostics_page.png/json` shows the child title `诊断` with the
  existing `HiLog` / `写入测试标记` loop.

### Settings Root Missing EH Settings Page

Type: feature gap / settings reachability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- System comparison against `eros_fe` settings showed `EH` as the first Settings child page, while
  NextE still exposed the current site toggle directly in Settings root and kept EH account/site
  actions scattered across the root account section.

Grounding:

- `eros_fe` settings root exposes `EH` in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`, routing to
  `EHRoutes.ehSetting`.
- The FE child page lives at `/Users/honjow/git/eros_fe/lib/pages/setting/eh_setting_page.dart` and
  contains gallery site, link redirect, Cookie, auto profile, website settings, My Tags, image limits,
  WebDAV/MySQL sync, supported links, one-step favorite, and clipboard detection rows.
- NextE intentionally kept this lane to the EH account/site actions it already owns: site mode,
  login, cookie import, My Tags, and logout. It did not implement website settings, cloud sync,
  link handlers, image-limit fetching, or favorite write behavior.

Implementation:

- `b6052df feat(settings): add eh settings page` adds `EhSettingsPage`,
  exports/registers the `EhSettings` route, and replaces the root `站点` toggle row with a first-level
  `EH` row.
- `EhSettingsPage` uses the existing HDS settings child-page pattern and reuses the existing
  `SiteModeSettings`, `EhLogin`, `EhCookieImport`, `MyTags`, and `CookieJarSettings.clear()` flows.
- 2026-06-20 correction: disabled `网站设置` / `图片限制` placeholder rows were removed from
  `EhSettingsPage`. They remain future lanes, not visible settings rows.
- Scope is limited to Settings information architecture and existing action reachability. It does not
  change `CookieJarSettings`, `EhCookieStore`, `AuthState`, WebView login, cookie import parsing, or
  destructive EH writes.

Evidence:

- Android FE comparison, 2026-06-19: ADB target `fa967a75`, launched
  `com.honjow.fehviewer/.MainActivity` with `su`; Settings root showed `E·H` above Layout/Read, and
  EH settings showed `画廊站点`, `E-Hentai` / `ExHentai`, `Cookie`, `我的标签`, `图片限制`, WebDAV/MySQL,
  and link/favorite/clipboard rows.
  Evidence directory: `.hvigor/outputs/eh-settings-fe-comparison/`, especially
  `fe_settings_root_after_back.png`, `fe_settings_root_after_back.xml`, `fe_eh_settings.png`, and
  `fe_eh_settings.xml`.
- Deterministic contracts/gates:
  `scripts/test_settings_eh_entry_contract.mjs`,
  `scripts/test_settings_layout_entry_contract.mjs`,
  `scripts/test_settings_search_entry_contract.mjs`,
  `scripts/test_settings_reader_entry_contract.mjs`,
  `scripts/test_settings_about_entry_contract.mjs`,
  `scripts/test_settings_advanced_entry_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- HarmonyOS emulator evidence, 2026-06-19: target `127.0.0.1:5555`, hdc outside sandbox, official
  signed HAP installed. Settings root showed `EH` above `布局`; tapping it opened EH settings with
  `站点`, `表站 (E-Hentai)`, `登录账号`, `使用 Cookie 登录`, and scoped not-yet-implemented
  `网站设置` / `图片限制` rows.
  Evidence directory: `.hvigor/outputs/eh-settings-nexte-evidence/`, especially
  `nexte_settings_root_final.png`, `nexte_settings_root_final_layout.json`,
  `nexte_eh_settings_page_final.png`, and `nexte_eh_settings_page_final_layout.json`.
- HarmonyOS emulator evidence for the 2026-06-20 placeholder correction: target `127.0.0.1:5555`,
  signed HAP installed. Settings root still exposed `EH`; EH settings layout showed `站点`, account,
  `我的标签`, and `退出登录`, with `网站设置: 0` and `图片限制: 0`. The site row trailing value rendered
  as full `表站`, not the previous truncated long label. Evidence directory:
  `.hvigor/outputs/settings-eh-placeholders-hidden/`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings root placement and minimal EH settings scope. No
  further device validation is required unless Settings root or EH settings routing changes again.

Follow-up, 2026-06-22:

- User feedback: settings and user-visible translation strings should not use slang labels such as
  `表站` / `里站`. Those are community nicknames, not product terminology.
- Current code evidence: `feature/settings/src/main/ets/pages/EhSettingsPage.ets` returns those labels
  in `siteLabel()`, and `entry/src/main/resources/zh_CN/element/string.json` currently uses the same
  slang in search hint, ExHentai access-denied text, EH settings site hint, and ExHentai lock text.
- Expected wording: use official names in UI copy, for example `E-Hentai` and `ExHentai`, with concise
  Chinese descriptions only where needed. Settings rows should show the official service name directly
  instead of slang plus parenthetical explanation.
- Next repair should update resource strings and the EH settings site label, and adjust any contract
  that currently requires compact `表站` / `里站` labels. Historical docs and internal comments can be
  cleaned opportunistically, but the acceptance gate should focus on user-visible strings first.

Status, 2026-06-22: implemented / pending controller acceptance.

- Scope: `EhSettingsPage.siteLabel()` now returns `E-Hentai` / `ExHentai`; zh_CN user-visible strings
  no longer use `表站` / `里站`; base/en search hint no longer says "table site"; the stale Settings
  page comment was also updated to official names.
- Contract update: `scripts/test_settings_eh_entry_contract.mjs` now requires official site labels and
  rejects `表站` / `里站` / `table site` in user-visible resource strings.
- Verified: `node scripts/test_settings_eh_entry_contract.mjs`,
  `python3 scripts/check_i18n_duplicates.py`, `node scripts/test_v1_decorator_inventory_contract.mjs`,
  `git diff --check`, `scripts/build_hvigor_signed.sh`, and local emulator `127.0.0.1:5555`
  install/start smoke with screenshot evidence in `.hvigor/outputs/settings-official-site-copy/`.

### Security Settings Exposure Without Enforcement

Type: settings trustworthiness / partial feature exposure

Priority suggestion: P1

Status: corrected / pending controller acceptance

Source:

- System comparison against `eros_fe` settings showed `Security` as a first-level Settings child page,
  while NextE lacked a matching route or page.
- Follow-up audit found the first implementation exposed an auto-lock selector even though NextE still
  had no lifecycle lock enforcement, biometric unlock surface, or recent-task privacy/masking.

Grounding:

- `eros_fe` settings root exposes `Security` in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`, routing to
  `EHRoutes.securitySetting`.
- The FE child page lives at `/Users/honjow/git/eros_fe/lib/pages/setting/security_setting_page.dart`
  and shows `最近任务中模糊处理` plus `自动锁定`.
- FE auto-lock is backed by `AutoLockController` and local authentication. NextE did not copy that
  implementation because HarmonyOS lifecycle, biometric, and recent-task privacy behavior need their
  own platform validation.

Implementation:

- `e32121d feat(settings): add security settings page` adds `SecuritySettingsPage`,
  exports/registers the `SecuritySettings` route, and adds a Settings root `安全` row between
  `高级` and `关于`.
- Added `SecuritySettingsState` / `SecuritySettings` as a V2 holder plus single-writer preferences
  path for the auto-lock timeout foundation.
- The recent-task blur row is visible but disabled with explicit copy saying HarmonyOS window privacy
  support is not implemented yet. This avoids pretending to protect recent tasks without a verified
  platform API.
- Scope is limited to Settings reachability and persisted auto-lock preference selection. It does not
  implement biometric unlock overlay, lifecycle lock enforcement, recent-task privacy/masking, or any
  auth-cookie-login behavior.
- 2026-06-20 correction: Settings root no longer exposes the `安全` entry. The parked route/page/state
  remain for a future platform-validated security lane, but users are not shown an auto-lock preference
  that does not actually lock the app.

Evidence:

- Android FE comparison, 2026-06-19: ADB target `fa967a75`, launched
  `com.honjow.fehviewer/.MainActivity` with `su`; Settings root showed `安全`, and Security settings
  showed `最近任务中模糊处理` and `自动锁定 / 停用`.
  Evidence directory: `.hvigor/outputs/security-settings-fe-comparison/`, especially
  `fe_settings_root.png`, `fe_settings_root.xml`, `fe_security_settings.png`, and
  `fe_security_settings.xml`.
- Deterministic contracts/gates:
  `scripts/test_settings_security_entry_contract.mjs`,
  `scripts/test_settings_eh_entry_contract.mjs`,
  `scripts/test_settings_layout_entry_contract.mjs`,
  `scripts/test_settings_search_entry_contract.mjs`,
  `scripts/test_settings_reader_entry_contract.mjs`,
  `scripts/test_settings_about_entry_contract.mjs`,
  `scripts/test_settings_advanced_entry_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- HarmonyOS emulator evidence, 2026-06-19: target `127.0.0.1:5555`, hdc outside sandbox, official
  signed HAP installed. Settings root showed `安全` between `高级` and `关于`; tapping it opened
  Security settings with disabled recent-task blur copy, auto-lock `停用`, and a full timeout menu.
  Selecting `5 分钟` updated the page, then QA restored the value to `停用`.
  Evidence directory: `.hvigor/outputs/security-settings-nexte-evidence/`, especially
  `nexte_settings_root.png`, `nexte_settings_root_layout.json`,
  `nexte_security_settings_page.png`, `nexte_security_settings_page_layout.json`,
  `nexte_security_auto_lock_menu.png`, `nexte_security_auto_lock_menu_layout.json`,
  `nexte_security_auto_lock_5m.png`, `nexte_security_auto_lock_5m_layout.json`,
  `nexte_security_auto_lock_restored.png`, and `nexte_security_auto_lock_restored_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance that Security is no longer visible from Settings root until actual
  protection is wired.
- Future separate lanes are still needed for real recent-task privacy/masking and biometric
  auto-lock enforcement.

### Viewed History Data Has No User Surface

Type: feature gap / navigation reachability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- `docs/ui-architecture-audit.md` F3/M5: History had a model, persisted state, and detail-page write
  path, but no user-facing page or entry point.

Grounding:

- `eros_fe` exposes History as an optional tab in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/tabhome_controller.dart`, backed by
  `/Users/honjow/git/eros_fe/lib/pages/tab/view/history_page.dart`.
- The FE History page renders recently viewed galleries, supports pull/sync, and has a clear-history
  title-bar action. NextE already records a lightweight `ViewedGallery` 5 seconds after detail open,
  matching the FE debounce semantics.

Implementation:

- Added `ViewedHistoryPage` under `feature/user`, reading `connectViewedHistory()` and rendering stored
  entries in an HDS secondary list.
- Added a Settings root `历史` row that pushes the new `History` route.
- History rows show cover/title/category/page-count/uploader/time and click through to `GalleryDetail`
  with title/thumb seed params.
- Added a title-bar clear-history action wired to `ViewedHistorySettings.clear()`.
- Scope is limited to local history reachability. It does not add a configurable History bottom tab,
  WebDAV/MySQL sync, history deletion confirmation, or per-row delete.

Evidence:

- Android FE comparison: ADB target `fa967a75`, launched with
  `/opt/homebrew/bin/adb shell su -c 'am start -n com.honjow.fehviewer/.MainActivity'`; foreground
  confirmed by `dumpsys window`; screenshot captured at
  `/private/tmp/nexte_viewed_history_fe_reference/fe_foreground.png`. Source grounding confirms FE
  History as a tab list with a clear action.
- Deterministic contracts: `scripts/test_viewed_history_contract.mjs`,
  `scripts/test_viewed_history_surface_contract.mjs`.
- Gates: `scripts/test_viewed_history_surface_contract.mjs`,
  `scripts/test_viewed_history_contract.mjs`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, `git diff --check`, and official signed Hvigor build through
  `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened a real gallery detail, waited past the 5s viewed-history debounce, entered Settings ->
  `历史`, saw a real history list with cover/title/meta/time, and clicked the first history row back
  into the matching GalleryDetail page. Evidence directory:
  `/private/tmp/nexte_viewed_history_acceptance/`, especially `settings.png`,
  `history_page.png`, `history_page.json`, `back_detail.png`, and `back_detail.json`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings entry, History list, and history-row-to-detail
  screenshots. No further device validation is required unless History route, Settings entry, or
  viewed-history persistence changes again.

### Settings Root About Row Is Not Routable

Type: feature gap / settings reachability

Priority suggestion: P2

Status: implemented / needs controller acceptance

Source:

- Settings root already had an `关于` row, but it was a static `NextE v1.0.0` row with no route,
  while `eros_fe` exposes About as a settings child page.

Grounding:

- `eros_fe` reference: `/Users/honjow/git/eros_fe/lib/pages/setting/about_page.dart` renders a normal
  About page with app name, unofficial E-Hentai client subtitle, version, update check, and license.
- `eros_fe` settings root exposes `关于` as a tappable row in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`.
- HarmonyOS reference: `/Users/honjow/git/V2Next/entry/src/main/ets/pages/AboutPage.ets` uses a native
  settings-style About page with grouped rows and bundle version lookup.

Implementation:

- Added `feature/settings/src/main/ets/pages/AboutPage.ets` using the existing HDS
  `HdsNavDestination` + `SecondaryListScaffold` + `GroupedListSection` + `ConciseListRow` pattern.
- The Settings root `关于` row now pushes the `About` route instead of showing only a static trailing
  version string.
- Entry route map imports/registers `About`; settings module exports `AboutPage`.
- Scope is limited to About reachability and app/version/license information. This does not implement
  online update checks, external project links, or a full third-party license browser.

Evidence:

- Android FE comparison: ADB target `fa967a75`, `su` launched `com.honjow.fehviewer/.MainActivity`;
  Settings and About screenshots captured at
  `/private/tmp/nexte_settings_about_fe_reference/fe_settings.png` and
  `/private/tmp/nexte_settings_about_fe_reference/fe_about.png`.
- Deterministic contract: `scripts/test_settings_about_entry_contract.mjs`.
- Gates: `scripts/test_settings_about_entry_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`, and official
  signed Hvigor build through `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Settings root showed `关于`; clicking it opened About with `NextE`, subtitle, version, platform,
  source license, and unofficial-client notice. Evidence directory:
  `/private/tmp/nexte_settings_about_acceptance/`, especially `settings.jpeg`, `settings_layout.json`,
  `about.jpeg`, and `about_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings row and About page screenshots. No further device
  validation is required unless Settings root or About route changes again.

### Toplist Applies My Tags Hidden Filter

Type: feature parity / EH settings

Priority suggestion: P1

Status: in progress

Grounding:

- `eros_fe` reference: `/Users/honjow/git/eros_fe/lib/pages/tab/fetch_list.dart` and
  `tag_controller.dart` apply the user's My Tags hide rule when building gallery lists; NextE already
  has the same local `UserTagStore.anyHidden()` path for normal gallery/search list filtering.
- Main information: users who marked tags as hidden should not see matching galleries in the Toplist by
  default.
- Primary action: a single EH settings switch controls whether Toplist applies the user's hidden My Tags;
  secondary action is leaving it off to show the raw ranking list.
- Scope: implement the default-on Toplist local hide filter and settings switch only; no Advanced Search
  `f_sft`, no server-side Toplist filter params, no MyTags write changes, no list UI redesign.
- HarmonyOS expression: reuse `EhSettingsPage` + `ConciseListRow` switch and a small
  Preferences-backed AppStorageV2 holder, then reload retained Toplist period pages when the switch changes.
