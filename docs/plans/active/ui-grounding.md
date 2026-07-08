# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: reader image loading retry stabilization

Status: active
Reference implementation: current NextE `feature/reader/src/main/ets/pages/ReaderPage.ets` cached image display pipeline, `shared/src/main/ets/services/CachedImageFileService.ets` in-flight image-cache joins, `shared/src/main/ets/network/EhHttpClient.ets` streamed binary download diagnostics, and the exported 2026-07-08 reader log showing repeated `http_binary_stream_retry` timeouts on large pages.
Surface type: existing Reader image loading, progress, retry behavior, and Reader Settings preload row only; no Reader chrome layout, gesture model, page order, parser, or EH endpoint change.
Primary information: when large gallery pages load slowly, the Reader should distinguish resolving, requesting image bytes, receiving image bytes, and preparing local images; it shows a native busy indicator until bytes arrive, then native linear progress when byte totals are known; users can reduce or increase forward preloading from 0 to 5 pages.
Primary action: open Reader Settings, choose the preload page count, then open a large gallery in Reader and wait for current/adjacent pages to load; the Reader should keep using cached local `file://` display URIs, bounded automatic re-source retries, and the existing retry overlay when attempts are exhausted.
Reuse or deviation: reuse `CachedImageFileService.load()`/`cached()`, visible Reader image components, native `LoadingProgress()` for request/no-total waits, native `ProgressType.Linear` for determinate downloads, and native settings row dropdown menus; deviate by replacing the off-screen `Image(remoteUrl)` warmer with a cache-backed warmer, giving streamed image downloads bounded reader-specific connect and no-progress timeouts while keeping the long binary read timeout for active streams, clearing automatic retry count only after success or explicit source reset, and replacing hardcoded preload windows with the persisted 0..5 setting.
Verification: grounding ledger review, V1 decorator inventory, diff check, and follow-up device/manual QA on the reported large-gallery log scenario; this source pass does not claim a signed build or real-device smoke.

## Active: account asset balance row

Status: active
Reference implementation: current NextE `feature/settings/src/main/ets/pages/AccountPage.ets` grouped account status rows, `shared/src/main/ets/network/EhApiService.ets` EH-only `getEhHome()` account data fetch, and `../eros_fe/lib/common/parser/archiver_parser.dart` GP/Credits text preservation pattern for account funds.
Surface type: Account hub informational row only; no exchange action, archive submit, GP conversion, Credits conversion, ExHentai endpoint, or destructive EH write.
Primary information: the account page shows the EH asset balance as two peer values, preserving EH's own GP/kGP and Credits unit text.
Primary action: open Account or tap the row to refresh; the row loads from `https://e-hentai.org/exchange.php?t=gp` regardless of current EH/EX site mode and shows unavailable rather than guessing when the current-balance text cannot be identified.
Reuse or deviation: reuse `SecondaryListScaffold`, `GroupedListSection`, and `ConciseListRow`; deviate from trailing-value settings rows by putting the combined `GP / Credits` value in one subtitle line so neither balance is visually promoted over the other.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, diff check, signed HarmonyOS build, and account page smoke when an authorized target/session is available.

## Active: list tail-appear pagination trigger

Status: active
Reference implementation: current NextE `shared/src/main/ets/components/PullRefreshListScaffold.ets`, `PullRefreshGridScaffold.ets`, `PullRefreshWaterFlowScaffold.ets`, `shared/src/main/ets/utils/BasicDataSource.ets`, Home/Search/Favorites `loadMore()` VM guards, and `../JHenTai/lib/src/widget/eh_gallery_collection.dart` last-item builder-triggered `handleLoadMore`.
Surface type: existing list/grid/waterfall pagination trigger timing and lazy data append path only; no visual layout, card, footer copy, paging cursor, or network API change.
Primary information: gallery and local lazy lists keep showing the same content and loading footer while the next page can start before the hard tail and append without copying the whole already-rendered list.
Primary action: scroll a paged Home/Search/Favorites/all-thumbnails list toward the tail; the existing `canLoadMore()`/`hasMore()` guards decide whether the next page starts before the hard `onReachEnd` boundary.
Reuse or deviation: reuse the existing page item builders, `onReachEnd`/`onNearEnd`, `canStartBottomRefresh`, page ViewModel concurrency guards, and `LazyForEach` `onDataAdd` notification style; deviate only by making `BasicDataSource.appendData()` push into the stable backing array and by giving WaterFlow the same near-end hook Grid already uses.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and a paged Home/Search/Favorites smoke; performance QA should compare a 120Hz scroll trace before/after a WaterFlow or cover-wall load-more append.

## Active: detail preview pull-up entry

Status: active
Reference implementation: current NextE `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` detail `PullRefreshListScaffold`, `feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets` `moreButton()` / `onMore(initialImagePage)`, `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets` initial-image-page positioning, and existing shared `PullRefresh` bottom-refresh wiring.
Surface type: Gallery detail bottom-edge gesture only; no preview-card layout, thumbnail mode, AllThumbnails paging, reader launch, network parser, or copy change.
Primary information: the detail page still shows the same header, comments, first preview page, and explicit preview entries; when the user reaches the bottom, the same all-thumbnails destination is available by continuing the upward pull.
Primary action: scroll to the bottom of a detail page with preview images and pull upward past the threshold; the app opens AllThumbnails with the same initial image page as the preview card's bottom more-preview button.
Reuse or deviation: reuse the existing detail scroller, `PullRefreshListScaffold` bottom refresh API, `GalleryPreviewGrid` entry-page semantics, and `openThumbnails()` route params; deviate only by adding a gesture alias for an existing visible action.
Verification: grounding ledger review, V1 decorator inventory, diff check, and device/manual QA on a detail page with previews; gesture QA should also cover hidden/horizontal thumbnail modes and a loaded gallery with no extra preview page.

## Active: search history scroll recovery

Status: active
Reference implementation: current NextE `feature/search/src/main/ets/pages/GallerySearchPage.ets` `SearchSuggestionView()` scrollable suggestion list, the same page's HDS `bindToScrollable` linkage, `feature/home/src/main/ets/pages/TabEditPage.ets` tag translation cache pattern, and FE `../eros_fe/lib/pages/tab/view/search_page.dart` `_searchHistoryBtnWithTranslate()`.
Surface type: Search landing history area only; no query semantics, suggestion UI, result list, search filter behavior, or history persistence change.
Primary information: when recent search chips exceed the visible search landing area, the user should still see the same history header, clear action, and chips, with overflow reachable by vertical scroll; long history text wraps; translated tag matches show a secondary line under the raw query.
Primary action: open Search with no active query, swipe the recent-search history area, tap a chip to search, long-press a chip to delete it, or read the translated tag subtitle when local tag translation is enabled.
Reuse or deviation: reuse the existing search page scroller pattern, history chip layout, `TagQuery.parse()` and `TagTranslationService.translateFullTagAsync()`; deviate only by giving the history branch its own `Scroll` and by rendering FE-style translated history as a secondary chip line.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and X7 Search history overflow smoke.

## Active: account switch identity and per-account favorites state

Status: active
Reference implementation: current NextE `feature/settings/src/main/ets/pages/AccountPage.ets` account switcher rows, `shared/src/main/ets/services/UserProfileService.ets` stored per-member profile snapshots, `shared/src/main/ets/settings/CookieJarSettings.ets` active account switching, and Favorites selector metadata flow in `feature/user/src/main/ets/components/FavcatPage.ets` plus FE `../eros_fe/lib/pages/controller/favorite_sel_controller.dart`.
Surface type: Account hub switcher rows, Account Cookie summary/detail count, and Favorites favcat selector metadata after account changes; no new account management surface or destructive EH action.
Primary information: each saved account row should show the best stored identity for that memberId, active Cookie count should reflect the current jar, and Favorites category names/counts should belong to the active account.
Primary action: tap a saved account row to switch accounts; adding a Cookie/password account should best-effort fetch and save its forum profile; opening Account Cookie or Favorites after switching should show active-account data.
Reuse or deviation: reuse the existing `SecondaryListScaffold`/account row structure, `AuthState` as a non-sensitive reactive mirror, `UserProfileService` profile snapshots, `CookieJarSettings` as the single account switch writer, and `FavcatListSettings`; deviate only by making favcat snapshot storage memberId-scoped with legacy global fallback.
Verification: cookie import contract, favcat snapshot contract, grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and account switch smoke on an authorized target covering row identity, Cookie count, and Favorites favcat names/counts.

## Active: index route-map coordinator

Status: active
Reference implementation: current NextE `entry/src/main/ets/pages/Index.ets` Navigation `routerMap`, `../V2Next/entry/src/main/ets/model/IndexRouteCoordinator.ets`, and HarmonyOS `Navigation` + `NavPathStack` + `navDestination`.
Surface type: app navigation shell route registration only; no visible page or settings surface change.
Primary information: route names resolve to a typed destination family before the ArkUI builder renders the existing page component.
Primary action: pushing an existing route name still opens the same page; unknown or safe-mode-blocked routes render an empty destination.
Reuse or deviation: reuse the existing HDS Navigation shell, shared `NavPathStack`, `SafeModeGate`, and all page components; deviate only by moving route-name lookup out of the builder so `Index` owns component rendering while the coordinator owns string resolution.
Verification: grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: storage import preview and diagnostics

Status: active
Reference implementation: `../eros_fe/lib/pages/setting/advanced_setting_page.dart` import/export settings rows, `../eros_fe/lib/utils/import_export.dart` backup file flow, and current NextE `feature/settings/src/main/ets/pages/CacheSettingsPage.ets` Storage import/export sheets.
Surface type: Storage settings import action, encrypted-backup password sheet, and restore confirmation dialog only; no new settings page or sync pathway.
Primary information: before restore, the user sees the backup type and record counts for settings/local data/sensitive items; invalid files show a concrete import failure reason instead of one generic unreadable message.
Primary action: tap Import, choose a backup file, enter password when required, review the restore summary, then confirm or cancel.
Reuse or deviation: reuse the existing Storage page rows, AppModalScaffold password sheet, BackupService.preview(), and platform AlertDialog; deviate from the old generic confirmation only by adding section counts and parser-code-specific toasts.
Verification: settings backup contract, grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and emulator Storage import/export smoke covering the visible confirmation path.

## Active: toplist page jump dialog

Status: active
Reference implementation: `../eros_fe/lib/pages/tab/controller/tabview_controller.dart` `showJumpDialog()` / `_jumpToPage()`, `../eros_fe/lib/common/parser/gallery_list_parser.dart` `table.ptt` page parsing, and `../V2Next/feature/detail/src/main/ets/pages/TopicDetailPage.ets` `CustomContentDialog` jump-floor input.
Surface type: Toplist title-bar jump action and active period input dialog only; no search/home/favorites page-jump surface.
Primary information: the user sees a compact page-number dialog with the valid Toplist range from EH's parsed `table.ptt`.
Primary action: open the Toplist title menu, enter a 1-based page number, confirm, and replace the active ranking period with `toplist.php?p=<page-1>`; use the adjacent first-page action to reload page 1 after a jump.
Reuse or deviation: reuse the existing title-bar command bus and retained ToplistPeriodPage VM ownership; deviate from the existing all-thumbnails sheet because this is a short scalar input better expressed as a system dialog.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and Toplist jump smoke on an emulator.

## Active: reader double-page switch and per-gallery pairing

Status: active
Reference implementation: current NextE `feature/reader/src/main/ets/pages/ReaderPage.ets` Reader chrome button row, `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets` native switch rows, and eros-style absolute image index reading progress.
Surface type: Reader bottom chrome plus Reader Settings double-page row only; no image loading, gesture recognizer, or spread renderer redesign.
Primary information: the user sees one global double-page on/off control, while each gallery keeps its own odd/even spread pairing through reading progress cache.
Primary action: toggle double-page in settings or Reader chrome, and in double-page mode tap one icon to advance exactly one image page so the current gallery's pairing shifts.
Reuse or deviation: reuse existing circular Reader toolbar buttons, `ConciseListRow` switch semantics, and the existing `GalleryReadProgressState` persistence path; deviate from the old A/B menu because pairing is not a global preference.
Verification: grounding ledger review, read-progress persistence contract only if data persistence changes, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and X7 Reader smoke.

## Active: reader direction menu

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets` `DirMenu()` native direction picker, current `feature/reader/src/main/ets/pages/ReaderPage.ets` bottom chrome button row, and `ReadModeSettings.setMode()` as the single persisted writer.
Surface type: Reader bottom chrome direction control only; no Reader Settings, gesture, pager, or double-page model redesign.
Primary information: the direction button still shows the current LTR/RTL/vertical icon, and the menu shows all three direction choices with a checkmark on the active mode.
Primary action: tap the Reader direction button, choose left-to-right, right-to-left, or vertical from the native menu, then return to reading with the selected mode persisted.
Reuse or deviation: reuse the settings page's native `Menu`/`MenuItem` direction picker semantics and existing circular Reader toolbar button; deviate only by replacing the old cyclic tap behavior so users can choose directly.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and X7 Reader chrome smoke.

## Active: Huawei Cloud sync failure detail

Status: active
Reference implementation: current NextE `feature/settings/src/main/ets/pages/SyncSettingsPage.ets` provider row/status pattern, `shared/src/main/ets/settings/SyncSettings.ets` persisted provider status, and `shared/src/main/ets/sync/HuaweiCloudSyncService.ets` RDB cloud progress callback.
Surface type: Sync settings Huawei Cloud provider status and manual-sync toast only; no new navigation surface, table-management UI, or AGC administration UI.
Primary information: when manual Huawei Cloud sync fails, the user should see the current progress code and failing table counts instead of a generic failure label.
Primary action: tap "同步到华为云" and read the immediate toast/status row detail for the failing table.
Reuse or deviation: reuse the existing `ConciseListRow` status subtitle and `SyncSettings` persistence; deviate only by storing the last failure detail so page/process recreation does not erase the diagnostic.
Verification: Huawei cloud sync contract, sync design contract, V1 decorator inventory, grounding ledger review, diff check, signed HarmonyOS build, and 197 layout/hilog evidence showing `image_block_user_rules:up=0/0,down=0/39,fail=39`.

## Active: download management search and sorting

Status: active
Reference implementation: `../eros_n_ohos/lib/pages/nav/downloads/downloads_page.dart` status-grouped Downloads page, `../eros_fe/lib/pages/item/download_gallery_item.dart` gallery task row, `../eros_fe/lib/pages/item/download_archiver_item.dart` archive task row, current NextE `entry/src/main/ets/components/DownloadTypeBar.ets` title-bottom queue selector, and `feature/user/src/main/ets/pages/FavoritesPage.ets` native order menu pattern.
Surface type: Downloads tab task management list and title-bar actions only; no executor, RDB schema, or archive submit changes.
Primary information: visible download tasks should be searchable, grouped by status, sorted by added time/title, and show enough row metadata to distinguish task type, progress, and queued time.
Primary action: search/filter visible tasks, choose a sort mode from a native menu, resume/pause/retry one ordinary gallery task, retry an archive task, or tap completed content to read locally.
Reuse or deviation: reuse the existing HDS title-bar bottomBuilder, shared `AppSearchField`, task cards, current task state fields, and FavoritesPage command-bus menu anchor; deviate only by deriving grouped/sorted visible arrays in the page instead of mutating queue order, and by not exposing archive pause until byte-range resume exists.
Verification: download management plan doc, grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and X7 Downloads search/sort/group smoke.

## Active: download export feedback and reuse

Status: active
Reference implementation: `../V2Next/feature/detail/src/main/ets/pages/TopicDetailPage.ets` reply `LoadingDialog`, current NextE `feature/download/src/main/ets/pages/DownloadQueuePage.ets` completed-task export menu, and `shared/src/main/ets/services/DownloadExportService.ets` deterministic export file paths.
Surface type: Downloads tab completed-task export action only; no export-history page, progress bar, cancel action, or manifest cache.
Primary information: after choosing an export format, the user sees a native blocking loading dialog until the export file is ready, then the system share sheet opens; PDF failures show the decoder/export error in the toast.
Primary action: open a completed download task menu, choose one export format, wait for the native loading dialog to close, and pick a target app from the system share sheet.
Reuse or deviation: reuse Next2V's `CustomDialogController` + system `LoadingDialog`, existing ShareUtil share handoff, the export file itself as the reuse cache for archive-like formats, and HarmonyOS ImageKit decode for PDF images that are not directly embeddable as JPEG/PNG.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed build, and X7 completed-task export smoke covering loading-to-share, repeated same-format export, and PDF export from system-decodable images.

## Active: security background privacy and native unlock

Status: active
Reference implementation: `../eros_fe/lib/common/controller/auto_lock_controller.dart`, `../eros_fe/lib/pages/tab/view/unlock_page.dart`, existing NextE `feature/settings/src/main/ets/pages/SecuritySettingsPage.ets`, and `entry/src/main/ets/entryability/EntryAbility.ets` as the window/lifecycle owner.
Surface type: Security settings rows plus a root full-screen Gaussian-blur lock overlay only; no custom password page or new navigation route.
Primary information: users see whether recent-task privacy is enabled and, when locked, the current app stays in place behind a heavily blurred privacy layer.
Primary action: toggle recent-task protection, choose an auto-lock timeout, return from background, and unlock with the HarmonyOS system authentication sheet.
Reuse or deviation: reuse `ConciseListRow`, the existing auto-lock dropdown, native `Window.setWindowPrivacyMode`, `@ohos.userIAM.userAuth`, and the existing root `Stack` overlay; deviate from eros_fe only by not building a custom Flutter unlock page.
Verification: grounding ledger review, V1 decorator inventory, i18n resource check, signed HarmonyOS build, and 197/Emulator smoke for recent-task privacy plus blurred foreground unlock.

## Active: about page update check

Status: active
Reference implementation: `../eros_fe/lib/pages/setting/about_page.dart` update row and `../eros_fe/lib/common/controller/update_controller.dart` GitHub latest-release check, current NextE `feature/settings/src/main/ets/pages/AboutPage.ets`, and existing external browser `Want` usage in `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets`.
Surface type: About page app-info section only; no in-app HAP download, installer handoff, automatic background polling, Markdown renderer, or update-source settings.
Primary information: users see the installed version and a clear row for checking whether GitHub Releases has a newer NextE version.
Primary action: tap Check for updates, wait for a short checking state, then either see the latest-version result or open the GitHub release page from the update dialog.
Reuse or deviation: reuse `ConciseListRow`, `showAlertDialog`, `promptAction` toast, `bundleManager` version lookup, and native browser `Want`; deviate from eros_fe by showing plain truncated release notes instead of Markdown and by leaving downloads/install to the release page.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, diff check, signed build, and emulator About-page check/update smoke.

## Active: download source cover seed and archive progress publish

Status: active
Reference implementation: `feature/download/src/main/ets/pages/DownloadQueuePage.ets` existing cover-to-source entry, `feature/gallery/src/main/ets/components/GalleryHeaderCard.ets` detail header `EhThumbnail` source-size path, and `shared/src/main/ets/settings/DownloadQueueSettings.ets` ordinary gallery stream-progress throttle.
Surface type: Downloads tab cover source navigation and archive download progress publishing only; no task-card visual redesign.
Primary information: opening the source gallery from a downloaded task should paint the detail cover from stable seeded metadata, while large archive downloads should expose coarse live progress without freezing the app.
Primary action: tap a download-list cover to open the source detail, or start a large archive download and keep navigating while progress advances.
Reuse or deviation: reuse `GalleryDetailParams` source dimensions and the existing ordinary-download 500ms progress throttle pattern; deviate only by preserving cover dimensions in download tasks and throttling archiver queue publication.
Verification: download queue RDB contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and 197 archive hilog/user-path smoke.

## Active: reader image block action safety

Status: active
Reference implementation: `feature/reader/src/main/ets/pages/ReaderPage.ets` existing Reader top/bottom chrome, `shared/src/main/ets/components/PreviewThumbTile.ets` native `MenuItem` image-block actions, and `feature/download/src/main/ets/pages/DownloadQueuePage.ets` `showAlertDialog` confirmation pattern.
Surface type: Reader chrome current-image block action only.
Primary information: reading controls stay focused on page navigation, current page state, save/original, auto-read, thumbnails, and mode.
Primary action: when image blocking is enabled, open the secondary Reader menu and explicitly confirm adding a local image block rule for the current image.
Reuse or deviation: reuse the existing image-block runtime write path and platform menu/dialog components; remove the one-tap bottom-toolbar block button so the side-effect action is not mixed with frequent reader controls.
Verification: grounding ledger review, V1 decorator inventory, i18n resources, diff check, signed HarmonyOS build, and Reader chrome smoke.

## Active: image block source rule previews

Status: active
Reference implementation: current NextE `feature/settings/src/main/ets/pages/ImageBlockSettingsPage.ets` local-rule preview slot, `shared/src/main/ets/services/ImageBlockRuntimeService.ets` preview sprite crop path, and existing `EhApiService.getGalleryDetail()` / `getPreviewImages()` gallery preview loading.
Surface type: Image block settings local-rule and subscription-rule preview only; no new rules page, no AGC data-object change, and no synced thumbnail payload.
Primary information: synced or restored rules should show an actual EH source thumbnail when `source_url` / `source_page` can identify the gallery image, instead of leaving the preview column blank.
Primary action: add or sync an image-block rule with source metadata, open image-block settings, and let the page fetch a preview from the source gallery previews for display.
Reuse or deviation: keep rule, cloud sync, and backup records as metadata only; use `preview_path` only as a legacy/local file reference and hold fetched local-cache preview paths in the settings page state for the current session.
Verification: image-block foundation contract, settings backup contract, grounding ledger review, V1 decorator inventory, Huawei cloud sync contract, sync design contract, diff check, signed build, and 237 device settings smoke.

## Active: sprite thumbnail loading indicator

Status: active
Reference implementation: `shared/src/main/ets/components/EhThumbnail.ets` cover placeholder spinner and `shared/src/main/ets/components/EhSpriteThumbnail.ets` preview sprite crop renderer used by detail preview/all-thumbnails.
Surface type: Gallery detail preview thumbnails and all-thumbnails grid/horizontal thumbnails only.
Primary information: while EH sprite thumbnails are still decoding, each thumbnail slot should visibly show loading instead of becoming a blank white hole with only the page number.
Primary action: wait for preview thumbnails to load, then tap a thumbnail to open Reader; long-press image-block actions remain unchanged.
Reuse or deviation: reuse the existing shared sprite thumbnail renderer and existing `LoadingProgress`/cover placeholder treatment; do not change preview grid layout, detail page spacing, or thumbnail sizing.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and detail preview/all-thumbnails loading smoke.

## Active: detail action strip edge alignment

Status: active
Reference implementation: `5a486221` detail action strip edge alignment and current `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` Read FAB `visualActionEdge` handling.
Surface type: Gallery detail relation/action strip only.
Primary information: secondary gallery actions remain visible as compact chips.
Primary action: tap similar/torrent/archiver/rate/download chips; the strip follows the same left/right edge as the Read action.
Reuse or deviation: reuse the existing action-edge state, Scroll scroller, width measurement, and translate animation from the accepted pre-`85d49d55` implementation.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and detail page light/dark smoke.

## Active: home source trailing action theme

Status: active
Reference implementation: `shared/src/main/ets/components/SubTabBar.ets` cached bar `themeTracked()` color refresh plus `feature/gallery/src/main/ets/pages/GalleryTorrentsPage.ets` secondary transparent icon action.
Surface type: Home custom SubTab source bar trailing manage action only.
Primary information: the pinned manage button stays a secondary affordance beside the scrollable SubTab labels.
Primary action: tap the trailing list icon to open custom SubTab management.
Reuse or deviation: reuse transparent secondary icon-button treatment, existing `font_secondary` icon tint, and SubTabBar's `effectiveDark` read so the cached title-bottom content repaints when dark/light mode changes.
Verification: grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and dark/light visual smoke.

## Active: image block visual management

Status: active
Reference implementation: NextE `feature/settings/src/main/ets/pages/ImageBlockSettingsPage.ets`, `shared/src/main/ets/components/PreviewThumbTile.ets`, `shared/src/main/ets/components/EhSpriteThumbnail.ets`, Reader-side `ImageBlockRuntimeService.addLocalRuleForFile()` / `addWhitelistForFile()`, and existing HDS settings sections for provider/update actions; subscription rule rows reuse the same preview-led local rule layout rather than a text-only settings row.
Surface type: EH Settings child page for image blocking management plus Reader/thumbnail blocked-image presentation.
Primary information: image-block records are images first, with readable source, enable state, threshold, preview/placeholder, traceable gallery/page metadata, and stable already-blocked thumbnail state while rules refresh.
Primary action: toggle image blocking globally, refresh/toggle rule subscriptions, open subscription rules from a separate row, copy submit-ready local rules, tune one rule, delete mistaken local rules, remove false-positive allowlist entries, and long-press a thumbnail to add/ignore a matching rule.
Reuse or deviation: reuse `SecondaryListScaffold`, `GroupedListSection`, `ConciseListRow`, `AppModalScaffold`, native `Toggle`, native `Slider`, existing preview image row treatment, `EhSpriteThumbnail`'s native image clipping, and EH image-page keys for thumbnail hash caching; only generate a cropped preview file for sprite-backed manual thumbnail rules so settings rows do not all show the same sprite sheet.
Verification: image-block foundation contract, reader image-block contract, image-block sample contract, i18n duplicate check, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, image-block thumbnail hash logs, and 197 settings/Reader/thumbnail screenshots.

## Active: non-sheet input keyboard avoidance

Status: active
Reference implementation: `feature/search/src/main/ets/pages/GallerySearchPage.ets`, `feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets`, and `feature/home/src/main/ets/pages/TabEditPage.ets` page-level `KeyboardAvoidMode.RESIZE` / `OFFSET` lifecycle handling.
Surface type: pushed full-page input/settings surfaces only; half-modal input fields keep their existing `SheetKeyboardAvoidMode` handling and are excluded from this pass.
Primary information: focused text fields in WebDAV, download, translation, EH profile, password login, and cookie import pages remain visible when the soft keyboard opens.
Primary action: focus a field near the lower part of the page and continue editing without the keyboard covering the input.
Reuse or deviation: reuse the existing page lifecycle keyboard-avoid pattern; do not add manual keyboard-height padding, sheet parameters, or input layout changes.
Verification: static input scan excluding sheet-hosted fields, grounding ledger review, V1 decorator inventory, diff check, signed HarmonyOS build, and simulator/phone smoke for WebDAV field focus.

## Active: gallery archiver half-modal

Status: active
Reference implementation: `../eros_fe/lib/pages/gallery/view/archiver_dialog.dart` `showArchiverDialog()` / `ArchiverView`, `feature/gallery/src/main/ets/pages/GalleryTorrentsPage.ets` modal/page dual content pattern, and `shared/src/main/ets/components/AppModalScaffold.ets`.
Surface type: Gallery detail action-row half-modal for archive quote/options; the route page remains only as a compatibility wrapper.
Primary information: GP/Credits balance plus Download and H@H archive options with resolution/type, size, and cost.
Primary action: tap an archive option to open the protected native confirmation; close/retry are secondary sheet actions, and no archive submit is performed before confirmation.
Reuse or deviation: reuse `bindSheet` + `AppModalScaffold` and extract `GalleryArchiverContent({ modal })` like torrent content; deviate from the previous full NavDestination main path because FE presents this as a lightweight dialog/sheet from gallery detail.
Verification: gallery archiver readonly contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 gallery-detail screenshot/layout plus hilog showing `detail_archiver_open` and either quote load or `archiver_missing_or_token`.

## Active: download task live progress counters

Status: active
Reference implementation: `/Users/honjow/git/EhViewer-NekoInverter/app/src/main/java/com/hippo/ehviewer/download/DownloadManager.kt` `NotifyTask` updating `finished/downloaded/total/state` together, and `/Users/honjow/git/JHenTai/lib/src/service/gallery_download_service.dart` `GalleryDownloadProgress` using per-image downloaded facts as the progress source.
Surface type: Downloads tab Gallery/Archiver task card status text, progress bar, and task action diagnostics only; no visual redesign of the card layout.
Primary information: each visible task row must show a status that agrees with the downloaded/seeded/expected file counts and live stream progress.
Primary action: while a task downloads, the same row updates its progress text/bar without switching tabs; after completion, the row is only complete when the expected file count is satisfied.
Reuse or deviation: reuse the existing stable task card rows and `DownloadQueueState.revision`, but preserve each existing `DownloadGalleryTask` / `DownloadArchiverTask` observed object identity across queue updates so mounted rows read live `@Trace` task fields directly; do not reintroduce shadow `visible*` progress params or fresh-snapshot-only updates.
Verification: download workbench contract, gallery download queue contract, gallery download executor contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 evidence that a visible downloading row's status text count and progress bar advance together without switching tabs.

## Active: ordinary download quality identity

Status: active
Reference implementation: `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` download original/resampled prompt and `feature/download/src/main/ets/pages/DownloadQueuePage.ets` existing Gallery task card metadata/status layout.
Surface type: Downloads tab Gallery task card metadata plus ordinary gallery download queue identity; no card layout redesign.
Primary information: a Gallery download row must tell the user whether it is `重采样图片` or `原图`, and the two qualities must not overwrite each other's task, seeds, files, or actions.
Primary action: choose resampled or original from the detail download prompt, then resume/pause/delete/read that exact quality from the Downloads tab.
Reuse or deviation: reuse the existing task card metadata line and existing queue executors; deviate only by adding `preferOriginal` to task matching, RDB primary keys, seed storage, file directory names, and task action calls.
Verification: download workbench contract, download queue RDB contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Downloads smoke when both ordinary qualities are queued for one gallery.

## Active: modal scaffold nested vertical scroll

Status: active
Reference implementation: `shared/src/main/ets/components/AppModalScaffold.ets` shared sheet chrome and its internal scrollable `List`, used by `feature/search/src/main/ets/components/SearchFilterSheet.ets`.
Surface type: Shared half-modal content scroll gesture handoff; no visual redesign.
Primary information: modal content remains scrollable while top-edge downward drags can reach the sheet container.
Primary action: drag inside modal content scrolls the list first, then hands edge overflow to the parent sheet for dismissal/resize.
Reuse or deviation: reuse ArkUI `nestedScroll` on the existing modal `List`; add only `SELF_FIRST` to both vertical directions.
Verification: V1 decorator inventory, grounding ledger review, diff check, and signed HarmonyOS build.

## Active: waterfall tag strip nested horizontal scroll

Status: active
Reference implementation: `shared/src/main/ets/components/GalleryWaterfallCard.ets` existing two-row horizontal tag strip inside `RetainedSubtabHost.ets`'s horizontal Swiper.
Surface type: Waterfall gallery card tag strip gesture handoff; no visual redesign.
Primary information: waterfall cards keep the compact tag strip visible without blocking page-level horizontal subtab swipes once the strip reaches an edge.
Primary action: horizontal drag on tags scrolls tags first, then hands edge overflow to the outer Swiper.
Reuse or deviation: reuse ArkUI `nestedScroll` on the existing tag `Scroll`; change only `SELF_ONLY` to `SELF_FIRST`.
Verification: V1 decorator inventory, grounding ledger review, and signed HarmonyOS build.

## Active: retained subtab key-list realignment

Status: active
Reference implementation: `shared/src/main/ets/components/RetainedSubtabHost.ets` retained Swiper host, `feature/home/src/main/ets/pages/HomePage.ets` custom-profile uuid keys, and `entry/src/main/ets/components/HomeSourceBar.ets` selected-index-from-key bar model.
Surface type: Home/custom SubTab retained Swiper state; no visual redesign.
Primary information: the selected subtab is identified by stable profile uuid, not by whatever index the Swiper previously held.
Primary action: when custom profile keys are reordered, hidden, restored, or sync-rewritten, the host realigns the Swiper and active page to the selected key.
Reuse or deviation: reuse `RetainedSubtabHost` as the single framework fix; selected-key changes still animate, key-list reshapes realign without animation to avoid index drift.
Verification: retained tab contract, V1 decorator inventory, grounding ledger review, and signed HarmonyOS build.

## Active: gallery list reset diagnostics

Status: active
Reference implementation: `shared/src/main/ets/diagnostics/DiagnosticLogger.ets` existing redacted persistent hilog sink, `feature/home/src/main/ets/components/GallerySourcePage.ets` retained source lifecycle, and `feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets` first-page / load-more state transitions.
Surface type: no visible UI change; retained gallery list diagnostics only.
Primary information: when a retained list unexpectedly returns to one page, logs must show whether it came from a new VM, an explicit reload/refresh, or a local-block version change.
Primary action: user reproduces the list reset; developer filters `[home-list-anchor]` / `local_block_*` logs and identifies the state transition.
Reuse or deviation: reuse `DiagnosticLogger` instead of a temporary console/logging path; no layout, button, sheet, color, or navigation changes.
Verification: local block contract, V1 decorator inventory, grounding ledger review, signed HarmonyOS build, and filtered hilog capture on `192.168.50.103:12345`.

## Active: download queue batch title actions

Status: active
Reference implementation: `entry/src/main/ets/pages/Index.ets` existing tab title-bar menu items, `entry/src/main/ets/components/DownloadTypeBar.ets` retained Gallery/Archiver segmented control, and `feature/download/src/main/ets/pages/DownloadQueuePage.ets` per-task resume/pause actions.
Surface type: Downloads tab title-bar trailing menu only.
Primary information: the task list remains the main surface; the title bar exposes queue-level controls for the currently selected Gallery or Archiver queue.
Primary action: tap Continue all to retry/resume eligible tasks in the selected queue, or Pause all to pause currently downloading tasks; destructive bulk delete is intentionally not included because current remove semantics delete local files.
Reuse or deviation: reuse HDS title-bar menu records and existing per-task `DownloadQueueSettings` executors; do not add a summary card, floating toolbar, background agent, or new queue scheduler in this slice.
Verification: download workbench contract, download queue RDB contract, grounding ledger review, i18n duplicate check, V1 decorator inventory, signed HarmonyOS build, and X7 Downloads tab menu smoke evidence.

## Active: download incremental refresh action

Status: active
Reference implementation: `../eros_fe/lib/pages/item/download_gallery_item.dart` completed row tap-to-read behavior, `feature/download/src/main/ets/pages/DownloadQueuePage.ets` bottom task action row, `shared/src/main/ets/settings/DownloadQueueSettings.ets` seed preparation / merge / executor path, and `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` detail-page download seed preparation.
Surface type: Downloads tab gallery task card bottom action row for completed local downloads.
Primary information: completed gallery tasks keep the complete status line visible, use the content area as the local read affordance, and expose lightweight refresh/remove actions in the bottom row.
Primary action: tap the small refresh icon on a completed gallery task to fetch the current detail preview pages, merge seed metadata by page, and let the existing downloader handle newly pending images.
Reuse or deviation: reuse the bottom task action row and `prepareGallerySeeds -> mergePreparedSeeds -> downloadGalleryImages` flow instead of adding a second update engine; deviate only by allowing completed tasks to re-enter preparation/download when remote seed refresh discovers new pages.
Verification: gallery download executor contract, gallery download queue contract, download workbench contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Downloads tab layout evidence.

## Active: detail newer-version incremental download

Status: active
Reference implementation: `/private/tmp/EhViewer/app/src/main/java/com/hippo/ehviewer/ui/scene/GalleryDetailScene.kt` `showGalleryUpgradeDialog()` and `/private/tmp/EhViewer/app/src/main/java/com/hippo/ehviewer/spider/SpiderQueen.kt` `prepareUpgrade()`; NextE reuse point is `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` detail title menu plus `shared/src/main/ets/settings/DownloadQueueSettings.ets` parent-seed inheritance.
Surface type: Gallery detail title-bar menu action opening a standard AppModalScaffold selection sheet.
Primary information: when the current gallery already has a completed local download and EH detail exposes newer versions, the sheet lists those newer versions by title plus posted time/gid so the user chooses the target update.
Primary action: tap one newer-version row to fetch that version detail, enqueue a child gallery download, set the current gid as `upgradeFromGid`, and let the existing imgkey-based inheritance copy already-downloaded parent files before downloading missing pages.
Reuse or deviation: reuse HDS title-bar menu records, `AppModalScaffold`, `GroupedListSection`, and `ConciseListRow`; do not change the primary Read FAB, do not add a second update engine, and do not auto-submit remote archive/gallery writes.
Verification: gallery download executor contract, gallery download queue contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 detail-menu smoke evidence.

## Active: completed download row reader entry

Status: active
Reference implementation: `../eros_fe/lib/pages/item/download_gallery_item.dart` tap completed row to enter local reader, `ArchiveImageService.imagesForTask()` archive-to-Reader path, and the completed Gallery task `openDownloadedTask()` local file Reader path.
Surface type: Downloads tab gallery and archiver task cards.
Primary information: completed task rows show title, cover/icon, metadata, and a complete status line; they do not show a full progress bar or a duplicated read button.
Primary action: tap the completed task content area to open the local Reader path; tap the cover/icon to open the original gallery detail when gid/token are available. Incomplete/error rows stay inert except for retry/pause/remove actions.
Reuse or deviation: reuse the existing read methods and keep cover/source navigation separate from local Reader navigation; remove/refresh/retry live in the bottom action row so there is no right-side button stack.
Verification: gallery download queue contract, download workbench contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Downloads tab smoke evidence; source/open logs must cover both Gallery and Archiver rows, and Archiver source navigation must keep the stored cover seed.

## Active: queued download row resume affordance

Status: active
Reference implementation: `feature/download/src/main/ets/pages/DownloadQueuePage.ets` existing per-task resume button, `shared/src/main/ets/settings/DownloadQueueSettings.ets` restored `QUEUED/READY/PARTIAL` gallery states, and the Archiver task row which already treats `QUEUED` as resumable.
Surface type: Downloads tab Gallery task bottom action row.
Primary information: a queued Gallery task is a resumable task state, not a terminal or read-ready row.
Primary action: tap the retry/continue capsule on a queued Gallery task to run the same `downloadGalleryImages()` executor used by READY, PAUSED, PARTIAL, and ERROR tasks.
Reuse or deviation: reuse the shared executor; do not add a new queue state, scheduler, or separate start button.
Verification: download workbench contract, download queue RDB contract, V1 decorator inventory, signed HarmonyOS build.

## Active: download task error detail

Status: active
Reference implementation: `feature/download/src/main/ets/pages/DownloadQueuePage.ets` existing task progress subtitle, `shared/src/main/ets/model/DownloadGalleryTask.ets` `prepareError`, and `DownloadArchiverTask.error`.
Surface type: Downloads tab Gallery and Archiver task card status subtitle only.
Primary information: failed task rows should show the stored failure reason next to the error status so retry/remove is understandable without opening another surface.
Primary action: the existing low-weight retry button remains the action; the subtitle simply explains what failed.
Reuse or deviation: reuse the existing one-line progress/status subtitle and ellipsis behavior; do not add a second details row, toast-only path, modal, or new error model.
Verification: gallery download prepare contract, download workbench contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Downloads tab smoke evidence.

## Active: download task pause action

Status: active
Reference implementation: `feature/download/src/main/ets/pages/DownloadQueuePage.ets` bottom retry/remove task actions, and `shared/src/main/ets/settings/DownloadQueueSettings.ets` joined in-flight worker maps.
Surface type: Downloads tab Gallery and Archiver task bottom action row while a task is actively downloading.
Primary information: a running task remains visible with its current progress; pause is a lightweight action beside remove, not a separate management page.
Primary action: tap the small pause icon to stop the task after the current in-flight batch/stream settles, keep already downloaded files, and let the existing retry/resume icon continue later.
Reuse or deviation: reuse the current task card status model and cancellation markers; do not introduce a new background agent, per-request abort API, or right-side stacked controls in this slice.
Verification: download workbench contract, download queue RDB contract, grounding ledger review, i18n duplicate check, V1 decorator inventory, signed HarmonyOS build, and X7 Downloads tab smoke evidence.

## Active: download speed-limit setting

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/DownloadSettingsPage.ets` existing counter rows for concurrency / interval / retry, and `shared/src/main/ets/settings/DownloadQueueSettings.ets` gallery image batch executor.
Surface type: Download settings child page and Gallery queue image executor.
Primary information: users can see whether the gallery queue has an average speed cap, alongside concurrency, interval, retry, and original-image policy.
Primary action: tap +/- on the speed-limit row to move between off and bounded KB/s steps; the gallery queue delays after successful batches to respect the configured average rate.
Reuse or deviation: reuse the existing `ConciseListRow` counter pattern and the gallery queue batch loop; do not throttle Reader image cache or rewrite HTTP streaming in this slice.
Verification: download settings contract, grounding ledger review, i18n duplicate check, V1 decorator inventory, signed HarmonyOS build, and X7 Download settings smoke evidence.

## Active: storage sync settings

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/CacheSettingsPage.ets` storage category entry, `feature/settings/src/main/ets/pages/DiagnosticsLogPage.ets` settings child-page structure, `shared/src/main/ets/components/ConciseListRow.ets` switch/input rows, `../V2Next/feature/settings/src/main/ets/pages/BackupSettingsPage.ets` backup/export grouping, and `../V2Next/shared/src/main/ets/storage/LocalDataCloudSync.ets` Huawei RDB cloud-sync wiring.
Surface type: Storage settings child page with sync entry first, export/import second, cache usage/actions last, plus a provider overview and a WebDAV child page. Local/private development builds show Huawei Cloud by default; public release builds without AGC/HGC cloud setup can disable it through the signed-build environment flag.
Primary information: provider enablement, WebDAV last sync state/configuration status, Huawei Cloud last state when available, and the enabled durable dataset groups shared by both providers.
Primary action: tap the top sync card from Storage, then tap the WebDAV provider row to open its child page; WebDAV configuration and WebDAV "sync now" live there. Huawei Cloud enablement and "sync now" stay in the Huawei Cloud provider card. Dataset switches stay on the overview because they are provider-neutral.
Reuse or deviation: reuse NextE `SecondaryListScaffold`, `GroupedListSection`, `ConciseListRow`, V2 settings holder restore/persist pattern, and storage-page navigation; keep Storage actions separated as sync, export/import, then cache instead of mixing sync into backup/restore. Keep provider-specific forms/actions in their own provider card or child page instead of mixing WebDAV credentials with the overview. Deviate from the old single backup file by presenting dataset switches because WebDAV now writes manifest plus per-dataset shards and Huawei Cloud marks the same selected RDB tables.
Verification: sync design contract, Huawei cloud sync contract, local WebDAV sharded server contract, grounding ledger review, V1 decorator inventory, and signed HarmonyOS build.

## Active: safe mode shell

Status: active
Reference implementation: `entry/src/main/ets/pages/Index.ets` existing HDS bottom-tab shell, `feature/home/src/main/ets/pages/HomePage.ets` custom-profile driven retained source tabs, `entry/src/main/ets/components/HomeSourceBar.ets` pinned source bar, and `feature/settings/src/main/ets/pages/SettingsPage.ets` shared settings-list primitives.
Surface type: build-gated restricted app shell plus About-version unlock gesture.
Primary information: restricted builds should first show Gallery fixed to the NoH profile, Download, and the reduced Settings surface; normal builds remain unchanged.
Primary action: in a safe-mode build, tapping About version five times persists the unlock and restores the normal tabs, settings entries, login/account routes, custom tab management, search, favorites, and toplist.
Reuse or deviation: reuse the existing HDS tab shell, `CustomProfile` gallery query path, `SecondaryListScaffold` / `ConciseListRow`, and AppStorageV2 settings restore; deviate only by centralizing visibility and route blocking in `SafeModeGate` instead of scattering raw build-flag checks.
Verification: safe-mode build flag/static contract, grounding ledger review, i18n duplicate check, V1 decorator inventory, and signed normal plus `NEXTE_SAFE_MODE=1` builds.

## Active: normal settings root order

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/SettingsPage.ets` pre-safe-mode root grouping and the existing `ConciseListRow` / `GroupedListSection` settings primitives.
Surface type: Settings root information architecture in normal builds.
Primary information: normal Settings should keep the user-facing category order EH, Interface, Reader, Search, Translation, History, Storage, Diagnostics, About; safe mode only hides restricted entries and must not reorder the remaining normal surface.
Primary action: tapping a category row navigates to its existing child page; About remains reachable for the safe-mode unlock gesture.
Reuse or deviation: reuse the existing root settings rows and safe-mode visibility guard; deviate only by placing Translation and History back after Search instead of above Interface.
Verification: safe-mode contract normal-order assertion, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Settings screenshot/layout order evidence.

## Active: settings account summary entry

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/AccountPage.ets` `AccountRow` active-account card and `feature/settings/src/main/ets/pages/SettingsPage.ets` existing account entry route.
Surface type: Settings root account entry only.
Primary information: when logged in, the top Settings account entry should show the same account identity hierarchy as the account switcher: avatar, nickname when available, and member ID as secondary text.
Primary action: tapping the account card opens `AccountPage`; signed-out users still tap the existing login row.
Reuse or deviation: reuse the account switcher card structure and theme tokens; deviate only by replacing the right-side radio selection control with a chevron because this Settings row is navigation, not selection.
Verification: grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Settings screenshot showing the logged-in account card with avatar/name/ID/chevron.

## Active: WebView login profile capture

Status: active
Reference implementation: `entry/src/main/ets/pages/EhLoginWebPage.ets` WebView cookie capture, `entry/src/main/ets/pages/GalleryWebPage.ets` profile DOM capture, and `shared/src/main/ets/services/UserProfileService.ets` profile persistence.
Surface type: WebView login completion flow plus the existing Settings account entry.
Primary information: after a successful WebView login, the account identity should populate nickname/avatar automatically when the forum profile page is reachable; member ID remains the fallback.
Primary action: user completes the existing WebView login form; the app loads the active profile once, saves profile metadata if available, and returns as before.
Reuse or deviation: reuse the existing WebView session and `UserProfileService.applyProfileDomPayload()` path instead of adding a second parser or new setting; deviate only by delaying the login success pop until the best-effort profile capture attempt finishes or fails.
Verification: grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and logged-in Settings/Account screenshots showing clipped avatar and stable account-entry hierarchy.

## Active: WebView login form styling

Status: active
Reference implementation: `entry/src/main/ets/pages/EhLoginWebPage.ets` existing WebView login cookie capture and `entry/src/main/ets/pages/GalleryWebPage.ets` direct ArkWeb controller ownership.
Surface type: EH forums WebView login page only; gallery WebView and normal native password/cookie login pages are out of scope.
Primary information: the forums login form, username/password inputs, real captcha/Turnstile area, and submit button must remain visible and usable.
Primary action: user opens Web login, completes any captcha, enters credentials, submits, and the existing cookie capture finishes login.
Reuse or deviation: reuse the login page WebView lifecycle and cookie capture; deviate from the generic `EhWebView` wrapper because the login page must call `loadUrl()` and `runJavaScript()` through the exact same controller instance used by the visible Web component. Keep the captcha node in the forum form, but hide forum title/options chrome and add the native-style password visibility affordance in the password row.
Verification: web-login cookie capture contract, cookie import contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 Web login screenshot/log proving the visible forums page is not styled through an `about:blank` controller and still shows the password visibility button plus captcha.

## Active: custom-tab tag suggestion labels

Status: active
Reference implementation: `feature/search/src/main/ets/pages/GallerySearchPage.ets` localized tag suggestion display and `shared/src/main/ets/components/TagQueryComposer.ets` custom-tab saved-search tag composer.
Surface type: custom home sub-tab editor tag keyword suggestion list.
Primary information: local translation matches should show the localized namespace label plus localized tag name, while the raw EH query remains visible as supporting text.
Primary action: tapping a suggestion appends the raw namespace/key exact EH tag to the custom tab search query.
Reuse or deviation: reuse the Search page's namespace-label mapping and existing `TagQueryComposer` suggestion flow; deviate only from the previous raw `expandNamespace()` title so translated candidates no longer display an English namespace prefix.
Verification: search tagsuggest contract, grounding ledger review, i18n duplicate check, V1 decorator inventory, and signed HarmonyOS build.

## Active: reader gesture probe

Status: active
Reference implementation: HarmonyOS official `PinchGesture` "实现图片跟手缩放" example, HarmonyOS official `TapGesture` double-tap coordinate example, NextE hidden QA route pattern in `entry/src/main/ets/pages/CoverFallbackProbePage.ets`, and current Reader gesture code in `feature/reader/src/main/ets/pages/ReaderPage.ets`.
Surface type: hidden internal QA page opened by `nexte://qa/reader-gesture`; no Reader product behavior changes in this step.
Primary information: a single image surface with live scale, offset, pinch anchor ratio, and last event readout so double-tap and pinch state can be inspected.
Primary action: double-tap the image to verify zoom animation remains visible; manually pinch the zoomed image to verify the official anchor-ratio model before migrating anything into Reader.
Reuse or deviation: reuse the existing `HdsNavDestination`, immersive title-bar, `ThemeConstants`, `InternalQaRoutes`, and `DiagnosticLogger`; deviate from Reader by excluding Swiper/cache/chrome so the gesture math is isolated.
Verification: grounding ledger review, V1 decorator inventory, signed HarmonyOS build, emulator hidden-route launch, double-tap burst screenshots/logs; pinch remains `needs manual QA` if automation still cannot synthesize a two-finger gesture.

## Active: remote favorite folder cache

Status: active
Reference implementation: existing `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` remote favorite sheet cache path, `shared/src/main/ets/settings/FavcatListSettings.ets` persisted favcat snapshot, and eros_fe profile-backed favorite category metadata.
Surface type: gallery detail favorite selection half-modal data source only; no visual layout change.
Primary information: favorite-folder names should appear from the last real cached snapshot immediately, then update from the authoritative gallery favorite popup response.
Primary action: open the existing favorite selection sheet; choose/remove a remote favorite folder after the background popup refresh reconciles current state.
Reuse or deviation: reuse the existing `RemoteFavoriteSlotCacheState` and `FavcatListSettings` snapshot instead of creating a second cache; deviate by letting popup refreshes persist names while preserving previous nonzero counts when the popup supplies names without counts.
Verification: favcat snapshot contract, gallery remote favorite sheet contract, favorites selector contract, grounding ledger review, V1 decorator inventory, and signed HarmonyOS build.

## Active: diagnostics log export

Status: active
Reference implementation: `../V2Next/shared/src/main/ets/diagnostics/*`, `../V2Next/shared/src/main/ets/settings/DiagnosticsSettings.ets`, `../V2Next/shared/src/main/ets/settings/DiagnosticsFileExport.ets`, and `../V2Next/feature/settings/src/main/ets/pages/DiagnosticsLogPage.ets`.
Surface type: Settings diagnostics child page plus app lifecycle diagnostics sink.
Primary information: redacted local diagnostics logs, retained startup log files, current launch record count, and the active minimum log level.
Primary action: keep diagnostics enabled by default, export/share a redacted log file, share retained log files, clear this launch's in-memory records, or write a test marker for user-feedback correlation.
Reuse or deviation: reuse NextE `SecondaryListScaffold` / `GroupedListSection` / `ConciseListRow` settings chrome and existing `AdvancedSettings` route; port NExt2V's redactor/store/file-sink/export structure while preserving NextE's existing `DiagnosticLogger.info(category,event,message)` call sites instead of rewriting the app around structured context objects in one lane.
Verification: diagnostics logger contract, i18n duplicate check, secret safety contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 emulator settings path with a retained/shareable log file plus Hilog evidence from `manual_marker` and reader `image_decoded` dimensions.

## Active: reader original image display

Status: active
Reference implementation: `../eros_fe/lib/pages/image_view/view/view_image.dart` long-press current image path into `showImageSheet`, `../eros_fe/lib/pages/image_view/view/view_widget.dart` `showSaveActionSheet` / `showShareActionSheet`, and `../eros_fe/lib/network/request.dart` / `api.dart` showpage parsing of `originImageUrl`.
Surface type: Reader bottom toolbar current-page image source action.
Primary information: the current reader page remains the primary surface; original image display is an explicit per-page source switch backed by the parsed `/fullimg` URL.
Primary action: tap the Reader toolbar original badge to resolve and display the current page's original image; save/share use whatever source is currently displayed.
Reuse or deviation: reuse NextE `ImageResolveService`, `CachedImageFileService`, existing Reader chrome buttons, and the existing single/double/vertical image renderers; deviate from eros_fe's save/share action sheet by adding an in-reader view toggle because this lane is about viewing the original, not only exporting it.
Verification: reader original-image contract, image-page parser contract, current-image share/save contracts, i18n duplicate check, V1 decorator inventory, grounding ledger review, signed HarmonyOS build, and X7 emulator user path with screenshot plus hilog evidence containing `original_mode_on` / `display_original` and `fullimg true`.

## Active: local block rules

Status: active
Reference implementation: `../eros_fe/lib/common/controller/block_controller.dart`, `../eros_fe/lib/pages/setting/block/blockers_page.dart`, `feature/settings/src/main/ets/pages/SearchSettingsPage.ets`, and `feature/gallery/src/main/ets/components/GalleryCommentsCard.ets`.
Surface type: EH settings entry, local block rules settings page, retained gallery-list/search/favorites filtering, gallery-detail comment preview, and full comments page.
Primary information: local block rules hide galleries by title/uploader and comments by author/text or low score; raw comment data remains available for reply-reference resolution.
Primary action: add a local block rule from the single title-bar `+` entry, edit/enable/disable/remove existing rules in their buckets, choose whether blocked comments are hidden or collapsed, or enable score-threshold filtering for comments.
Reuse or deviation: reuse eros_fe's four rule buckets plus low-score threshold, NextE `SecondaryListScaffold` / `GroupedListSection` / `ConciseListRow` settings chrome, existing per-comment cards, and the retained-list VM `setData()` refresh path used by tag translation/favcat metadata updates; deviate by storing rules in AppStorageV2-backed preferences instead of FE profile JSON and by showing blocked comments as a compact collapsed card when the user chooses that display mode.
Verification: local block contract covering title/uploader/comment-author/comment-text/score/regex/disabled rules, grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and emulator user paths for the single add entry retaining the last selected type, adding title/uploader rules, re-filtering already-loaded Home rows, persistence after restart, comment/commentator filtering, hide-vs-collapse display mode, score-threshold filtering after vote-state changes, edit/delete cleanup, and no real-device interaction.

## Active: Toplist hidden My Tags setting

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/EhSettingsPage.ets` existing HDS settings rows, `shared/src/main/ets/components/ConciseListRow.ets`, and `shared/src/main/ets/network/EhApiService.ets` existing `UserTagStore.anyHidden()` local list filtering.
Surface type: EH settings page switch plus Toplist gallery-list fetch path.
Primary information: Toplist can hide galleries carrying tags the user already marked hidden in My Tags; the setting defaults on so rankings do not ignore the user's local blocked-tag preference.
Primary action: toggle the EH Settings switch to apply or stop applying My Tags hidden-tag filtering to Toplist; Advanced Search `disableTagFilter/f_sft` remains a separate search-only server parameter.
Reuse or deviation: reuse the existing `GroupedListSection` / `ConciseListRow` switch row and existing `filterHidden()` logic; deviate only by adding a dedicated Toplist-local state field instead of reusing Search Filter state.
Verification: Toplist hidden-filter contract, gallery paging contract, grounding ledger review, V1 decorator inventory, i18n duplicate check, and signed HarmonyOS build.

## Active: async tag translation visible refresh

Status: active
Reference implementation: `shared/src/main/ets/utils/BasicDataSource.ets` `setData()` reload contract, `shared/src/main/ets/components/GalleryCard.ets` / `GalleryWaterfallCard.ets` tag chip render path, and `feature/gallery/src/main/ets/components/GalleryTagsCard.ets` detail tag member render path.
Surface type: gallery list/search/favorites cards and gallery detail tag chips that receive translated tag text after the first raw render.
Primary information: raw EH tag text may appear briefly, but the same visible card/chip must update to the localized `translat` value when async tag translation finishes.
Primary action: no new user action; existing card tap/tag tap/long press behavior remains unchanged while render identity changes only to refresh translated text.
Reuse or deviation: reuse the existing `BasicDataSource.setData()` reload path and existing card/chip components; deviate from pure `gid` / namespace-only `ForEach` keys because async translation changes display text without changing gallery identity.
Verification: tag translation contract, page cache contract, grounding ledger review, V1 decorator inventory, emulator screenshot evidence for list/detail translated tags, and signed HarmonyOS build.

## Active: pull-refresh edge-drag ownership

Status: active
Reference implementation: `../V2Next/shared/src/main/ets/components/PullRefreshListScaffold.ets` and `../V2Next/shared/src/main/ets/components/SecondaryListScaffold.ets` both use `EdgeEffect.None`; HarmonyOS offline docs say child scroll nodes should disable edge effect when custom nested/edge scrolling owns the movement.
Surface type: shared List/Grid/WaterFlow scaffolds that sit under custom `PullRefresh`, plus the plain secondary list scaffold default.
Primary information: list content should move once during an edge pull, with the custom refresh indicator and content offset remaining the only visible pull feedback.
Primary action: drag down at the top to refresh or drag up at the bottom for manual load-more where supported; normal list scrolling remains unchanged.
Reuse or deviation: reuse V2Next's no-native-edge-effect scaffold policy for pull-refresh surfaces; keep `alwaysEnabled` only as a local opt-in for non-refresh sparse-content lists such as Settings pages and Search suggestions.
Verification: scroll edge-effect ownership contract, search tag-suggestion contract, V1 decorator inventory, grounding ledger review, and signed HarmonyOS build.

## Active: gallery waterfall tag strip and root gallery title

Status: active
Reference implementation: `shared/src/main/ets/components/GalleryWaterfallCard.ets` existing tag chips/colors/search action, `feature/gallery/src/main/ets/components/GalleryTagsCard.ets` odd/even image distribution, and `entry/src/main/ets/pages/Index.ets` localized HDS tab title resources.
Surface type: Waterfall-mode gallery card tag strip plus the root Gallery tab title bar.
Primary information: tag chips remain visible in a fixed two-line area and start from the left; the root gallery tab title reads the localized gallery label instead of the site name.
Primary action: tapping a tag still publishes the raw EH exact tag search; horizontal drag scrolls the two-line tag strip without handing the gesture to the outer tab Swiper.
Reuse or deviation: reuse the existing `GalleryWaterfallCard` chip color/user-tag lookup and native horizontal scroll surface; deviate from the previous two-chip-column List because it forced top and bottom tags to share column widths.
Verification: gallery waterflow contract, gallery-list parser contract, favorites load-more contract, home title actions contract, grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: comment translation

Status: active
Reference implementation: `../eros_n/lib/pages/gallery/comments_page.dart`, `../eros_n/lib/pages/gallery/comment_translation_provider.dart`, `../eros_n/lib/utils/translation/translate_helper.dart`, and `../eros_n/lib/pages/setting/translation_setting_page.dart`.
Surface type: full gallery comments page comment rows plus a Settings translation page.
Primary information: the comment remains the primary object; translation is an optional per-comment alternate text backed by a local cache, with the original text still available.
Primary action: tapping the translate footer icon translates or toggles a comment; settings let the user enable translation, auto-translate full comments, choose Google-only fallback behavior, and enter an OpenAI-compatible API URL/key/model.
Reuse or deviation: reuse NextE `GalleryCommentsCard` footer actions, `SecondaryListScaffold`, `GroupedListSection`, `ConciseListRow`, V2 settings holders, and `LocalDataStore`; deviate from eros_n by skipping model-list fetching and complex bilingual style previews in the first closure.
Verification: comment translation contract, grounding ledger review, V1 decorator inventory, i18n duplicate check, and signed HarmonyOS build.

## Active: gallery detail read button HDS style

Status: active
Reference implementation: `../V2Next/feature/detail/src/main/ets/components/HdsMiniBarButton.ets` and `../V2Next/feature/detail/src/main/ets/pages/TopicDetailPage.ets` reply/resume FAB hosts.
Surface type: gallery detail page-level floating Read / Resume action plus its Layout settings selector.
Primary information: the existing Read / Resume label remains the button content; the optional new style changes material only, not the reader entry behavior.
Primary action: tapping the floating button opens Reader at the current resume index; secondary action is choosing Filled or HDS material in `LayoutSettingsPage`.
Reuse or deviation: reuse V2Next HDS `HdsTabs` floating material parameters (`barWidth`, `barHeight`, `activityPadding`, `barBottomMargin`, `systemMaterialEffect`) and NextE's existing translate-based smart-edge animation; deviate only by making the HDS bar a capsule instead of V2Next's circle.
Verification: read-button-style contract, existing gallery detail FAB/header contracts, grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: gallery detail bottom preview entry position

Status: active
Reference implementation: `feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets` entry split and `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets` existing image-page scroll helpers.
Surface type: gallery detail preview section entry into the all-thumbnails grid.
Primary information: the top/header entry opens all thumbnails from the beginning; the bottom grid entry opens near the last thumbnail already visible on the detail page.
Primary action: tapping a thumbnail in all thumbnails still opens Reader at that image page.
Reuse or deviation: reuse `AllThumbnailsParams` and the existing `visibleIndexForImagePage` / `loadImagePage` path; only add an optional initial image page for the bottom grid entry.
Verification: all-thumbnails page jump contract, thumbnail mode contract, grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: favorites retained favcat preference

Status: active
Reference implementation: `entry/src/main/ets/components/FavcatBar.ets`, `feature/user/src/main/ets/pages/FavoritesPage.ets`, `feature/user/src/main/ets/pages/FavoriteSelectorPage.ets`, and `shared/src/main/ets/components/RetainedSubtabHost.ets`.
Surface type: Favorites favcat sub-tabs plus the full-screen favorite-category selector.
Primary information: the selected favcat is a stable key where `a` means all favorites, `0..9` are remote EH favorite slots, and `l` is the local-only slot.
Primary action: tapping either the pinned sub-tab chip or the selector row switches the retained Favorites page and persists the same stable key for the next app launch.
Reuse or deviation: reuse the existing `SubtabSelectionSettings.setFavoritesFavcat` preference writer for every selection path; deviate from the old selector-only direct V2 mutation because it updated memory without writing `subtab.favoritesFavcat`.
Verification: retained subtab preference contract, favorites selector contract, V1 decorator inventory, grounding ledger review, and signed HarmonyOS build.

## Active: gallery detail comment cards

Status: active
Reference implementation: `../V2Next/shared/src/main/ets/components/ReplyCard.ets`, `../V2Next/feature/detail/src/main/ets/components/HotRepliesPanel.ets`, and `feature/gallery/src/main/ets/components/GalleryCommentsCard.ets`.
Surface type: gallery detail comments preview and full comments page comment list.
Primary information: each comment is the primary object and should read as its own white card; the detail preview still exposes only the first two comments as one close-knit group.
Primary action: tapping a preview comment or the comments header opens the full comments page; full comments keep author, vote, reply, and edit actions, with reply and own-comment edit sharing the same bottom composer surface.
Reuse or deviation: reuse Next2V's white top-level reply-card surface, `SPACE_SM - 2` reply spacing on both preview and full comments surfaces, and V2Next's shared large-card radii (`RADIUS_MD = 22`, `RADIUS_CARD = 24`); keep narrow grid tiles on a compact `GALLERY_GRID_CARD_RADIUS = 16`, keep the detail header cover on its dedicated inset radius, keep the Waterfall category corner badge attached to the cover's true top-right corner like Grid/eros_fe instead of manually shifting it inward, remove the old outer grouped card because it produced card-inside-card chrome, invert quote colors so quoted replies sit on a secondary gray block with `COMMENT_QUOTE_RADIUS = 8` inside the white comment card, keep score badges on the dark-aware secondary surface instead of separator chrome, emphasize only resolved `@user` reply mentions with the same link/accent color while leaving unresolved text plain, and retire the old edit half-modal by reusing the reply composer context preview for edits.
Verification: gallery comment card layout contract, V2Next card radius contract, full-comments entry contract, reply-reference contract including resolved mention emphasis, badge/vote/compose contracts, V1 decorator inventory, grounding ledger review, and signed HarmonyOS build.

## Active: retained subtab settled selection timing

Status: active
Reference implementation: `shared/src/main/ets/components/RetainedSubtabHost.ets`, `shared/src/main/ets/components/SubTabBar.ets`, and the V2Next retained-tab visual-index pattern used by Home/Toplist/Favorites.
Surface type: retained Home source, Toplist period, and Favorites favcat Swiper-backed SubTab surfaces.
Primary information: during a horizontal swipe, the SubTab indicator should track gesture progress without prematurely snapping to the destination tab or rebuilding the selected-key surface.
Primary action: swiping or tapping a subtab changes the retained page; selection state is committed only after the Swiper settles.
Reuse or deviation: reuse Next2V's split between high-frequency visual state and discrete selection state: `visualIndex` drives only the indicator/highlight, while SubTabBar recenters from a discrete `selectedIndex` using native `ListScroller.scrollToIndex(..., ScrollAlign.CENTER)` instead of hand-computed `xOffset`; deviate from the old `onChange` path by not publishing `selectedKey`, `activeKey`, or integer `visualIndex` from `onChange` because ArkUI can fire it before the transition visually finishes.
Verification: retained-tab framework contract, retained subtab preference contract, grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: gallery list adaptive cover slot

Status: active
Reference implementation: `../eros_fe/lib/pages/item/gallery_item.dart` `_CoverImage`, `shared/src/main/ets/components/GalleryCard.ets`, and `shared/src/main/ets/components/EhThumbnail.ets`.
Surface type: LIST-mode gallery card cover in non-fixed row-height mode.
Primary information: the cover image remains the left-side visual anchor; the fit decision compares parsed image dimensions against the actual cover container ratio, not a guessed row height.
Primary action: tapping the row still opens gallery detail; this lane only corrects cover fill/background presentation for adaptive list rows.
Reuse or deviation: reuse the existing measured list width and `EhThumbnail` gradient/blur letterbox background; deviate from the old precomputed `LIST_CARD_COVER_ASPECT` slot by measuring the stretched cover slot height after the right column lays out.
Verification: list responsive cover contract, list height mode contract, cover presentation contract, grounding ledger review, V1 decorator inventory, and signed HarmonyOS build.

## Active: gallery list tag chip radius token

Status: active
Reference implementation: `shared/src/main/ets/components/GalleryCard.ets`, `shared/src/main/ets/components/GalleryWaterfallCard.ets`, and `shared/src/main/ets/theme/ThemeConstants.ets`.
Surface type: ordinary gallery tag chips in LIST and WATERFALL browsing cards.
Primary information: tag chips remain compact tag labels; their corner radius stays tuned, and user-configured tag colors must match the editable MyTags color rather than EH's darker preview border/fill color.
Primary action: tapping a tag still publishes the existing exact-tag search.
Reuse or deviation: reuse the existing tag chip renderers and `UserTagStore` lookup; keep inline list colors as fallback, but when a MyTags entry exists prefer `EhUsertag.colorCode` before `fillColor`, matching the edit sheet and MyTags list badge.
Verification: tag chip contract, MyTags setusertag contract, grounding ledger review, V1 decorator inventory, and signed HarmonyOS build.

## Active: gallery cover wall mode

Status: active
Reference implementation: `../eros_fe/lib/pages/tab/view/list/waterfall_flow.dart`, `../eros_fe/lib/pages/item/gallery_item_flow.dart`, and NextE `shared/src/main/ets/components/GalleryWaterfallCard.ets`.
Surface type: gallery browsing list mode for Home, Search, and Favorites.
Primary information: the cover image is the entire card, with only the existing category/translated corner badge exposed over the image.
Primary action: tapping a cover opens the same gallery detail route; refresh, load-more, footer retry, and scroll-title linkage remain the existing WaterFlow behavior.
Reuse or deviation: reuse `PullRefreshWaterFlowScaffold`, native `FlowItem`, the bounded source-ratio cover policy, and the shared `GalleryCategoryCornerBadge`; deviate from Waterfall by using `GALLERY_COVER_WALL_MIN_W = 120` and omitting title, rating, page/favorite overlay, meta, and tag chips.
Verification: gallery cover wall mode contract, gallery grid mode contract, gallery waterflow contract, settings layout entry contract, i18n duplicate check, grounding ledger review, V1 decorator inventory, and signed HarmonyOS build.

## Active: toplist jump menu icon

Status: active
Reference implementation: NextE `entry/src/main/ets/pages/Index.ets` `topOnlyMenu()` ranking title-bar menu.
Surface type: Toplist title-bar overflow menu action.
Primary information: the menu exposes page navigation actions; the icon should distinguish jump-to-page from jump-to-first-page without changing labels.
Primary action: tapping `toplist_jump_page` still opens the existing page-number dialog.
Reuse or deviation: reuse the existing HDS menu item shape and only replace the jump icon with `sys.symbol.chevron_right_circle`.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, `git diff --check`, and signed HarmonyOS build to confirm the system symbol exists.

## Active: gallery torrent sheet

Status: active
Reference implementation: `../eros_fe/lib/pages/gallery/view/torrent_dialog.dart` `showTorrentDialog()` / `TorrentItem`, and NextE `feature/gallery/src/main/ets/pages/GalleryTorrentsPage.ets`.
Surface type: gallery detail torrent list opened as a half-modal sheet, with the legacy pushed page kept as a fallback route.
Primary information: each torrent row should show seeds, peers, downloads, size, filename, posted time, and uploader without the metric row collapsing into one visual string.
Primary action: tapping the filename shares/opens the `.torrent` URL; tapping the right action shares the magnet link; closing the sheet returns to the same gallery detail scroll context.
Reuse or deviation: reuse NextE `AppModalScaffold`, `SecondaryListScaffold`, existing torrent parser/network/share helpers, and one shared torrent content component; deviate from the old pushed-only page because eros_fe presents torrent as a dialog instead of a navigation destination.
Verification: grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and sheet screenshot covering loading, one long filename row, and multiple torrent rows.

## Active: gallery detail action chips

Status: active
Reference implementation: NextE `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` existing `relationsRow()` action cluster, and `shared/src/main/ets/components/GalleryWaterfallCard.ets` horizontal chip-strip scrolling.
Surface type: gallery detail auxiliary action row below the info bar.
Primary information: the row exposes secondary actions, not gallery metadata; each action should read as a tappable control with an icon and label.
Primary action: similar search, torrents, rating, archiver, and gallery download keep their existing actions while becoming compact chip targets; parent-gallery navigation moves to the existing title-bar menu.
Reuse or deviation: reuse the existing detail section card, title-bar menu, native horizontal `Scroll`, and the detail page's smart-grip hand-edge state; deviate only from tiny text links by using local capsule `Button` chips with theme-colored icon/text, and place the chip row on a start-based rail so short rows animate left/right with `translate` instead of jumping through centered alignment.
Verification: grounding ledger review, detail header visual contract, V1 decorator inventory, signed HarmonyOS build, and detail screenshot on a narrow viewport with all available actions.

## Active: gallery download executor progress

Status: active
Reference implementation: `../eros_fe/lib/common/controller/download_controller.dart` `downloadGallery()` / `_startImageTask()`, `../eros_fe/lib/common/controller/download/image_download_processor.dart` `downloadImageFlow()` / `fetchImageInfo()`, and NextE `feature/download/src/main/ets/pages/DownloadQueuePage.ets`.
Surface type: Downloads tab Gallery queue task card plus the Settings root entry to the dedicated Download settings page.
Primary information: each queued gallery shows seed preparation, real image-file download progress, error state, and complete state from recorded sandbox file metadata; Archiver shows real local archive download tasks and complete local archive packages; Download settings expose the executor policies it currently consumes: image concurrency, request interval throttling, per-image retry count, failed-task auto retry, and original-image mode; archive-bot balance and check-in validation rows keep independent row-local loading feedback and diagnostic evidence.
Primary action: detail-page Download starts seed preparation and then the bounded gallery image executor; Archiver local submit adds and downloads a real archive task; failed or partial queue rows can resume through a low-weight icon action, completed gallery rows enter the normal Reader with local file images, completed archive rows unzip into cache and enter the same Reader, while Remove remains secondary; Settings > Download opens the existing dedicated policy page.
Reuse or deviation: reuse the existing HDS task card, `EhThumbnail`, progress bar, RDB-backed queue, persisted download settings page, Reader route, protected Archiver confirmation flow, platform `zlib.decompressFile`, and circle icon actions; deviate from FE's async zip reader by extracting a completed sandbox zip to cache first because Harmony's built-in zip API exposes whole-file decompression, not random entry reads.
Verification: gallery download executor contract, archive reader contract, download settings contract, gallery download preparation contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and X7 completed-task Reader smoke when a small downloaded task is available.

## Active: tag info intro image sizing

Status: active
Reference implementation: `feature/gallery/src/main/ets/components/GalleryTagsCard.ets` `TagInfoIntroImage`, `shared/src/main/ets/components/PreviewThumbTile.ets`, and `feature/reader/src/main/ets/pages/ReaderPage.ets` image `onComplete` metric handling.
Surface type: tag-info half-modal image block rendered from tag translation Markdown intro images.
Primary information: the intro image itself is the primary visual; its white rounded surface should match the loaded image ratio instead of reserving a tall placeholder after the image has decoded.
Primary action: no new action; the sheet still only supports close, vote, and My Tags management.
Reuse or deviation: reuse the existing two-column image masonry and rounded image component; deviate from the old URL-only ratio guess by replacing the fallback aspect ratio with decoded image width/height from `Image.onComplete` when available.
Verification: gallery tag-info contract, grounding ledger review, V1 decorator inventory, and current tag-info sheet screenshots with landscape and portrait intro images.

## Active: WebView login cookie handoff

Status: active
Reference implementation: `entry/src/main/ets/pages/EhLoginWebPage.ets`, `entry/src/main/ets/pages/GalleryWebPage.ets` cookie-domain merge, and `shared/src/main/ets/settings/CookieJarSettings.ets` `refreshIgneous()` / complete-jar persistence.
Surface type: WebView login completion flow plus Home custom-profile source restoration.
Primary information: after login, the app must hold a native cookie jar that covers table-site, ExHentai, and forums cookies; after app/profile restore, built-in Home sources must still include the login-gated watched/subscription profile.
Primary action: the user signs in in the WebView and returns to the native app; selecting the subscription source loads `/watched`, and tapping a gallery opens native detail with the same authenticated request stack.
Reuse or deviation: reuse the existing WebView login form, complete `CookieJarSettings` jar writer, `refreshIgneous()` uconfig fetch, and `CustomProfilesSettings` built-in profile model; deviate only by collecting the ExHentai WebCookieManager domain during login and repairing missing built-in profiles from old/synced data.
Verification: web-login cookie capture contract, custom-profiles contract, cookie round-trip/set-cookie contracts, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and emulator auth-path logs when a real account is available.

## Active: download gallery task card structure

Status: active
Reference implementation: NextE `feature/download/src/main/ets/pages/DownloadQueuePage.ets` gallery and archiver task cards, plus `../eros_fe/lib/pages/tab/view/download_page.dart` download task rows.
Surface type: Downloads tab gallery queue task card.
Primary information: the gallery title is the primary row text and must get the full content-column width after the cover.
Primary action: tapping completed content still opens local Reader; pause/resume and overflow actions stay secondary controls inside the content area.
Reuse or deviation: reuse the existing cover, progress/status builders, and circle action buttons; deviate from the old three-column card by treating actions as part of the right content column instead of a third outer column that shrinks the title, while keeping the proven `FlexAlign.End` action grouping instead of a `Blank().layoutWeight(1)` spacer; keep the action column width stable but use a smaller button frame with the same icon size.
Verification: download workbench contract, grounding ledger review, V1 decorator inventory, signed HarmonyOS build, and device screenshot of long titles with original/resampled tasks.

## Active: archiver stream timeout

Status: active
Reference implementation: NextE `shared/src/main/ets/settings/DownloadQueueSettings.ets` archiver stream path, `shared/src/main/ets/network/EhHttpClient.ets` `requestInStream`, and `../eros_fe/lib/common/controller/download_controller.dart` archive download flow.
Surface type: existing Archiver local download task, no new UI surface.
Primary information: a large archive task should keep showing real progress until completion or a concrete network failure.
Primary action: the user starts an archive download from the detail Archiver sheet, then watches the existing Downloads tab task progress; failed tasks keep their retry path.
Reuse or deviation: reuse the existing stream-to-file client, retry count, task persistence, and progress UI; deviate only by giving archive streams a longer read timeout than ordinary image downloads because 197 logs showed 777 MB archive transfers timing out mid-stream under the generic 20 s binary timeout.
Verification: 197 hilog evidence for the old `archiver_download_stream_progress` followed by repeated `Operation timeout`, the fixed build retry reaching `archiver_download_done | bytes=777185766`, download RDB contract, grounding ledger review, V1 decorator inventory, and signed HarmonyOS build.

## Active: thumbnail grid density gesture

Status: active
Reference implementation: NextE gallery list `PullRefreshGridScaffold` pinch-density path, `feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets`, `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets`, and eros_fe `../eros_fe/lib/pages/gallery/view/all_thumbnails_page.dart`.
Surface type: gallery detail inline thumbnail grid plus the all-thumbnails page only.
Primary information: thumbnail cards remain page-preview thumbnails; the density control changes only how many thumbnail cells fit per row.
Primary action: two-finger pinch on thumbnail grids and the Layout settings row adjust the shared thumbnail column width; tapping thumbnails still opens the reader.
Reuse or deviation: reuse the existing list-mode column-width state, slider page, and `PullRefreshGridScaffold.pinchModeKey`; deviate only by wiring the detail inline bare `Grid` to the same persisted thumbnail key because it is not a pull-refresh page.
Verification: responsive thumbnail grid contract, grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and settings/all-thumbnails smoke on X7 when available.

## Active: gallery date seek after jump

Status: active
Reference implementation: `../eros_fe/lib/pages/tab/controller/tabview_controller.dart` `buildTimeDialog()` / `_jumpToPageWithGidOrTime()`, `../eros_fe/lib/pages/tab/fetch_list.dart` `loadFrom()`, and `../eros_fe/lib/network/request.dart` `getGallery()`.
Surface type: Home gallery title-bar menu action for ordinary/custom gallery sources.
Primary information: the active gallery list is replaced by EH results after the chosen date; existing rows remain visible while the request is in flight.
Primary action: selecting the title-bar date-jump action opens native `UIContext.showDatePickerDialog`, confirms a `seek=yyyy-MM-dd` after-jump, scrolls the active retained list to its new top, then pull-to-refresh prepends the EH `prev` page; the title-bar back-to-top action leaves normal lists as a scroll-to-top but reloads page 1 when this source is in date-jump mode. gid/manual Prev jumping remain out of scope for this slice.
Reuse or deviation: reuse the existing HomeSource command bus, retained `GallerySourcePage`, `GalleryListViewModel`, `PullRefresh*Scaffold` prepend callback, and EH list request path; deviate from FE's combined time/gid sheet by using the platform date picker because this slice only implements the forward date seek, the resulting previous-page chain, and an explicit first-page escape through the existing back-to-top menu item.
Verification: grounding ledger review, gallery paging contract, V1 decorator inventory, signed HarmonyOS build, and emulator smoke covering date seek, pull-to-refresh previous-page prepend, then back-to-top returning to page 1 instead of prepending again.

## Active: favorites jump navigation

Status: active
Reference implementation: `../eros_fe/lib/pages/tab/controller/favorite/favorite_tabbar_controller.dart` `showJumpDialog()` / `jumpToTop()`, `../eros_fe/lib/pages/tab/controller/favorite/favorite_sublist_controller.dart` `fetchPrevData()` / `fetchDataFrom()`, and `../eros_fe/lib/pages/tab/controller/tabview_controller.dart` `showJumpDialog()` / `loadPrevious()`.
Surface type: Favorites bottom tab title-bar menu plus the active retained favorite-folder page.
Primary information: the active remote favorite folder remains the list being browsed; jump actions replace that retained page with the requested favorites page or date-seek result while preserving old rows during the request.
Primary action: tapping the Favorites jump action opens page-number input when EH exposes page navigation, otherwise the platform date picker; after a jump, pull-to-refresh loads the previous favorites page and the title-bar first-page action reloads the current favorite folder from page 1. Search, sort, folder selection, and local favorites stay secondary/unchanged.
Reuse or deviation: reuse `FavSelectionBridge`, retained `FavcatPage`, `FavoritesViewModel`, existing HDS title-bar menu items, Toplist's page-number `CustomContentDialog`, Gallery's `showDatePickerDialog`, and the current `PullRefresh*Scaffold` refresh hook; deviate from FE by omitting manual gid/offset jump for this slice and by hiding remote jump behavior for the local-only `l` folder.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and simulator smoke covering remote page jump, date jump fallback, pull-to-refresh previous-page prepend, first-page escape, and local favorites without a remote jump path.

## Active: download task restore scan

Status: active
Reference implementation: `../eros_fe/lib/pages/setting/download_setting_page.dart` restore/rebuild task-data rows, `../eros_fe/lib/common/controller/download_controller.dart` `restoreGalleryTasks()` / `downloadTaskMigration()`, and `../eros_fe/lib/store/hive/hive.dart` archiver task map persistence.
Surface type: Settings > Download maintenance row.
Primary information: the user sees a simple "Restore downloads" setting row that scans existing download metadata rather than a new download queue surface.
Primary action: tapping the row asks the platform DOWNLOAD directory flow if needed, scans `download-gallery` and `download-archiver` metadata, imports missing tasks into the RDB-backed queue, and reports the result by toast; archive-bot and executor policy rows remain separate.
Reuse or deviation: reuse NextE `DownloadQueueSettings` metadata parser, RDB repository, settings row pattern, and row-local loading suffix; deviate from FE's Hive/SAF migration because Harmony's public Download app directory is resolved through `DocumentViewPicker.save()` with `DocumentPickerMode.DOWNLOAD`.
Verification: download settings contract, grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and device/settings smoke when a public Download task directory is available.

## Active: download completion notification

Status: active
Reference implementation: NextE `feature/settings/src/main/ets/pages/DownloadSettingsPage.ets`, `shared/src/main/ets/settings/DownloadSettings.ets`, `shared/src/main/ets/settings/DownloadQueueSettings.ets`, and HarmonyOS `notificationManager` basic text notifications.
Surface type: Settings > Download policy row plus system notification after a local download finishes.
Primary information: notification preference is part of download policy and defaults off; a notification means a gallery task reached COMPLETE or an archive file finished successfully.
Primary action: toggling the row enables the persisted preference and requests the platform notification authorization; completed downloads publish a short system notification without adding a new notification center or root settings entry.
Reuse or deviation: reuse the existing download settings single writer, grouped settings row, i18n resources, and queue completion points; deviate only by adding a thin notification service so permission/publish failures are logged and never change task completion.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and device smoke for permission prompt plus completed-download notification when available.

## Active: completed download export

Status: active
Reference implementation: `../eros_fe/lib/pages/tab/controller/download_view_controller.dart` `_showExportSheet()` / `_exportZip()` / `_exportEpub()`, `../eros_fe/lib/common/epub/epub_builder.dart` `buildEpub()`, and NextE `feature/download/src/main/ets/pages/DownloadQueuePage.ets` existing completed-task overflow menu.
Surface type: Downloads tab completed gallery and archiver task overflow actions, including the nested export-format submenu.
Primary information: completed tasks remain ordinary download rows; export actions expose file formats only when local files already exist.
Primary action: tapping a completed gallery task still opens Reader; overflow shows a single Export parent item, and the submenu exports CBZ/ZIP/EPUB/HTMLZ/PDF into the app's public Download export directory before opening the system share sheet, while completed archiver tasks can additionally copy and share the original archive file.
Reuse or deviation: reuse `DownloadImageSeed.filePath` page order, `ArchiveImageService.imagePathsForTask()`, `DownloadArchiverTask.filePath`, `DownloadQueueSettings` public Download directory setup, `ShareUtil.shareFile()`, and ArkUI `MenuItemOptions.builder` for the second-level menu; deviate from eros_fe by keeping a public Download copy after export, by using the original first downloaded image as the EPUB cover item without generating a cropped or re-encoded cover, by packaging HTMLZ as `index.html` plus original image resources, by generating PDF pages from original JPEG/PNG streams when the source can be embedded directly, and by running ZIP CRC/file writes in TaskPool so they do not block the UI thread.
Verification: grounding ledger review, V1 decorator inventory, i18n duplicate check, diff check, signed HarmonyOS build, and X7 emulator smoke that the completed-task menu shows a single Export parent, expands CBZ/ZIP/EPUB/HTMLZ/PDF as a submenu, and opens the system share sheet for an HTMLZ export without producing a new appfreeze.

## Active: download media library hiding

Status: active
Reference implementation: NextE `feature/settings/src/main/ets/pages/DownloadSettingsPage.ets`, `shared/src/main/ets/settings/DownloadQueueSettings.ets`, and OpenHarmony media scanner `.nomedia` handling.
Surface type: Settings > Download policy row.
Primary information: the user sees whether public gallery/archive downloads are kept out of media-library scans.
Primary action: toggling the switch persists the preference and reconciles `.nomedia` in the already-resolved download folders; later download startup reconciles it again before writing files.
Reuse or deviation: reuse the existing download settings V2 holder, `ConciseListRow` switch, public `DocumentPickerMode.DOWNLOAD` root flow, and queue storage preparation; deviate only by writing or removing `.nomedia` inside `download-gallery` and `download-archiver`, leaving export files shareable.
Verification: download settings contract, download queue RDB contract, grounding ledger review, V1 decorator inventory, i18n duplicate check, diff check, and signed HarmonyOS build.

## Active: reader closed thumbnail strip hit area

Status: active
Reference implementation: NextE `feature/reader/src/main/ets/pages/ReaderPage.ets` `ReaderBottomBar` / `ReaderTapOverlay`, plus `../eros_fe/lib/pages/image_view/view_widget.dart` bottom chrome + optional thumbnail list.
Surface type: Reader bottom chrome hit area.
Primary information: when the reader chrome is visible but the thumbnail strip is closed, only the visible toolbar should intercept touches.
Primary action: center/edge taps above the visible toolbar continue to route through the reader tap zones; opening the thumbnail strip still shows the tappable strip.
Reuse or deviation: reuse the existing reader bottom toolbar, local `showThumbStrip` toggle, and tap overlay; deviate only by collapsing the strip container height/padding to 0 and making bottom chrome height conditional when the strip is closed.
Verification: reader thumbnail filmstrip contract, reader tap-zone contract, grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: gallery comment HTML links and inline styles

Status: active
Reference implementation: `../eros_fe/lib/common/parser/gallery_detail_parser.dart` `parseGalleryComment()` linkify pass, `../eros_fe/lib/pages/gallery/view/comment_item.dart` `buildCommentTile()`, `../eros_fe/lib/const/const.dart` `commentUrlRegExp`, and NextE `feature/gallery/src/main/ets/components/GalleryCommentsCard.ets` existing comment `Span` URL handling.
Surface type: Gallery detail comment preview and full comments page body text.
Primary information: comments keep their original readable text and inline meaning; HTML anchor labels remain labels, while bold/italic/underline/strike/span color are visible instead of being flattened to plain text.
Primary action: tapping a linked comment label opens the href through the existing EH URL router or in-app web page; translated comments preserve structure only when the source text still maps exactly to the parsed comment body, otherwise they fall back to plain translated text.
Reuse or deviation: reuse `EhCommentParser`, `EhGalleryComment`, `GalleryCommentsCard` `CommentTextSegment`, `EhUrlRouter`, `GalleryWeb`, page cache cloning, and FE's recursive inline-node semantics; deviate from FE by storing serializable text-span ranges instead of a parsed DOM element because NextE cache/state must survive ArkTS model copying.
Verification: comment parser contract, reply reference contract, comment translation contract, grounding ledger review, V1 decorator inventory, diff check, and signed HarmonyOS build.
