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
- Settings and settings-like management pages must reuse the shared HDS/NextE settings primitives first:
  `SecondaryListScaffold`, `GroupedListSection`, `ConciseListRow`, `AppModalScaffold`, and their local
  variants. If the current primitive lacks a needed row height, divider, prefix/suffix, modal title, or
  subtitle behavior, extend the shared primitive with a narrow opt-in parameter or wrapper. Do not hand-roll
  page-local settings rows, dividers, or modal chrome because one screen exposes a missing capability.
- Gallery Grid is separated from Waterfall: Grid uses grid scaffold semantics and compact fixed-size
  cards; Waterfall is a separate masonry mode, not an alias for Grid. `8bc9afb` implements the current
  recovery target and is pending controller acceptance, not a default active lane.
- Gallery preview grids follow the same native responsive rule: detail preview and AllThumbnails use
  ArkUI `repeat(auto-fit, PREVIEW_THUMB_MIN_W)` and `PreviewThumbTile` measures its own actual Grid cell
  width. Do not reintroduce scaffold-level `onCellSize` / manual column or cell-width calculation for
  preview thumbnails.
- Gallery cover fit/backdrop policy is baseline. Use proportional image rendering only: `Cover` means
  equal-scale crop, never non-uniform stretch/fill. Choose fit from source image ratio vs the current
  slot ratio: ratio-close slots may use `Cover` to avoid unnecessary letterbox; large ratio mismatches
  use `Contain` to preserve the whole cover. For `Contain` gaps, loading/error placeholders stay as
  explicit placeholders; loaded primary-cover surfaces should move toward a same-cover blurred backdrop
  instead of a harsh gray block. List/header/grid thumbnails may keep stable placeholders where they
  protect loading and scroll rhythm. Gray background is never a reason to stretch covers.
- Waterfall cover ratio policy is baseline: normal covers follow the parsed EH source ratio for true
  masonry rhythm, but extreme strip/webtoon ratios must be bounded like the `eros_fe` strategy
  (`max(imgWidth / imgHeight, 1 / 2)`) so a single Korean/webtoon-style cover cannot create an
  unboundedly tall card. Inside the bounded slot, render proportionally and crop/clip if needed; never
  restore non-uniform stretching and never remove list/grid thumbnail placeholders to solve a Waterfall
  cover problem.
- Gallery Grid immersive safe-area and title-scroll linkage are baseline: top/bottom title or
  tab-bar avoidance must be real scroll content or native scroll footer content, not top/bottom
  `Grid.padding` / `WaterFlow.padding` and not `contentStartOffset` / `contentEndOffset`. Grid uses
  `GridLayoutOptions.irregularIndexes` for full-row spacer items while keeping native
  `repeat(auto-fit, ...)`. Waterfall uses `WaterFlowSections` so top/bottom reserves are full-width
  section items instead of ordinary masonry `FlowItem`s. Do not restore any padding-region or
  non-content offset model that makes cards disappear under translucent chrome or delays HDS title
  auto-hide.
- AllThumbnails is a responsive preview grid, not a hero layout. Page 1 must render as the same
  `PreviewThumbTile` grid cell shape as pages 2/3/4. If a spacer/index bug makes the first real
  thumbnail full-width, fix the grid spacer item-count contract; do not special-case page 1 or change
  preview thumbnail aspect/fit semantics.
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
  Details live in the domain intake files. Reopen only from fresh evidence, not from old history.
- Recently Closed / Pending Acceptance is a record of finished work waiting for user/device evidence; it is
  not a default QA backlog. Do not spend a turn re-verifying those rows just because Active Queue is empty.
  If no fresh regression is reported, continue with the first Active Queue feature lane instead.
- Settings shell audit is implemented and pending controller acceptance. Reopen Settings only for a fresh
  Settings regression or a separately scoped Settings feature request.
- Recent implemented/pending clusters are tracked in domain intake files: write operations, Favorites
  color metadata, Search route/filter fixes, Reader cache/chrome/loading/gesture repairs, Grid/Waterfall
  recovery, MyTags management/color parsing, Gallery comments, Settings terminology/placement, and
  retained sub-tab preferences.
- Reader/detail/comment verification should start from a fixed gallery deep link unless the lane is
  specifically testing entry navigation. Use `scripts/launch_gallery_deeplink.sh <target> <url>` to
  force-stop and open the same gallery before entering the target surface; do not spend repeated QA cycles
  manually replaying Home -> list -> detail setup when that path is not under test.

## Feature Parity Scheduling Rule

Until the high-visibility eros_fe parity gaps are closed, default scheduling must move product capability
forward instead of looping on already-implemented polish or pending-acceptance rows. If the user does not
provide a fresh P0/P1 regression, choose the first item in Active Queue and implement that feature lane.

Do not open a turn whose main output is only "re-read pending acceptance", "run another generic QA pass", or
"scan old intake for something already implemented". Pending acceptance waits for user/device evidence.
Engineering turns should advance a bounded FE parity feature or fix a fresh blocking regression.

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
- Smart-grip-aware floating action alignment is no longer parked indefinitely; it is queued after the tag
  translation lane below. Do not mix it into Home bottom-tab auto-hide or other lanes by default. When opened,
  use Next2V's `MotionHandStateService`, `MotionHandEdgeState`, `MotionReplyAlignmentState`, and
  `ReplyActionAlignmentSettings` as HarmonyOS implementation references.
- Gallery comments bottom floating reply composer is reopened: the current implementation failed controller
  screenshot acceptance because it is neither visually floating nor correctly keyboard-avoiding. The white
  composer area expands upward into a large blank panel when the keyboard is open. Code evidence points to
  `GalleryCommentsPage.CommentComposer()` adding `layout.keyboardHeight` to the composer's own bottom
  padding instead of letting ArkUI keyboard avoidance resize/translate the editing surface. This was
  addressed by `64d3ba0 fix(comments): refine floating reply composer` and should not remain the next
  default lane unless fresh screenshots reopen it.

## Active Queue

Pick from here for the next user-visible bug or feature lane. Prefer items with clear user benefit and
a bounded validation path.

1. Reader loading-state isolation and cached page-turn presentation. This is a fresh P1 regression from
   user runtime feedback and temporarily preempts FE parity work. No normal Reader loading/resolving
   indicator may be stacked over a currently visible image, including HTML/image resolving, jumping, cached
   forward turns, horizontal, vertical, or double-page modes. Fix the state model so loading is mutually
   exclusive with readable image presentation, and so a cached/pre-resolved next page does not flash black
   before painting. Do not bundle Reader gesture redesign, double-page architecture, thumbnail strip,
   auto-read, or offline download work into this lane.
2. Tag translation database and localized search candidates. User-visible
   benefit: Chinese/localized tag understanding and search candidate quality, instead of the current tiny
   hardcoded `TagTranslationService` stub. Scope this first lane to the smallest real FE-parity slice:
   replace/extend the stub with the real tag-translation data source or import path, support raw tag ->
   localized display lookup, and feed localized matches into the existing search candidate area with raw
   exact tag insertion. Do not bundle QuickSearch, image search, saved-query management, MyTags write flows,
   or a redesigned SearchFilter into this lane.
3. Smart-grip / action-alignment support for the gallery detail read/resume action. Run this after the tag
   translation lane unless the user explicitly redirects. Reuse the Next2V motion-hand/alignment model with
   fixed-left/fixed-right/follow-operation fallback, and do not reopen Home bottom-tab auto-hide.

When the items above are implemented or explicitly paused, refill Active Queue from the FE parity pool
in this order, one bounded slice at a time:

1. QuickSearch saved-query workflow.
2. Favorites workspace depth: favcat tabs/counts/local slot/search/jump behavior.
3. Download/archive/offline Reader path.
4. MyTags/user-tag wiring into list/detail/search behavior.
5. Auth/WebView/uconfig depth that blocks FE parity.
6. Comment/rating/favorite/tag write-operation acceptance and missing display details.
7. Sync/security/blocking/long-tail FE features.

Do not let the queue become empty while these gaps remain. If the current top item looks too large, split its
first user-visible slice; do not replace it with pending-acceptance rechecks.

## Recently Closed / Pending Acceptance

- Gallery comment vote state closure is implemented by `f7944f4 fix(comments): support vote cancellation`.
  It covers upvote, downvote, withdraw upvote, and withdraw downvote: all four actions use action-specific
  confirmation copy, optimistic row score/icon update, neutral `comment_vote=0` parsing, returned
  score/vote application, and failure rollback. Contracts, i18n parity, V1 inventory, and official signed
  Hvigor build passed. Status: pending real EH account acceptance on a votable comment.
- Common favcat color resolver coverage is implemented by `afbb7bd fix(gallery): resolve favcat colors in
  home lists`. Home/Popular/Toplist gallery lists apply the shared non-placeholder `FavcatSlotResolver`
  and re-resolve visible rows when account favcat metadata arrives late. Status: pending controller/device
  acceptance with a real favorited Home/Popular row.
- Gallery comment reply reference display is implemented and pending real-comment acceptance: NextE now
  parses existing `@author + encoded comment id` markers into quoted-floor blocks when the referenced
  comment is present in the loaded list. Contract/build/local emulator smoke passed; final acceptance needs
  a real loaded comment sample containing that marker.
- Waterfall tag strip alignment and horizontal overflow is implemented with local emulator evidence:
  `75f558e` plus follow-up local diff changed Waterfall tags to a native horizontal two-line `List`;
  `.hvigor/outputs/waterfall-tag-strip-qa/after-real-bounds-swipe.png` shows the strip scrolling inside
  the card while the top tab stays put. Status: pending controller acceptance, not the next default lane.

## eros_fe Feature Parity Gap Pool

The short Active Queue is only the next stabilization lane. It is not the full product backlog. NextE still
has broad feature-depth gaps against `../eros_fe`; see `docs/plans/active/eros-fe-parity-gap-audit.md` and
`docs/plans/active/project-current-state-and-next-plan.md` "Post-stabilization eros_fe feature lanes" before
claiming parity or selecting a new major feature lane.

- Auth foundation depth: manual cookie import validation, WebView login preservation, cookie jar persistence,
  ExHentai/igneous gating, and secret-safety/package-leak checks.
- Search parity depth: local tag-translation database, translation-backed Chinese/localized tag suggestions,
  QuickSearch saved queries, scoped search, URL jump, and image search. Network `tagsuggest` alone is not
  full FE search parity.
- Favorites parity architecture: per-favcat workspace, local favorites slot, favorite-scoped search,
  colored/count favcat selector, jump/sort/cursor behavior, and independent state retention.
- MyTags/usertag management parity: tagset hierarchy, color/watch/hide/weight editing, add/delete flows,
  tagset create/rename/delete, and wiring usertag metadata into list/detail colors and hide filters.
- Download/archive/offline reading: queue management, per-image token/509 retry, archive polling/download,
  offline Reader source, and HarmonyOS-safe storage/export UX.
- Comments/rating/write-operation depth: comment parser/display completeness, reply-floor quote rendering,
  poster/uploader navigation, gallery rating submit, favorite move/note editing, and tag edit/add actions.
- Sync and long-tail FE features: WebDAV history/read-progress/QuickSearch/custom-group sync, custom tab
  groups/profiles, torrents, similar/search-by-image flows, image blocking/pHash/QR filtering, EPUB export,
  update/about polish, and tablet/safe-mode variants.

Promote exactly one bounded subfeature from this pool into Active Queue when it becomes the next lane. Do not
bundle an entire FE parity domain into a single patch.

## Pending Explicit Authorization

- Tag/MyTags write actions are implemented pending controller acceptance / authorized real-submit
  verification. This includes taggallery vote, existing MyTags/setusertag editing, existing MyTags
  deletion, MyTags new-user-tag add, and MyTags tagset create/rename/delete. Because these are real
  EH account writes, do not execute final submit by default. Reopen implementation only for a fresh
  tag-vote, MyTags edit/delete/add, or tagset-management regression.

## Lane Selection Rule

Before editing product code, state:

1. User-visible benefit for this turn.
2. Why the item is Active Queue, not Current Baseline, Closed, or Parked.
3. Files likely to change.
4. Which baseline/closed items will not be reopened.
5. Verification that only covers this turn's risk.

If an item is fixed and verified, move it out of Active Queue in this file or mark it pending acceptance.
Do not leave completed work in Active Queue where it can be restarted after compaction.
