# Current Dispatch State

Status: active scheduling control file.

Purpose:

- This is the short source of truth for lane selection after context compaction.
- Read this before using `product-bug-intake.md` or long active plans to choose work.
- `product-bug-intake.md` is the short intake index and writing-rule file; it is not the scheduling entry point.
- Each turn should select at most one item from Active Queue unless the user explicitly redirects.
- Authority order: this file wins for current scheduling and frozen baselines. Domain intake files under
  `docs/plans/active/intake/` are evidence ledgers. Historical parity / regression files such as
  `docs/parity-driver.md`, `docs/parity-visual-review.md`, and
  `docs/plans/active/gallery-visual-navigation-regression-contract.md` are source evidence only; do not
  implement directly from an old historical note if it conflicts with this file. Promote the needed
  current rule into this file first.

## Current Baseline

These items are current behavior or visual baselines. Do not re-implement, redesign, or re-verify them
as the main output of a new turn unless fresh P0 evidence shows a regression.

- SearchFilter shape, control proportions, and current rounded treatment are baseline.
- Search filter entry belongs in the title/menu/action area, not inside the search input row.
- Search title/header may hide while scrolling, but the bottomBuilder search field remains visible.
- Gallery Grid is separated from Waterfall: Grid uses grid scaffold semantics and fixed-size cards;
  Waterfall is a separate mode, not an alias for Grid. This separation is baseline, but the current
  compact Grid visual target and Waterfall width/viewport behavior are active issues.
- Gallery cover fit/backdrop policy is baseline. Use proportional image rendering only: `Cover` means
  equal-scale crop, never non-uniform stretch/fill. Choose fit from source image ratio vs the current
  slot ratio: ratio-close slots may use `Cover` to avoid unnecessary letterbox; large ratio mismatches
  use `Contain` to preserve the whole cover. For `Contain` gaps, loading/error placeholders stay as
  explicit placeholders; loaded primary-cover surfaces should move toward a same-cover blurred backdrop
  instead of a harsh gray block. List/header/grid thumbnails may keep stable placeholders where they
  protect loading and scroll rhythm. Gray background is never a reason to stretch covers.
- Gallery Grid immersive safe-area handling is baseline: top/bottom title or tab-bar avoidance uses
  real full-row spacer content, while `Grid.padding` stays horizontal-only. Do not restore top/bottom
  Grid padding or any padding-region approach that makes cards disappear under translucent chrome.
  Waterfall must follow the same safe-area principle when its width/viewport lane is fixed.
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
- The old "Grid was accidentally implemented with WaterFlow" conflation fix is closed. Do not reuse
  WaterFlow as Grid. Current Grid compactness/category-badge and Waterfall width/viewport failures are
  new active issues, not a reopening of the old conflation bug.
- Repeated Reader double-page wording/contract-only cleanup is closed as a main deliverable. Docs may
  record status, but wording changes are not user-visible progress.
- The previous Gallery Grid card information-density repair (`b85353d`) is superseded as a UX target:
  it added metadata but kept a large-card / tag/rating hybrid instead of the desired compact phone
  three-column Grid with persistent category-colored translation badge.
- Dispatch intake is split by domain: `product-bug-intake.md` is now a short index/write-rule file,
  while long evidence lives under `docs/plans/active/intake/`. New intake should go to the matching
  domain file first, and only near-term scheduling changes should update this dispatch file.
- Historical parity / regression docs are superseded as scheduling sources. They may be used to recover
  FE/HarmonyOS mechanism details, but a stale historical PASS or old implementation note cannot reopen
  or override a current baseline by itself.
- Implemented/pending-acceptance work is not a scheduling item unless fresh regression evidence appears.
  Details live in the domain intake files. This includes the download workbench cleanup, comment peek
  navigation, search route/session and search entry behavior, local favorite removal safety, gallery
  rating, comment vote/compose/edit, tag vote, MyTags edit/delete/add, gallery archiver submit plumbing,
  gallery detail full-title access, settings shell cleanup, and search/history destructive-action
  confirmation gates.
- Settings shell cleanup is closed as a broad audit. Reopen Settings only for a fresh Settings regression
  or a separately scoped Settings feature request such as Reader Settings row readability.
- Previous Waterfall exposure is not accepted as complete: the mode is scaffolded but broken. Treat
  Waterfall width/viewport repair as part of the Active Grid/Waterfall layout recovery lane, not as a
  completed historical PASS.
- Gallery Grid immersive chrome disappearance is handled as a baseline rule above. Do not reopen the
  old bug except for a fresh reproduction that cards disappear under translucent chrome despite the
  spacer model.

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
- Persisting last selected sub-tabs is a low-priority UX optimization: Home gallery source, Favorites
  favcat, and Toplist period currently reset to defaults after app restart. This should be handled later
  as retained user preference state, not ahead of write-operation and search/favorites correctness bugs.
- Home bottom-tab auto-hide and smart-grip-aware floating action alignment are medium-priority UX
  enhancements. They should not interrupt the current Grid/Waterfall recovery lane, but they are good
  candidates for a later bounded platform-UX lane because Next2V already has working patterns:
  `HomeTabAutoHideState`, `MotionHandStateService`, `MotionHandEdgeState`,
  `MotionReplyAlignmentState`, and `ReplyActionAlignmentSettings`.

## Active Queue

Pick from here for the next user-visible bug or feature lane. Prefer items with clear user benefit and
a bounded validation path.

1. Gallery browsing layout recovery: compact Grid and Waterfall correctness. User-visible benefit is
   high because Home/Search/Favorites browsing currently has two visible failures:
   regular-phone Grid should be a compact three-column cover wall with persistent category-colored
   translation badge and minimal title/date text, not a two-column large-card / tag/rating hybrid;
   cover images must follow the baseline fit/backdrop policy above, not stretch to hide gray gaps;
   Waterfall is exposed but current widths are unusable and its viewport model must not repeat the old
   top/bottom padding/safe-area issue. Next lane should fix `GalleryGridCard`, grid width constants/contracts, and
   `PullRefreshWaterFlowScaffold` / `GalleryWaterfallCard` width + immersive viewport behavior together.
2. Remote favorite sheet lifecycle regression: the detail menu `EH 收藏` action can flash the half-modal
   and close it immediately. This is a high-priority write-entry usability bug and should be the next
   lane immediately after the current Grid/Waterfall lane is either fixed or explicitly paused.
3. Comment write actions: vote up/down, reply/new comment, and own-comment edit are implemented pending
   controller acceptance / authorized real-submit verification; continue here only if fresh acceptance
   finds a comment write regression.
4. Tag/MyTags write actions: taggallery vote, existing MyTags/setusertag editing, existing MyTags
   deletion, and MyTags new-user-tag add are implemented pending controller acceptance / authorized
   real-submit verification. Reopen here only for a fresh tag-vote / MyTags edit / MyTags delete /
   MyTags add regression, or for a separately scoped tagset-management lane.
5. AllThumbnails large-gallery jump and preview-page scrolling: reopen only if current acceptance finds
   a remaining mismatch beyond the documented 1700-page jump-to-600 evidence.
6. Reader UI/chrome/loading visible issues: only reopen Reader here if the outcome is a concrete visual
   or gesture fix, not more architecture discussion.
7. Reader gesture matrix: only continue if current device evidence shows a failed basic action such as
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
