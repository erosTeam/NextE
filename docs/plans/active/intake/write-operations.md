# Write Operations Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Feature Completion Gap: EH Write Operations Are Still Mostly Missing

Type: feature gap / core product completeness

Priority suggestion: P0/P1

Status: active intake / remote favorite write path implemented pending acceptance / gallery rating write
implemented pending authorized real-submit acceptance / comment vote implemented pending authorized
real-submit acceptance / comment compose-reply implemented pending authorized real-submit acceptance /
own-comment edit implemented pending authorized real-submit acceptance / taggallery vote implemented pending
authorized real-submit acceptance / MyTags existing usertag edit implemented pending authorized real-submit
acceptance / MyTags existing usertag delete implemented pending authorized real-submit acceptance

Source:

- User feedback, 2026-06-20: project effort has been over-spent on repeated Reader/Grid/Search
  rework while practical feature completeness, especially write operations, still lags behind the
  full `eros_fe` client.
- User-named examples: remote site favorites, comment reply, comment voting, gallery rating, and other
  frequently used EH actions.
- Read-only NextE inspection:
  - NextE has strong browsing surfaces: Home/Search/Favorites/Detail/Reader/Settings/Download shells,
    local favorite state, remote favorite browsing, read-only comments, torrent/archiver read surfaces,
    and some non-destructive write-entry affordances.
  - `GalleryCommentsPage` now implements bounded comment write actions: vote up/down, protected
    new/reply composition, and own-comment edit on the full comments page.
  - `GalleryEditTagsPage` now implements protected tag vote actions from the detail title menu's
    `编辑标签` entry. It no longer presents tag editing as a read-only unsupported surface.
  - `GalleryArchiverPage` and download queue flows expose read/queue surfaces but do not complete the
    destructive archive/download submit pipeline.
  - Gallery rating now has a protected `rategallery` path in NextE: it opens an HDS rating sheet,
    requires a selected half-star value before submit, assembles the EH `api.php` request from parsed
    API metadata, applies returned rating state, and publishes a V2 mutation to retained lists.
    Automated QA remains non-destructive and does not click the final submit action without explicit
    authorization.
  - Remote EH favorite now has an in-detail sheet: `EH 收藏` opens favnote + favcat selection with left
    cancel and right confirm. The confirm path submits the EH favorite form and refreshes detail state;
    automated QA still cancels by default because the operation is non-idempotent.
  - Local favorites are implemented separately from remote EH favorite mutation.
- Read-only `eros_fe` comparison:
  - `GalleryFavController` handles add/remove/move favorites with favcat/favnote.
  - Gallery rating is exposed through rating dialog/controller code and updates detail state.
  - `CommentController` covers comment translate, vote up/down, post/edit/reply style actions.
  - `TagInfoController` / `Api.tagGallery` submit `method=taggallery` with `apikey`, `apiuid`, `gid`,
    `token`, `tags`, and `vote`.
  - Archiver and download controllers cover quote/submit/download flows more deeply than NextE.

Scheduling judgment:

- The next major progress should be user-visible feature completion, not another long cycle of Reader
  double-page architecture or repeated visual QA, unless a current P0 defect blocks basic use.
- Prefer bounded write lanes that can reuse the project destructive-write policy:
  1. Comment actions: comment vote, reply/new comment, and own-comment edit are implemented; reopen only
     for acceptance regressions.
  2. Tag/MyTags write actions: taggallery vote, existing MyTags/setusertag editing, existing MyTags
     deletion, and MyTags new-user-tag add are implemented; reopen only for acceptance regressions or
     separately scoped tagset management.
  3. Archiver/download submit and offline executor: high value but larger and riskier; schedule after
     smaller write operations unless the user explicitly prioritizes downloads.

Handled status:

- Gallery rating real write loop: `implemented / pending controller acceptance and authorized real-submit
  verification`. Scope: protected `rategallery` API submit, HDS modal selection UI, detail-state refresh,
  retained Home/Search/Favorites rating mutation, non-destructive simulator verification, and Android
  eros_fe source/device comparison. Remaining gap: final submit was not clicked because EH rating is a
  real account write and still needs an explicitly authorized test target.
- Comment vote up/down: `implemented / pending controller acceptance and authorized real-submit
  verification`. Commit: `e68ec9a feat(gallery): add protected comment voting`. Scope: protected
  `votecomment` API submit, api metadata route plumbing, full-comments up/down footer actions, native
  confirmation before submit, local score/vote refresh from the API response, i18n strings, and
  deterministic contracts. Device evidence: Mate X7 emulator `127.0.0.1:5555`, official signed HAP,
  opened a real gallery with 45 comments, entered full comments, exposed vote buttons, opened the
  `赞成` confirmation dialog, and cancelled. Evidence files live under
  `.hvigor/outputs/comment-vote-write/`. Remaining gap: final vote submit was not clicked because EH
  comment voting is a real account write and still needs an explicitly authorized test target.
- Comment compose/reply: `implemented / pending controller acceptance and authorized real-submit
  verification`. Commit: `df673c9 feat(gallery): add comment compose flow`. Scope: protected
  `/g/{gid}/{token}` form submit with `commenttext_new`, full-comments new-comment title action, detail
  menu entry so zero-comment peeks can still reach the full comments page, reply footer action with
  `@author` plus EH-compatible encoded comment id prefill, HDS `AppModalScaffold` compose sheet, login and
  minimum-length gates, i18n strings, and deterministic contracts. Device evidence: Mate X7 emulator
  `127.0.0.1:5555`, official signed HAP, entered a real gallery, opened detail menu `评论`, opened full
  comments, opened new-comment sheet, typed draft text to verify send-state gating, opened reply sheet and
  verified prefill, then cancelled. Evidence files live under `.hvigor/outputs/comment-compose-write/`.
  Remaining gap: final comment submit was not clicked because EH comments are real account writes and still
  need an explicitly authorized test target.
- Own-comment edit: `implemented / pending controller acceptance and authorized real-submit verification`.
  Commit: `974b698 feat(gallery): support editing own comments`. Scope: full-comments edit footer action
  appears only when `EhCommentParser` sets `canEdit`, edit mode reuses the HDS compose sheet, pre-fills the
  original plain-text comment, labels the sheet as edit, submits the same protected gallery comment form with
  `commenttext_edit` and `edit_comment`, refreshes comments after success, and extends deterministic
  contracts/i18n. FE grounding: Android eros_fe source
  `/Users/honjow/git/eros_fe/lib/pages/gallery/controller/comment_controller.dart` and
  `/Users/honjow/git/eros_fe/lib/network/request.dart` show edit prefill plus
  `commenttext_edit`/`edit_comment`; Android FE was launched via `adb su` and screenshot evidence was
  captured, but the foreground FE state was a rating dialog rather than an editable own-comment sample.
  Device evidence: Mate X7 emulator `127.0.0.1:5555`, official signed HAP, opened a gallery comments page
  and confirmed the current no-comment sample did not expose false edit actions. Evidence files live under
  `.hvigor/outputs/comment-edit-write/`. Remaining gap: final edit submit and edit-sheet screenshot require
  an actual own-comment sample or explicitly authorized test comment creation/editing; no real EH comment was
  edited during automated validation.
- Gallery tag vote: `implemented / pending controller acceptance and authorized real-submit verification`.
  Commit: `eb14d9a feat(gallery): support protected tag voting`. Scope: protected `/api.php`
  `method=taggallery` submit, detail-scraped `apikey/apiuid` retention in `GalleryEditTagsPage`,
  tag-chip action sheet from the detail title menu's `编辑标签` route, up/down actions for unvoted tags,
  withdraw via opposite vote for already voted tags, native confirmation before submit, local tag-vote state
  update after success, i18n strings, and deterministic contract coverage. FE grounding:
  `/Users/honjow/git/eros_fe/lib/pages/gallery/view/taginfo_dialog.dart`,
  `/Users/honjow/git/eros_fe/lib/pages/gallery/controller/taginfo_controller.dart`, and
  `/Users/honjow/git/eros_fe/lib/network/api.dart` (`Api.tagGallery`). Device evidence: Mate X7 emulator
  `127.0.0.1:5555`, official signed HAP, opened Home gallery detail, used the title menu `编辑标签`,
  opened the tag action sheet for `language:chinese`, opened the `赞成标签` confirmation dialog, and
  cancelled. Evidence files live under `.hvigor/outputs/gallery-tag-vote/`. Remaining gap: final tag-vote
  submit was not clicked because EH tag voting is a real account write and still needs an explicitly
  authorized test target.
- MyTags existing usertag edit: `implemented / pending controller acceptance and authorized real-submit
  verification`. Commit: `de990f9 feat(user): edit existing my tags`. Scope: Settings `我的标签` existing-tag edit sheet, protected
  `/api.php method=setusertag` request assembly with `apiuid`, `apikey`, `tagid`, `tagwatch`, `taghide`,
  `tagcolor`, and `tagweight`, HDS `AppModalScaffold` edit UI, native confirmation before submit, current
  tagset reload after success, shared `UserTagStore` update, and `UserTagSignal` bump for retained state.
  FE grounding: `/Users/honjow/git/eros_fe/lib/pages/setting/mytags/eh_mytags_page.dart`,
  `/Users/honjow/git/eros_fe/lib/pages/setting/mytags/eh_usertag_page.dart`,
  `/Users/honjow/git/eros_fe/lib/pages/setting/mytags/eh_usertag_edit_dialog.dart`,
  `/Users/honjow/git/eros_fe/lib/pages/setting/controller/eh_mytags_controller.dart`, and
  `/Users/honjow/git/eros_fe/lib/network/api.dart` (`setUserTag`). Android FE evidence was captured under
  `.hvigor/outputs/mytags-setusertag-fe-comparison/`. Device evidence: Mate X7 emulator `127.0.0.1:5555`,
  official signed HAP, opened Settings `我的标签`, opened an existing `language:chinese` tag edit sheet,
  toggled draft hide/watch state, opened the save confirmation dialog, and cancelled. Evidence files live
  under `.hvigor/outputs/mytags-setusertag-nexte/`. Remaining gap: final `setusertag` submit was not clicked
  because EH usertag editing is a real account write and still needs an explicitly authorized test target.
  New tag creation and tagset create/rename/delete remain out of scope.
- MyTags existing usertag delete: `implemented / pending controller acceptance and authorized real-submit
  verification`. Scope: Settings `我的标签` existing-tag edit sheet now has a HDS modal title-bar trash
  action, native destructive confirmation, and protected `/mytags` form submit using eros_fe's
  `usertag_action=mass` + repeated `modify_usertags[]` fields. On success it reloads the current tagset,
  closes the sheet, and republishes `UserTagStore` / `UserTagSignal` for retained tag-color state.
  FE grounding: `/Users/honjow/git/eros_fe/lib/network/request.dart` (`actionDeleteUserTag`),
  `/Users/honjow/git/eros_fe/lib/pages/setting/controller/eh_mytags_controller.dart`
  (`deleteUserTag`), and `/Users/honjow/git/eros_fe/lib/pages/setting/mytags/eh_usertag_page.dart`
  (`SlidableAction` red trash delete affordance). Android FE evidence was captured under
  `.hvigor/outputs/mytags-delete-fe-comparison/`, including MyTags tagset rows and a row-swiped trash
  action. HarmonyOS simulator evidence was captured under `.hvigor/outputs/mytags-delete-nexte/`:
  opened Settings `我的标签`, opened the existing `language:chinese` edit sheet, clicked the HDS trash
  action, opened the delete confirmation dialog, and cancelled. Remaining gap: final delete submit was
  not clicked because EH MyTags deletion is a real account write and still needs an explicitly authorized
  test target. Tagset create/rename/delete remain out of scope.
- MyTags new usertag add: `implemented / pending controller acceptance and authorized real-submit
  verification`. Scope: Settings `我的标签` HDS title-bar plus action, HDS `AppModalScaffold` add sheet,
  `/api.php method=tagsuggest` candidate lookup, existing-user-tag filtering, candidate fill into the
  `namespace:tag` draft, mutually exclusive watch/hide toggles, weight/color/default-color draft state,
  native confirmation before submit, and protected `/mytags` form submit using eros_fe's
  `usertag_action=add`, `tagname_new`, `tagcolor_new`, `tagweight_new`, `tagwatch_new`, `taghide_new`,
  and `usertag_target=0`. FE grounding:
  `/Users/honjow/git/eros_fe/lib/network/request.dart` (`actionNewUserTag`),
  `/Users/honjow/git/eros_fe/lib/pages/setting/controller/eh_mytags_controller.dart`
  (`reSearch` / `tapAddUserTagItem`), and
  `/Users/honjow/git/eros_fe/lib/pages/setting/mytags/eh_usertag_page.dart` (search mode with existing
  rows and new tag candidates). Android FE evidence was captured under
  `.hvigor/outputs/mytags-add-fe-comparison/`, including search mode with `goat` candidates.
  HarmonyOS simulator evidence was captured under `.hvigor/outputs/mytags-add-nexte/`: opened Settings
  `我的标签`, opened the plus add sheet, typed `goat`, selected `male:goat`, verified stale candidates clear
  after selection, opened the add confirmation dialog, and cancelled. Remaining gap: final add submit was
  not clicked because EH MyTags creation is a real account write and still needs an explicitly authorized
  test target. Tagset create/rename/delete remain out of scope.

Implementation constraints:

- EH writes are non-idempotent. Tests should open dialogs, validate params, and cancel by default.
- Any real submit requires explicit user authorization and should prefer the user's own test gallery or
  a low-risk account-owned surface.
- Do not hide missing write operations behind disabled rows without honest copy. If a row is visible,
  its scope and unavailable behavior must be clear.
- Do not conflate local-only features with EH remote writes. Local favorite removal safety is not a
  substitute for remote favorite add/move/remove.

Acceptance shape:

- For each write lane, FE source grounding identifies the endpoint/action, user-facing control,
  current-value state, and failure handling.
- NextE exposes a discoverable entry, shows current state, confirms destructive action, submits only
  when authorized, refreshes visible state, and reports errors clearly.
- Deterministic contracts cover route/entry visibility, request parameter assembly, auth gating, and
  "no accidental submit during tests."
- Device evidence covers the non-destructive dialog/preview path; real-submit evidence is required only
  when the user explicitly authorizes it.

### Gallery Comment UP And Score Badges Need Unified Low-Weight Styling

Type: UI quality / readability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Implementation:

- Changeset: `00b477b style(gallery): unify comment badges`.
- Added centralized comment badge tokens in `ThemeConstants` and a shared `CommentBadge` builder in
  `GalleryCommentsCard`.
- Changed `comment_uploader` to the short `UP` label in all locales.
- Kept uploader badges branded, changed numeric score badges to neutral/low-weight chips, and preserved
  score-detail click behavior on the full comments page.
- Added `scripts/test_gallery_comment_badge_style_contract.mjs` and updated the score-details contract so
  it no longer expects saturated positive/negative score colors.

Validation:

- FE grounding: Android eros_fe opened through ADB/su. Current public detail did not expose a visible comment
  badge in the captured viewport, so product semantics were grounded from
  `/Users/honjow/git/eros_fe/lib/pages/gallery/view/comment_item.dart` (`_CommentHead` uses the same compact
  pill grammar for `UP` and score) plus screenshots:
  `.hvigor/outputs/comment-badge-style/fe_current.png` and
  `.hvigor/outputs/comment-badge-style/fe_comments.png`.
- NextE device evidence: Mate X7 emulator `127.0.0.1:5555`, official signed HAP installed via hdc outside
  sandbox. Opened a real Home gallery `[Takeda Hiromitsu] Chadou Yamato Nadeshiko NTR...`; comment peek
  showed the branded `UP` badge, full comments showed neutral `+715/+155/...` score badges, and tapping
  `+715` opened the score-details dialog.
- Evidence files:
  `.hvigor/outputs/comment-badge-style/nexte_comments.png`,
  `.hvigor/outputs/comment-badge-style/nexte_full_comments.png`,
  `.hvigor/outputs/comment-badge-style/nexte_score_badge.png`,
  `.hvigor/outputs/comment-badge-style/nexte_score_details.png`.
- Gates: targeted contracts, V1 decorator inventory, i18n parity, `git diff --check`, and official signed
  Hvigor build passed; full contract sweep is rerun before commit.

Source:

- User feedback on gallery detail/full-comments comment badges.

Current behavior:

- Uploader comments show the localized `comment_uploader` badge; Chinese currently reads `楼主`.
- Non-uploader comments in the full comments page show a numeric score badge such as `+3` or `-1`.
- The uploader badge and score badge use different text sizes, padding, and visual weight:
  uploader uses `FONT_SIZE_TINY` with smaller padding; score uses `FONT_SIZE_CAPTION`, Medium weight,
  and larger padding.
- Both badges use the small `RADIUS_SM` corner radius.
- Score badges use saturated semantic colors: positive green and negative red.

Expected behavior:

- Use `UP` for the uploader badge instead of `楼主`.
- Uploader and score badges should share one visual grammar: same height, typography, padding, and radius.
- Badge radius should be more chip-like and better coordinated with the comment bubble, not the very small
  `RADIUS_SM` look.
- The `UP` badge can keep the theme/brand color.
- Score badges should be lower-weight neutral badges. Keep the `+` / `-` text, but do not use strong
  green/red backgrounds because they compete with the comment content.
- Preserve score-details behavior: tapping a score badge on the full comments page still opens score details.

Why this matters:

- The badge is pinned to the comment header's right side, so inconsistent badge size immediately makes the
  comment header look uneven.
- Strong red/green score backgrounds overemphasize community score relative to author/body/time.

Likely modules to inspect:

- `feature/gallery/src/main/ets/components/GalleryCommentsCard.ets`
- `entry/src/main/resources/base/element/string.json`
- `entry/src/main/resources/zh_CN/element/string.json`
- `entry/src/main/resources/en_US/element/string.json`
- `entry/src/main/resources/ja_JP/element/string.json`
- `entry/src/main/resources/base/element/color.json`
- `entry/src/main/resources/dark/element/color.json`

Implementation direction to evaluate:

- Extract or centralize a small comment-badge builder/style inside `GalleryCommentsCard` so uploader and score
  badges cannot drift in size.
- Update `comment_uploader` display text to `UP` across locales unless a locale-specific short equivalent is
  explicitly chosen later.
- Use a shared rounded chip radius, likely `ThemeConstants.CHIP_RADIUS` or a nearby token already used for
  detail chips.
- Keep `UP` on brand background with readable on-brand text.
- Render score badges with neutral/subtle background and secondary/tertiary foreground, not positive/negative
  saturated backgrounds.
- Keep score click affordance and score details dialog on the full comments page.

Acceptance shape:

- Uploader `UP` badge and numeric score badge have matching height, padding, radius, and text weight.
- `UP` remains theme-colored; numeric score is visually quieter and neutral.
- Positive and negative scores no longer use saturated green/red backgrounds.
- Full comments page score badge still opens score details when details exist.
- Detail-page comment peek still suppresses numeric score badges and only shows the uploader `UP` badge when relevant.

### Gallery Comment Peek Cannot Open Full Comments When Only One Or Two Comments Exist

Type: bug / detail-page navigation / reading comments

Priority suggestion: P1

Status: implemented / pending controller acceptance

Source:

- User report, 2026-06-20: when a gallery has only one or two comments, the detail-page comment peek
  cannot navigate to the full comments page. This is unreasonable because the exposed peek rows clamp
  comment body text and there is no expand/collapse affordance; the full comments page is the only way
  to read long comments completely.
- User also expects tapping a broad area of the exposed comment preview to open the full comments page.
  The current header-only target is too thin, especially if there are only a couple of comments.
- Link handling caveat: comments may contain URLs. If native link taps need to remain accessible, use a
  deliberate event/area split, but do not leave the full-page entry as a tiny header-only target.
- Read-only NextE inspection:
  - `GalleryDetailPage.openComments()` already routes to `GalleryComments`.
  - Detail page passes `GalleryCommentsCard({ comments, max: 2, onMore })`.
  - `GalleryCommentsCard.hasMore()` returns `this.max > 0 && this.comments.length > this.max`.
  - Header `onClick` only calls `onMore()` when `hasMore()` is true.
  - `shown()` returns all comments when `comments.length <= max`, so one/two-comment peeks render on the
    detail page but have no full-comments navigation.
  - `CommentRow` currently has no row/card-level click to open full comments.

Observed behavior:

- With three or more comments, the header shows `查看全部` and can open full comments.
- With one or two comments, the detail page still shows truncated/comment-clamped preview rows, but no
  obvious full-page navigation is available.
- Long one/two-comment galleries become hard to read because the peek has `maxLines(4)` and no expand or
  full-page affordance.

Expected behavior:

- Any gallery with at least one parsed comment should have a reliable path from the detail comment peek
  to the full comments page.
- The full comments entry should be broad enough to be comfortable: header row plus comment preview area,
  or at least a clear, visible row/card affordance.
- If URLs inside comment text are tappable through `enableDataDetector`, preserve link activation where
  feasible. A good fallback is making the comment card/background or non-text region open full comments
  while link text keeps URL behavior.
- Full comments page remains the place for complete text, score details, uploader-only filter, refresh,
  and future write actions.

Likely root cause:

- `hasMore()` conflates "there are more than two comments" with "there should be a full comments page
  entry." The latter should be true whenever `max > 0` and `comments.length > 0`, because peek mode clamps
  comment body text even if there are only one or two comments.

Implementation direction:

- Split the concepts:
  - `hasMoreThanPeek()` for `查看全部` / count wording when `comments.length > max`.
  - `canOpenFullComments()` for navigation when `max > 0 && comments.length > 0`.
- Keep or adjust header wording so one/two-comment peeks still communicate full-page availability.
- Add a broad tap target for the comment peek card or each preview row to call `onMore()`.
- Preserve author tap-to-search and URL link behavior as much as ArkUI allows; do not make author/link
  taps accidentally navigate away if the user intended those actions.

Acceptance shape:

- Gallery with one comment: tapping the comment peek opens `GalleryComments`, and the full page shows the
  complete comment text.
- Gallery with two comments: tapping either exposed comment or the comments area opens `GalleryComments`.
- Gallery with three or more comments: existing `查看全部` affordance still works, and the broader peek
  target also works.
- Author tap still searches uploader. URL text inside a comment remains usable or the limitation is
  explicitly documented with a safer tap-area compromise.
- Deterministic contract covers `canOpenFullComments()` independent of `comments.length > max`, and
  protects a broad row/card tap target in peek mode.

Implementation / evidence:

- Commit: `1a2046a fix(gallery): open full comments from peeks`.
- Scope: detail comment peeks with one or two parsed comments now expose the full-comments entry instead
  of requiring `comments.length > max`. The detail menu also keeps a full-comments path for zero-comment
  peeks where the full comments page is still the canonical read/write surface.
- Deterministic gates: `scripts/test_gallery_comment_full_entry_contract.mjs`,
  `scripts/test_gallery_comment_badge_style_contract.mjs`, and
  `scripts/test_v1_decorator_inventory_contract.mjs`.
- Remaining acceptance: controller/user review on a gallery with one/two comments and one with three or
  more comments.

### Gallery Archiver Options Are Not Reachable

Type: feature gap / gallery archive parity

Priority suggestion: P1

Status: implemented / pending device acceptance

Source:

- `eros_fe` exposes the gallery detail `归档` action and opens an archiver options dialog, while
  NextE parsed `archiverLink` but had no route/page/entry for the quote/options page.

Grounding:

- `eros_fe/lib/pages/gallery/view/archiver_dialog.dart` renders `ArchiverView` / `HatHGridView`.
- `eros_fe/lib/common/parser/archiver_parser.dart` parses G/C balance, Download options, and H@H
  resolution options from `archiver.php`.
- FE controller builds `/archiver.php?gid=<gid>&token=<token>&or=<archiverLink>`.

Implementation:

- Added read-only `EhGalleryArchiverQuote` / item model and `EhGalleryArchiverParser`.
- Added `EhApiService.getGalleryArchiver()` for a read-only GET of the archiver quote page.
- Added `GalleryArchiverParams`, `GalleryArchiverPage`, route registration, gallery-module export,
  i18n strings, and a low-weight detail-page `归档` entry when `archiverLink` exists.
- Scope is intentionally non-destructive: no POST, no archive submit/download, no download-queue write,
  no offline reader integration, and no local file creation.

Evidence:

- Android FE comparison: ADB target `fa967a75`, `su` launched `com.honjow.fehviewer`, opened
  `https://e-hentai.org/g/3989982/16600a66e8/`, tapped `归档`, and captured the FE dialog showing
  `G 17,825,119`, `C 16,323,703`, Download options, and H@H options. Screenshot:
  `.hvigor/outputs/archiver-readonly-fe-comparison/fe_archiver_dialog.png`.
- Deterministic contract: `scripts/test_gallery_archiver_readonly_contract.mjs` locks the model,
  parser, API, route, detail entry, i18n, and read-only boundary.
- Gates: `scripts/test_gallery_archiver_readonly_contract.mjs`,
  `scripts/test_gallery_detail_parser_contract.mjs`, `scripts/test_gallery_info_page_contract.mjs`,
  `scripts/test_gallery_torrents_contract.mjs`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, `git diff --check`, and official signed Hvigor build through
  `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened the same public gallery and confirmed the detail page still renders, but the logged-out EH
  response did not expose `archiverLink`, so the `归档` route could not be reached there. Evidence:
  `.hvigor/outputs/archiver-readonly-nexte-smoke/detail.png` and `detail_layout.json`.

Remaining acceptance:

- Needs a logged-in and unlocked HarmonyOS target where EH exposes `archiverLink` to verify the NextE
  `归档` entry and read-only quote page on device. Physical target `192.168.50.200:12345` was connected
  but `aa start` returned `Error Code:10106102 The device screen is locked during the application
  launch, unlock screen failed.`
