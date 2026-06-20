# Gallery List, Grid, And Thumbnails Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Waterfall Top Reserve Was A Normal Masonry Item

Type: browsing mode bug / viewport chrome avoidance

Priority suggestion: P1

Status: implemented / pending controller acceptance

Implementation:

- `PullRefreshWaterFlowScaffold` now uses `WaterFlowSections`: a one-item full-width top reserve section,
  the real gallery content section, and a one-item full-width bottom reserve section.
- Home, Search, and Favorites Waterfall branches pass `itemCount: this.vm.itemCount` so section counts
  match the rendered `FlowItem`s.
- Scope is intentionally narrow: Grid scaffold semantics, cover policy, badge shape, Reader, and
  SearchFilter are unchanged.

Verification:

- Local HarmonyOS emulator target `127.0.0.1:5555`, hdc outside sandbox.
- Initial Home Waterfall screenshot:
  `/Users/honjow/git/NextE-wt/waterfall-top-avoidance/.hvigor/outputs/waterfall-top-avoidance/start.png`.
- Layout proof: first `FlowItem` is the full-width reserve `[18,122][1062,415]`; the first left/right
  content cards both begin at `y=415`, not under the title/tab chrome.
- Scrolled screenshot:
  `/Users/honjow/git/NextE-wt/waterfall-top-avoidance/.hvigor/outputs/waterfall-top-avoidance/scrolled.png`.
- Gates: `node scripts/test_gallery_waterflow_contract.mjs`,
  `node scripts/test_gallery_grid_mode_contract.mjs`,
  `node scripts/test_grid_immersive_spacer_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`, `git diff --check`, and
  `scripts/build_hvigor_signed.sh`.

### AllThumbnails First Real Thumbnail Rendered Full Width

Type: bug / preview grid layout

Priority suggestion: P1

Status: implemented / pending controller acceptance

Implementation:

- `GalleryAllThumbnailsPage` now passes `itemCount: this.vm.itemCount` into `PullRefreshGridScaffold`.
- The shared grid scaffold marks full-row spacer indexes as `[0, itemCount + 1]`; without the real item
  count, the default `0` also marks index `1`, which is the first real thumbnail after the top spacer.
- Scope is intentionally narrow: no preview aspect/fit change, no page-1 hero, no Reader or large-jump
  pagination change.

Verification:

- Deterministic contracts:
  - `node scripts/test_responsive_grid_contract.mjs`
  - `node scripts/test_grid_immersive_spacer_contract.mjs`
  - `node scripts/test_all_thumbnails_page_jump_contract.mjs`
- V2 gate: `node scripts/test_v1_decorator_inventory_contract.mjs` reports `0 file(s)`.
- Official signed build: `scripts/build_hvigor_signed.sh`.
- Emulator evidence on local HarmonyOS target `127.0.0.1:5555`, hdc run outside sandbox:
  - Detail preview before opening all thumbnails:
    `/Users/honjow/git/NextE-wt/all-thumbnails-first-tile/.hvigor/outputs/all-thumbnails-first-tile/detail.png`.
  - AllThumbnails top after the fix:
    `/Users/honjow/git/NextE-wt/all-thumbnails-first-tile/.hvigor/outputs/all-thumbnails-first-tile/allthumb.png`.
    Pages `1`, `2`, and `3` render as same-row normal grid cells; page `1` is no longer full-width.

### AllThumbnails Far Jump Conflicts With Thumbnail Page Loading

Type: P0/P1 bug / browsing preview pagination

Priority suggestion: P0/P1

Status: implemented / pending controller acceptance

Implementation:

- `38137e1 fix(gallery): anchor thumbnail jump paging` changes
  `AllThumbnailsViewModel.loadNext()` from the contiguous first-page cursor (`loadedPages`) to a sparse
  forward neighbor cursor based on `currentPreviewPage + 1`.
- A direct jump via `loadImagePage(page)` still loads the target thumbnail page, but subsequent bottom
  pagination now requests the target neighborhood (`targetPreviewPage + 1`, skipping already loaded
  pages) instead of returning to early preview pages.
- `loadPreviousPreviewPage()` remains centered on the current sparse page and continues to request the
  immediate previous thumbnail page.
- Reader seed state remains separate: `loadedPages` is still exposed as the contiguous first-page seed
  count for Reader startup, but it is no longer used as the AllThumbnails bottom request source.
- Follow-up implementation in progress after device validation exposed a remaining discontinuity:
  jumping from the early preview range to page 120 in a 138-page gallery showed the target page, but the
  same viewport still mixed early pages 8-20 with target pages 101-122. `loadImagePage(page)` now loads
  a small target preview-page neighborhood (`target - 1`, `target`, `target + 1`, clamped to real
  preview pages) and skips pages already loaded. This keeps the first post-jump viewport and the next
  up/down scrolls centered on the target neighborhood instead of stitching the early range directly to
  the target page.

Verification:

- FE grounding:
  `/Users/honjow/git/eros_fe/lib/pages/gallery/controller/all_thumbnails_controller.dart` uses
  `fetchThumbnailsFromPage(fromPage)` to request `page: fromPage - 1` and reset
  `_pageState.currentImagePage = fromPage - 1`; subsequent next/previous preview loads use
  `currentImagePage + 1` / `currentImagePage - 1`.
- Android FE ADB evidence:
  `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump/eros_fe_reference.png`.
- Deterministic contract:
  `node scripts/test_all_thumbnails_page_jump_contract.mjs` now simulates a 1000-page gallery with an
  early loaded range, a jump to page 600, target-neighborhood preloading, and forward/backward neighbor
  loading from the target preview page rather than preview page 1.
- Full deterministic contracts passed via `for f in scripts/test_*contract.mjs; do node "$f" || exit 1; done`.
- V2-only gate passed: `node scripts/test_v1_decorator_inventory_contract.mjs` reports `0 file(s)`.
- Signed macOS build passed: `scripts/build_hvigor_signed.sh`.
- HarmonyOS install/start smoke passed on `127.0.0.1:5555`; evidence:
  `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump/nexte_start.png` and
  `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump/nexte_gallery_detail.png`.
- Follow-up device validation on Mate X7 simulator `127.0.0.1:5555`, signed HAP installed with hdc
  outside sandbox:
  - Before the neighborhood fix, `jump to 120` produced a mixed viewport with early pages 8-20 directly
    followed by target pages 101-122:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump-acceptance/after_jump.png`.
  - After the neighborhood fix, `jump to 120` showed a continuous target-neighborhood viewport
    `89..123`, then down-scroll showed `124..138`, and up-scroll returned to `89..123` without jumping
    back to the early range. Evidence:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump-acceptance/fix_after_jump.png`,
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump-acceptance/fix_scroll_down.png`,
    and `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-far-jump-acceptance/fix_scroll_up.png`.
- Large-gallery device validation on 2026-06-20 used public gallery
  `https://e-hentai.org/g/3998992/f5b5c954d2/` (`1700` pages, `85` preview pages). Android FE ADB
  reference was captured with `su` on device `fa967a75`, showing the same 1700-page gallery detail:
  `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-large-acceptance/fe_large_detail.png`.
  NextE was validated on Mate X7 simulator `127.0.0.1:5555` with hdc outside sandbox:
  - Detail page showed the same gallery and `1700` page count:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-large-acceptance/nexte_large_detail.png`.
  - AllThumbnails initially showed the early range `1..20`:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-large-acceptance/nexte_allthumb_initial.png`.
  - Jumping directly to page `600` landed in the target neighborhood `569..603`, including `600`, with
    no early `1..20` range stitched into the viewport:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-large-acceptance/nexte_after_jump600.png`.
  - Scrolling down stayed in the adjacent target neighborhood `590..624`:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-large-acceptance/nexte_after_jump600_scroll_down.png`.
  - Scrolling back up returned to the target neighborhood `569..596`, not the initial pages:
    `/Users/honjow/git/NextE/.hvigor/outputs/all-thumbnails-large-acceptance/nexte_after_jump600_scroll_up.png`.
  - Layout JSON evidence for the same sequence is saved beside the screenshots:
    `nexte_after_jump600_layout.json`, `nexte_after_jump600_scroll_down_layout.json`, and
    `nexte_after_jump600_scroll_up_layout.json`.

Remaining acceptance:

- Controller/user can review the large-gallery evidence above. No additional product-code change is
  planned for this item unless review finds a reproducible mismatch beyond the validated 1700-page
  jump-to-600 flow.

Source:

- User-reported current behavior on very large galleries, around 1000 pages: the AllThumbnails /
  preview page may have only the first few thumbnail pages loaded, then the user jumps directly to page
  500/600+.
- The UI can appear to jump, but subsequent preview scrolling / thumbnail-page loading conflicts with
  the original loaded range. This makes the preview page hard to use.
- This is not the Reader later-thumbnail start bug above. It concerns the AllThumbnails / preview page's
  own far-jump and subsequent thumbnail pagination state, not opening Reader from a clicked thumbnail.

Observed behavior:

- A far jump in AllThumbnails can look successful initially.
- After the jump, scrolling up/down or letting preview pagination load more thumbnails may use stale
  loaded-page/cursor state from the initial range.
- The preview can jump back toward early pages, request the wrong neighboring thumbnail page, duplicate
  items, leave holes, or otherwise desynchronize visible absolute indices from loaded thumbnail pages.

Expected behavior:

- Jumping to a far preview page should first locate and load the thumbnail page/range containing the
  target absolute index.
- The page should establish a correct sparse loaded range around the target.
- Subsequent up/down scrolling should request adjacent thumbnail pages based on the target neighborhood,
  not based on the initial first-page cursor.
- Reader startIndex / seed image-page logic must remain separate and must not be used as proof that the
  AllThumbnails preview pagination is correct.

Likely modules to inspect:

- `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets`
- `feature/gallery/src/main/ets/viewmodel/*` if AllThumbnails state has moved out of the page.
- `feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets` only to confirm Reader-specific sparse
  start logic is not accidentally coupled to preview pagination.
- `shared/src/main/ets/parser/EhGalleryImageParser.ets`
- EH gallery thumbnail-page service methods and `ReaderParams` / image seed models only for boundary
  checks.
- eros_fe thumbnail / preview page jump behavior for product and EH mechanism grounding.

Implementation direction to evaluate:

- Treat far jump as a preview-page pagination operation: compute the target thumbnail page / page group
  from absolute image index, load that group first, then scroll to the matching absolute index.
- Keep each thumbnail seed's `absoluteIndex`, `/s/...` image-page URL, and source preview-page marker.
- Maintain loaded ranges as sparse intervals around the target, not as a single append-only cursor from
  page 1.
- `onReachEnd` and any upward/backward load should use the nearest loaded interval around the current
  viewport.
- Do not conflate this with Reader startIndex. Reader may consume the clicked seed later, but preview
  pagination correctness must stand on its own.

Acceptance shape:

- Use a very large gallery, approximately 1000 pages.
- Open AllThumbnails / preview page with only the first few thumbnail pages loaded.
- Jump directly to page 500/600+.
- The visible thumbnail sequence and labels correspond to the target absolute page range.
- Scrolling upward/downward continues loading adjacent thumbnail pages from the target neighborhood.
- The page does not jump back to early pages, duplicate ranges, show holes, or desynchronize preview
  page loading state.
- Deterministic contract should simulate a 1000-page gallery, early loaded range, far jump to 500+, and
  subsequent forward/backward pagination requests based on the target range rather than the initial range.

### Very Tall Gallery Covers Break List Row Height

Type: bug

Priority suggestion: P0/P1

Status: accepted

Implementation:

- `14d471c fix(gallery): bound list cover row height` clamps list cover row height behavior for
  extreme tall/narrow covers.
- Scope: `GalleryCard` applies explicit list-cover sizing constraints so extreme cover ratios cannot
  force fixed-height list rows to become unboundedly tall.

Evidence:

- Deterministic contracts: `scripts/test_cover_presentation_contract.mjs`,
  `scripts/test_list_height_mode_contract.mjs`, `scripts/test_list_responsive_cover_contract.mjs`.
- Historical Mate X7 evidence exists for Home fixed/adaptive list modes, but active visual acceptance
  is not automatically closed by history.
- Current-main acceptance, 2026-06-19:
  `scripts/test_cover_presentation_contract.mjs`, `scripts/test_list_height_mode_contract.mjs`,
  `scripts/test_list_responsive_cover_contract.mjs`, and
  `scripts/test_v1_decorator_inventory_contract.mjs` all passed.
- Android FE reference, 2026-06-19: ADB target `fa967a75` was brought to foreground with
  `adb shell su -c 'am start -n com.honjow.fehviewer/.MainActivity'`, foreground confirmed as
  `com.honjow.fehviewer/.MainActivity`, and the current FE screen was captured at
  `/private/tmp/nexte_tall_cover_row_height_fe_reference/fe_foreground.png`.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox: fixed-height list mode was
  checked via the real Settings switch, a `webtoon` search result list was captured, and visible
  `ListItem` rows stayed bounded (first webtoon result row height 638px; no multi-screen row stretch).
  Adaptive mode was toggled through Settings, the Gallery default list was captured, and visible rows
  remained bounded while allowing content growth (first adaptive content row height 720px). The setting
  was restored to fixed-height checked=true after capture. Evidence directory:
  `/private/tmp/nexte_tall_cover_row_height_acceptance`, especially `fixed.png`, `fixed.json`,
  `adaptive.png`, `adaptive.json`, `settings_fixed_toggle.json`, and `settings_fixed_restored.json`.

Closure:

- Accepted for fixed and adaptive list row-height behavior. The real-device evidence covers running
  list surfaces and the deterministic contracts lock the explicit cover-slot policy for extreme
  tall/narrow source ratios. No product code changed in this acceptance update.

Source:

- User-reported current behavior.

Observed behavior:

- Gallery list rows can still become very tall even when fixed list height is selected.
- Some Korean webtoon-style galleries have extremely tall/narrow covers.
- The list cover respects the raw cover ratio too much, so the cover height stretches and pushes the whole row much taller than intended.

Expected behavior:

- Fixed-height list mode must keep rows fixed even for extreme cover ratios.
- Adaptive/non-fixed list mode may grow for tags/content, but it still needs a maximum supported cover aspect ratio.
- When a cover is taller than that allowed ratio, NextE should handle it deliberately instead of stretching the row indefinitely.

Why this matters:

- A single extreme cover can destroy scan density and make the list feel broken.
- The fixed-height setting currently appears unreliable to users if cover ratio can override it.
- This affects a high-frequency browsing surface, not a low-priority visual edge case.

Likely failure mode:

- `EhThumbnail` / `GalleryCard` may use source cover ratio or `aspectRatio` in a way that can exceed the intended row height.
- Fixed-height row constraints may not prevent a child image from requesting a taller layout.
- Adaptive mode may have no maximum cover-ratio clamp.

Likely modules to inspect:

- `shared/src/main/ets/components/GalleryCard.ets`
- `shared/src/main/ets/components/EhThumbnail.ets`
- `shared/src/main/ets/state/ListModeState.ets`
- `scripts/test_list_height_mode_contract.mjs`
- `scripts/test_list_responsive_cover_contract.mjs`
- eros_fe list item cover sizing and maximum ratio handling.

Implementation direction to evaluate:

- Define an explicit maximum list-cover height / aspect-ratio policy for both fixed and adaptive modes.
- Fixed mode should ensure the cover cannot expand the row beyond the fixed row height.
- Adaptive mode should still clamp extreme cover ratios so very tall/narrow covers do not dominate the list.
- The fix should not be a one-off `maxWidth` patch; it should be based on row/container sizing and cover-ratio policy.
- Preserve normal cover containment/cropping behavior for ordinary manga/doujin covers.

Acceptance shape:

- Use or fixture a gallery list item with an extreme tall/narrow cover ratio.
- In fixed-height mode, the row remains fixed height and the cover is handled within the allowed slot.
- In adaptive mode, the row may adapt for content but does not stretch indefinitely because of the cover ratio alone.
- Ordinary cover ratios still render as before.

### Gallery Thumbnail Loading Indicator Appears Static

Type: visual feedback bug / gallery browsing loading state

Priority suggestion: P1

Status: implemented / pending controller acceptance

Implementation:

- `EhThumbnail` no longer places the normal fixed-size / cover-ratio / contain-fit thumbnail loading
  overlay in ArkUI's `.overlay(...)` modifier path. The loading/error overlay is now rendered as an
  in-tree `Stack` child for those thumbnail paths.
- `CoverFallbackProbePage` now isolates three loading cases on one internal QA route:
  independent native `LoadingProgress`, forced `EhThumbnail(THUMBNAIL_VISUAL_LOADING)`, and a pending
  `Image` with an equivalent native loading overlay.
- The stretch-height legacy path is intentionally left unchanged because there are no current business
  call sites, and changing that layout path is outside this lane.

Validation:

- Before fix, timed screenshots on local emulator target `127.0.0.1:5555` showed native and pending
  image loading regions changing over time, while both forced `EhThumbnail` loading regions were static:
  `0 / 11025` and `0 / 14400` changed pixels in the measured spinner boxes.
- After fix, timed screenshots showed motion in all relevant boxes:
  top forced card `865-937 / 14400` changed pixels, forced thumbnail `527-861 / 11025`, native
  `902-1579 / 11025`, pending image `695-1093 / 11025`.
- Evidence artifacts:
  `.hvigor/outputs/thumbnail-loading-probe/frame-a.jpeg` through `frame-c.jpeg` and
  `.hvigor/outputs/thumbnail-loading-probe-fixed/frame-a.jpeg` through `frame-c.jpeg`.
- Gates: `scripts/build_hvigor_signed.sh`,
  `node scripts/test_cover_presentation_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`, and `git diff --check`.

Source:

- User-reported repeatedly on real gallery list browsing: while cover thumbnails are loading, the
  loading indicator appears completely static. Even if the visible loading window is only around
  300-500ms, the indicator should show some visible motion instead of looking frozen.

Read-only current-state notes:

- `shared/src/main/ets/components/EhThumbnail.ets` renders `LoadingProgress()` in `loaderOverlay()`
  while `!loaded && !failed`.
- `scripts/test_cover_presentation_contract.mjs` currently asserts that the loading overlay and forced
  loading probe exist, and the historical probe evidence confirms one `LoadingProgress` node is present.
- Those checks are static. They do not prove the native indicator animates in the real list surface, do
  not compare multiple frames over time, and do not catch a visually frozen spinner.
- Other app surfaces, such as list footers and page-level loading, use the same native
  `LoadingProgress()` and have been observed to animate normally. Therefore the first hypothesis should
  be the thumbnail loading path, overlay composition, `Image` callback timing, or list/grid virtualization
  behavior, not a global native component failure.

Expected behavior:

- During real thumbnail loading, the loading affordance must visibly animate or otherwise communicate
  live progress/activity.
- A static `LoadingProgress()` node, a single screenshot, or source grep is not sufficient acceptance.
- If ArkUI native `LoadingProgress` is visually frozen in `EhThumbnail` under current list/grid
  composition, replace it with a deterministic lightweight animated affordance or a shared wrapper that
  is proven to animate in this surface.

Implementation direction:

- First reproduce with a slow/forced thumbnail-loading scenario in Home/Search/Favorites list or grid.
- Use an explicit QA isolation matrix before replacing the indicator:
  1. independent `LoadingProgress()` in the same page;
  2. `EhThumbnail(visualState=THUMBNAIL_VISUAL_LOADING)` with no real image;
  3. real `Image(slowUrl)` with the same `EhThumbnail` overlay kept pending by a slow test endpoint.
- Do not block the UI thread with an ArkTS `sleep`; that would freeze the entire render loop and make the
  result meaningless. Use a delayed/slow URL or controlled network response instead.
- Capture timed device evidence: short video or at least two/three frames from the same loading state
  showing whether the indicator changes over time.
- Keep this scoped to thumbnail loading affordance. Do not reopen cover fit, placeholder policy, grid
  column count, Reader loading, or error fallback unless the reproduction shows they are directly involved.
- Update cover/loading contracts so they no longer imply animation from the existence of
  `LoadingProgress`; add a contract/probe requirement for a timed or explicitly animated state if a custom
  wrapper is introduced.

Acceptance shape:

- Device evidence on a real list/grid thumbnail loading state shows visible motion while the image is
  unresolved.
- Forced internal probe evidence, if used, must be time-based or animated-state based, not only a static
  screenshot with a `LoadingProgress` node.
- Loaded and error states remain unchanged: loaded images clear the overlay, and error fallback still
  shows the explicit image marker on the placeholder.

### Gallery Grid Mode Uses Broken WaterFlow Layout

Type: P0/P1 bug / browsing core layout

Priority suggestion: P0/P1

Status: implemented / pending user acceptance

Implementation:

- `3913012 fix(gallery): render grid mode with grid scaffold` separated user-visible Grid from
  WaterFlow by moving Home, Search, and Favorites `ListMode.GRID` branches to
  `PullRefreshGridScaffold` + `GridItem`.
- `f46f109 fix(gallery): bound grid card height` completes the grid semantics correction by bounding
  `GalleryGridCard` itself: fixed cover ratio, fixed title/info/tag area, and a small bounded tag sample
  so content cannot create masonry-like unequal card heights.

Evidence:

- Deterministic contracts: `scripts/test_gallery_grid_mode_contract.mjs`,
  `scripts/test_gallery_grid_card_visual_contract.mjs`, and `scripts/test_gallery_waterflow_contract.mjs`.
- Full contract suite, i18n parity, `git diff --check`, and V1 decorator inventory passed in the fixing
  lane.
- Official signed build passed via `scripts/build_hvigor_signed.sh`.
- HarmonyOS Mate X7 simulator, hdc outside sandbox, signed HAP installed:
  - Outer/phone-like width Home grid: `.hvigor/outputs/reader-gesture-rework/nexte_grid_fixed_home_2tags.png`
  - Outer/phone-like Search results grid: `.hvigor/outputs/reader-gesture-rework/nexte_grid_fixed_search_results.png`
  - Expanded inner-screen Search results grid: `.hvigor/outputs/reader-gesture-rework/nexte_grid_fixed_search_expand.png`
  - Favorites surface opened but local Favorites count was 0, so device evidence only proves the surface
    remained usable/empty; the Favcat grid branch is covered by deterministic contract and shared code.

Source:

- User-reported current behavior: the gallery "grid" layout is visibly unusable. Covers are not
  controlled, cards can overlap, and the result does not behave like a responsive grid.
- Read-only inspection:
  - `feature/home/src/main/ets/components/GalleryListBody.ets`
  - `feature/search/src/main/ets/pages/GallerySearchPage.ets`
  - `feature/user/src/main/ets/components/FavcatPage.ets`
  all render `ListMode.GRID` through `PullRefreshWaterFlowScaffold` + `FlowItem`, not through a
  normal `Grid` + `GridItem`.
- `shared/src/main/ets/state/ListModeState.ets` already defines `WATERFALL = 'waterfall'`, but
  `feature/settings/src/main/ets/pages/LayoutSettingsPage.ets` only exposes list/simple/grid and the
  main list surfaces do not branch on `ListMode.WATERFALL`.
- `PullRefreshGridScaffold` and `ResponsiveGrid` exist, but the current list grid branches do not use
  them.

Observed behavior:

- Selecting "网格" can produce overlapping or visually broken cover cards.
- After the first scaffold fix, "网格" still looked like a Waterfall pre-stage because `GalleryGridCard`
  allowed title/tags/content to auto-expand each item, producing unequal card heights.
- Grid card cover size is not clearly derived from the current pane/container width.
- The UI is not a complete responsive grid unless both the scaffold and the card have a stable sizing
  contract: fixed cell width, fixed cover ratio, fixed title/info area, and bounded metadata/tags.
- The waterfall concept is mixed into grid mode, while a separate user-visible waterfall mode is not
  implemented.

Expected behavior:

- "网格" should be a true responsive grid: stable columns, stable cell width, no overlap, and cover/card
  dimensions derived from current container width.
- Every grid card should have the same height within the same responsive grid: cover uses a fixed-ratio
  slot, title is fixed line-count/height, and tags/metadata are bounded or clipped instead of expanding
  the item.
- "瀑布流" should be a separate mode if exposed: it should use `WaterFlow` deliberately, with variable
  item heights and its own acceptance evidence.
- Grid and waterfall must not be conflated. If waterfall is not ready, do not use WaterFlow as the
  implementation behind the "网格" label.

Likely root cause:

- The `GRID` branch renders `PullRefreshWaterFlowScaffold` and `FlowItem`, so item placement depends on
  WaterFlow behavior even though the user selected a grid.
- Current callers do not pass `minColumnWidth` / `onCellSize`, so responsive column sizing is not wired
  into the gallery browsing surfaces.
- `GalleryGridCard` originally limited only the cover ratio. Its title/tags remained natural-flow content,
  so long tag lists could still create masonry-like unequal item heights.

Implementation direction:

- Rewire `ListMode.GRID` on Home, Search, and Favorites to `PullRefreshGridScaffold` + `GridItem`.
- Pass a real `minColumnWidth` and derive columns/cell width from the measured pane/container, using the
  existing `ResponsiveGrid` policy.
- Give `GalleryGridCard` a stable card-size contract: fixed cover ratio, fixed title height, fixed tag/info
  area, bounded tag count, and clipping so content cannot stretch grid rows.
- Add a separate `ListMode.WATERFALL` branch only when the waterfall mode has its own settings entry,
  layout contract, and device evidence. Until then, keep waterfall out of the "网格" path.

Acceptance shape:

- In Home, Search results, and Favorites, selecting "网格" shows a stable responsive grid with uniform
  card heights and aligned rows, not merely a non-overlapping WaterFlow.
- Long titles and many tags are truncated/bounded; they never make one grid item taller than neighbors.
- Foldable outer/inner widths and ordinary phone width produce sensible column counts and readable cover
  sizes.
- Switching list/simple/grid does not leave stale layout artifacts or reuse WaterFlow for grid.
- If waterfall is exposed later, it appears as a distinct choice and is verified separately.

### Gallery Grid Card Information Density Is Wrong

Type: bug / browsing core UX

Priority suggestion: P1

Status: implemented / pending controller acceptance

Implementation:

- `8bc9afb fix(gallery): recover grid and waterfall browsing layouts` rewrites Grid as a compact
  phone-first browsing wall while keeping `ListMode.GRID` on `PullRefreshGridScaffold` / `GridItem`.
- Grid now uses native ArkUI `repeat(auto-fit, <minWidth>vp)` track sizing instead of hand-counted
  columns, with `GALLERY_GRID_MIN_W = 106`, fixed card rhythm, fixed cover slot, title + simple meta,
  and no default tag/rating-heavy block.
- Grid category signal is a shared right-top corner badge: category color is always present, text is only
  shown when translated/language text exists, and the badge is sized to keep 2-3 character labels visible.
- Grid cover rendering remains proportional: normal ratios can crop, large source/slot mismatches use
  contain with the designed list/grid placeholder backing. It does not use non-uniform stretch/fill.

Verification:

- Deterministic contracts:
  `node scripts/test_gallery_grid_mode_contract.mjs`,
  `node scripts/test_gallery_grid_card_visual_contract.mjs`,
  `node scripts/test_responsive_grid_contract.mjs`, and
  `node scripts/test_v1_decorator_inventory_contract.mjs`.
- Signed macOS build passed: `scripts/build_hvigor_signed.sh`.
- HarmonyOS simulator `127.0.0.1:5555`, official signed HAP installed with hdc outside sandbox:
  `.hvigor/outputs/gallery-browsing-layout-recovery/current-after-grey-boundary/screen.jpeg` shows Home
  Grid as three compact columns with the shared corner badge and list/grid placeholder behavior intact.
  Layout dump confirms first-row `GridItem` count `3` with bounds
  `[18,415][354,1113]`, `[372,415][708,1113]`, `[727,415][1063,1113]`.

Remaining acceptance:

- Pending controller/user visual acceptance. Do not reopen this item from historical notes unless current
  screenshots show a fresh Grid regression.

Follow-up, 2026-06-20:

- Preview grids no longer retain the old hand-calculated cell-width path. `PullRefreshGridScaffold`
  removed `onCellSize` / `estimatedColumns` / `estimatedColumnWidth`; `GalleryPreviewGrid` and
  `GalleryAllThumbnailsPage` now use ArkUI `repeat(auto-fit, PREVIEW_THUMB_MIN_W)` directly; and
  `PreviewThumbTile` measures its own real Grid cell width before sizing the sprite thumbnail. This keeps
  the FE strategy of stable preview frames and true-aspect thumbnails without reintroducing caller-side
  column counting.
- FE grounding:
  - `eros_fe/lib/pages/item/gallery_item_grid.dart` keeps a fixed Grid cover slot and switches fit mode
    by source-vs-slot ratio instead of non-uniform stretch.
  - `eros_fe/lib/pages/item/gallery_item_flow.dart` sizes waterfall covers from source dimensions.
  - `eros_fe/lib/pages/item/gallery_item_flow_large.dart` clamps extreme tall covers via
    `max(imgWidth / imgHeight, 1 / 2)`, matching NextE's bounded Waterfall ratio policy.
- Additional validation:
  - `node scripts/test_responsive_grid_contract.mjs`
  - `node scripts/test_gallery_grid_mode_contract.mjs`
  - `node scripts/test_gallery_waterflow_contract.mjs`
  - `node scripts/test_gallery_grid_card_visual_contract.mjs`
  - `node scripts/test_v1_decorator_inventory_contract.mjs`
  - `scripts/build_hvigor_signed.sh`
  - HarmonyOS simulator `127.0.0.1:5555`:
    `.hvigor/outputs/native-preview-grid-cell/detail-preview.jpeg` shows the detail inline preview grid
    as three columns with true-aspect thumbnails and stable page labels;
    `.hvigor/outputs/native-preview-grid-cell/allthumbs.jpeg` shows AllThumbnails as the same three-column
    stable preview grid. The layout dump shows page labels `1..12` aligned in three columns with x bounds
    around `187/531/874`.

Source:

- User screenshot, 2026-06-20: Home grid cards show large empty white areas below the title/tag area and
  appear to omit important browsing information. User asked why this was accepted and noted Waterfall has
  still not been scheduled.
- User clarification, 2026-06-20: the missing signal is more specific than generic density. FE grid keeps
  a persistent top-right category-colored badge whose color identifies the gallery category and whose
  text carries translation/language state. NextE currently gates the badge behind `translated.length > 0`,
  places it at the top-left, and therefore loses the always-on category-color signal.
- User clarification, 2026-06-20: Grid should be a compact phone-first browsing wall. On a regular phone
  it should show three columns, use a fixed cover container close to the A-series / `1 / sqrt(2)` ratio,
  and keep the below-cover text minimal (title + date/simple metadata). It should not carry the richer
  tag/rating-heavy semantics of Waterfall Large.
- Read-only NextE inspection:
  - `ThemeConstants.GALLERY_GRID_MIN_W = 150`, which produces two columns on ordinary phone widths
    (`floor((contentWidth + gap) / (150 + gap))`). That is too wide for the intended compact grid.
  - `ThemeConstants.GALLERY_GRID_COVER_RATIO = 0.7`, which is close to `1 / sqrt(2)` if ArkUI
    `aspectRatio` is width / height; the ratio direction is acceptable, but the cell width and info block
    make the result feel like a large card rather than a compact grid tile.
  - `GalleryGridCard` still contains a tag sample and rating/meta row, and its persistent category signal
    is not actually persistent because the category-colored badge is rendered only when
    `gallery.translated.length > 0`.
  - Existing grid visual contracts encode the current mixed design instead of the intended compact
    3-column grid contract.
- Read-only `eros_fe` inspection:
  - `eros_fe/lib/pages/item/gallery_item_grid.dart` small grid card shows cover, translated/category
    corner, page count/favorite overlay, title, and post time. It does not show tag chips.
  - `eros_fe/lib/pages/item/gallery_item_flow.dart` is the smaller Waterfall item and is mostly cover-only.
  - `eros_fe/lib/pages/item/gallery_item_flow_large.dart` is the richer waterfall card with cover,
    rating/favorite, title, and tags.
  - `eros_fe/lib/pages/setting/layout_setting_page.dart` exposes separate list modes: list, simple list,
    waterfall, waterfall large, and grid.

Observed behavior:

- NextE's current Grid is structurally a real Grid, but the product semantics are still muddled:
  the cell width pushes ordinary phones toward two columns, and the info area borrows tag/rating-heavy
  ideas from richer Waterfall cards instead of staying compact.
- The category/translation badge is not an always-on category signal. It is conditional on translation text
  and positioned differently from the FE grid mental model.
- The result is neither FE-like compact Grid nor a richer Waterfall Large card; it looks unfinished despite
  passing the earlier "no WaterFlow / fixed height" contracts.
- Earlier acceptance only covered scaffold separation, no overlap, uniform row height, and responsive
  columns. It did not validate information density or whether the visible fields are the right fields
  for browsing.

Expected behavior:

- Grid remains a true responsive `Grid` with uniform cells, not WaterFlow.
- Ordinary phone widths should render three grid columns. Foldable/tablet widths can derive more columns
  from the same responsive min-width policy, but the phone baseline must not be a two-column large-card
  layout.
- The cover container should remain fixed-ratio and close to A-series `1 / sqrt(2)` vertical cover shape.
- Cover imagery must stay proportional. `Cover` is allowed only as equal-scale cover/crop when the source
  image ratio is close enough to the current slot; it must never become non-uniform stretch/fill. When
  source ratio and slot ratio differ materially, use `Contain` so the whole cover remains visible.
- Grid information should be deliberately minimal: cover, persistent category-colored translation/language
  badge, page/favorite overlay, short title, and date / simple metadata. Tags and rich rating blocks belong
  to Waterfall / Waterfall Large unless a later product decision explicitly adds them to Grid.
- The category-colored badge should be always present as a category signal, not conditional on
  `translated.length > 0`. Text can prefer translated/language, but the color/category signal must remain.

Cover fit / placeholder / backdrop scope:

- Historical FE grounding exists in `docs/parity-driver.md` and
  `docs/plans/active/gallery-visual-navigation-regression-contract.md`: `eros_fe`
  `/Users/honjow/git/eros_fe/lib/pages/item/gallery_item.dart` `_CoverImage` defaults to
  `BoxFit.cover`, then switches to `BoxFit.contain` only for large aspect-ratio mismatch:
  adaptive mode uses `imageRatio > 1 || imageRatio < 3 / 5`; fixed-height mode compares
  `imageRatio = imgWidth / imgHeight` against `containRatio = coverImageWidth / coverImageHeight` and
  uses contain when `imageRatio - containRatio > 0.28` or `containRatio - imageRatio > 0.2`.
- FE also has `EhSettingService.blurringOfCoverBackground` / `blurring_cover_background`: when the
  foreground cover uses `Contain`, the background can be another same-cover `CoverImg(blurHash: true,
  fit: BoxFit.cover)` instead of a plain gray fill.
- NextE should preserve that product model in HarmonyOS terms: compute cover fit from current slot ratio
  and available source dimensions; use proportional `Cover` for close ratios, proportional `Contain` for
  large mismatches, and never use non-uniform stretch/fill.
- `Contain` gaps are a backdrop problem, not an image-fit excuse. Current fallback can be the existing
  theme placeholder, but the stable target for exposed primary-cover surfaces is a same-cover blurred
  backdrop rather than a harsh gray block.
- Loading/error states are different from loaded-state letterbox gaps. Loading/error may continue to use
  explicit placeholders and spinner/error affordances.
- Do not generalize primary-cover backdrop changes to every thumbnail. List/header/grid/simple/waterfall
  thumbnails may keep stable placeholders where they protect loading, scroll rhythm, and retained layout.
- If the implementation uses shared `EhThumbnail`, new no-gray or blurred-backdrop behavior must be
  opt-in by surface/presentation mode. Do not change global thumbnail defaults in a way that removes
  placeholders from list browsing or reintroduces cover distortion.

Likely root cause:

- The previous Grid repair over-corrected for masonry risk by locking a large info block and clipping
  content, then used a tag sample as the secondary content. That solved row alignment but did not define
  a complete Grid information hierarchy.
- The visual contract encoded the incomplete hierarchy, so it allowed the screenshot failure to pass.

Implementation direction:

- Rework Grid as a compact 3-column browsing wall, not a large-card or waterfall hybrid.
- Re-ground against `eros_fe` grid and waterfall variants: FE grid's post time and compact metadata,
  FE waterfall-large's rating/tags, and NextE/HarmonyOS scanning needs.
- Update `ThemeConstants.GALLERY_GRID_MIN_W` / responsive contract so ordinary phone width yields three
  columns while avoiding four columns on common phone widths unless the product deliberately allows it.
- Update `GalleryGridCard` to a fixed-height compact layout: persistent top-right category-colored badge,
  fixed cover ratio, title, and date/simple meta. Remove tag chips and rich rating-heavy blocks from the
  default Grid card unless a later lane explicitly designs a separate rich-grid variant.
- Update `scripts/test_gallery_grid_card_visual_contract.mjs` so it no longer locks the current
  incomplete tag/rating hybrid as acceptable.

Acceptance shape:

- Home, Search, and Favorites Grid screenshots on regular phone width show three compact columns, stable
  equal heights, and no large empty white region under normal data.
- Grid cards show a persistent category-colored top-right badge; the category signal is visible even when
  translated/language text is missing.
- Grid card below-cover information is minimal and readable: short title + date/simple metadata.
- Grid cards remain readable on outer-screen phone width and expanded foldable/tablet width.
- Long title/tag data is bounded without making the item masonry-like.
- Contract proves the compact grid width, persistent category badge, no default tag-chip block, and fixed
  card rhythm.

Previous implementation / evidence:

- Commit: `b85353d fix(gallery): improve grid card density`.
- Scope: `GalleryGridCard` keeps true fixed-cell Grid semantics, but the info block now shows title,
  compact post-time/rating metadata, and a bounded one-line tag sample instead of the previous large
  sparse tag area. Home, Search, and Favorites continue to route `ListMode.GRID` through
  `PullRefreshGridScaffold` + `GridItem` + `GalleryGridCard`.
- Deterministic gates: `scripts/test_gallery_grid_card_visual_contract.mjs`,
  `scripts/test_gallery_grid_mode_contract.mjs`, `scripts/test_responsive_grid_contract.mjs`, and
  `scripts/test_v1_decorator_inventory_contract.mjs`.
- Remaining acceptance: controller/user visual review of current Grid screenshots on target devices.

Reopen reason:

- Current user feedback rejects the current visual target: phone Grid still does not match the expected
  compact three-column FE grid mental model, and the category-color signal is not persistent. Treat the
  previous implementation as partial scaffolding, not accepted UX.

### Waterfall Mode Width And Viewport Are Broken After Launch

Type: browsing mode bug / layout correctness

Priority suggestion: P1

Status: implemented / pending controller acceptance

Implementation:

- `8bc9afb fix(gallery): recover grid and waterfall browsing layouts` repairs Waterfall as a distinct
  `ListMode.WATERFALL` branch using `PullRefreshWaterFlowScaffold` / `WaterFlow` / `FlowItem`, not the
  Grid scaffold.
- Waterfall now uses native ArkUI `repeat(auto-fit, <minWidth>vp)` track sizing with its own
  `GALLERY_WATERFALL_MIN_W = 160`; it no longer shares Grid width or hand-calculated `cellWidth`.
- Waterfall viewport avoidance now uses `contentStartOffset` / `contentEndOffset` rather than
  top/bottom `WaterFlow.padding`, preserving the floating chrome semantics without padding-region
  disappearance.
- `GalleryWaterfallCard` keeps masonry semantics: cover height follows EH source aspect ratio within
  bounds (`0.5..1.35` width/height) so extreme strip/webtoon covers cannot make a card unboundedly tall,
  and `forceCoverFit` crops inside the bounded slot instead of showing list/grid grey letterbox.
- Waterfall uses the same shared category corner badge as Grid while keeping richer title/rating/tags
  semantics separate from compact Grid.

Verification:

- FE grounding: `eros_fe/lib/pages/item/gallery_item_grid.dart` defines min/max fixed cover-ratio guards;
  `eros_fe/lib/pages/item/gallery_item_flow_large.dart` uses `max(imgWidth / imgHeight, 1 / 2)` to clamp
  extreme tall covers. NextE follows this product strategy in HarmonyOS-native form.
- Deterministic contracts:
  `node scripts/test_gallery_waterflow_contract.mjs`,
  `node scripts/test_gallery_grid_mode_contract.mjs`,
  `node scripts/test_responsive_grid_contract.mjs`, and
  `node scripts/test_v1_decorator_inventory_contract.mjs`.
- Signed macOS build passed: `scripts/build_hvigor_signed.sh`.
- HarmonyOS simulator `127.0.0.1:5555`, official signed HAP installed with hdc outside sandbox:
  `.hvigor/outputs/gallery-browsing-layout-recovery/waterfall-bounded-cover-final/screen.jpeg` shows
  Home Waterfall as two columns, bounded variable-height masonry, no fixed-ratio grey letterbox on
  visible covers, and the shared corner badge.
  Layout dump confirms first-row `FlowItem` count `2` with bounds
  `[18,415][531,1529]` and `[549,415][1062,1189]`.

Remaining acceptance:

- Pending controller/user visual acceptance. Search/Favorites use the same branches and contracts, but
  this device pass directly captured Home; reopen only for a fresh surface-specific regression.

Current feedback:

- User feedback, 2026-06-20: the current Waterfall mode is "completely unusable"; widths are wrong.
- Side inspection confirms a likely root cause: `PullRefreshWaterFlowScaffold` renders `FlowItem() {
  GalleryWaterfallCard({ gallery: g }) }`, and `GalleryWaterfallCard` / `EhThumbnail` rely on
  `.width('100%')` without an explicit stable item/cell width. If `FlowItem` does not strongly constrain
  its child to the resolved WaterFlow column width, the card can resolve an incorrect width.
- `PullRefreshWaterFlowScaffold` also still uses `WaterFlow.padding.top/bottom` for immersive
  title/bottom-bar avoidance. This repeats the Grid padding-region bug shape and should be fixed before
  Waterfall is called complete.

Expected behavior:

- Waterfall should be a distinct user-visible mode with correct column widths, masonry placement, and
  stable card widths on Home, Search, and Favorites.
- The card width should be derived from the current WaterFlow column/container width, not from an
  ambiguous `%` chain inside `FlowItem`.
- Waterfall should not use top/bottom padding as immersive chrome avoidance; use real spacer content /
  overlay-safe viewport modeling before acceptance.
- Grid and Waterfall semantics must remain separate: compact fixed-cell Grid vs variable-height masonry.

Implementation direction:

- Treat current Waterfall launch as scaffold-only and broken until width is corrected.
- Give `FlowItem` / its child wrapper an explicit width derived from the measured column width, or pass
  `cellWidth` to `GalleryWaterfallCard` so the card and thumbnail use deterministic width.
- Remove top/bottom `WaterFlow.padding` for immersive chrome and replace it with real spacer content or a
  WaterFlow-compatible equivalent.
- Update contracts so they prove width constraint and no top/bottom padding, not merely that `WaterFlow`,
  `FlowItem`, and `GalleryWaterfallCard` strings exist.

Acceptance shape:

- Home, Search, and Favorites Waterfall screenshots show correct column widths, no oversized/narrow cards,
  and real masonry variable-height placement.
- Slow-scroll under translucent top/bottom chrome does not make Waterfall items disappear in padding
  regions.
- Device/simulator evidence should include at least regular phone width and foldable/tablet width.
- Contract locks: explicit width path, no immersive top/bottom padding, Grid and Waterfall stay separate.

Previous implementation:

- NextE now exposes one `Waterfall` mode as the first waterfall launch, leaving separate
  `Waterfall Large` parity for a future lane.
- `feature/settings/src/main/ets/pages/LayoutSettingsPage.ets` adds `ListMode.WATERFALL` to the
  persisted view-mode selector with i18n label `view_waterfall`.
- Home, Search, and Favorites add a separate `ListMode.WATERFALL` branch that renders
  `PullRefreshWaterFlowScaffold` + `FlowItem` + `GalleryWaterfallCard`.
- `GalleryWaterfallCard` is a distinct masonry card: cover height follows bounded EH source aspect
  ratio, and its compact title/meta/tag block is not constrained by Grid's fixed info-area heights.
- Grid remains unchanged as the fixed-cell branch using `PullRefreshGridScaffold` + `GridItem` +
  `GalleryGridCard`.

Verification:

- Android eros_fe FE comparison on device `fa967a75`:
  `.hvigor/outputs/gallery-waterfall-launch-fe/fe_style_page.png` and
  `.hvigor/outputs/gallery-waterfall-launch-fe/fe_list_style_options.png` show `列表样式` with
  separate `瀑布流`, `瀑布流 - 大`, and `网格` options.
- Deterministic contracts:
  `node scripts/test_gallery_grid_mode_contract.mjs`,
  `node scripts/test_gallery_waterflow_contract.mjs`,
  `node scripts/test_settings_layout_entry_contract.mjs`,
  `python3 scripts/check_i18n_duplicates.py`, and
  `node scripts/test_v1_decorator_inventory_contract.mjs`.
- Signed macOS build passed: `scripts/build_hvigor_signed.sh`.
- HarmonyOS simulator `127.0.0.1:5555` evidence:
  `.hvigor/outputs/gallery-waterfall-launch-nexte/mode_menu.png` shows the NextE layout menu with
  `列表 / 简洁 / 网格 / 瀑布流`, and
  `.hvigor/outputs/gallery-waterfall-launch-nexte/home_waterfall.png` plus
  `home_waterfall.json` confirm the Home page renders `WaterFlow:1` / `FlowItem:3` after selecting
  Waterfall.

Previous remaining acceptance, now superseded:

- Controller/user should review the Home waterfall screenshot and, if needed, repeat on Search and
  Favorites with live data. Source contracts already lock all three surfaces to the distinct
  Waterfall branch.

Superseded by current feedback:

- User reports the current Waterfall width is not usable, so screenshot review is no longer enough.
  The next lane must fix width/viewport correctness before asking for controller acceptance again.

Source:

- User feedback: Waterfall has not been arranged despite repeated discussion of Grid vs Waterfall
  separation.
- Read-only NextE inspection:
  - `shared/src/main/ets/state/ListModeState.ets` defines `ListMode.WATERFALL`.
  - `shared/src/main/ets/components/PullRefreshWaterFlowScaffold.ets` exists and is exported.
  - `feature/settings/src/main/ets/pages/LayoutSettingsPage.ets` only exposes list, simple, and grid.
- Read-only `eros_fe` inspection:
  - `layout_setting_page.dart` exposes both `waterfall` and `waterfallLarge` separately from `grid`.
  - `waterfall_flow.dart` routes small waterfall to `GalleryItemFlow` and large waterfall to
    `GalleryItemFlowLarge`.

Expected behavior:

- Waterfall should be a distinct user-visible mode, not hidden behind Grid and not treated as already
  implemented because scaffolding exists.
- It needs its own card semantics and acceptance:
  - small Waterfall can be cover-first / cover-only masonry;
  - large Waterfall can be rich cover + rating/title/tags masonry;
  - settings entry must make the mode explicit.

Implementation direction:

- Do not launch Waterfall in the same lane as Grid card information repair.
- Decide whether NextE first exposes one Waterfall mode or separate Waterfall / Large Waterfall options.
- Add settings/i18n, route Home/Search/Favorites through the existing WaterFlow scaffold, and add
  contracts that `ListMode.GRID` and `ListMode.WATERFALL` stay separate.

Acceptance shape:

- Settings exposes Waterfall as a distinct mode.
- Home, Search, and Favorites render Waterfall with masonry semantics and no Grid row-alignment contract.
- Switching list/simple/grid/waterfall does not leave stale layout state.
- Device screenshots show clear visual distinction between Grid and Waterfall.

### Detail Header Cover Flickers After Opening From List

Type: bug / UX regression

Priority suggestion: P1

Status: accepted

Implementation:

- `34b08d1 fix(gallery): seed detail cover dimensions` carries parsed list/search/favorites cover
  dimensions through `GalleryDetailParams`, seeds `GalleryDetailPage` with `imgWidth/imgHeight`, and
  keeps the detail header cover on the real-ratio path from the first frame instead of waiting for
  detail HTML enrichment.
- Scope: list/search/favorites gallery-result opens into detail. Sparse URL/deep-link opens still
  start without dimensions and use the existing gdata/detail enrichment path.

Evidence:

- Deterministic contracts: `scripts/test_gallery_detail_seed_cover_contract.mjs`,
  `scripts/test_gallery_data_parser_contract.mjs`, `scripts/test_cover_presentation_contract.mjs`,
  and `scripts/test_v1_decorator_inventory_contract.mjs`.
- Official macOS DevEco/Hvigor signed build: `scripts/build_hvigor_signed.sh`, installed
  `entry/build/default/outputs/default/entry-default-signed.hap` on Mate X7 target
  `127.0.0.1:5555`.
- Device evidence from Home list row → detail: `/private/tmp/nexte_detail_cover_flicker_nexte_evidence/`,
  especially `after_install_start.png`, `verified_early.png`, `verified_early.json`,
  `verified_settled.png`, and `verified_settled.json`.
- Android FE comparison evidence for the detail-page product semantics:
  `/private/tmp/nexte_detail_cover_flicker_fe_comparison/fe_detail.png`.
- Current-main contract recheck, 2026-06-19: `scripts/test_gallery_detail_seed_cover_contract.mjs`,
  `scripts/test_gallery_data_parser_contract.mjs`, `scripts/test_cover_presentation_contract.mjs`, and
  `scripts/test_v1_decorator_inventory_contract.mjs` all passed. No product code changed after the
  existing Mate X7 device evidence in this acceptance update.

Closure:

- Accepted for the list-to-detail header cover seed/flicker bug. No repeat fold/unfold matrix is
  required unless later changes touch list sizing, detail header cover presentation, or thumbnail
  routing again. No product code changed in this acceptance update.

Source:

- User-reported current behavior.

Observed behavior:

- After opening a gallery detail page from a list row, the detail header cover flashes briefly.

Expected behavior:

- The detail header should paint from the list-row seed and transition into the loaded detail state without a visible cover flash.
- If the fetched detail data updates the same cover URL or only enriches metadata, the cover surface should remain visually stable.
- If the fetched detail data truly changes the cover URL or image dimensions, the transition should still avoid a blank/placeholder flash unless the old cover is invalid.

Why this matters:

- The list-to-detail path is a high-frequency navigation flow.
- A flashing header cover makes the detail page feel unstable even when the gallery data loads correctly.

Likely failure mode:

- `GalleryDetailPage` seeds the ViewModel from the list-row `GalleryDetailParams`, then
  `GalleryDetailViewModel.fetchAndApply()` merges gdata/detail results into `gallery`.
- If the merge changes `thumbUrl`, source dimensions, or the `EhThumbnail` input identity, the thumbnail
  component may reset its loading/error state and briefly show the loading/placeholder layer.
- This is distinct from the older cover-presentation shape bug and from the sub-tab empty-state flash gate.

Likely modules to inspect:

- `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets`
- `feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets`
- `feature/gallery/src/main/ets/components/GalleryHeaderCard.ets`
- `shared/src/main/ets/components/EhThumbnail.ets`
- `shared/src/main/ets/model/EhGallery.ets`

Implementation direction to evaluate:

- Reproduce on device/simulator first with a list-row open, capturing the initial header paint and the post-detail-merge state.
- Compare seed gallery fields and loaded detail fields for `thumbUrl`, `thumbUrlL`, `imgWidth`, and `imgHeight`.
- Preserve the already-painted seed cover while richer detail metadata loads when the actual cover URL is equivalent.
- If thumbnail state reset is necessary for a real URL change, keep the previous rendered image until the new one is ready where ArkUI supports that behavior.
- Add a deterministic contract that treats list-to-detail header-cover stability as separate from cover shape/presentation acceptance.

Acceptance shape:

- Open a gallery detail page from a visible list row.
- The header cover appears immediately from the row seed.
- During detail/gdata enrichment, the header cover does not flash blank, placeholder, or loading overlay over the already-painted image.
- The final loaded detail header still uses the correct cover presentation, rounded visible image content, and current cover fallback behavior.

### Grid Items Disappear In Immersive Chrome Padding Region

Type: gallery grid rendering / immersive chrome viewport bug

Priority suggestion: P1

Status: implemented / pending controller acceptance

Source:

- User feedback, 2026-06-20: in Grid mode only, gallery cards can disappear abruptly when they enter the
  top/bottom "pending" / immersive chrome area, even though the card is still visually expected to be
  visible through the semi-transparent title/bottom bars. List mode does not show the same issue.
- Related UX note: next-page loading currently appears to trigger only at the physical bottom; a smoother
  model would also prefetch when the final or near-final rendered item enters the visible range.

Current implementation notes:

- `PullRefreshListScaffold` models top/bottom immersive chrome as real spacer `ListItem`s. Its List only
  uses horizontal padding, so content can continue rendering underneath the semi-transparent chrome.
- `PullRefreshGridScaffold` models the same top/bottom avoidance as `Grid.padding.top` and
  `Grid.padding.bottom`.
- HarmonyOS Grid documentation says Grid padding has special child display behavior: a `GridItem` partly
  inside the content area and padding may display, but an item fully inside the padding area may not
  display. This matches the observed Grid-only disappearance.
- Home, Search, and Favorites Grid branches all use `PullRefreshGridScaffold`, so the issue is shared.
- `PullRefreshWaterFlowScaffold` also uses top/bottom padding; future Waterfall may inherit the same bug
  unless it is designed with real spacer content instead of padding-as-viewport.
- Home, Search, and Favorites pagination currently wire `onReachEnd -> vm.loadMore()`. The shared scaffolds
  expose `onScrollIndex` for list mode, but current gallery call sites do not use it for near-end prefetch.

Expected behavior:

- Grid cards should keep rendering while they are visually under / behind the semi-transparent top or
  bottom chrome. The immersive area is still part of the visible reading/browsing canvas.
- Top/bottom chrome should behave as overlay, not as a Grid padding region that removes visible content.
- The last grid row should still be scrollable above the bottom bar when needed; this requires real spacer
  content at the end, not a `Grid.padding.bottom` avoidance hack.
- Pagination should start before the user physically hits the bottom, ideally when the visible end index
  is within a small threshold from `itemCount - 1`.

Implementation direction:

- Stop using `Grid.padding.top` / `Grid.padding.bottom` for immersive title/bottom-bar avoidance in
  `PullRefreshGridScaffold`.
- Replace top/bottom Grid padding with real full-row spacer content, matching the List scaffold model.
  Prefer proper full-row `GridItem` / irregular item support so the spacer scrolls as part of Grid content.
- Keep only horizontal Grid padding for layout margins.
- Add / tune explicit `cachedCount` only as a secondary smoothness guard, not as the root fix.
- Add a shared near-end pagination event to `PullRefreshGridScaffold` and `PullRefreshListScaffold`, based
  on visible end index and a configurable threshold, guarded by existing `canLoadMore()` / `isLoadingMore`.
- Audit `PullRefreshWaterFlowScaffold` before launching Waterfall; it must not repeat the same
  top/bottom-padding-as-immersive-inset bug.

Acceptance shape:

- Home, Search, and Favorites Grid mode: slow-scroll cards under the bottom bar and top chrome; cards do
  not disappear while still visually expected through semi-transparent chrome.
- The final grid row can still be scrolled above the bottom bar and is not permanently hidden by overlay.
- List mode remains unchanged and does not regress.
- On a long Home/Search/Favorites gallery list, slow-scroll near the bottom and verify next-page loading
  starts before hitting the terminal footer.
- While a page load is in flight, continued scrolling does not enqueue duplicate `loadMore()` requests.
- Deterministic contract covers: `PullRefreshGridScaffold` no longer uses top/bottom Grid padding for
  immersive inset, top/bottom spacer content exists, near-end trigger wiring exists for Grid/List, and
  duplicate-load guards remain in the VM path.

Implementation / evidence:

- Commit: `d2a65d2 fix(gallery): keep grid cards visible under chrome`.
- Scope: `PullRefreshGridScaffold` now models top/bottom chrome avoidance as real full-row `GridItem`
  spacer content and keeps `Grid.padding` horizontal-only. Home, Search, and Favorites Grid branches pass
  `itemCount`, a near-end threshold, and `onNearEnd -> vm.loadMore()` while retaining the existing
  `canStartBottomRefresh -> vm.canLoadMore()` guard.
- Deterministic gates:
  - `node scripts/test_grid_immersive_spacer_contract.mjs`
  - `node scripts/test_gallery_grid_mode_contract.mjs`
  - `node scripts/test_responsive_grid_contract.mjs`
  - `node scripts/test_gallery_waterflow_contract.mjs`
  - `node scripts/test_v1_decorator_inventory_contract.mjs`
  - `git diff --check`
- Build gate: `scripts/build_hvigor_signed.sh` passed on 2026-06-20.
- Simulator evidence: installed `entry-default-signed.hap` on local `127.0.0.1:5555`, switched Layout
  settings from `瀑布流` to `网格` through the real UI, and captured Home Grid before/after scroll:
  `.hvigor/outputs/grid-immersive-spacer-nexte/home_grid_confirm.png`,
  `.hvigor/outputs/grid-immersive-spacer-nexte/home_grid_scrolled.png`,
  `.hvigor/outputs/grid-immersive-spacer-nexte/home_grid_confirm_layout.json`,
  `.hvigor/outputs/grid-immersive-spacer-nexte/home_grid_scrolled_layout.json`.
- Runtime layout proof: before scroll `Grid: 1 / GridItem: 5 / WaterFlow: 0 / FlowItem: 0`; after scroll
  `Grid: 1 / GridItem: 6 / WaterFlow: 0 / FlowItem: 0`. The scrolled screenshot shows grid cards still
  rendered behind the translucent bottom navigation bar instead of disappearing in the chrome region.
- Controller still needs to accept the visual behavior on target devices; Waterfall spacer behavior remains
  a separate future audit and was not changed in this lane.

Maintenance boundary:

- Do not revert `PullRefreshGridScaffold` back to top/bottom `Grid.padding` for title/bottom-bar
  avoidance. The real full-row spacer model is the current baseline because padding regions can unload
  cards that are still visible behind translucent chrome.
- Do not treat safe-area/chrome issues as a reason to merge Grid back into WaterFlow or to remove Grid
  scaffold semantics. Fix safe-area behavior inside the relevant scaffold.
- When Waterfall width/viewport is repaired, it should use the same overlay-safe principle: real spacer
  content or an equivalent content-space model, not top/bottom padding that creates a non-rendering
  pending region.

### Grid And Waterfall Scroll Do Not Drive Title-Bar Auto-Hide Immediately

Type: gallery browsing / title-bar scroll linkage regression

Priority suggestion: P1

Status: implemented / pending controller acceptance

User feedback:

- 2026-06-20: in Grid/Waterfall modes, scrolling upward does not immediately drive the top title/header
  auto-hide. The list appears to scroll inside its own reserved top space first; only after reaching that
  internal boundary does the outer HDS title-bar behavior start responding.
- During this phase, cards can be visible under the title/header chrome but unreadable because the title
  has not moved with the scroll.

Read-only NextE inspection:

- `entry/src/main/ets/pages/Index.ets` binds the HDS title auto-hide to the active tab scroller through
  `.dynamicHideTitleBar(...).bindToScrollable([this.titleScroller])`.
- Home/Favorites retained sub-tabs correctly pass the active page's `Scroller` upward.
- Current `PullRefreshGridScaffold` and `PullRefreshWaterFlowScaffold` both render their scrollable
  content with the same `Scroller`, but they now use
  `.contentStartOffset(this.topSpacerHeight())` and `.contentEndOffset(this.bottomSpacerHeight())`.
- Earlier documentation/acceptance described "real full-row spacer content"; the current source is not
  that exact model. `contentStartOffset` may create an internal leading scroll reserve that does not
  behave the same as normal content for HDS title-bar auto-hide.

Expected behavior:

- The first upward scroll gesture on Grid/Waterfall should move content and drive HDS title/header
  hide together, like List mode.
- There should not be a hidden internal top-reserve phase where content scrolls behind a still-visible
  title/header before the title auto-hide starts.
- Top/bottom chrome avoidance must still avoid the older Grid padding disappearance problem; do not
  restore top/bottom `Grid.padding` / `WaterFlow.padding`.

Implementation direction:

- Audit `contentStartOffset` / `contentEndOffset` behavior with HDS `bindToScrollable`. If they do not
  participate in title auto-hide like normal content, replace them with real content spacers or another
  HDS-compatible content-space model.
- Grid and Waterfall should share the same overlay-safe scroll model. Fix both scaffolds together if
  they share the same `contentStartOffset` issue.
- Keep horizontal padding only for layout margins.
- Do not solve this by disabling title auto-hide, adding page-local top padding, or moving content under
  the title without scroll linkage.

Acceptance:

- Home Grid: first upward scroll starts hiding the title/header immediately and content remains readable.
- Home Waterfall: same behavior; no internal top-reserve phase before title movement.
- Search/Favorites Grid/Waterfall use the same scaffold behavior.
- Cards still render under translucent chrome without disappearing, and final rows remain reachable above
  the bottom tab bar.
- Deterministic contracts must distinguish real content spacer / compatible content-space behavior from
  `Grid.padding` and should not call a `contentStartOffset` rewrite accepted until device evidence proves
  title-bar linkage.

Implementation update:

- Commit: this lane's Grid/Waterfall scroll-linkage fix.
- Scope:
  - `PullRefreshGridScaffold` replaced `contentStartOffset` / `contentEndOffset` with real spacer
    `GridItem`s. Full-row behavior comes from `GridLayoutOptions.irregularIndexes`, so native
    `repeat(auto-fit, ...)` remains the column model and no hand-calculated column count is restored.
  - `PullRefreshWaterFlowScaffold` removed `contentStartOffset` / `contentEndOffset`, uses a real top
    `FlowItem` spacer and native `footer` bottom spacer, while preserving native
    `repeat(auto-fit, GALLERY_WATERFALL_MIN_W)`.
  - Contracts updated so Grid/Waterfall cannot regress back to non-content offset reserve or top/bottom
    padding.
- Contracts:
  - `node scripts/test_grid_immersive_spacer_contract.mjs`
  - `node scripts/test_gallery_waterflow_contract.mjs`
  - `node scripts/test_responsive_grid_contract.mjs`
  - `node scripts/test_gallery_grid_mode_contract.mjs`
  - `node scripts/test_gallery_grid_card_visual_contract.mjs`
  - `node scripts/test_all_thumbnails_page_jump_contract.mjs`
  - `node scripts/test_v1_decorator_inventory_contract.mjs`
  - `git diff --check`
- Build:
  - `scripts/build_hvigor_signed.sh` passed with existing warnings only.
- Device evidence:
  - Target: local HarmonyOS emulator `127.0.0.1:5555`; no real devices used.
  - Waterfall before: `.hvigor/outputs/grid-waterfall-scroll/before.jpeg`
  - Waterfall after short upward scroll: `.hvigor/outputs/grid-waterfall-scroll/waterfall-short-scroll.jpeg`
  - Grid before: `.hvigor/outputs/grid-waterfall-scroll/grid-before.jpeg`
  - Grid after short upward scroll: `.hvigor/outputs/grid-waterfall-scroll/grid-short-scroll.jpeg`
  - Visual result: in both modes, one short upward scroll immediately hides the main HDS title/header
    while leaving the selector/bottomBuilder visible; no initial internal reserve-only scroll phase was
    observed.
