# Settings And History Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Settings Shell Audit: Visible Rows Must Be Real Or Honest

Type: feature gap / settings trustworthiness

Priority suggestion: P1

Status: active intake / Security, Download, EH placeholders, and Search destructive-action safety implemented pending controller acceptance

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
  remains available. Contract updated: `scripts/test_download_settings_contract.mjs` now locks that
  Settings root must not contain `settings_download` or `pushPathByName('DownloadSettings', null)`
  until the executor consumes those preferences.
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
  `scripts/test_download_settings_contract.mjs`,
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
