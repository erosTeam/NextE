# Current Dispatch State

Status: active scheduling control file.

Purpose:

- This is the short source of truth for lane selection after context compaction.
- Read this before using `product-bug-intake.md` or long active plans to choose work.
- `product-bug-intake.md` is the short intake index and writing-rule file; it is not the scheduling entry point.
- Each turn should select at most one item from Active Queue unless the user explicitly redirects.

## Current Baseline

These items are current behavior or visual baselines. Do not re-implement, redesign, or re-verify them
as the main output of a new turn unless fresh P0 evidence shows a regression.

- SearchFilter shape, control proportions, and current rounded treatment are baseline.
- Search filter entry belongs in the title/menu/action area, not inside the search input row.
- Search title/header may hide while scrolling, but the bottomBuilder search field remains visible.
- Gallery Grid is separated from Waterfall: Grid uses grid scaffold semantics and fixed-size cards;
  Waterfall is a separate future mode, not an alias for Grid.
- AllThumbnails later-thumbnail Reader start is implemented and should not be reopened without a new
  reproduction.
- Reader single-page core baseline is accepted. Double-page is not final architecture, but the current
  grouped-row mitigation is the shipped interim behavior until a deliberate Reader redesign lane is
  opened.

## Closed / Superseded

Historical feedback in this section must not trigger new implementation.

- SearchFilter old "rounded corner is strange" and "filter button in the wrong place" feedback is
  superseded by the current baseline above.
- Repeated SearchFilter typography/spacing micro-adjustments are closed unless the user provides a new
  current screenshot and asks to reopen that surface.
- Repeated Gallery Grid vs WaterFlow implementation work is closed. Only user acceptance or a new
  regression can reopen it.
- Repeated Reader double-page wording/contract-only cleanup is closed as a main deliverable. Docs may
  record status, but wording changes are not user-visible progress.
- Download page task workbench cleanup is implemented and pending controller acceptance: the pinned
  Gallery / Archiver selector is followed directly by task cards or empty state, without queue summary
  rows before the workbench content.
- Gallery Grid card information density repair is implemented and pending controller acceptance: Grid
  still uses real Grid scaffold and fixed-height cards, but the card info block now shows title,
  compact post-time/rating metadata, and a one-line tag sample without the previous large empty tag area.
- Gallery comment peek full-comments entry is implemented and pending controller acceptance: one/two-comment
  detail peeks expose `查看全部`, and tapping the peek header opens the full comments page.
- Search route/session state is implemented and pending controller acceptance: action-seeded tag/uploader
  searches are converted by `Index` into route/session params so old Search pages do not consume them.
- Gallery local favorite removal safety is implemented and pending controller acceptance: the existing local
  remove action now requires a native destructive confirmation before changing local state.
- Gallery rating safety entry is implemented and pending controller acceptance: detail exposes a rating
  entry, but it opens a native non-destructive dialog and only offers cancel / in-app web until the
  protected EH rating write flow is designed.
- Gallery rating real write loop is implemented and pending controller acceptance / authorized real-submit
  verification: detail rating now opens an HDS modal sheet, supports half-star selection, gates submit until
  a value is selected, posts the protected `rategallery` API path, applies returned rating state, and publishes
  a V2 rating mutation to retained Home/Search/Favorites lists. Automated validation remains non-destructive
  and does not click the final submit action.
- Dispatch intake is split by domain: `product-bug-intake.md` is now a short index/write-rule file,
  while long evidence lives under `docs/plans/active/intake/`. New intake should go to the matching
  domain file first, and only near-term scheduling changes should update this dispatch file.
- Remote EH favorite sheet/write path is implemented and pending controller acceptance: detail opens an
  in-place `EH 收藏` sheet with left cancel, right confirm, favnote input, favcat slots, and remove state.
  Favcat slots now use an account-level real-name cache, no transient loading row is inserted into the
  sheet content, confirm uses optimistic close/update with failure rollback, and detail/home/search/
  favorites retained lists consume a V2 favorite mutation after remote writes. Favorites visible rows also
  re-resolve missing favcat slots when real favcat metadata arrives late, so favorite heart colors can
  update in the current process without requiring an app restart.
- Search entry behavior is implemented and pending controller acceptance: the Search title-bar field
  syncs IME submitted text before bumping the page submit bus, clearing the field returns to history/blank,
  live filter edits only reapply an existing non-empty query, and the Favorites title-bar search action
  opens favorite-scope compose/history instead of auto-running an empty favorite search.
- Gallery comment vote up/down is implemented and pending controller acceptance / authorized real-submit
  verification: full comments now shows bounded up/down actions for voteable comments, opens a native
  confirmation before posting `votecomment`, and applies returned score/vote state locally. Simulator
  validation opened the confirmation dialog and cancelled; no real EH vote was submitted.
- Gallery comment compose/reply is implemented and pending controller acceptance / authorized real-submit
  verification: full comments now exposes a new-comment title action, detail menus can open full comments
  even when the detail peek has no rows, reply actions prefill `@author` plus EH-compatible encoded comment
  id, and submission posts `commenttext_new` to `/g/{gid}/{token}`. Simulator validation opened the HDS
  compose/reply sheets, typed draft text, confirmed send-state gating, and cancelled; no real EH comment was
  submitted.
- Gallery own-comment edit is implemented and pending controller acceptance / authorized real-submit
  verification: full comments now shows edit actions only for parser-confirmed `canEdit` comments, pre-fills
  the original text in the same HDS compose sheet, and submits `commenttext_edit` plus `edit_comment` through
  the protected gallery comment form path. Simulator validation confirmed the current sample page opens
  without false edit actions; no real EH edit was submitted because no editable own-comment sample was
  available during non-destructive QA.
- Security settings root exposure is corrected and pending controller acceptance: the unfinished
  recent-task privacy / auto-lock page is no longer reachable from Settings root until real
  lifecycle/biometric lock enforcement exists. The parked V2 preference/page code remains for a future
  platform-validated lane, but Settings root no longer implies security protection is already wired.
- Download settings root exposure is corrected and pending controller acceptance: the unfinished
  concurrency/original-image policy page is no longer reachable from Settings root because the current
  download queue/executor does not consume those preferences. The Download tab/workbench remains
  available; the parked settings page can return when a real executor lane wires the policy.
- EH settings disabled placeholder exposure is corrected and pending controller acceptance: disabled
  `网站设置` / `图片限制` rows are no longer visible in EH settings until the protected website-settings
  profile flow or image-limit refresh surface exists. EH settings remains scoped to real account/site
  loops.
- Advanced settings root wording is corrected and pending controller acceptance: the root entry and
  child title now use `诊断` / Diagnostics because the current implemented loop is native HiLog
  diagnostics, not eros_fe's full Advanced maintenance surface with cache/proxy/import/export rows.
- Search settings history clear safety is corrected and pending controller acceptance: tapping
  `清除` in Search settings now opens a native confirmation dialog before clearing persisted search
  history instead of deleting immediately.
- Search page history clear safety is corrected and pending controller acceptance: tapping `清除`
  on the Search landing/history page now opens a native confirmation dialog before clearing all
  persisted search history. Cancel preserves the visible history list.
- Search settings filter reset safety is corrected and pending controller acceptance: tapping
  `重置筛选` now opens a native confirmation dialog before clearing the saved filter profile.
- Viewed history clear safety is corrected and pending controller acceptance: tapping the History page
  trash action now opens a native destructive confirmation dialog before clearing viewed history.
- Gallery tag vote write entry is implemented and pending controller acceptance / authorized real-submit
  verification: the detail title menu's `编辑标签` page no longer shows a read-only unsupported notice,
  loads detail-scraped `apikey/apiuid`, opens an HDS modal action sheet from a tag chip, confirms before
  posting protected `/api.php method=taggallery`, and updates local tag vote state after success.
  Simulator validation opened the action sheet and confirmation dialog, then cancelled; no real EH tag
  vote was submitted.
- MyTags existing tag edit is implemented and pending controller acceptance / authorized real-submit
  verification: Settings `我的标签` can open an existing usertag in an HDS modal sheet, edit watch/hide,
  weight, and color/default-color draft state, confirm before posting protected `/api.php method=setusertag`,
  reload the current tagset after success, and publish the shared usertag cache signal. Android eros_fe was
  used for source and UI grounding; simulator validation opened the edit sheet, changed draft state, opened
  the save confirmation dialog, and cancelled. No real EH usertag edit was submitted.
- MyTags existing tag delete is implemented and pending controller acceptance / authorized real-submit
  verification: Settings `我的标签` edit sheet now exposes a HDS modal title-bar trash action for the
  selected existing usertag, opens a native confirmation, posts eros_fe-compatible `/mytags`
  `usertag_action=mass` + `modify_usertags[]` only after confirmation, reloads the current tagset, and
  republishes the shared usertag cache. Android eros_fe device comparison confirmed MyTags uses tagset
  rows and existing-tag rows with a red trash delete affordance; HarmonyOS simulator validation opened
  the delete confirmation and cancelled. No real EH usertag was deleted.
- MyTags new usertag add is implemented and pending controller acceptance / authorized real-submit
  verification: Settings `我的标签` now exposes a HDS title-bar plus action, opens an HDS modal add sheet,
  searches EH tag suggestions through `/api.php method=tagsuggest`, excludes already-owned tags, fills the
  selected `namespace:tag`, edits watch/hide/weight/color draft state, and confirms before posting the
  eros_fe-compatible `/mytags` `usertag_action=add` form. Android eros_fe comparison confirmed MyTags
  search mode keeps existing matches above new-tag candidates; HarmonyOS simulator validation opened the
  add sheet, selected `male:goat`, opened the add confirmation dialog, and cancelled. No real EH usertag
  was added.
- Waterfall mode proper launch is implemented and pending controller acceptance: Layout settings now
  exposes `瀑布流` as a distinct persisted view mode, while Home/Search/Favorites route
  `ListMode.WATERFALL` through `PullRefreshWaterFlowScaffold` + `FlowItem` + `GalleryWaterfallCard`.
  Grid remains a separate fixed-cell branch using `PullRefreshGridScaffold` + `GridItem` +
  `GalleryGridCard`. Android eros_fe comparison confirmed `瀑布流` / `瀑布流 - 大` / `网格` are
  separate list-style choices, and HarmonyOS simulator evidence shows the NextE menu entry and Home
  `WaterFlow` rendering.

## Parked / Guidance Only

Items here are real concerns, but they are not active implementation lanes by default.

- Reader final double-page architecture is parked unless current behavior shows P0 reading failure.
  The current implementation is an interim grouped-row mitigation, not the final target.
- Reader double-page center gap/seam policy is parked as future redesign guidance: paired pages should
  default to a contiguous zero-gutter spread unless a deliberate display option says otherwise.
- In Reader lanes, `eros_fe` is only a feature/EH-mechanism and historical-pitfall reference. It is not
  the design or architecture benchmark.
- Mature reader architecture references, such as Tachiyomi/Mihon-style pager and zoom surface models,
  should guide future Reader redesign together with HarmonyOS-native V2Next image-preview patterns.
- Boundary handoff from zoomed pan to page turn is a future enhancement unless current zoomed pan
  blocks normal reading.
- Gallery detail long-title full-text access is a low-priority optimization. A scrollable or expandable
  title area may be explored later, but it must not interrupt the current feature-completion/write
  operation lanes.
- Persisting last selected sub-tabs is a low-priority UX optimization: Home gallery source, Favorites
  favcat, and Toplist period currently reset to defaults after app restart. This should be handled later
  as retained user preference state, not ahead of write-operation and search/favorites correctness bugs.

## Active Queue

Pick from here for the next user-visible bug or feature lane. Prefer items with clear user benefit and
a bounded validation path.

1. Comment write actions: vote up/down, reply/new comment, and own-comment edit are implemented pending
   controller acceptance / authorized real-submit verification; continue here only if fresh acceptance
   finds a comment write regression.
2. Settings shell audit: continue with remaining rows/pages that are only shells, disabled placeholders,
   not wired to real behavior, or unsafe/destructive without confirmation; Security, Download, EH
   placeholder exposure, Search history clear safety, Search filter reset safety, and Viewed history
   clear safety are already corrected pending acceptance.
3. Tag/MyTags write actions: taggallery vote, existing MyTags/setusertag editing, existing MyTags
   deletion, and MyTags new-user-tag add are implemented pending controller acceptance / authorized
   real-submit verification. Reopen here only for a fresh tag-vote / MyTags edit / MyTags delete /
   MyTags add regression, or for a separately scoped tagset-management lane.
4. AllThumbnails large-gallery jump and preview-page scrolling: reopen only if current acceptance finds
   a remaining mismatch beyond the documented 1700-page jump-to-600 evidence.
5. Reader UI/chrome/loading visible issues: only reopen Reader here if the outcome is a concrete visual
   or gesture fix, not more architecture discussion.
6. Reader gesture matrix: only continue if current device evidence shows a failed basic action such as
   normal fit-scale swipe, pinch, zoomed pan, double tap, center tap, or ready-state overlay cleanup.

## Lane Selection Rule

Before editing product code, state:

1. User-visible benefit for this turn.
2. Why the item is Active Queue, not Current Baseline, Closed, or Parked.
3. Files likely to change.
4. Which baseline/closed items will not be reopened.
5. Verification that only covers this turn's risk.

If an item is fixed and verified, move it out of Active Queue in this file or mark it pending acceptance.
Do not leave completed work in Active Queue where it can be restarted after compaction.
