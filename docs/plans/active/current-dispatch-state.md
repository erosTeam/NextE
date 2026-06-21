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
  Details live in the domain intake files. This includes the download workbench cleanup, comment peek
  navigation, local favorite removal safety, gallery rating, comment vote/compose/edit, tag vote,
  MyTags edit/delete/add, gallery archiver submit plumbing, gallery detail full-title access, settings
  shell cleanup, and search/history destructive-action confirmation gates. Search route/session work is
  closed for query isolation, but the action-seeded autofocus regression below is reopened by fresh
  device/user evidence.
- MyTags tagset management is implemented pending controller acceptance / authorized real-submit
  verification: create, rename, and delete now follow the `eros_fe` tagset action model with separate
  title actions and focused name sheets.
- Settings shell cleanup is closed as a broad audit. Reopen Settings only for a fresh Settings regression
  or a separately scoped Settings feature request such as Reader Settings row readability.
- Previous Waterfall exposure being scaffold-only is superseded by `8bc9afb`, which repairs width,
  viewport spacer handling, and bounded source-ratio cover behavior pending controller acceptance.
- Gallery Grid immersive chrome disappearance is handled as a baseline rule above. Do not reopen the
  old bug except for a fresh reproduction that cards disappear under translucent chrome despite the
  spacer model.
- Remote favorite sheet lifecycle regression is implemented pending controller acceptance: detail page
  modal surfaces now share one `bindSheet` host so rating/full-title false bindings cannot close the
  `EH 收藏` sheet after it opens. Reopen only for a fresh reproduction after this fix.
- Search/Favorites favTitle-to-favcat color consistency is implemented pending controller acceptance:
  Search and Favorites now share one non-placeholder favcat slot resolver, and visible Search rows
  re-resolve when account favcat metadata arrives. Reopen only if a current Search result still shows a
  stale/default heart color after real favcat metadata has loaded.
- Reader Settings row separators and subtitle readability are implemented pending controller acceptance:
  Reader Settings now has visible row dividers, and `ConciseListRow` supports opt-in multiline subtitles
  for the volume-key hint while keeping the default row behavior stable. Reopen only with a fresh Reader
  Settings screenshot showing unreadable row grouping or clipped subtitle text.
- Settings shared row subtitle readability is implemented pending controller acceptance:
  `ConciseListRow` now defaults ordinary subtitles to two lines and lets HDS measure row height naturally
  instead of forcing NextE's old fixed `52/60/84` wrapper policy. Layout Settings Japanese-title
  explanatory text benefits without a page-local one-off, and Reader Settings keeps its explicit
  three-line volume-key hint.
- MyTags tagset route depth is implemented pending controller acceptance: Settings opens the tagset-list
  landing page, tapping a tagset pushes a routed detail instance with `MyTagsPageParams(tagsetId)`, and
  system Back returns from detail to the tagset list instead of exiting directly to Settings.
- MyTags editable color parsing is implemented pending controller acceptance: `d1b78d3` adds the
  editable `colorCode` field to parsed user tags, uses the fourth preview style color like `eros_fe`
  instead of the display border/derived color, and keeps the reusable color picker selection matched
  when the current hex equals a saved favorite. Contracts, V1 inventory, official signed build, and
  simulator MyTags edit-sheet smoke evidence passed. No real `setusertag` submit was clicked.
- Gallery Grid title-bar scroll linkage is implemented pending controller acceptance: Grid no
  longer uses `contentStartOffset` / `contentEndOffset`, uses `GridLayoutOptions.irregularIndexes` for
  full-row top/bottom spacer content, and Waterfall uses `WaterFlowSections` so top/bottom reserves are
  full-width section items instead of normal masonry `FlowItem`s. Simulator evidence on `127.0.0.1:5555`
  shows Waterfall content starts below the tab/header reserve and a short upward scroll lets content pass
  under the floating chrome as expected.
- Gallery thumbnail loading motion is implemented pending controller acceptance: timed internal QA probe
  evidence showed native `LoadingProgress` animated while `EhThumbnail`'s old `.overlay(...)` path was
  static, and `EhThumbnail` now renders normal loading/error overlays as in-tree `Stack` children.
  Post-fix timed screenshots on `127.0.0.1:5555` show changed pixels in both forced thumbnail loading
  boxes and native/pending-image controls.
- Reader bottom chrome/save/cache is implemented pending controller acceptance: `56747e6` makes the
  download/save action match the neutral toolbar weight, wires current-image save through the HarmonyOS
  system save flow, keeps the thumbnail strip/slider linked to the current page, and adds same-process
  Reader session plus `/s/` resolve caching. Simulator evidence on `127.0.0.1:5555` showed the second
  same-gallery Reader open hit `session_cache_hit` / `resolve_memory_cache` with no repeated
  `resolve_spage` or `merge_preview_page`.
- Reader page-turn gesture ownership is implemented pending controller acceptance: horizontal swipes are
  owned by the native Swiper only, the old transparent overlay `onTouch` short-swipe fallback is removed,
  and hidden chrome is no longer opacity-only mounted over the reader canvas. Simulator evidence on
  `127.0.0.1:5555` showed initial hidden chrome layout contained only Swiper/Image, a short center drag
  kept the page at `1 / 522`, and a normal center horizontal swipe advanced to `2 / 522`.
- Search action-seeded autofocus regression is implemented pending controller acceptance: action-seeded
  routes now default the page-owned search field to no autofocus until route params explicitly enable it,
  while manual title-bar Search still flips autofocus on after the field mounts. Simulator evidence on
  `127.0.0.1:5555` showed manual Search opened the keyboard, and gallery-detail tag seeded Search opened
  results without an input-method window.
- Comment vote live state and uploader-only parity are implemented pending controller acceptance /
  authorized real-submit verification: vote controls now use native thumbs symbols, apply an optimistic
  row-local selected state before `votecomment` returns, roll back on failure, and overwrite score/vote
  from the EH response on success. Score-less uploader rows are treated as uploader comments like
  `eros_fe`, so the uploader badge and uploader-only filter work even when the literal `Uploader Comment`
  marker is absent. Simulator evidence on `127.0.0.1:5555` showed the full comments page with UP badge,
  thumbs actions, score badges, uploader-only filtering down to one uploader row, and the vote confirm
  dialog without submitting the destructive write. A real successful vote submit still requires explicit
  authorization before marking accepted.
- Gallery comment footer visual polish is implemented pending controller acceptance: reply now uses
  `ellipsis_message`, own-comment edit uses `square_and_pencil`, vote icons remain native thumbs, and
  footer actions use a compact local hit/visual size instead of the global primary button height. Local
  simulator evidence on `127.0.0.1:5555` captured the full comments page with compact grouped footer
  actions; no comment vote/reply/edit destructive action was submitted.
- AllThumbnails large-gallery jump and preview-page scrolling is implemented pending controller
  acceptance. Existing evidence in `docs/plans/active/intake/gallery-list-grid.md` covers the
  1700-page public gallery `https://e-hentai.org/g/3998992/f5b5c954d2/`, Android FE ADB `su`
  grounding, NextE Mate X7 simulator jump-to-600, and adjacent up/down preview scrolling without
  returning to the initial page range. Reopen only with a fresh mismatch beyond that evidence.
- Retained sub-tab preference is implemented pending controller acceptance: Home source, Favorites
  favcat, and Toplist period selections are restored from Preferences during startup and saved when the
  user changes retained sub-tabs. Logged-out restore clamps unavailable watched/favcat selections to
  valid visible tabs. Reopen only with a fresh restart-state mismatch.
- Search tag query normalization is implemented pending controller acceptance: detail/list/waterfall tag
  taps and Search tag suggestions now share `EhConstants.exactTagSearchQuery()`, which splits
  pipe-separated display aliases on `|`, uses the first trimmed tag segment, compacts namespaces, and adds
  the EH exact-match `$` suffix for non-uploader namespaced tag searches. `eros_fe` source grounding:
  `gallery_detail_parser.dart` pipe normalization and `NavigatorUtil.goSearchPageWithParam()` exact tag
  rewrite. Simulator evidence on `127.0.0.1:5555` showed tapping the visible `big breasts` list tag
  opened Search with `f:"big breasts$"` in the search field; pipe alias behavior is covered by
  `scripts/test_tag_search_query_contract.mjs`.
- Reader loading-state overlay regression is implemented pending controller acceptance: horizontal,
  vertical, and spread image surfaces now keep the `Image` opacity at `0` until `Image.onComplete`
  flips `imageLoaded`, so the normal loading stage can only cover an invisible pending image, not readable
  content. Simulator evidence on `127.0.0.1:5555` in `.hvigor/outputs/reader-loading-overlay/` shows a
  ready Reader page with one Image and no loading/resolving text in the layout.
- Gallery detail internal WebView launch/content loading is implemented pending controller acceptance: `GalleryWebPage`
  now consumes typed route params in `onReady`, waits until both route params and the ArkWeb controller are
  ready, refuses to call `loadUrl('')`, initializes ArkWeb at ability startup, injects the app EH cookie
  jar into ArkWeb, and safe-loads the target URL. Simulator evidence on `127.0.0.1:5555` showed
  Home -> detail -> overflow -> `应用内网页` kept `com.erosteam.nexte` foreground and opened the internal
  WebView route with live EH gallery content (`Front`, `Watched`, gallery titles, tags, pagination, and
  thumbnail links in the layout tree). Evidence is in `.hvigor/outputs/gallery-webview-open/` and
  `.hvigor/outputs/gallery-webview-content/`.

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
- Home bottom-tab auto-hide and smart-grip-aware floating action alignment are medium-priority UX
  enhancements. They should not interrupt the current Grid/Waterfall recovery lane, but they are good
  candidates for a later bounded platform-UX lane because Next2V already has working patterns:
  `HomeTabAutoHideState`, `MotionHandStateService`, `MotionHandEdgeState`,
  `MotionReplyAlignmentState`, and `ReplyActionAlignmentSettings`.

## Active Queue

Pick from here for the next user-visible bug or feature lane. Prefer items with clear user benefit and
a bounded validation path.

1. Waterfall extreme strip cover blur: keep the bounded Waterfall cover slot for very tall/webtoon
   covers, but do not expand an extreme narrow foreground thumbnail to the full column width after the
   ratio clamp. Source ratios below the Waterfall minimum should fit by bounded slot height / true source
   ratio, with side area handled as placeholder/backdrop, not by restoring unbounded card height and not
   by using `forceCoverFit` full-width cover scaling.
2. Tag/MyTags write actions: taggallery vote, existing MyTags/setusertag editing, existing MyTags
   deletion, MyTags new-user-tag add, and MyTags tagset create/rename/delete are implemented pending
   controller acceptance / authorized real-submit verification. Reopen here only for a fresh tag-vote,
   MyTags edit/delete/add, or tagset-management regression.

## Lane Selection Rule

Before editing product code, state:

1. User-visible benefit for this turn.
2. Why the item is Active Queue, not Current Baseline, Closed, or Parked.
3. Files likely to change.
4. Which baseline/closed items will not be reopened.
5. Verification that only covers this turn's risk.

If an item is fixed and verified, move it out of Active Queue in this file or mark it pending acceptance.
Do not leave completed work in Active Queue where it can be restarted after compaction.
