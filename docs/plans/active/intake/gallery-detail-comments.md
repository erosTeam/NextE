# Gallery Detail And Comments Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
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

Status: implemented / pending controller acceptance

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
- `scripts/test_gallery_comment_compose_contract.mjs` no longer locks the stale `doc_plaintext` reply
  icon and verifies the footer action builders do not use `ThemeConstants.BUTTON_HEIGHT`.
- Footer actions use compact local hit/visual sizing so the secondary action cluster no longer reserves
  primary-button-sized boxes.

Verification:

- `node scripts/test_gallery_comment_compose_contract.mjs`
- `node scripts/test_gallery_comment_vote_contract.mjs`
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

### Gallery Comment Vote Must Refresh Visible Score And Icon State

Type: write-action regression / UI state refresh

Priority suggestion: P1

Status: accepted / needs verification

Source:

- User feedback, 2026-06-21: after voting a comment up or down, the comment score does not update in place,
  and the vote button icon state does not visually change.

Research:

- `GalleryCommentsPage.applyVoteResult` already intends to replace the matching local comment with the
  returned `commentVote` and `commentScore`.
- `scripts/test_gallery_comment_vote_contract.mjs` currently checks that intent at the source level, but it
  does not prove the visible comment row re-renders the score badge and selected vote icon after a successful
  vote.
- This means the next fix should treat the user report as a visible-state regression even if the network
  request and toast are successful.

Expected behavior:

- After a successful upvote or downvote response, the same visible comment row updates its score immediately
  from the returned `commentScore`; no manual refresh or leaving/re-entering the page should be required.
- The voted button immediately switches to the selected visual state, using the filled native thumb symbol
  once the icon-polish lane is applied; the opposite vote remains neutral.
- While a vote is pending, only pending/disabled feedback should be shown. After success, do not leave stale
  icons or stale score text on screen.
- If the request fails, preserve or restore the previous visible score and vote state, then show the failure
  feedback.

Acceptance shape:

- Open the full comments page with an authorized account and a votable comment.
- Upvote the comment and confirm the dialog.
- When the success path completes, the score badge/text for that comment changes in place and the upvote icon
  shows selected state without refreshing the page.
- Repeat with downvote; the downvote selected state and returned score are visible immediately.
- Add or tighten an automated contract so the comment card renders from the refreshed `comments` array state,
  not from a stale copied row or a one-time snapshot.

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
