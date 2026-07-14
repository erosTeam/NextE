# Gallery Detail And Comments Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- This file is an evidence ledger, not a priority queue. Start from the user's latest request and use `../product-bug-intake.md` for intake writing rules.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Gallery Detail Page Lacks Pull-To-Refresh

Type: bug / UX gap

Priority suggestion: P1

Status: accepted

Implementation:

- `7bc3bde feat(gallery): refresh detail page` added detail-page refresh behavior.
- Scope: `GalleryDetailPage` now exposes the project refresh gesture/path, and
  `GalleryDetailViewModel` owns the reload path so refresh preserves the current gallery identity
  instead of navigating away or creating a second fetch mechanism.

Evidence:

- Deterministic contract: `scripts/test_gallery_detail_refresh_contract.mjs`.
- Implementation commit exists on repository history.
- Current Mate X7 emulator acceptance on `127.0.0.1:5555`, with hdc through the approved DevEco hdc
  path and the current official signed HAP installed: opened public detail
  `https://e-hentai.org/g/3989982/16600a66e8/`, performed a pull-to-refresh gesture, and observed
  `detail_refresh_ok | gid=3989982 images=20 comments=0` in hilog. Before/after layouts stayed on the
  same detail page with header/title/tags/preview intact and no error/empty terminal copy.
- Evidence directory: `/private/tmp/nexte_detail_refresh_acceptance_evidence/`, especially
  `before.png`, `before.json`, `after_logged_pull.png`, and `after_logged_pull.json`.

Remaining acceptance:

- None for the successful refresh path. A live failed-refresh path was not forced on device because it
  would require mutating network/source state; failure feedback remains protected by
  `scripts/test_gallery_detail_refresh_contract.mjs`.

Source:

- User-reported current behavior.

Observed behavior:

- Gallery detail pages do not support pull-to-refresh.

Expected behavior:

- A user should be able to pull down on a gallery detail page to refresh the current gallery detail data.
- Refresh should preserve the current gallery identity and remain on the same detail page.

Why this matters:

- Detail pages can contain dynamic or auth-sensitive data such as favorite state, tags, comments summary, image counts, and availability/error state.
- Without refresh, users must leave and reopen the detail page to retry or update data.

Likely modules to inspect:

- `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets`
- `feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets`
- existing shared pull-refresh components in `shared/src/main/ets/components/`
- eros_fe gallery detail refresh behavior.

Implementation direction to evaluate:

- Add a detail-page refresh gesture using the project's existing pull-refresh scaffold/component pattern.
- Route refresh into the existing detail ViewModel reload path instead of creating a second fetch path.
- Keep current navigation state, gallery params, safe-area behavior, and scroll position rules intentional.
- Ensure loading/error UI does not blank already loaded detail content unless the current project pattern requires it.

Acceptance shape:

- Open a gallery detail page.
- Pull down to refresh.
- The current detail page reloads successfully without navigating away.
- On a failed refresh, the existing detail content should remain usable where possible and show a recoverable error state.

### Gallery Detail Primary Read Action Should Move To FAB / Smart Grip Lane

Type: UX redesign / feature enhancement

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- User-requested gallery detail adjustment: reference Next2V / V2Next, make the read/resume action a FAB,
  and evaluate HarmonyOS smart grip / 智感握姿.
- Already tracked in:
  - `docs/plans/active/controller-work-order-gallery-visual.md` Gate V4 `Detail primary actions redesign`.
  - `docs/plans/active/gallery-visual-navigation-regression-contract.md` lane `detail-primary-actions-redesign`.
  - `docs/plans/active/project-current-state-and-next-plan.md` Lane G `detail-primary-actions-redesign`.

Observed behavior:

- The current detail header still keeps `阅读` / resume as an inline compact capsule inside the header card.
- Header action sizing has partial evidence, but the broader product direction is to move the primary reading
  action out of the cramped header-card action model.

Expected behavior:

- Read/resume becomes the detail page's primary floating action, using a NextE-native FAB pattern.
- Favorite state/actions move to a title/menu/action location or another discoverable secondary-action surface
  instead of competing with the primary read action inside the cover/header card.
- Smart grip / 智感握姿 is evaluated as an enhancement, but the ordinary FAB path must work when the capability
  is unavailable or disabled.
- Follow-up enhancement, 2026-06-20: once the ordinary FAB baseline is accepted, the read/resume FAB
  should consume the same smart-grip / action-alignment model used by Next2V so it can automatically
  move to the detected or selected hand edge. In NextE terms this belongs to the gallery detail FAB,
  not Reader page image/gesture internals.

Why this matters:

- Detail -> Reader is one of the main product flows.
- Keeping the primary action inside the header card competes with title, uploader, cover, favorite state, and
  long-title stress handling.
- A FAB/action redesign can make the read/resume path more discoverable and reduce repeated header-card sizing churn.

Grounding required before implementation:

- Read eros_fe detail action semantics: `ReadButton`, favorite button/state, and how read/resume is weighted.
- Read V2Next / Next2V reply-FAB and title/menu action patterns as the HarmonyOS architecture reference.
- Verify HarmonyOS smart grip / 智感握姿 APIs through `harmony-next` or official docs before proposing code.
- Decide the ordinary FAB fallback first; do not make smart grip a prerequisite for the usable path.
- Preserve existing Reader launch, resume index, favorite-state visibility, and non-destructive favorite handling rules.

Likely modules to inspect:

- `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets`
- `feature/gallery/src/main/ets/components/GalleryHeaderCard.ets`
- `feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets`
- `shared/src/main/ets/model/RouteParams.ets`
- `entry/src/main/ets/pages/Index.ets`
- V2Next / Next2V detail or reply FAB components and title/menu action primitives.
- Next2V smart-grip/action-alignment references:
  - `/Users/honjow/git/V2Next/shared/src/main/ets/services/MotionHandStateService.ets`
  - `/Users/honjow/git/V2Next/shared/src/main/ets/state/MotionHandEdgeState.ets`
  - `/Users/honjow/git/V2Next/shared/src/main/ets/state/MotionReplyAlignmentState.ets`
  - `/Users/honjow/git/V2Next/shared/src/main/ets/settings/ReplyActionAlignmentSettings.ets`
  - `/Users/honjow/git/V2Next/feature/detail/src/main/ets/pages/TopicDetailPage.ets`

Implementation direction to evaluate:

- Remove read/resume from the detail header card only after the replacement FAB path is ready.
- Add a primary FAB that launches Reader with the same current start/resume behavior.
- Move favorite affordances to title/menu/action semantics with clear current-state feedback.
- Add capability-checked smart grip support as an enhancement, with ordinary FAB fallback.
- Keep this separate from cover presentation, list responsive cover sizing, SearchFilter, Reader gesture, and auth-cookie-login lanes.

Implementation:

- `feature/gallery/src/main/ets/components/GalleryHeaderCard.ets` no longer owns read/resume state,
  exposes no `onRead`, and renders no inline read capsule inside the dense cover/title header.
- `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` now owns a bottom-right capsule FAB that
  reuses the existing `openReader(this.resumeIndex())` path and the existing read/resume strings. The
  detail list reserves `SPACE_XXL + BUTTON_HEIGHT` bottom padding so the final content can scroll clear
  of the floating action.
- Ordinary FAB fallback is the only implemented path in this stage. Local `harmony-next` offline refs did
  not expose a `智感握姿` / smart-grip API hit, so no smart-grip code was introduced.

Acceptance shape:

- Detail first-read state: FAB launches Reader from page 1, without covering critical content or bottom gesture areas.
- Detail resume state: FAB clearly shows resume intent and opens the saved page.
- Favorited/unfavorited states remain discoverable after favorite controls leave the header card.
- Ordinary FAB layout works on devices without smart grip support.
- If smart grip is implemented, it has a capability check and does not break the ordinary FAB path.
- If smart grip/action alignment is implemented, switching fixed-left/fixed-right/follow-operation/smart-grip
  settings moves the detail read/resume FAB side without changing Reader launch or resume-index behavior.
- Device/simulator evidence covers at least first-read and resume states, plus available favorite-state evidence.

Evidence:

- FE grounding: eros_fe `ReadButton` at `lib/pages/gallery/view/gallery_widget.dart`, header placement at
  `lib/pages/gallery/view/header.dart` and `lib/pages/gallery/view/sliver/header_sliver.dart`, plus the
  sliver trailing read action at `lib/pages/gallery/view/sliver/gallery_page.dart`.
- Android FE reference: ADB target `fa967a75`, `su` launched `com.honjow.fehviewer/.MainActivity`, and
  a same-gallery detail screenshot was captured at
  `/private/tmp/nexte_detail_primary_fab_fe_reference/fe_detail.png`.
- Deterministic contracts: `scripts/test_gallery_detail_primary_fab_contract.mjs`,
  `scripts/test_gallery_detail_refresh_contract.mjs`, `scripts/test_gallery_detail_seed_cover_contract.mjs`,
  and `scripts/test_v1_decorator_inventory_contract.mjs`.
- Build: official signed Hvigor build through `scripts/build_hvigor_signed.sh` passed; no `dev.sh`.
- Device: Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, signed HAP installed. Deep link
  opened `https://e-hentai.org/g/3989982/16600a66e8/`; layout showed bottom-right FAB `继续 P2` at
  `[828,2296][980,2347]`, and clicking it opened Reader at `2 / 138`. Evidence directory:
  `/private/tmp/nexte_detail_primary_fab_acceptance/` (`detail_fab.png`,
  `detail_fab_layout.json`, `detail_fab_color.png`, `detail_fab_color_layout.json`,
  `reader_after_color_fab.png`, `reader_after_color_fab_layout.json`).

Remaining acceptance:

- Needs controller visual acceptance of the FAB placement and overlay behavior.
- First-read state and logged-in favorite action migration remain follow-up evidence/work. This stage keeps
  favorite state discoverability through existing detail info surfaces and does not perform destructive
  favorite writes.

### Gallery Detail Title Menu Needs More Actions

Type: UX enhancement / menu IA

Priority suggestion: P1

Status: implemented / needs controller acceptance

Implementation:

- Changeset: `d40ea05 feat(gallery): expand detail title menu`.
- Expanded `GalleryDetailPage.detailMenu()` so HDS keeps local favorite and share inline while refresh and
  power-user actions move into the overflow menu with `maxCount: 3`.
- Added non-destructive overflow actions for refresh, edit tags, copy gallery link, copy gallery title,
  external browser open, and internal WebView open.
- Added `GalleryWeb` and `GalleryEditTags` routes. The original edit-tags entry refetched and displayed
  current tags as a read-only surface; the later tag-vote follow-up below upgrades that route into a
  protected write surface.
- Follow-up: `eb14d9a feat(gallery): support protected tag voting` upgraded `GalleryEditTags` from the
  original read-only route into a protected tag vote surface. It opens an HDS action sheet from a tag chip,
  confirms before posting `/api.php method=taggallery`, and cancels during automated validation. This
  follow-up still does not implement freeform tag suggestion/add or MyTags/setusertag editing.
- Added deterministic coverage in `scripts/test_gallery_detail_menu_actions_contract.mjs`, and relaxed older
  refresh/local-favorite menu contracts so they preserve the new overflow behavior instead of requiring the
  obsolete three-item menu.

Validation:

- FE reference: Android eros_fe detail page captured through ADB/su at
  `.hvigor/outputs/gallery-detail-menu-actions/fe_current.png`.
- NextE device evidence: Mate X7 emulator target `127.0.0.1:5555`, official signed HAP install, detail deep
  link opened, overflow menu captured with `刷新`, `编辑标签`, `复制链接`, `复制标题`, `浏览器打开`, `应用内网页`.
- Edit-tags device evidence: `.hvigor/outputs/gallery-detail-menu-actions/nexte_edit_tags_onready_final.png`
  shows the route receives params, refetches detail tags, and displays namespace/tag chips in read-only mode.
- Tag-vote follow-up evidence: `.hvigor/outputs/gallery-tag-vote/tag_page.png`,
  `.hvigor/outputs/gallery-tag-vote/tag_sheet.png`, and
  `.hvigor/outputs/gallery-tag-vote/tag_confirm.png` show the current edit-tags route, action sheet, and
  protected confirmation dialog. No real EH tag vote was submitted.
- Gates: gallery detail menu contract, V1 decorator inventory, i18n duplicate check, `git diff --check`, and
  official signed Hvigor build passed during implementation; full contract sweep is rerun before commit.

Known follow-up:

- Internal WebView launch/content loading: `implemented / pending controller acceptance`. Commits:
  `fix(gallery): guard internal web route loading` and follow-up `fix(gallery): load internal web content`
  in current main history. Scope: `GalleryWebPage` consumes `GalleryWebParams` from
  `NavDestinationContext.pathInfo.param` in `onReady`, waits for both route params and the ArkWeb
  controller before loading, guards against `loadUrl('')`, injects the app EH cookie jar into ArkWeb,
  and safe-loads the target URL after `EntryAbility` initializes ArkWeb. Contract:
  `scripts/test_gallery_detail_menu_actions_contract.mjs`. Device evidence: Mate X7 emulator target
  `127.0.0.1:5555`, official signed HAP, Home -> first gallery detail -> overflow -> `应用内网页`; `aa dump`
  kept `com.erosteam.nexte` foreground. `.hvigor/outputs/gallery-webview-open/` shows the route opening
  without crashing, and `.hvigor/outputs/gallery-webview-content/` shows live EH gallery DOM content in
  the WebView layout (`Front`, `Watched`, gallery titles, tags, pagination, thumbnail links).

Source:

- User feedback on current gallery detail title actions.
- Current right-side actions are local favorite, share, and refresh. Refresh is somewhat redundant with
  pull-to-refresh, but still useful when scrolled near the bottom.
- User clarified HDS menu behavior: with `maxCount: 3`, adding a fourth item makes the third visible slot
  become the overflow menu button. The menu then contains the third-plus remaining actions.
- User requested considering Next2V-style actions such as external browser open and internal WebView open,
  and adding an edit-tags entry even if the write-flow design is not complete yet.

Current behavior:

- `GalleryDetailPage.detailMenu()` returns three title-bar actions with `maxCount: 3`:
  local favorite, share, and refresh.
- Because there are exactly three actions, all three render inline today.

Expected behavior:

- Keep the title bar visually compact: when more actions are added, only the highest-priority two actions
  should remain inline, with the third slot becoming the HDS overflow menu.
- Local favorite and share are the likely inline actions.
- Refresh should move into overflow when extra actions exist.
- Add overflow actions for:
  - refresh;
  - edit tags;
  - copy gallery link;
  - copy gallery title;
  - open in external browser;
  - open in internal WebView.

Why this matters:

- The detail page needs common power-user actions without crowding the title bar.
- HDS already gives a native overflow model; NextE should use that instead of adding custom buttons or
  additional visible chrome.
- External/internal web open gives users an escape hatch for EH pages that native parsing or feature parity
  has not caught up with yet.

Grounding required before implementation:

- Inspect V2Next / Next2V topic detail menu actions, especially `copyTitle`, `copyLink`, `share`,
  `openInApp`, and `openBrowser`.
- Inspect NextE's existing `ShareUtil`, `EhWebView`, login WebView page, route registration, and title-menu
  helper patterns.
- Decide menu ordering with the HDS `maxCount: 3` overflow behavior in mind; do not assume three actions
  stay inline after adding a fourth item.
- Preserve the existing FAB read/resume behavior and do not move read back into the title menu.

Implementation direction to evaluate:

- Build a stable gallery URL helper for `/g/{gid}/{token}/` using current site mode.
- Add copy-link and copy-title actions with toast feedback.
- Add external browser open via a system view-data Want, using the same safe URL.
- Add a generic internal EH WebView route/page before wiring "open in internal WebView"; reuse `EhWebView`
  and the proven UA/cookie boundary from the login WebView where appropriate.
- Add an edit-tags menu entry that opens a native sheet/page skeleton. Do not perform EH tag write operations
  in this lane unless a separate destructive-write flow is explicitly designed and authorized.

Edit-tags boundary:

- The entry is allowed as a visible menu item.
- The current implementation supports protected tag voting through `taggallery`; it must not silently submit
  without the explicit confirmation dialog.
- Freeform tag suggestion/add and `setusertag`/MyTags editing remain out of scope for this detail-menu item
  unless a separate destructive-write lane is opened.
- Future real tag editing must follow the project destructive-write boundary: explicit user action,
  confirmation where appropriate, and test-gallery/device evidence.

Acceptance shape:

- With more than three title actions, the title bar shows only the intended inline actions plus overflow.
- Refresh remains available from overflow.
- Copy link and copy title work and give user feedback.
- External browser open launches the gallery URL through the system.
- Internal WebView open displays the gallery page in-app, or is clearly marked blocked until the generic WebView
  route exists.
- Edit-tags opens a non-destructive entry surface and does not submit any write operation.

### Gallery Detail Long Title Needs Full-Text Access

Type: low-priority UX optimization / detail readability

Priority suggestion: P3

Status: implemented / pending device-controller acceptance

Source:

- User feedback, 2026-06-20: after moving the favorite and read actions out of the detail header, the
  header has more room for title information. Some gallery titles are still long and currently truncate
  with an ellipsis, making the full title hard to inspect from the detail page.
- User proposal: consider making the title area a scrollable container so the full title can be viewed.
- User explicitly marked this as a supplemental low-priority optimization that can be scheduled later.

Design judgment:

- Full-title access is useful, but it should not interrupt the current feature-completion queue
  (remote favorites, rating write, comments, Settings shell audit).
- A horizontally scrollable title area is technically plausible, especially now that read/favorite are
  no longer competing inside the header card, but it has interaction risks:
  - horizontal drag can feel odd inside a vertically scrolling detail page;
  - scrollable text discoverability is weak if there is no affordance;
  - title text may be used for copy/search flows, so copy-title and overflow actions should keep working.
- Alternatives to evaluate before implementation:
  - allow the header title to expand to more lines because action pressure was reduced;
  - tap the title or a small affordance to open a full-title sheet/dialog;
  - keep the compact ellipsis but make `复制标题` / full-title preview easy from the title/menu action;
  - use a constrained horizontal scroll only inside the title text area if it proves comfortable on
    device.

Expected behavior:

- The compact detail header remains stable and does not grow unpredictably for very long titles.
- Users have an obvious way to inspect or copy the full gallery title without leaving the detail page.
- The solution must not reintroduce read/favorite actions into the header card or crowd title actions.

Acceptance shape:

- Test with at least one very long title on phone-width and foldable/tablet-width layouts.
- Confirm full title can be inspected without breaking vertical detail-page scrolling.
- Confirm copy-title action still works and title truncation/expansion does not cause header cover or
  tag/comment layout shifts.

Implementation:

- Detail header title text now opens a close-only HDS `AppModalScaffold` sheet with the
  full display title and optional alternate title.
- Scope: the compact detail header still truncates long titles inside the fixed cover-height layout;
  uploader tap/search and existing copy-title menu action remain separate.
- Explicitly not done: horizontal title scrolling, header expansion, Reader/Favorites/Search changes,
  or moving read/favorite actions back into the header.

Validation:

- Deterministic contract: `scripts/test_gallery_detail_full_title_contract.mjs`.
- Current HarmonyOS simulator smoke on local `127.0.0.1:5555`: installed the signed HAP, opened a Home
  gallery detail page, confirmed the title group is a separate clickable node from uploader, tapped the
  title, and verified the HDS modal sheet shows `完整标题`, `显示标题`, and the full title text. Evidence:
  `.hvigor/outputs/detail-full-title-sheet/detail_layout.json`,
  `.hvigor/outputs/detail-full-title-sheet/detail.png`,
  `.hvigor/outputs/detail-full-title-sheet/sheet_layout.json`, and
  `.hvigor/outputs/detail-full-title-sheet/sheet.png`.
- Controller acceptance still needed on a deliberately long-title gallery sample.

### Gallery Detail Tags Do Not Jump To Search

Type: feature gap / UX gap

Priority suggestion: P1

Status: accepted

Implementation:

- `45bc895 feat(gallery): search from detail tags` wires gallery detail tags into the shared Search
  route/action path.
- Scope: `GalleryTagsCard` tag taps dispatch through the existing shared search/navigation path
  rather than adding a separate detail-only search implementation.
- `f01e71a fix(gallery): format detail tag searches` closes the follow-up query-format/action-focus
  gap: multi-word detail tags now publish quoted EH field queries, and action-seeded Search opens
  results-first without requesting IME focus.

Evidence:

- Deterministic contract: `scripts/test_tag_chip_contract.mjs`.
- Current contracts/gates: `scripts/test_tag_chip_contract.mjs`,
  `scripts/test_detail_people_search_contract.mjs`, `scripts/test_search_input_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  and `git diff --check`.
- Official signed build: `bash scripts/build_hvigor_signed.sh`.
- Current Mate X7 emulator pass on `127.0.0.1:5555` with hdc outside the sandbox: opened a gallery
  detail page, tapped the female `big breasts` tag, verified Search opened with
  `female:"big breasts"`, result list loaded, no IME/keyboard bundle took focus, and Back returned to
  the same detail page. Evidence directory: `/private/tmp/nexte_detail_tag_query_evidence/`,
  especially `detail_tag_detail.json`, `detail_tag_search.json`, `detail_tag_search.png`,
  and `detail_tag_back_detail.json`.

Remaining acceptance:

- None for the current tag-query/action-focus scope unless this detail tag, Search action bus, or
  Search title field path changes again.

Regression watch, 2026-06-20:

- User re-raised the UX expectation: tapping a detail tag should mean "show me results for this tag",
  not "open a focused search composer". The keyboard must not appear for action-seeded tag/uploader/
  similar searches.
- This was previously accepted in `f01e71a` and device evidence said no IME focus. If a current build
  again opens the keyboard from a tag tap, treat it as a regression against the accepted
  action-seeded-search contract, not as a new feature request.
- Contract/device acceptance should explicitly cover: detail tag tap -> Search field displays the tag
  query, results run automatically, `focusOnAppear=false`, and the IME/keyboard stays hidden.

Source:

- User-reported missing behavior.

Observed behavior:

- Tapping a tag on the gallery detail page does not appear to jump to a search for that tag.

Expected behavior:

- Tapping a detail tag should open the shared Search page with an appropriate tag query seeded and executed.
- Namespace-aware tags should preserve the correct EH search syntax.

Why this matters:

- Tag-to-search is a high-frequency discovery path in EH-style browsing.
- Without it, users cannot naturally pivot from a gallery detail page to related galleries by tag.

Likely modules to inspect:

- `feature/gallery/src/main/ets/components/GalleryTagsCard.ets`
- `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets`
- `shared/src/main/ets/state/SearchActionState.ets`
- `feature/search/src/main/ets/pages/GallerySearchPage.ets`
- eros_fe detail tag tap / search query formatting behavior.

Implementation direction to evaluate:

- Wire detail tag tap into the existing shared search action bus rather than creating a second search route.
- Preserve namespace-qualified query formatting based on eros_fe behavior.
- Push or focus the shared Search page in normal gallery scope, not favorite scope.
- Keep My Tags / usertag color display behavior separate from navigation behavior.

Acceptance shape:

- Open a gallery detail page with namespaced tags.
- Tap a tag.
- Search page opens with the correct query visible in the title-bar field.
- Results load for that tag query.
- Returning to the detail page should keep normal navigation behavior.

### Gallery Comment Footer Icons And Spacing Need Native Semantics

Type: UX polish / parity gap

Priority suggestion: P1

Status: reopened / current implementation rejected by device screenshot

Source:

- User feedback, 2026-06-21: comment vote controls should not use generic up/down arrows. The desired
  semantics are thumbs up / thumbs down, matching the original comment tail behavior.
- User feedback, 2026-06-21: full comments page action buttons are visually much too spread out. In the
  current screenshot, the three footer icons leave enough horizontal room between them to fit another
  button, while the Next2V reference keeps like/reply/more actions grouped at a compact, readable rhythm.
- User feedback, 2026-06-21: vote icons have since changed to thumbs, but edit and reply still appear to
  use the same document icon; icon spacing and the excessive bottom height remain unresolved.

Research:

- HarmonyOS system symbols already provide the needed native resources in the installed SDK:
  - `$r('sys.symbol.hand_thumbsup')`
  - `$r('sys.symbol.hand_thumbsup_fill')`
  - `$r('sys.symbol.hand_thumbsdown')`
  - `$r('sys.symbol.hand_thumbsdown_fill')`
  - `$r('sys.symbol.ellipsis_message')` for reply/comment thread action
  - `$r('sys.symbol.square_and_pencil')` for own-comment edit
- `SymbolGlyph` supports common transform attributes such as `.rotate({ angle: 180 })`, but rotation is
  unnecessary here because a real thumbs-down symbol exists.
- eros_fe uses outline thumbs for neutral state and solid thumbs for the selected vote state:
  `FontAwesomeIcons.thumbsUp` / `solidThumbsUp` and `thumbsDown` / `solidThumbsDown`.

Implemented behavior:

- `GalleryCommentsCard.VoteAction` keeps the native thumb symbols from the vote lane.
- `GalleryCommentsCard.EditAction` now uses `$r('sys.symbol.square_and_pencil')`.
- `GalleryCommentsCard.ReplyAction` now uses `$r('sys.symbol.ellipsis_message')`.
- Footer icon and sizing changes are verified in the rendered comments path, not by source-shape assertions.
- Footer actions use compact local hit/visual sizing so the secondary action cluster no longer reserves
  primary-button-sized boxes.

Verification:

- `node scripts/test_v1_decorator_inventory_contract.mjs`
- `scripts/build_hvigor_signed.sh`
- Local simulator `127.0.0.1:5555` screenshot:
  `.hvigor/outputs/comment-footer-actions/full3.png`

Expected behavior:

- Upvote neutral state uses `hand_thumbsup`; selected upvote uses `hand_thumbsup_fill`.
- Downvote neutral state uses `hand_thumbsdown`; selected downvote uses `hand_thumbsdown_fill`.
- Do not rotate `hand_thumbsup_fill` to fake a downvote.
- Reply uses `ellipsis_message`.
- Own-comment edit uses `square_and_pencil`.
- The footer actions should be compactly grouped, closer to the Next2V comment reference: enough hit area
  to tap, but no large dead-looking gaps between like/dislike-or-reply/edit/reply icons. Prefer a small
  local action-cluster width/padding adjustment over changing the whole comment-card spacing.
- Keep this scoped to comment action icons and compact footer sizing; do not redesign the full comment
  composer or avatar system in the same patch unless that lane is explicitly opened.

Acceptance shape:

- A comment with no vote shows outline thumbs up/down.
- A comment with an upvote shows filled thumbs up and outline thumbs down.
- A comment with a downvote shows outline thumbs up and filled thumbs down.
- Reply and edit have distinct symbols: `ellipsis_message` and `square_and_pencil`.
- The footer action row does not add excessive bottom height compared with the comment text/time row.
- The three visible footer actions are visually grouped; there is not enough empty space between adjacent
  action icons to look like a missing fourth button.

### Gallery Comments Need Bottom Floating Reply Composer

Type: UX redesign / comment write surface

Priority suggestion: P1

Status: implemented / pending controller acceptance

Source:

- User feedback, 2026-06-22: the full comments page title action / reply entry still feels wrong. A
  comment reply should not be represented primarily by a strange top-right button or a generic half-modal.
- Desired direction: use a bottom-attached floating reply composer that feels closer to a chat input area.
  When replying to another comment, show a compact quoted preview with the target author/comment excerpt and
  a clear cancel affordance; sending creates a new reply/comment, not an inline edit of the quoted row.
- Visual references: Telegram-style rounded floating input/reply preview and eros_fe's existing bottom
  comment text field. Do not copy Telegram chrome wholesale and do not force a flat Eros FE clone; combine
  the rounded floating container with NextE/HDS visual language.
- User feedback, 2026-06-22 after implementation attempt: the current composer is not visually floating
  and does not correctly avoid the soft keyboard. The screenshot shows a large blank white area between the
  input row and keyboard, with the composer behaving like an oversized in-page bottom panel rather than a
  compact floating bar attached above the keyboard.
- User feedback, 2026-06-22 follow-up: tapping a row reply action does not automatically focus the input /
  raise the keyboard, and the two-line quoted reply header is not left-aligned.

Research:

- eros_fe grounds the interaction model:
  - `lib/pages/gallery/view/comment_page.dart` renders a bottom comment text field with `_buildOriText`
    above the input for edit/reply state, a multiline text controller, focus node, and a send button.
  - `lib/pages/gallery/view/comment_item.dart` triggers `commentController.reptyComment(reptyCommentId:
    galleryComment.id!)` from each comment row's reply icon.
- NextE already has protected comment submit/reply plumbing. This lane should mostly replace the
  presentation surface and state transitions, not invent another comment write API path.

Expected behavior:

- Full comments page exposes one persistent bottom composer entry, visually separated from the scroll list
  and safe-area aware.
- Tapping a row reply action switches the composer into reply mode, shows a quoted preview of the target
  author/comment, focuses the input, and allows cancelling back to plain new-comment mode.
- Plain new comment and reply share the same composer surface and send-state gating.
- Own-comment edit may reuse the same composer pattern only if it remains clearly labelled as edit and
  cannot be confused with replying. If that would enlarge the patch, keep edit on the existing path and
  only redesign new/reply first.
- Preserve current non-destructive QA rule: opening/typing/cancelling can be validated; final EH comment
  submit still needs explicit authorization.

Acceptance shape:

- The full comments page no longer relies on a top-right reply/new-comment button as the primary compose
  interaction.
- Replying to a comment shows a quoted/cancellable context above the text input.
- Cancelling a reply clears the quote and returns to plain new-comment mode without losing the page state.
- Keyboard appearance and safe-area padding do not cover the send button or hide the active quote.
- Existing comment vote, uploader-only filter, score badge, and footer icon behavior remain unchanged.

Implementation note:

- Implemented in `feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets` as a bottom floating
  `CommentComposer()` for plain new comments and row replies. Own-comment edit intentionally remains on
  the existing sheet path to keep this lane narrow.
- UI validation uses the signed build and captured device path.
- Device evidence on local HarmonyOS emulator `127.0.0.1:5555`: comments page composer
  `.hvigor/outputs/comment-floating-composer/comments-final.jpeg`; reply mode with quoted preview
  `.hvigor/outputs/comment-floating-composer/comments-reply.jpeg`.
- No final EH comment submit was executed.

Regression evidence / likely cause:

- Current code evidence in `GalleryCommentsPage.CommentComposer()`: the composer is a child of
  `Stack({ alignContent: Alignment.Bottom })`, but it is not positioned as a compact overlay above the
  keyboard. Instead, its bottom padding adds `layout.bottomAvoidHeight + layout.keyboardHeight`, so the
  keyboard height inflates the composer container itself. That explains the current screenshot: the white
  card grows upward and leaves a huge empty body instead of moving a compact floating input bar above the
  input method.
- Next2V grounding corrects the fix direction: do not manually compute a keyboard-height offset for this
  surface. `TopicEditorPage` sets `getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)` before
  editing and restores `KeyboardAvoidMode.OFFSET` on disappear, so the page compresses above the keyboard
  and the TextArea/caret tracking remains usable. Its contract explicitly forbids padding by
  `keyboardHeight` because `RESIZE` already excludes the keyboard. Sheet-like surfaces use
  `SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE` in `BindSheetHelper.defaultSheetOptions()`.
- `layout.keyboardHeight` may still be used as a boolean-style signal that the keyboard is open, for
  example to choose a small bottom gap, but it should not be added as a large padding/height/offset that
  creates a keyboard-sized blank strip.
- Focus evidence: ArkUI `TextArea` supports focus control, and the project already has the right pattern in
  `AppSearchField`: assign a stable `.id(...)`, then defer
  `getUIContext().getFocusController().requestFocus(id)` until the field is mounted. Reply mode should use
  the same idea for the composer input instead of expecting the user to tap the field manually.
- Alignment evidence: ArkUI `align` defaults can center text-related components. The quote/header container
  and both quote text lines should explicitly use start alignment (`alignItems(VerticalAlign.Start)` /
  `textAlign(TextAlign.Start)` or equivalent local pattern) so the author line and excerpt line share a
  clean left edge.

Reopened acceptance:

- The composer must remain a compact rounded floating container; it must not expand to fill the space
  between the list and keyboard.
- When the soft keyboard appears, the composer sits immediately above it with only normal spacing/safe-area
  clearance.
- Keyboard avoidance should be platform-driven through `KeyboardAvoidMode.RESIZE` or the relevant sheet
  `SheetKeyboardAvoidMode`, not a hand-rolled `keyboardHeight` geometry calculation.
- The comments list remains visible behind/above the composer where space allows; the page should not turn
  into a mostly blank white panel.
- Device evidence must include keyboard-open screenshots for plain new-comment mode and row-reply quote
  mode. A screenshot without the keyboard is insufficient for acceptance.
- Tapping a comment's reply action automatically focuses the composer input and opens the soft keyboard.
- The quoted reply header's author line and excerpt line are left-aligned with each other and with the
  input content start; they must not appear centered.

### Gallery Comment Reply References Need Parsed Floor Quote Display

Type: comment parity gap / read presentation

Priority suggestion: P2

Status: implemented / pending real-comment acceptance

Implementation:

- `GalleryCommentsCard` now parses the existing NextE reply marker forms before rendering:
  `@author #commentId#` and the newline BCD-style dot/dash code written by the current reply composer.
- Resolution is conservative: the quoted floor is rendered only when the target `commentId` is present in
  the currently loaded comments. If the id cannot be resolved, the raw comment text is preserved.
- Resolved reply markers are stripped from the visible body and a compact quoted-floor block is rendered
  above the comment body with referenced author and excerpt.

Verification:

- `node scripts/test_gallery_comment_full_entry_contract.mjs`
- `node scripts/test_v1_decorator_inventory_contract.mjs`
- `scripts/build_hvigor_signed.sh`
- Local emulator smoke opened a gallery detail page from a fixed deep link after installing the signed HAP:
  `.hvigor/outputs/comment-reply-reference-smoke/screen.png`.

Remaining acceptance:

- Needs a real comment sample containing a reply marker on a loaded full comments page, or an authorized
  safe fixture path, to visually confirm the quoted-floor block against production EH data.

Source:

- User feedback, 2026-06-22: after the bottom reply composer was repaired, verify whether replies also
  reference the replied floor like LFE. LFE writes an `@user` prefix plus an encoded comment id so the
  referenced floor can be located accurately.

Research:

- NextE currently implements the send-side marker only. `GalleryCommentsPage.encodeCommentId()` maps each
  digit to a 4-bit dot/dash code, and `openReplyComment()` pre-fills the composer with
  `@author\nencodedCommentId\n`.
- NextE does not implement the read/display side yet. `GalleryCommentsCard` renders `c.contentText`
  directly with URL data detection, so submitted comments containing `@author` plus the encoded id are not
  parsed into a quoted floor block.
- LFE implements both sides:
  - `lib/pages/gallery/controller/comment_controller.dart::parserCommentRepty()` parses `@user`, optional
    `#id#`, and the BCD-style newline code, then resolves the referenced comment by id or by nearest matching
    author fallback.
  - `parserAllCommentRepty()` supports multiple references in one comment.
  - `reptyComment()` writes `@${name}\n${bcdCode.enCode(id)}\n` when composing a reply.
  - `lib/pages/gallery/view/comment_item.dart::_CommentReply` renders the resolved referenced comments as
    compact quote cards above the current comment body.

Expected behavior:

- Existing reply compose behavior should continue writing the current `@author + encoded comment id` marker.
- When rendering full comments, parse the marker back into referenced comment metadata if the target comment
  is present in the loaded comment list.
- Render a compact quoted-floor block above the comment body, with referenced author and a short excerpt.
- Support the LFE-compatible forms first: explicit `#id#` and newline BCD-style code. Author-only fallback
  can stay conservative and should not guess across unrelated users if the current list cannot identify the
  target safely.
- Keep this scoped to read presentation. Do not redesign the already repaired bottom composer and do not
  add another comment write API path.

Acceptance shape:

- A reply composed through NextE still starts with `@author` and the encoded target `commentId`.
- After the comment list reloads or receives comments containing that marker, the row shows a quoted
  reference block instead of only raw `@author` marker text.
- If the encoded id cannot be resolved from the current comment list, fall back to plain text without
  breaking URL detection or the rest of the comment body.
- Add a small runnable contract for encode/decode and render-path detection using synthetic comments.

### Gallery Comment Vote Must Refresh Visible Score And Icon State

Type: write-action regression / UI state refresh

Priority suggestion: P1

Status: implemented / pending real EH account acceptance

Source:

- User feedback, 2026-06-21: after voting a comment up or down, the comment score does not update in place,
  and the vote button icon state does not visually change.
- User feedback, 2026-06-22: current main-thread validation is now focused on comment upvote/downvote.
  The API path may exist, but the confirmation dialog and final success/failure feedback are still wrong.
  Re-tapping the already-selected upvote/downvote should be treated as a vote-cancel/withdraw path with
  matching prompt and toast copy, not as another ordinary up/down vote.
- Implementation: `f7944f4 fix(comments): support vote cancellation`.

Research:

- `GalleryCommentsPage.applyVoteResult` already intends to replace the matching local comment with the
  returned `commentVote` and `commentScore`.
- Source inspection alone does not prove the visible comment row re-renders the score badge and selected
  vote icon after a successful vote; that needs device-path evidence.
- This means the next fix should treat the user report as a visible-state regression even if the network
  request and toast are successful.
- Current NextE code only models two prompt/success states: `vote > 0` and `vote < 0`. That is insufficient
  for cancel/withdraw feedback.
- Current `EhApiPhpService.voteComment()` rejects any `comment_vote` outside `1/-1` and also rejects a
  returned `commentVote` outside `1/-1`. This can incorrectly classify a successful cancel result as a
  failure if EH returns `comment_vote: 0`.
- eros_fe evidence: `Api.commitVote()` sends the chosen `comment_vote` directly; `CommitVoteRes.fromJson`
  parses missing/zero `comment_vote` as `0`; `CommentController._paraRes()` writes `rult.commentVote` back
  to the row. The FE controller only shows the normal up/down success toast when `commentVote != 0`, which
  means `0` is a real neutral/withdraw state even if FE's own toast copy is sparse.

Expected behavior:

- After a successful upvote or downvote response, the same visible comment row updates its score immediately
  from the returned `commentScore`; no manual refresh or leaving/re-entering the page should be required.
- The voted button immediately switches to the selected visual state, using the filled native thumb symbol
  once the icon-polish lane is applied; the opposite vote remains neutral.
- While a vote is pending, only pending/disabled feedback should be shown. After success, do not leave stale
  icons or stale score text on screen.
- If the request fails, preserve or restore the previous visible score and vote state, then show the failure
  feedback.
- If the user taps the already-selected upvote or downvote button, the UI must present a cancel/withdraw
  confirmation and send the correct neutral vote request/handle the neutral response according to EH API
  behavior. The final state must clear the filled thumb icon and use the returned neutral score/vote state.
- Dialog title/message and toast copy must match the action actually being taken:
  upvote, downvote, withdraw upvote, or withdraw downvote. Do not reuse "点赞成功" / "点踩成功" for a
  withdraw result.

Acceptance shape:

- Open the full comments page with an authorized account and a votable comment.
- Upvote the comment and confirm the dialog.
- When the success path completes, the score badge/text for that comment changes in place and the upvote icon
  shows selected state without refreshing the page.
- Repeat with downvote; the downvote selected state and returned score are visible immediately.
- Tap the selected upvote again; the dialog clearly says this will cancel/withdraw the upvote. After success,
  the row returns to neutral thumb icons and shows the returned score.
- Tap the selected downvote again; the dialog clearly says this will cancel/withdraw the downvote. After
  success, the row returns to neutral thumb icons and shows the returned score.
- Failure toast/copy for any of the four paths must be generic enough or state-specific enough to be truthful.
- Add or tighten an automated contract so the comment card renders from the refreshed `comments` array state,
  not from a stale copied row or a one-time snapshot.
- Add a small contract for vote-state decision text and neutral `commentVote = 0` handling so the cancel path
  cannot regress into the old two-state prompt model.

Verification:

- `python3 scripts/check_i18n_duplicates.py`
- `node scripts/test_v1_decorator_inventory_contract.mjs` -> `0 file(s)`
- `scripts/build_hvigor_signed.sh` -> `BUILD SUCCESSFUL`

Remaining acceptance:

- Run one authorized real-account check on a votable comment: upvote, downvote, withdraw upvote, withdraw
  downvote. Confirm returned score/icon state matches the visible row after each submit.

### Gallery Uploader Badge And Uploader-Only Filter Regression

Type: read/filter regression / parity break

Priority suggestion: P1

Status: accepted / needs verification

Source:

- User feedback, 2026-06-21: comments by the gallery uploader no longer show the uploader marker, and tapping
  "uploader only" does not filter the comment list.

Research:

- `GalleryCommentsCard` still has a visible `c.isUploader` branch that renders the `comment_uploader` badge.
- `GalleryCommentsPage.visibleComments()` still intends to filter by the uploader's `memberId`, falling back
  to `c.isUploader`.
- Existing contracts are mostly source-shape checks. They can pass while the real refreshed/seeded comment
  data no longer carries `isUploader`, or while the menu toggles state without changing the visible rows.

Expected behavior:

- The uploader's own comment must show the compact uploader badge in both the detail-page comment peek and
  the full comments page.
- The full comments page's "uploader only" menu action must immediately narrow the list to the uploader's
  comments; switching back must restore all comments.
- Refreshing comments, posting/editing/replying, or entering the full comments page from detail must preserve
  `isUploader` and `memberId` enough for the badge and filter to keep working.
- Do not replace this with a new heuristic if the parser can preserve EH's uploader marker/member id. Keep the
  data path boring: parse marker -> model field -> card badge/filter.

Acceptance shape:

- Use a gallery with at least one uploader comment and at least one non-uploader comment.
- Detail peek shows the uploader badge on the uploader comment when that comment is visible.
- Full comments page shows the same uploader badge before any filter is applied.
- Tap "uploader only"; only uploader comments remain visible, with no network write or refresh side effect.
- Tap the all-comments option; the original full list returns.
- Add or tighten a runnable contract using a synthetic comment list so it fails if `visibleComments()` does
  not actually reduce visible rows, or if the card no longer renders the uploader badge branch.
