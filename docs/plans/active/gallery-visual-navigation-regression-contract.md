# Gallery visual + navigation regression contract

- **status**: ACTIVE — REOPENED; completed archive was invalid because several acceptance gates remain partial/unsolved.
- **created**: 2026-06-16 13:11:31 +0800
- **source**: user feedback in controller chat after #37/#38; persisted because chat-only notes are lost after context compaction
- **scope owner**: controller, not Claude self-report
- **reopened**: 2026-06-17 — controller audit after user correction. Previous archive claim is invalid; use the item-by-item audit below before any next work.

## Control-plane state

This file is the active contract for the next NextE gallery pass. Do not treat prior chat context, Claude PASS summaries, or visual screenshots as sufficient state.

Current blocking conclusions:

- `b5791a9` (`fix(gallery): detail preview row to eros_fe ThumbHorizontalList`) is **not fully accepted**. It fixed part of the thumbnail rendering defect (larger/no-white-border path), but it collapsed eros_fe product semantics: horizontal thumbnails are optional, default grid must remain, hide-gallery-thumbnails exists, and the all-thumbnails page entry must still be reachable in horizontal mode.
- `da493c1` (`feat(cards): tint list/grid/simple card rating stars...`) is **not controller-accepted in this contract** yet. It may be technically correct, but no further gallery work should proceed until this contract is addressed.
- Do not continue feature work or cosmetic spot-fixes before the P0 items below are audited and gated.

Non-negotiable project safety:

- Do **not** delete, move, overwrite, or call disposable any untracked/ignored project paths. `.harness/`, `.harness/state/*`, `docs/plans/`, `CLAUDE.md`, screenshots, fixtures, generated state, and any `??`/`!!` path are project/control-plane assets unless the current user explicitly authorizes deletion of the exact path.
- Do **not** run `git clean`, `rm -rf`, or equivalent cleanup.
- User reports in this file are ground truth observations. If source or logs appear to contradict them, first reproduce and collect evidence; do not invent user-behavior explanations.

## User-reported defects to preserve across compaction

### P0 — Gallery sub-tab switching white-screens / reloads

User report:

> “现在子 tab只要一切换，就会从白屏刷新，重新加载。我真的很无法理解这个东西”

Classification:

- P0 UX regression.
- It is not acceptable for source/favcat/toplist/search-like sub-tab switches to blank the whole body and re-fetch from a white screen.
- Switching a sub-tab/selector should preserve current body content or show an in-body loading affordance while the new dataset loads. Pinned chrome/selector must not unmount.

Starting evidence / suspected paths (not yet final root cause):

- Existing audit already described this class: `docs/ui-architecture-audit.md` F1b — switching source/period/favcat zeros itemCount and trips `PageLoadingState`, unmounting controls.
- `feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets:58-59` clears data and sets `itemCount = 0` on order toggle.
- `feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets:144-145` clears data and sets `itemCount = 0` on favcat switch.
- `feature/user/src/main/ets/pages/FavoritesPage.ets:116-118` renders `PageLoadingState()` when `isLoading && itemCount === 0`.
- Audit home/toplist/search equivalents before concluding; do not fix only favorites if the same anti-pattern exists in `GalleryListBody`, `GalleryListViewModel`, `HomePage`, `ToplistPage`, or search/favorites viewmodels.

Required behavior gate:

- Device test: switch every visible gallery sub-tab/selector relevant to current UI (Home source, Toplist period, Favorites favcat/order, search filters if applicable). Capture video or paired screenshots before/during/after.
- PASS only if there is no full-white page flash and no wholesale remount of pinned selector chrome.
- Old content may remain dimmed/stale while loading, or an in-body spinner/skeleton may appear, but the page must not look blank/reset.
- Add deterministic structural gate preventing `setData([])` + `itemCount = 0` before network completion on selector switches unless the page explicitly renders a non-white skeleton that preserves chrome.

### P0 — False 404 on some galleries

User report:

> “某些画廊出现奇怪的 404 报错，但其实根本就没有 404”

Classification:

- P0 correctness / diagnostic defect.
- Do not report “404” unless the captured HTTP response status for the exact requested URL is 404.
- Parse failures, Sad Panda, wrong host, stale token, gdata/detail mismatch, image-page showpage failure, gateway errors, or empty bodies must not be mislabeled as HTTP 404.

Starting evidence / suspect paths (not final root cause):

- `shared/src/main/ets/network/EhHttpClient.ets` returns raw `responseCode` from the platform HTTP client.
- `shared/src/main/ets/network/EhApiService.ets` throws `gallery list HTTP ${statusCode}`, `gallery detail HTTP ${statusCode}`, `gallery preview HTTP ${statusCode}`, etc.
- `shared/src/main/ets/network/EhApiPhpService.ets` throws `showpage HTTP ${statusCode}` / `gdata HTTP ${statusCode}`.
- `shared/src/main/ets/services/ImageResolveService.ets` throws `image page HTTP ${statusCode}`.
- Need full URL + site mode + cookies + responseCode + body signature in logs before assigning cause.

Required behavior gate:

- Add diagnostic logging around failing gallery open/load: requested URL, base host (`e-hentai`/`exhentai`), gid/token, route source, HTTP status, content-type if available, body prefix/sentinel (`<title>`, Sad Panda marker, EH gallery marker, Cloudflare/login marker), and final displayed error text.
- Reproduce with at least one user-reported false-404 gallery on device/network.
- PASS only if displayed error distinguishes true HTTP 404 from parse/not-auth/sad-panda/network/empty-body/gateway cases.

### P0 — Detail preview semantics collapsed by #37

User reports:

- Horizontal thumbnail scrolling is only an optional layout in eros_fe.
- Even in horizontal layout, the user can still jump to the full all-thumbnails page.
- NextE currently appears to have no switch and the full preview entry has been weakened/hidden.

Verified eros_fe source:

- `eros_fe/lib/pages/gallery/view/sliver/gallery_page.dart:292-299`:
  - `hideGalleryThumbnails` controls whether inline thumbnails are hidden.
  - `horizontalThumbnails` is passed into `ThumbTile`.
- `gallery_page.dart:430-455`: `ThumbTile(horizontal)` chooses `ThumbHorizontalList`; false branch uses `ThumbSliverGrid` + `MorePreviewButton`.
- `eros_fe/lib/common/service/ehsetting_service.dart:331-339`: defaults are `hideGalleryThumbnails=false`, `horizontalThumbnails=false`.
- `eros_fe/lib/pages/setting/layout_setting_page.dart:165-189`: settings UI exposes `Hide Gallery Thumbnails` and `Horizontal Thumbnails` switches.

Required behavior gate:

- Default should remain grid, not horizontal.
- Settings must expose/persist hide-gallery-thumbnails and horizontal-thumbnails equivalents before claiming parity.
- Horizontal layout must still provide a clear all-thumbnails page entry.
- Hidden-inline mode must still offer a full preview entry equivalent to eros_fe `MorePreviewButton` behavior.
- `AllThumbnails` route must remain functional.

### P0 — Detail header action sizing still wrong

User report:

- Read button and favorite button sizes are not coordinated.
- User explicitly raised this earlier; it was not actually improved.

Required behavior gate:

- Inspect eros_fe `ReadButton` / `GalleryFavButton` and current `GalleryHeaderCard.ets` source.
- Test read/unread/resume and favorited/unfavorited states.
- PASS only if action heights, corner radii, icon/text baselines, padding, and visual weight are coordinated in the same row/block.

### P0 — Detail title long-text stress breaks layout

User report:

- Long gallery titles can push lower UI out of the card.
- Current title line control is insufficient or absent in practice.

Required behavior gate:

- Use synthetic/real galleries with very long EN title, long JP title, EN+JP double-title, long uploader, favorited state, and resume-read state.
- PASS only if title maxLines/layout priority keeps cover, buttons, favorite state, and metadata inside the header card without overflow, clipping, or overlap.
- Do not claim this is fixed by the mere presence of a `maxLines` call; verify on device/screenshot.

### P1 — Detail tag chips too thin / not rounded enough

User report:

- Detail page tags have too small a corner radius.
- Tag height is too low; chips look thin/long instead of rounded and comfortable.

Required behavior gate:

- Compare eros_fe tag group/member chip padding/radius/height and NextE `GalleryTagsCard.ets`.
- Preserve existing semantics: namespace color, member usertag coloring, hidden/watched state, and any tag search behavior must not regress.
- PASS only with screenshot evidence on dense tag groups and colored usertags.

### P1 — Gallery cover image presentation wrong

User reports:

- Gallery list cover crop is crude horizontal cropping and does not match eros_fe.
- Detail cover treatment has the same crop/fit problem.
- When list cover images are not loaded yet, placeholder background is too close to the list/page background, so the card looks cut in half.

Required behavior gate:

- Audit eros_fe list cover (`_CoverImage` / `CoverImg` / item widgets), grid cover, and detail header cover. Determine actual `BoxFit`, alignment, aspect, clip, placeholder, and loaded/error state behavior.
- Audit NextE `EhThumbnail`, `GalleryCard`, `GalleryGridCard`, and `GalleryHeaderCard` parameters. Do not use one crude `cover` strategy for all contexts if eros_fe differs.
- State matrix must be tested: loaded, loading/placeholder, and error in light/dark if possible.
- PASS only if placeholder has a distinct internal surface and does not make the card look visually truncated.

### P1 — List card height modes missing/incomplete

User report:

- eros_fe has adaptive-height and fixed-height list layouts.
- NextE currently appears to use only adaptive height.

Required behavior gate:

- Verify eros_fe layout modes/source and defaults before changing.
- Determine whether NextE must expose a setting or map existing list/simple/grid modes to Fe’s fixed/adaptive behavior.
- PASS only if long title/tag density does not cause uncontrolled list rhythm, cover stretching, or excessive crop.

## Execution rules for the next worker/controller

Before any code change:

1. Read this file.
2. Read `docs/loop.md` and `docs/agent-guides/always-loaded-rules.md`.
3. Inspect eros_fe source for each item before designing a NextE change.
4. Inspect current NextE source and record exact file:line evidence.
5. Write a short implementation plan listing gates and screenshot artifacts.

Forbidden shortcuts:

- Do not fix one symptom by removing or hardcoding another feature.
- Do not replace optional eros_fe settings with one forced layout.
- Do not accept worker self-report as PASS.
- Do not claim “no 404” or “true 404” without HTTP evidence for the exact failing URL.
- Do not claim visual PASS from build/install alone.

Minimum validation bundle for any acceptance:

- Deterministic contract tests for structural behavior introduced/changed.
- `node scripts/test_v1_decorator_inventory_contract.mjs` reports 0.
- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon` success.
- `.harness/hooks/pre-commit` success.
- Device screenshots/videos for the relevant loaded/loading/error/long-title/sub-tab-switch cases.
- Controller review of diff + evidence, not just Claude/worker summary.

## Suggested implementation order

1. P0 freeze/diagnose sub-tab reload white-screen. Fix stale-body/skeleton/chrome preservation before visual polish.
2. P0 diagnose false 404 and add truthful error classification/observability.
3. P0 restore detail preview settings semantics (default grid, optional horizontal, hide-inline, full preview entry).
4. P0 detail header stress: title/action sizing/favorite/read coordination.
5. P1 image presentation contract: cover fit/alignment + placeholder/error state.
6. P1 tag chip shape.
7. P1 list card fixed/adaptive height modes.

## Current status log

- 2026-06-16 13:11:31 +0800 — Created from user feedback because chat-only context will be lost after compaction. No business code changed in this plan creation.
- 2026-06-16 17:06:54 +0800 — P0 selector white-screen regression controller-verified for reachable cases. Code/gates preserve stale content until replacement data arrives for Home/Toplist/Search selector reloads; `scripts/test_selector_reload_preserves_content_contract.mjs`, `scripts/test_gallery_paging_contract.mjs`, `scripts/test_secret_safety_contract.mjs`, V1 inventory, detail header contract, `.harness/hooks/pre-commit`, and `hvigorw assembleHap ...` pass. New HAP listing confirmed no forbidden raw credential resource. Device screenshots: `/tmp/nexte_qa/qa02a.jpeg` Home source transient, `/tmp/nexte_qa/qa05a.jpeg` Toplist period transient, `/tmp/nexte_qa/qa09a.jpeg` Search submit transient, `/tmp/nexte_qa/qa11a.jpeg` Search filter transient; contact sheet `/tmp/nexte_qa/p0_selector_transients_sheet.jpg`. Favorites favcat/order and site 表/里 device cases remain `BLOCKED` by logged-out state after security remediation; their code paths are covered structurally and must be re-device-verified after normal WebView login is available.
- 2026-06-16 23:13 +0800 — P0 #2 false-404 truthful error classification landed in two local commits (`1854cae` taxonomy+classifier+fixtures+contract, `ce99941` callsite wiring + i18n + logging + harness). `EhErrorClassifier.classifyResponse` is status-first then marker-first: ONLY a captured HTTP 404 → NotFound; HTTP 200 is not trusted (empty→SadPanda(ex)/EmptyBody, marker present→usable, else Cloudflare/Login/banned-RateLimited/SadPanda(ex)/ParseFailure); transport→Network. All six EhApiService web-page calls route through `fetch()`; the raw `... HTTP <code>` throws are gone. The six gallery ViewModels surface a localized `EhErrorText.forUser(err)` message (10 `error_*` keys × base/zh_CN/en_US/ja_JP); cookie-free dev string (kind/status/host/sentinel) still goes to hilog. Gates: `test_error_classification_contract.mjs` 55 assertions, `harness-verify` 10/10, V1 inventory 0, i18n parity, detail-parser regression, `dev.sh --build-only` BUILD SUCCESSFUL. **Device QA on `192.168.50.197:12345`** (the only Connected target; `.103/.200/.237` Offline): built app installed + launched, home list renders (`/tmp/nexte_qa/p0_smoke.jpeg`); deep-linked `/g/1/0000000000/` → EH returned HTTP **200** (no 404) → classified **parse-failure** (hilog `[gallery] detail_load_failed | detail parse-failure status=200 host=e-hentai`), UI shows localized "无法解析此页面,应用可能需要更新。" + retry, **NOT a false 404** (`/tmp/nexte_qa/p0_404.jpeg`). **BLOCKED**: two-device QA (`.103/.200/.237` Offline per `hdc list targets -v`); a true-HTTP-404→NotFound device repro (EH served 200 here, not 404 — the 404→NotFound mapping is covered by the contract); ExHentai Sad Panda / logged-in repro (app is logged out after security remediation — needs in-app WebView login). api.php showpage/gdata + the `/s/` image-page path keep their existing fallback/non-fatal handling (out of scope for this gallery-open pass).
- 2026-06-16 23:58 +0800 — P0 #3 detail preview semantics restored (one local commit on top of the dev-tooling fix `ebdd610`). eros_fe ThumbTile three modes are back, driven by two persisted booleans (`ThumbnailModeState` / `ThumbnailModeSettings`, both default false → GRID): GRID (default) = inline wrap-grid peek of the first preview page + centered "更多预览" entry; HORIZONTAL = tappable "预览 (n) 查看全部 >" header (always opens all-thumbnails) over the horizontal row; HIDDEN-INLINE = no inline previews, just the "更多预览" entry (takes precedence over horizontal). The separate AllThumbnails route is reachable in EVERY mode. Settings page exposes both as native HDS switches; GalleryDetailPage connects the reactive holder so a toggle re-renders live. New blocking gate `scripts/test_thumbnail_mode_contract.mjs` (default-grid + three-mode dispatch + all-mode entry + persistence + route). Gates: thumbnail-mode contract, harness-verify 12/12, V1 0, i18n 4-locale parity, `dev.sh --build-only` BUILD SUCCESSFUL. **Device QA on `192.168.50.197:12345` via `dev.sh --launch` (keep-awake OverrideTimeout=13600000ms)** — all three modes screenshotted: GRID `/tmp/nexte_qa/p3_grid.jpeg` + `/tmp/nexte_qa/p3_settings.jpeg`, HORIZONTAL `/tmp/nexte_qa/p3_horiz.jpeg`, HIDDEN `/tmp/nexte_qa/p3_hidden.jpeg`; the two switches `/tmp/nexte_qa/p3_set2.jpeg` + `/tmp/nexte_qa/p3_tg.jpeg`; live toggle switching grid→horizontal→hidden; and the hidden-mode "更多预览" opening the AllThumbnails grid page `/tmp/nexte_qa/p3_at2.jpeg`. **User visual correction after controller contact sheet:** on the 1400px-wide test device, the restored default GRID currently renders 4 columns and is visually too narrow; expected reasonable layout is 3 columns on this device, but the fix must be responsive (derive columns from available width / minimum comfortable thumbnail width), not a hardcoded column count. Additional thumbnail-tile correction in the same pass: occasionally thumbnail source dimensions appear wrong, tile layout must not let bad/flat aspect ratios break the row; page numbers should sit at a fixed, consistent position across tiles; very flat thumbnails should be centered inside a stable tile frame instead of pulling the number/visual baseline around. This correction is blocking before accepting P0 #3 visual polish. Note: this device is currently logged in (ID 2007706, 表站); device left with both toggles ON after QA (user can reset in 设置). Remaining P0/P1 in this contract (detail header sizing, title long-text, tag chips, cover presentation, list card height) not yet started.
- 2026-06-16 23:25 +0800 — Device-QA keep-awake regression fixed before P0 #3. Claude's P0 #2 QA exposed that `dev.sh --launch` / `--log` did not refresh keep-awake, even though `scripts/sign.py` already called `scripts/keep_awake.sh` around install. Commit `ebdd610` restores V2Next parity in `dev.sh`, adds `scripts/test_devsh_keepawake_contract.mjs`, and registers the harness gate (`devsh-keepawake`, harness now 11/11). Device evidence on `192.168.50.197:12345`: sentinel `OverrideTimeout=60000ms` before launch, `HDC_TARGET=192.168.50.197:12345 bash dev.sh --launch` changes it to `OverrideTimeout=13600000ms`, and deep-link + screenshot keeps `OverrideTimeout=13600000ms`; artifact `/tmp/nexte_qa/p0_keepawake.jpeg`. This is a dev-tooling fix, not a gallery P0 acceptance by itself.
- 2026-06-17 00:03 +0800 — P0 #3 detail preview semantics landed in commit `919fde3` (`feat(gallery): restore eros_fe detail preview modes — grid default + horizontal/hide toggles`). Implementation adds persisted `ThumbnailModeState` / `ThumbnailModeSettings` with both booleans default false (out-of-box GRID), settings switches for `hideGalleryThumbnails` and `horizontalThumbnails`, restores detail preview dispatch to grid / horizontal / hidden-inline, and keeps the all-thumbnails entry reachable. Gates: `scripts/test_thumbnail_mode_contract.mjs`, V1 inventory 0, i18n parity, `dev.sh --build-only`, `.harness/hooks/pre-commit` (12/12). Device QA on `192.168.50.197:12345` used the fixed keep-awake path (`OverrideTimeout=13600000ms`): default GRID shows 4-column inline previews + `更多预览` (`/tmp/nexte_qa/p3_grid.jpeg`), settings exposes both switches (`/tmp/nexte_qa/p3_set2.jpeg`), HORIZONTAL shows `预览 (112) 查看全部 >` + horizontal preview row (`/tmp/nexte_qa/p3_horiz.jpeg`), HIDDEN shows no inline thumbnails and only `更多预览` (`/tmp/nexte_qa/p3_hidden.jpeg`), and AllThumbnails route opens a paged preview grid (`/tmp/nexte_qa/p3_at2.jpeg`). Controller visual contact sheet: `/tmp/nexte_qa/p3_contact_sheet.jpg`. Acceptance boundary: route reachability and core modes are accepted; the AllThumbnails screenshot still shows a left-side underlying/transition strip, so if later work touches this page, recapture a settled full-page screenshot before claiming final page polish.
- 2026-06-17 00:25 +0800 — P0 #3 follow-up (separate commit): responsive preview-grid columns + stable thumbnail tiles. User correction: the restored GRID rendered 4 too-narrow columns on this phone — column count must be DERIVED responsively (≈3 here), not hardcoded — plus a supplement: flat/wide or misdetected-dimension thumbs must not drag the page-number baseline. Added `ResponsiveGrid` (shared util; columns = floor((w+gap)/(minW+gap)), eros_fe max-cross-axis-extent model) keyed on `ThemeConstants.PREVIEW_THUMB_MIN_W=105`; `PullRefreshGridScaffold` gained `minColumnWidth` + an `onCellSize` callback; `GalleryAllThumbnailsPage` dropped hardcoded `columns: 4`; the detail inline GRID measures its pane and derives columns + tile width; a shared `PreviewThumbTile` gives every tile a FIXED frame (width × width*1.4) with the thumb contained+centered (no crop, letterboxed over BG_SUB) and the page number a sibling BELOW the frame. New blocking gate `scripts/test_responsive_grid_contract.mjs` (~1400px-class width→3 + adapts + never hardcoded; stable-frame invariants; first-page retained). Gates: responsive-grid 31 assertions, thumbnail-mode no-regression, harness-verify 13/13, V1 0, `dev.sh --build-only` SUCCESSFUL. Device QA on `192.168.50.197:12345` via `dev.sh --launch`: detail GRID now **3 columns** with uniform-height tiles + aligned page numbers (`/tmp/nexte_qa/p3s_g2.jpeg`); all-thumbnails page likewise 3-col stable tiles (`/tmp/nexte_qa/p3s_at.jpeg`). **BLOCKED**: the flat/wide-thumbnail VISUAL case — every tested AI-art gallery is portrait, so no flat thumbnail appeared to screenshot; the fixed-frame contract enforces the centered-contain + fixed-label behavior structurally until such a gallery is available.
- 2026-06-17 00:33 +0800 — First-page-preview gate RESOLVED (commit `4fdbd47`). Controller flagged a contradiction: the inline-grid screenshot `/tmp/nexte_qa/p3s_g2.jpeg` showed page numbers 31-40 while AllThumbnails showed 1-12. Cause = a scroll-position artifact, NOT a bug: this account's preview page holds 40 thumbs, so the inline grid IS the first preview page (1-40) and the earlier screenshot was scrolled to its bottom (31-40 + `更多预览`), while AllThumbnails showed its top (1-12); both are seeded from the SAME `vm.images` first page. Source chain: `EhApiService.getGalleryDetail` parses the detail `#gdt` first preview block → `GalleryDetailViewModel.images = res.images` (:61) → fed to BOTH the inline grid (`images: this.vm.images`, GalleryDetailPage:238) and `AllThumbnailsParams.firstPage` (`this.vm.images`, :139) → `AllThumbnailsViewModel.seed` `setData(p.firstPage)` (:39). Settled device proof on build `50f52fc`: `/tmp/nexte_qa/p3f3.jpeg` — default-GRID detail with the inline preview starting at pages 1/2/3 (3 columns, stable tiles). Contract `test_responsive_grid_contract.mjs` extended (35 assertions) to lock the seeding chain so the inline grid cannot regress to a non-first-page source. harness-verify 13/13.
- 2026-06-17 00:44 +0800 — P0 detail-header action sizing fixed (commit `ddfa28f`). User report: Read button + favourite sizes uncoordinated (a prior pass only moved position). Root cause from eros_fe grounding (ReadButton = filled pill primary @ gallery_widget.dart:228; GalleryFavButton = bare heart secondary @ gallery_favcat.dart:10) vs NextE: the Read pill was a HARDCODED 36px capsule with a 12px caption label, the favourite was a bare 16px heart + 12px text with no shared height/baseline/weight. Minimal fix: new tokens `ThemeConstants.ACTION_HEIGHT=36` + `ACTION_FAV_ICON=18`; `GalleryHeaderCard` Read pill height→ACTION_HEIGHT (no raw literal) + label CAPTION→BODY (CTA weight), favourite block→ACTION_HEIGHT + vertical-center + heart→ACTION_FAV_ICON (a peer to the pill). Semantics preserved (read/unread/resume via resumeIndex, favcat-slot heart colour, no toggle). `test_detail_header_visual_contract.mjs` extended + REGISTERED as a blocking harness gate (`detail-header-visual`): shared ACTION_HEIGHT used ≥2×, no raw height literal in the action row, heart+read use tokens, both tokens exist. Gates: detail-header-visual, harness-verify 14/14, V1 0, `dev.sh --build-only` SUCCESSFUL. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`**: UNFAVORITED+read header `/tmp/nexte_qa/h_u3.jpeg` (Read pill only, BODY weight, no heart = current unfavourited semantic); FAVORITED header `/tmp/nexte_qa/fav_h2.jpeg` ("高分" favTitle + green favcat heart + 阅读 pill on one coordinated baseline) — reproduced non-destructively by opening an already-favourited gallery from the logged-in account's 收藏 tab (no write op). RESUME state changes only the pill LABEL (继续 PN), identical coordinated geometry (prior evidence `/tmp/nexte_qa/p3f2.jpeg`); not separately re-shot. Stopped here per controller; long-title item NOT started.
- 2026-06-17 01:00 +0800 — P0 detail title long-text stress fixed (commit `30a0b7a`). Root cause: the right column was a FIXED COVER_H (175) holding title(maxLines 4) + JP + uploader + a `Blank()` spacer + the action row; when the text overflowed, the Blank collapsed and the Read/favourite action row was pushed past the card bottom (clipped/overlapping). Minimal structural + budgeted fix: title+JP+uploader wrapped in a `layoutWeight(1)` + `clip(true)` text group; the action row is now a RESERVED fixed-height sibling (the `Blank()` is gone), so the text area can only take space ABOVE it and can never push it out. New `titleMaxLines()` budgets the EN title against COVER_H − ACTION_HEIGHT − JP(2 lines) − uploader(1 line) reserves → 3 lines when both present, more when alone (cap 6), so the title truncates first while JP/uploader/fav/read stay visible. JP stays maxLines(2), uploader maxLines(1) + lineHeight. `test_detail_header_visual_contract.mjs` extended (sections 8–9): locks the layoutWeight+clip group, the reserved action row (no Blank spacer), the budgeted titleMaxLines() method, and a SYNTHETIC worst-case height simulation proving long-title+JP+uploader+action-row all fit COVER_H (catches "maxLines exists but row still pushed"). Gates: detail-header-visual, harness-verify 14/14, V1 0, `dev.sh --build-only` SUCCESSFUL. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`**: a real LONG-EN + LONG-JP + uploader + FAVOURITED gallery (Flock Blue, `/tmp/nexte_qa/lt2.jpeg`) renders EN title bounded to 3 lines (ellipsized) + JP title (2 lines) + uploader `te+p` + `高分` green favcat heart + 阅读 pill — ALL inside the card, no overflow/clip/overlap; the loading state with a 5–6-line title also kept the pill inside (`/tmp/nexte_qa/lt1.jpeg`). Long-uploader is structurally bounded (maxLines 1 + the reserved 1-line budget; test gallery's uploader is short — extreme long-uploader VISUAL not separately shot, covered by structure+contract). RESUME = same pill, label-only (`继续 PN`). Stopped per controller; tag-chips item NOT started.
- 2026-06-17 01:06 +0800 — P1 detail tag-chip shape fixed (commit `594315a`). User report: chips too thin + corner radius too small. eros_fe grounding (`TagButton` @ gallery_widget.dart:585-608: borderRadius 8, padding (6,3,6,4), fontSize 13 / line-height 1.3 → ~24px; namespace label = same TagButton, different colours only) vs NextE: both chips were RADIUS_SM(4) + 3px vertical padding + 12px caption with no lineHeight (~18px flat boxes). Geometry-only fix (new tokens `ThemeConstants.CHIP_RADIUS=10` + `CHIP_LINE_HEIGHT=16`): `GalleryTagsCard` namespace label + member chips → borderRadius CHIP_RADIUS, vertical padding 3→5, + lineHeight CHIP_LINE_HEIGHT; the 1px namespace align-nudge dropped (chips now share geometry). ALL semantics preserved unchanged: namespace tint only on the label, member bg = usertag fill | neutral grey (never namespace) via chipBg(), member text = vote → usertag → neutral via chipText(), ForEach key keeps `tagSig.version` for late My-Tags recolour, Flex wrap density unchanged, no tap added. New blocking gate `scripts/test_tag_chip_contract.mjs` locks CHIP_RADIUS≥8 + ≥5px vpad + lineHeight on both chips (no leftover RADIUS_SM / 3px padding) + the chipBg/chipText/namespace-only/wrap/recolour-key semantics. Gates: tag-chip, harness-verify 15/15, V1 0, `dev.sh --build-only` SUCCESSFUL. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`**: a dense multi-namespace gallery (Shunka Kikaku, `/tmp/nexte_qa/td3.jpeg`) — `作者`/`女性`/`男性` namespace pills with their pastel namespace tints preserved + ~12 wrapped member chips, all clearly rounder + taller/more comfortable than the old flat radius-4/3px-pad chips. **BLOCKED**: per-tag usertag-fill + vote-colour member-chip visual states — the tested galleries have no custom-coloured or voted tags on this account, so neither state was visible to screenshot; both are preserved in source (chipBg/chipText) and locked by the contract. Stopped per controller; cover/list-card items NOT started.
- 2026-06-17 01:22 +0800 — P1 gallery cover presentation fixed (commit `e73186f`). User report: (a) list cover crop is crude horizontal cropping, unlike eros_fe; (b) detail cover has the same crop/fit problem; (c) the loading placeholder background is too close to the list/page background so the card "looks cut in half." eros_fe grounding (CoverImg): the cover sits over a DISTINCT grey backdrop (systemGrey5/6, never the card surface) and is FITTED to a frame whose aspect can differ from the cover's, so the whole cover shows — no crude side-crop; where the frame IS the cover aspect (the grid cell) Cover is correct (nothing to crop). vs NextE: `EhThumbnail` used `ImageFit.Cover` + `backgroundColor(BG_SUB)` in EVERY branch — `BG_SUB`=`sys.color.ohos_id_color_sub_background` ≈ `card_background` (#FFFFFF light / #191919 dark), so an unloaded/short cover blended into the card; and Cover over the list row's tall-when-tag-rich frame and the fixed detail box clipped the cover's sides. Minimal context-specific fix: new DISTINCT token `ThemeConstants.COVER_PLACEHOLDER` → `app.color.cover_placeholder` (light #E6E8EB / dark #2E2E30, both distinct from card_background, added to base+dark color.json); `EhThumbnail` gains `@Param containFit` (default false), every branch's backdrop BG_SUB→COVER_PLACEHOLDER and objectFit hardcoded-Cover→`this.containFit ? Contain : Cover`; the list card (`GalleryCard`) and detail header (`GalleryHeaderCard`) pass `containFit:true` (frame ≠ cover aspect → fit the whole cover over the grey, no crop), the grid card (`GalleryGridCard`) deliberately does NOT (its cell IS the cover aspect). Data flow / click / URLs / cache / spinner overlay all untouched. New blocking gate `scripts/test_cover_presentation_contract.mjs` locks: containFit param exists, every branch backs onto COVER_PLACEHOLDER (never BG_SUB), objectFit is param-driven (never hardcoded Cover), list+detail pass containFit:true while grid does not (no one-size-fits-all), and cover_placeholder is defined in BOTH themes AND distinct from card_background. Gates: cover-presentation, harness-verify 16/16, V1 0, `dev.sh --build-only` BUILD SUCCESSFUL, `.harness/hooks/pre-commit` 16/16. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`**: home list covers now render the WHOLE cover — the tall tag-rich "[pixiv+twitter] Nyogiku" row shows the full standing figure that Cover would have side-cropped (`/tmp/cover_list.jpeg`); the detail header cover renders the full image with no top/bottom crop, Read pill + tag chips + info bar intact, app stable (`/tmp/cover_detail.jpeg`). **Locked-by-contract, not separately device-shot**: the unloaded-placeholder visual (covers load too fast to catch the placeholder state, but the distinct COVER_PLACEHOLDER token is verified in the resources + asserted distinct-from-card in both themes) and the dark-mode backdrop (dark cover_placeholder #2E2E30 distinct from card #191919, contract-asserted). Stopped per controller; list-card height item NOT started — awaiting acceptance.
- 2026-06-17 01:35 +0800 — Controller/user identified another P0 #3 preview-entry acceptance miss while list-card work was paused: the detail preview card header cannot open AllThumbnails in default GRID/HIDDEN modes, forcing users to scroll to/tap only the bottom `更多预览` button. Source cause: `GalleryPreviewGrid.sectionHeader(entry)` only calls `onMore()` when `entry=true`, and GRID/HIDDEN currently pass `false`; comments card and horizontal preview already treat the header as an entry. Required follow-up before resuming list-card: make the preview card header a valid AllThumbnails entry where the visual affordance supports it (no hidden tap target without affordance), preserve bottom MorePreviewButton, grid/horizontal/hidden semantics, and add contract + device QA for header-tap route reachability.
- 2026-06-17 01:38 +0800 — Controller/user identified another P0 #3 stable-tile visual regression: preview thumbnails now appear square/no-radius. Source cause: `PreviewThumbTile` passes `radius: 0` to `EhSpriteThumbnail` in both width-fit and height-fit branches, while the outer fixed frame only has `RADIUS_SM=4`; `EhSpriteThumbnail` itself supports `.borderRadius(this.radius).clip(true)`. Required follow-up before resuming list-card: restore visible rounded corners for detail GRID + AllThumbnails preview tiles without breaking the fixed frame/page-number baseline or flat/wide centered-contain behavior; extend `test_responsive_grid_contract.mjs` so `PreviewThumbTile` cannot pass radius 0, and device QA with screenshots.
- 2026-06-17 01:40 +0800 — Follow-up A (category/type badge geometry) fixed (commit `cf3b9ec`). User report: "画廊详情页里的画廊类型tag还是老的样子." Controller scoped it to the detail info-row category badge in `GalleryInfoBar` (the prior tag-chip pass only covered `GalleryTagsCard`, leaving the badge on the flat RADIUS_SM(4) + SPACE_XS(4) box, no lineHeight — visibly thinner/squarer than the upgraded chips). eros_fe grounding (`GalleryCategory` @ gallery_widget.dart:267-305: borderRadius 6, padding (6,3), fontSize 14.5, white text, category-colour bg). Minimal geometry-only fix tied to the chip token family: new single shared token `ThemeConstants.CHIP_PADDING_V=5` (the comfortable detail-chip vertical padding); `GalleryInfoBar` category badge → borderRadius RADIUS_SM→CHIP_RADIUS(10), + lineHeight CHIP_LINE_HEIGHT(16), vertical padding SPACE_XS→CHIP_PADDING_V; the `GalleryTagsCard` namespace + member chips migrated from the literal `top:5,bottom:5` onto CHIP_PADDING_V too, so the value is single-source (no duplicate magic number; pixel-identical 5→5). Category colour, white text, right-pinned position, all InfoBar semantics unchanged; the dense LIST-card chips deliberately stay snugger at 3px (untouched). Contracts: `test_detail_header_visual_contract.mjs` §3b added (badge uses CHIP_RADIUS not RADIUS_SM + CHIP_LINE_HEIGHT + CHIP_PADDING_V) + CHIP_PADDING_V≥5 token check; `test_tag_chip_contract.mjs` now asserts the chips use the shared CHIP_PADDING_V token. Gates: detail-header-visual, tag-chip, harness-verify 16/16, V1 0, `dev.sh --build-only` BUILD SUCCESSFUL, `.harness/hooks/pre-commit` 16/16. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`**: an AI-art gallery (Kamado Nezuko) detail — the `Misc` category badge now renders as a rounded comfortable pill matching the `原作`/`角色`/`女性`/`其他` namespace pills + the `ai generated` member chip directly below it, with its pink Misc colour preserved (`/tmp/cat_detail.jpeg`). Next in the paused queue: B preview thumbnail rounded corners, C preview-header tap entry, then D resume list-card height.
- 2026-06-17 01:53 +0800 — Follow-up B (preview thumbnail rounded corners) fixed (commit `8435aa6`). User report: "现在缩略图全部没有圆角了？" Source cause confirmed: `PreviewThumbTile` passed `radius: 0` to `EhSpriteThumbnail` in BOTH the height-fit and width-fit branches, so the actual sprite was square; a frame-filling thumb covered the outer frame's RADIUS_SM rounding → read as a hard square tile. Per the controller clarification, the radius must live on the IMAGE/SPRITE itself (not a decorative outer layer): `PreviewThumbTile` now passes `radius: ThemeConstants.RADIUS_SM` into `EhSpriteThumbnail` in both branches (the sprite already does `.borderRadius(this.radius).clip(true)`), same token as the frame so the silhouette is one consistent rounded rect; the frame stays as the neutral letterbox/placeholder surface. NO change to the fixed frame, contain (height-fit vs width-fit, no crop), centered letterbox for flat/wide thumbs, fixed page-number baseline, or the responsive 3-col derivation. Contract: `test_responsive_grid_contract.mjs` §4b added — the tile must never pass `radius:0` and must pass a real theme radius token into the sprite in BOTH branches (explicitly rejects `radius:0` + decorative outer borderRadius); now 37 assertions. Gates: responsive-grid, harness-verify 16/16, V1 0, `dev.sh --build-only` BUILD SUCCESSFUL, `.harness/hooks/pre-commit` 16/16. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`** (default GRID mode, toggles off): detail inline GRID — portrait BORGIA covers (pages 1-3, zoomed `/tmp/round_grid_zoom.png`) AND wide comic pages (pages 25-40, `/tmp/round_more.jpeg` + `/tmp/round_btn.jpeg`) all render with rounded corners, contained/centered in the stable frame (wide pages letterboxed top/bottom over grey), page numbers at a fixed baseline, 3 columns — this also captured the previously-BLOCKED flat/wide-thumbnail visual case (Borgia comic spreads are wider than the frame). AllThumbnails page (opened via the bottom `更多预览`): pages 1-12 rounded 3-col grid with fixed labels (`/tmp/round_all.jpeg`). Both surfaces use the same `PreviewThumbTile`, so the fix is uniform. Next: C preview-header tap entry, then D resume list-card height.
- 2026-06-17 01:59 +0800 — Follow-up C (preview card header = all-thumbnails entry in every mode) fixed (commit `0fbcb4d`). User report: "为什么不能点击缩略图卡片头部进入缩略图页?非要点最下面的按钮?" Source cause: `GalleryPreviewGrid.sectionHeader(entry)` only navigates + shows the `查看全部 >` affordance when `entry=true`, and only HORIZONTAL mode passed true; default GRID and HIDDEN passed `false`, leaving the header a plain non-tappable title so users had to scroll to the bottom `更多预览` button. Minimal fix: all three mode branches now pass `this.sectionHeader(true)`, so the header shows the visible `查看全部 >` affordance and the whole row navigates via `onMore` — no invisible tap target. GRID + HIDDEN still keep the bottom `MorePreviewButton` (two clear entries); HORIZONTAL unchanged. NO change to the three modes, inline first-page peek, stable tiles, responsive 3-col grid, or the hidden/horizontal settings. Contract: `test_thumbnail_mode_contract.mjs` §4b added — no mode leaves the header a non-entry (`sectionHeader(false)` forbidden), all three pass `sectionHeader(true)`, and the entry header shows the visible `detail_view_all` affordance + navigates via `onMore`. Gates: thumbnail-mode, harness-verify 16/16, V1 0, `dev.sh --build-only` BUILD SUCCESSFUL, `.harness/hooks/pre-commit` 16/16. **Device QA on `192.168.50.197:12345` via `dev.sh --launch`** (default GRID): the `预览 (347)` header now shows a blue `查看全部 >` affordance on the right (`/tmp/hdr_view.jpeg`), and tapping it opens the AllThumbnails page (own `预览` title bar + 3-col rounded grid, `/tmp/hdr_all.jpeg`); the bottom `更多预览` button is still present (preserved in code + earlier `/tmp/round_btn.jpeg`). **Paused-queue A+B+C all done — awaiting controller acceptance before resuming D (P1 list-card height).** D NOT started.
- 2026-06-17 09:16 +0800 — **D (P1 list-card fixed/adaptive row height) implemented (commit `26e2dfc`, pushed to `main`).** eros_fe grounding (Explore sweep): `fixedHeightOfListItems` (ehsetting_service.dart:179, **DEFAULT TRUE**; layout_setting_page.dart:251 user toggle, only enabled in list mode; gallery_item.dart `kFixedHeight=204` + fixed-height `TagWaterfallFlowViewBox` vs adaptive `TagBox` wrap; setting is orthogonal to list/simple/grid). NextE was adaptive-only (`GalleryCard` `constraintSize({minHeight: cardMinHeight()})`). **Resumed the paused D stash** (`stash@{0}`: state/settings plumbing only — reviewed, 100% valid, applied as-is and now superseded by this commit; safe to drop): `ListModeState.@Trace fixedHeight=true` (default = eros_fe parity), `StorageKeys.LIST_ITEM_FIXED_HEIGHT='layout.fixedHeightOfListItems'`, `ListModeSettings.restore` (default true) + `setFixedHeight` single-writer → Preferences. New rendering in `GalleryCard`: reads `connectListMode()` reactively (@Trace → live re-lay on toggle); **FIXED** → `constraintSize` min==max `cardMinHeight()` (uniform cover-height rows) + tag block in a `layoutWeight(1).clip(true)` middle so overflow tags clip and the meta row stays foot-anchored; **ADAPTIVE** → prior minHeight-only grow layout with two `Blank()` springs. One shared `tagChips()` @Builder feeds both; **`containFit:true` preserved in BOTH modes** → cover is Contain-over-grey, no stretch / no side-crop (cover-presentation fix intact). `SettingsPage` adds an optional toggle `settings_list_fixed_height` (4 locales; `sys.symbol.rectangle_grid_1x2` two-rows icon) wired to `setFixedHeight`; simple + grid layouts untouched. New blocking gate `scripts/test_list_height_mode_contract.mjs` (22 assertions: default-true, single-writer persistence, FIXED pin+clip vs ADAPTIVE grow, the containFit no-crop invariant, settings wiring, 4-locale label). Gates: list-height-mode, **harness-verify 19/19**, V1 0, i18n 4-locale parity, `dev.sh --build-only` BUILD SUCCESSFUL, pre-commit 19/19. **Device QA on `192.168.50.197:12345`** (same default 表站 list, account ID 2007706): FIXED (default ON — `/tmp/nexte_qa/d_fixed.jpeg`) — three cards at one uniform row height; the 8-tag *Frieren Girls* card clips its tag overflow with rating/Misc/94P/date foot-anchored; covers Contain (full figures, no stretch/crop). Settings (`/tmp/nexte_qa/d_settings.jpeg`) — new 固定列表行高 switch defaults ON, two-rows icon renders correctly. Toggle OFF → ADAPTIVE (`/tmp/nexte_qa/d_adaptive.jpeg`) — the same Frieren card grows to show all 8 tags; covers still contained. Live toggle + persistence verified; toggle restored to default ON after QA. **P1 list-card height DONE.** This was suggested-order item #7 (last); no list-card items remain open in this contract — awaiting controller acceptance.


## Reopened acceptance audit

The previous archive/completed claim is invalid. This file is active again until every documented acceptance gate is either verified solved or explicitly moved to a separate active gate with owner/evidence. Current known status:

| Original active item | Current status | Reason |
|---|---|---|
| P0 sub-tab switching white-screens / reloads | PARTIAL | Home/Toplist/Favorites favcat retention have evidence, but the original gate also named Favorites order, site 表/里 and search filters; older log marked some of these BLOCKED. |
| P0 false 404 on some galleries | PARTIAL | Cookie completeness + MaybeHidden shipped for the provided example, but the original true-404 / ExHentai Sad Panda / full auth matrix was not fully device-verified. |
| P0 detail preview semantics collapsed | PARTIAL | Modes and route entries shipped, but later thumbnail visual acceptance failed per user report; page polish also had prior screenshot caveats. |
| P0 detail header action sizing | PARTIAL | Main read/favorite states have evidence; full read/unread/resume/favorited/unfavorited matrix was not independently re-shot as one acceptance bundle. |
| P0 detail title long-text stress | PARTIAL | Long title case has evidence; extreme long-uploader/state matrix is structurally covered but not fully device-verified. |
| P1 detail tag chips shape | PARTIAL | Shape improved; usertag/vote-colored visual states remained blocked by unavailable data. |
| P1 gallery cover presentation | PARTIAL | Loaded presentation improved; full loaded/loading/error × light/dark matrix was not fully accepted. |
| P1 list card height modes | PARTIAL | Fixed/adaptive shipped, but stash still exists and must be reconciled; this does not close the whole visual contract. |
| Preview thumbnail rounded corners / thumbnail visual correctness | UNSOLVED | User explicitly reports it is not fixed. This overrides the previous doc claim; must be re-investigated with current screenshot/device evidence. |

Do not re-archive this file until the reopened audit is resolved item by item.

## Final completion summary (INVALIDATED; retained as historical record only)

Completed on 2026-06-17 after the final D/P1 list-card fixed/adaptive row-height pass. Final pushed head: `26e2dfc`.

Closed queue items:

- P0 sub-tab reload/white-screen and retained-subtab architecture: `cbb2583`, `c2b91fb`, `7a8287b`, `cb50e47`, `0e5a6f1`, `46ac1a5`.
- P0 false 404 / auth-cookie completeness and MaybeHidden classifier: `3d1bcad`, `667b1c9`, with gate doc archived in `docs/plans/completed/gallery-auth-cookie-completeness-404-gate.md`.
- P0 detail preview modes, responsive preview grid, rounded preview tiles, and preview header route entry: `919fde3`, `4fdbd47`, `8435aa6`, `0fbcb4d` plus related responsive/tile commits recorded above.
- P0 detail header action sizing and long-title stress: `ddfa28f`, `30a0b7a`.
- P1 tag chip shape: `594315a`.
- P1 cover presentation / placeholder contrast: `e73186f`.
- P1 list-card fixed/adaptive row-height modes: `26e2dfc`.

Validation at final D pass: `scripts/test_list_height_mode_contract.mjs`, full harness 19/19, V1 inventory 0, i18n parity, build-only, pre-commit hook, and .197 device QA for fixed/adaptive list rows.
