# eros_fe Parity Gap Audit

Research reference only. It is not a current plan, rule set or authorization source.

Status: planning reference, not an active implementation lane.

Last reviewed: 2026-06-22

Purpose:

- Track broad product/functionality gaps between NextE and `../eros_fe`.
- Keep this separate from current bug intake. Intake files record concrete bugs and near-term fixes;
  this file records feature-depth parity gaps.
- Use this before opening a new major lane so the main thread does not mistake "current active queue is
  short" for "NextE has reached eros_fe parity".

Source inventory:

- eros_fe routes: `../eros_fe/lib/route/routes.dart`, `../eros_fe/lib/route/app_pages.dart`.
- eros_fe major pages/controllers: `../eros_fe/lib/pages/**`, `../eros_fe/lib/common/controller/**`,
  `../eros_fe/lib/common/service/**`.
- NextE route map: `entry/src/main/ets/pages/Index.ets`.
- NextE modules: `feature/*`, `shared/src/main/ets/**`.
- Existing roadmap: `docs/roadmap.md`.
- Existing post-stabilization lanes:
  archived `docs/plans/archive/project-current-state-and-next-plan.md` snapshot.

## Summary

NextE has the main shell and many first-order surfaces:

- Five main tabs: Gallery, Favorites, Toplist, Download, Settings.
- Core gallery list/detail/reader route chain.
- Basic Search with advanced filter sheet, network `tagsuggest`, search history, URL jump, and favorite scope.
- Favorites page, favorite selector, local favorite state, remote favorite mutation surface.
- MyTags page with read/edit/add/delete/tagset management plumbing.
- Gallery comments page with comment write/reply/edit/vote plumbing.
- Rating, torrents, archiver, internal gallery WebView, info page, all-thumbnails page.
- Several settings pages and retained sub-tab preferences.

But NextE is still not feature-complete against eros_fe. The largest gaps are not single UI bugs; they are
feature-depth domains: local tag translation, QuickSearch, full favorites workspace behavior, full download
and offline reading, WebDAV/custom profile sync, image blocking, security enforcement, and advanced search /
write-operation polish.

## Status Legend

- `Present`: NextE has a user-visible path that roughly covers the eros_fe feature.
- `Partial`: NextE has an entry, model, parser, or narrow implementation, but not the full eros_fe workflow.
- `Missing`: no meaningful NextE product surface found.
- `Needs acceptance`: code exists, but current controller/device acceptance is still pending elsewhere.

## Gap Matrix

| Domain | eros_fe source | NextE source | Status | Main gap |
|---|---|---|---|---|
| Auth / cookies / site mode | `pages/login/**`, `common/controller/user_controller.dart`, `common/service/ehsetting_service.dart` | `EhLoginWebPage`, `EhCookieImportPage`, `CookieJarSettings`, `AuthState`, `EhSettingsPage` | Partial | Login and cookie shell exist, but full user/uconfig/donor/profile depth and ExHentai gating still need acceptance and hardening. |
| Main tab shell | `tabhome_controller.dart`, `custom_tabbar_page.dart`, `favorite_tabbar_page.dart` | `Index.ets`, `HomePage`, `FavoritesPage`, `ToplistPage`, `DownloadQueuePage`, `SettingsPage` | Partial | Fixed five-tab shell exists; custom profiles/tab groups, safe mode, tablet split layout, and overflow safety net are missing. |
| Gallery list / modes / tags | `gallery_item*.dart`, `fetch_list.dart`, `tag_controller.dart` | `GalleryCard`, `GalleryGridCard`, `GalleryWaterfallCard`, `UserTagStore`, `EhApiService.applyHiddenTagFilter` | Partial | Core list modes and hide filter exist; FE-level custom profile lists, full card parity, and tag translation DB are still incomplete. |
| Gallery detail | `gallery_page.dart`, `header.dart`, `gallery_info_page.dart`, `gallery_favcat.dart` | `GalleryDetailPage`, `GalleryInfoPage`, `GalleryHeaderCard`, `GalleryTagsCard` | Partial | Detail has many actions, but pull-to-refresh, smart-grip action alignment, richer info/action affordances, and acceptance polish remain. |
| Reader | `image_view/controller/view_controller.dart`, `image_view/view/**` | `ReaderPage`, `ReaderViewModel`, `ReaderImageTransformCoordinator` | Partial | Single-page core is usable; final pager/spread architecture, gesture proof, top/bottom toolbar parity, and offline source remain open. |
| Search | `search_page.dart`, `quick_search_page.dart`, `search_image_page.dart`, `gallery_filter_view.dart`, `quicksearch_controller.dart`, `tag_trans_controller.dart` | `GallerySearchPage`, `SearchFilterSheet`, `SearchViewModel`, `EhApiPhpService.tagsuggest`, `SearchSettingsPage` | Partial | Network tagsuggest exists; local translation DB, Chinese/localized search, QuickSearch, image search, and some focus/session issues remain. |
| Favorites | `favorite_tabbar_page.dart`, `favorite_sel_page.dart`, `fav_controller.dart`, `favorite_sel_controller.dart` | `FavoritesPage`, `FavcatPage`, `FavoriteSelectorPage`, `FavSelectionState`, `LocalFavState` | Partial | Favcat tabs and local slot exist; full FE workspace depth around sorting, cursor/jump behavior, notes, local/remote parity, and state independence needs acceptance. |
| MyTags / usertags | `setting/mytags/**`, `eh_mytags_controller.dart`, `tag_controller.dart` | `MyTagsPage`, `EhMytagsParser`, `UserTagStore`, `EhApiPhpService.setUserTag` | Partial | Management plumbing is deeper than a placeholder, but it still needs accepted end-to-end QA and full wiring into every list/detail/search/tag-translation path. |
| Tag translation | `tag_translat_page.dart`, `tag_trans_controller.dart` | `TagTranslationService` | Missing / stub | NextE has only a tiny built-in lookup. It does not download/decompress/index the FE tag translation DB or drive Chinese/localized candidate search. |
| Downloads / archives / offline | `download_page.dart`, `download_controller.dart`, `download_task_manager.dart`, `archiver_download_controller.dart` | `DownloadQueuePage`, `DownloadQueueSettings`, `GalleryArchiverPage` | Partial | Queue/workbench and some first-image/archive actions exist; full background queue, pause/resume/delete, per-image retry, archive offline reader source are not complete. |
| Comments / ratings / writes | `comment_controller.dart`, `rate_controller.dart`, `gallery_fav_controller.dart`, `taginfo_controller.dart` | `GalleryCommentsPage`, `GalleryCommentsCard`, `GalleryEditTagsPage`, `EhApiPhpService` | Partial | Write APIs exist; reply-floor quote display, comment rendering completeness, score/icon refresh proof, and authorized destructive write QA remain. |
| EH settings / uconfig | `eh_setting_page.dart`, `eh_mysettings_page.dart`, `eh_mysettings_controller.dart` | `EhSettingsPage`, `SiteModeSettings`, `CookieJarSettings` | Partial | NextE groups account/site basics; full EH uconfig/mysettings page and website settings are not equivalent yet. |
| Layout / read / download / search settings | `layout_setting_page.dart`, `read_setting_page.dart`, `download_setting_page.dart`, `search_setting_page.dart` | `LayoutSettingsPage`, `ReaderSettingsPage`, `DownloadSettingsPage`, `SearchSettingsPage` | Partial | Pages exist, but several rows are deliberately scoped to current data only and do not cover FE's full settings depth. |
| Security / auto lock | `security_setting_page.dart`, `auto_lock_controller.dart`, `unlock_page.dart` | `SecuritySettingsPage`, `SecuritySettingsState` | Partial / hidden risk | Preferences exist, but real lock/enforcement/unlock lifecycle is not complete enough to treat Security as accepted parity. |
| History | `history_page.dart`, `history_controller.dart` | `ViewedHistoryPage`, `ViewedHistorySettings` | Partial | Basic viewed-history surface exists; deletion, sync, richer controls, and FE retention semantics need acceptance. |
| Persistence / backup / app data import-export | `advanced_setting_page.dart`, `utils/import_export.dart`, `gallerycache_controller.dart` | `SettingsBootstrap`, Preferences-backed `*Settings`, no backup service | Missing / architecture gap | NextE lacks an app-data export/import workflow and still stores several growing data sets as Preferences JSON. Use V2Next's `LocalDataStore` and backup envelope/denylist/rollback model as the HarmonyOS reference. |
| WebDAV / sync | `webdav_setting_page.dart`, `webdav_controller.dart`, `login_webdav.dart` | none found | Missing | No WebDAV sync for history/read progress/QuickSearch/custom groups. |
| MySQL sync | `mysql_sync_page.dart`, `mysql_controller.dart` | intentionally not planned | Deferred / not a gap | Roadmap says MySQL sync is abandoned because no OHOS driver; do not reopen unless product direction changes. |
| Network custom hosts / proxy / DNS | `custom_hosts_page.dart`, `proxy_page.dart`, `dns_service.dart` | mostly not surfaced | Missing / partial infra | Roadmap prefers DoH/fallback/proxy architecture, but FE-level custom hosts/proxy settings are not complete. |
| Block rules | `setting/block/**`, `block_controller.dart` | none found | Missing | Title/uploader/commenter/comment regex block rules are not implemented as a user surface. |
| Image blocking | `image_block/**`, `image_block_controller.dart` | none found | Missing | pHash/QR/image hide lists are absent. |
| Search by image / similar | `search_image_page.dart`, `search_image_controller.dart`; detail similar action | Search URL jump and detail similar search exist; no upload flow | Partial | Similar title search exists, but image upload/search-by-image route is missing. |
| Torrents | `torrent_controller.dart`, `torrent_dialog.dart` | `GalleryTorrentsPage`, `EhGalleryTorrentParser` | Present / needs acceptance | Read/share surface exists; compare current behavior before reopening. |
| Archiver | `archiver_controller.dart`, `archiver_dialog.dart` | `GalleryArchiverPage`, `EhGalleryArchiverParser` | Partial | Quote/options page exists; full download/queue/offline archive behavior belongs to download lane. |
| Avatar / profile | `avatar_controller.dart`, `avatar_setting_page.dart`, `user_item.dart` | no avatar setting/page found | Missing | User avatar/profile presentation and settings are not FE-complete. |
| Update / about / license / logs | `update_controller.dart`, `about_page.dart`, `license_page.dart`, `log_page.dart` | `AboutPage`, `AdvancedSettingsPage`, diagnostics logs partly | Partial | About exists; update check, license/log parity, and diagnostics UX are shallow. |
| EPUB export | `common/epub/epub_builder.dart` | none found | Missing | EPUB export is absent. |

## Recommended Major Lanes

These lanes are project-level feature lanes. Do not implement from this audit directly; choose one bounded
subfeature only when the user asks for that lane or it is written into the current task plan.

### Lane A — Auth And EH Account Foundation

Why:

- Many FE parity features are not honestly testable while authentication, ExHentai, user profile, and
  uconfig are shallow.

Scope candidates:

- Harden WebView login and manual cookie import validation.
- Verify complete cookie jar persistence for unknown donor/permission cookies.
- Implement/accept ExHentai igneous detection and site switch gating.
- Add a real EH mysettings/uconfig surface instead of only basic site/account rows.
- Add secret-safety/package-leak checks.

### Lane B — Search And Tag Translation Depth

Why:

- User-facing search quality depends on local tag translation, exact tag query insertion, suggestions, and
  saved query workflows.

Scope candidates:

- Download/decompress/index the tag translation DB used by eros_fe.
- Feed translated/localized candidates into the existing in-page suggestion region.
- Add QuickSearch saved-query list/add/remove/clear.
- Add image search upload route.
- Keep action-seeded tag routes results-first and no-autofocus.

### Lane C — Favorites Workspace

Why:

- Favorites is not just a list; FE treats it as a workspace with favcat tabs, counts, colors, local slot,
  search, ordering, and cursor/jump controls.

Scope candidates:

- Accept or repair per-favcat state retention and sorting.
- Finish local favorite slot behavior.
- Finish note editing/move/remove with guarded write QA.
- Add jump/order actions and favorite-specific search polish.

### Lane D — MyTags / UserTag System

Why:

- MyTags affects list filtering, tag colors, watched/hidden behavior, search candidates, and detail tag
  rendering.

Scope candidates:

- End-to-end QA for tagset list -> usertag detail/manage.
- Verify setusertag/add/delete/create/rename/delete with explicit write authorization.
- Ensure UserTagStore loads early enough and affects list/detail/search consistently.
- Replace the tiny `TagTranslationService` table with the real translation database.

### Lane E — Download, Archive, And Offline Reader

Why:

- Download tab currently reads as a workbench, not FE's offline consumption path.

Scope candidates:

- Implement downloader service and durable queue state.
- Add pause/resume/delete/error retry semantics.
- Resolve per-image tokens and 509 retries.
- Wire downloaded/archived gallery as Reader source.
- Decide HarmonyOS background transfer path before broad implementation.

### Lane F — Comments, Rating, And Destructive Writes

Why:

- NextE now has many write endpoints, but acceptance must prove state updates and avoid accidental
  destructive submits.

Scope candidates:

- Add parsed reply-floor quote display.
- Verify comment vote score/icon update and uploader-only filter.
- Finish comment parser/display details: scoreDetails, links, member profile navigation, local time.
- Verify gallery rating, favorite notes/move/remove, tag edit/add with non-destructive QA first.

### Lane G — Sync / Security / Blocking / Long Tail

Why:

- These are FE long-tail features that should not interrupt core browse/search/favorites/download work, but
  they are real parity gaps.

Scope candidates:

- WebDAV sync for history/read progress/QuickSearch/custom groups.
- Settings maintenance depth: cache management, app data export/import, proxy/custom hosts, blockers, and
  WebDAV settings entry points.
- Custom tab/profile groups and safe-mode/tablet variants.
- Block rules and image blocking/pHash/QR filtering.
- Security auto-lock enforcement and unlock page.
- EPUB export, update check, profile/avatar/settings polish.

## Usage Rules

- Do not implement from this audit directly. First pick one bounded subfeature from the user's current
  request and verify current NextE code.
- Do not bundle a whole lane into one patch.
- Every lane must still provide the normal five-line grounding from `always-loaded-rules.md`.
- UI/interaction work needs FE comparison or must be marked `implemented / needs FE comparison`.
- Destructive EH writes need explicit authorization and should default to open-dialog/cancel QA.
