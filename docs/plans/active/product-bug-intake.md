# Product Bug / Feature Intake

Status: active intake from side conversations.

Purpose:

- Capture product-oriented bug reports, feature gaps, and eros_fe behavior notes without interrupting the main implementation thread.
- Keep entries visible to future agents during active-plan review, even after chat context compaction.
- This file is an intake queue, not an implementation claim and not acceptance evidence.

Operating rule:

- Do not treat an entry here as immediate authorization to interrupt an active lane.
- Main-thread scheduling should pull from this file when selecting the next user-visible feature or bug-fix lane.
- Prefer issues that improve core use flows over low-priority parity enhancements.
- Before implementation, verify the relevant eros_fe source behavior and current NextE code path.
- When an intake item is implemented/fixed and committed, update that item with `Status`,
  commit hash, implemented scope, contracts/device evidence, and remaining acceptance gaps.
- Valid status values for handled entries: `implemented`, `implemented / pending device acceptance`,
  `implemented / needs controller acceptance`, `accepted`, or `parked`.
- A small implementation commit does not need to update this file immediately, but once an intake item
  has a clear fixing commit on main, the next control-plane update must mark the item so it no longer
  reads as an unhandled queue item.
  Historical PASS logs do not imply current acceptance; use `implemented / pending device acceptance`
  until a current simulator/device/controller acceptance pass exists.
- Any new UI or feature lane must provide five-line grounding before product-code changes:
  1. Concrete eros_fe page/component/method path.
  2. Primary information and first-screen hierarchy.
  3. Primary and secondary actions with intended visual weight.
  4. This lane's usable loop and explicit non-scope.
  5. HarmonyOS / Next2V / HDS expression, such as segmented control, title-bar bottomBuilder,
     toolbar/menu, FAB, settings row, or list row pattern.
- If those five lines cannot be answered, do not write UI. Contracts, builds, and screenshots verify
  implementation risk; they do not replace source grounding.
- UI screenshot acceptance must inspect hierarchy, spacing, and action weight, not just that controls
  exist.

## Intake Items

### Reader Starts From Wrong Image When Opening Later Thumbnail Pages

Type: bug

Priority suggestion: P0/P1

Status: implemented / needs controller acceptance

Implementation:

- `91f1eb4 fix(reader): seed sparse thumbnail jumps` introduced the first sparse thumbnail-start fix:
  AllThumbnails passes loaded preview seeds and preview-page markers; Reader loads the target preview
  page before gap filling.
- `48f08d0 fix(reader): seed tapped thumbnail image page` extends that fix so the tapped `/s/...`
  image-page URL is passed explicitly, seeded into the target absolute Reader index, resolved first,
  and cached under that index.

Evidence:

- Deterministic contracts: `scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `scripts/test_reader_target_preview_page_contract.mjs`,
  `scripts/test_reader_placeholder_gap_turn_contract.mjs`,
  `scripts/test_image_page_reader_seed_contract.mjs`.
- Follow-up reader contracts that protect the same startup/jump surface:
  `scripts/test_all_thumbnails_page_jump_contract.mjs`, `scripts/test_reader_jump_contract.mjs`,
  `scripts/test_reader_vertical_initial_index_contract.mjs`.
- Final Mate X7 emulator pass on `127.0.0.1:5555` with hdc outside the sandbox and official signed HAP:
  public gallery `https://e-hentai.org/g/3989982/16600a66e8/`, AllThumbnails visible `40..45`,
  tapped page `41`, Reader first screen `41 / 138`, right tap stayed in the correct later range
  (`43 / 138` under the current double-page step setting), left tap returned to `41 / 138`.
  Evidence directory: `/private/tmp/nexte_reader_thumbnail_seed_evidence/`, especially
  `final_allthumbs_40_45.json`, `final_reader_page41_initial.json`,
  `final_reader_after_right.json`, `final_reader_back_to_41.json`,
  `final_reader_back_to_41.jpeg`.

Remaining acceptance:

- Needs controller/user acceptance review of the current evidence; no further device acceptance is
  required unless this Reader/AllThumbnails path changes again.

Source:

- User-reported prior device testing.

Observed behavior:

- In a gallery with multiple thumbnail pages, opening an image from a later thumbnail page can start the Reader from earlier pages instead of the tapped image.

Expected behavior:

- Tapping a thumbnail on page 2/3/etc. should open Reader with that exact image as the first visible page.
- Adjacent previous/next navigation should use the correct global image order.

Why this is likely tricky:

- EH image URLs cannot be derived directly from the gallery URL.
- The expected request chain is:
  1. gallery / thumbnail page
  2. parse each thumbnail's `/s/...` image-page URL
  3. request the image page
  4. parse the real full image URL
- Jumping to a later image needs the target thumbnail page and global index, not only gid/token.

Likely failure mode:

- The all-thumbnails / thumbnail-page click path may pass only a local index or only gallery gid/token.
- Reader may then resolve from the first thumbnail page and start near the beginning.

Likely modules to inspect:

- `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets`
- `shared/src/main/ets/model/RouteParams.ets`
- `feature/reader/src/main/ets/`
- `shared/src/main/ets/parser/EhGalleryImageParser.ets`
- eros_fe reader / gallery image index logic.

Implementation direction to evaluate:

- Preserve each thumbnail item's global absolute index.
- Preserve or pass the parsed `/s/...` image-page URL as a seed when opening Reader.
- Reader startup should prefer the seed image-page URL for the selected index, parse it into the real full image URL, and cache it under that index.
- If no seed URL is available, Reader should first resolve the thumbnail page containing the target index, not default to the first thumbnail page.

Acceptance shape:

- Use a multi-page-thumbnail gallery.
- Navigate to thumbnail page 2/3 or later.
- Tap a middle thumbnail.
- Reader first screen shows the tapped image.
- Previous/next navigation lands on the correct neighboring global indices.

Notes:

- This is a higher-priority user-visible bug than QuickSearch-style parity enhancements.
- Do not implement from memory alone; re-check eros_fe's actual request/index/cache flow before changing NextE.

### Gallery Detail Page Lacks Pull-To-Refresh

Type: bug / UX gap

Priority suggestion: P1

Status: implemented / pending device acceptance

Implementation:

- `7bc3bde feat(gallery): refresh detail page` added detail-page refresh behavior.
- Scope: `GalleryDetailPage` now exposes the project refresh gesture/path, and
  `GalleryDetailViewModel` owns the reload path so refresh preserves the current gallery identity
  instead of navigating away or creating a second fetch mechanism.

Evidence:

- Deterministic contract: `scripts/test_gallery_detail_refresh_contract.mjs`.
- Implementation commit exists on repository history. Treat any historical smoke as supporting
  evidence only; this intake item still needs current device/controller acceptance before marking
  `accepted`.

Remaining acceptance:

- Current simulator/device detail-page pull-to-refresh pass, including successful refresh and
  recoverable failed-refresh behavior where possible.

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

### Very Tall Gallery Covers Break List Row Height

Type: bug

Priority suggestion: P0/P1

Status: implemented / pending device acceptance

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

Remaining acceptance:

- Current targeted device/controller acceptance with an extreme tall/narrow cover fixture or real
  gallery in fixed and adaptive modes.

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

### Gallery Detail Tags Do Not Jump To Search

Type: feature gap / UX gap

Priority suggestion: P1

Status: implemented / pending device acceptance

Implementation:

- `45bc895 feat(gallery): search from detail tags` wires gallery detail tags into the shared Search
  route/action path.
- Scope: `GalleryTagsCard` tag taps dispatch through the existing shared search/navigation path
  rather than adding a separate detail-only search implementation.

Evidence:

- Deterministic contract: `scripts/test_tag_chip_contract.mjs`.
- Implementation commit exists on repository history. Treat historical device evidence as supporting
  context only until current acceptance is recorded.

Remaining acceptance:

- Current simulator/device pass: tap a namespaced detail tag, verify Search opens with the correct
  query and results load, then return to detail normally.

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

### Reader Layout, Gesture, And Loading Stack Is Broken

Type: P0 incident / reading core usability

Priority suggestion: P0

Status: implemented / needs controller acceptance

Implementation:

- `28db792 fix(reader): restore core interaction baseline` stops the unstable Reader enhancement stack
  from sitting on the hot path: streamed byte progress/cache files are parked, complex transform
  coordinator/pan-all gestures are removed from `ReaderPage`, and runtime double-page rendering is
  disabled even when a saved double-page setting exists.
- Reader first load and jump resolving now use a plain centered `LoadingProgress`; once an image URL is
  resolved, the `Image` renders the remote URL directly and clears the loading state through
  `Image.onComplete`.
- Bottom chrome returns to root-bottom anchoring, while horizontal Reader returns to a single full-width
  `Swiper` page. The quick column-mode pill reports off and no longer switches runtime double-page mode.

Evidence:

- Deterministic contracts: `scripts/test_reader_loading_progress_contract.mjs`,
  `scripts/test_reader_byte_progress_contract.mjs`, `scripts/test_reader_zoom_quality_contract.mjs`,
  `scripts/test_reader_double_page_contract.mjs`, `scripts/test_reader_column_mode_switch_contract.mjs`.
- Regression contracts run in the recovery lane: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `scripts/test_reader_slider_spread_contract.mjs`,
  `scripts/test_reader_initial_spread_start_contract.mjs`,
  `scripts/test_reader_failure_retry_ui_contract.mjs`.
- Gates: `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  `git diff --check`, official signed Hvigor build through `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  final evidence shows single full-width image layout, no loading/progress residue after ready, bottom
  chrome anchored at the bottom, one clear horizontal swipe advances the page, double tap zooms, zoomed
  vertical pan moves the image without turning pages, and two-finger `uinput` pinch changes scale.
  Evidence directory: `/private/tmp/nexte_reader_core_recovery_evidence/`, especially
  `step4_single_ready.png`, `step4_single_ready_layout.json`, `step5_chrome.png`,
  `step6_swipe.png`, `step7_doubletap.png`, `step8_pan.png`, `step9_pinch.png`.

Remaining acceptance:

- Needs controller/user acceptance of the recovery screenshots and gesture feel.
- Runtime double-page/spread slider refinements and determinate byte progress are intentionally parked.
  Re-enable them only in separate lanes after preserving the core Reader interaction contract above.

### Reader Loading State Is Unstable And Lacks Image Download Progress

Type: bug / reading UX gap

Priority suggestion: P0/P1

Status: parked by P0 recovery / do not extend before core Reader acceptance

Implementation:

- Superseding note: `28db792 fix(reader): restore core interaction baseline` parks the streamed
  byte-progress/cache-file path because device evidence showed the combined loading/progress/overlay
  stack could leave the Reader visually broken or non-interactive. The image download progress UX remains
  a future lane after core Reader acceptance, not active work.
- `0bf9744 fix(reader): center staged loading` replaces loose Reader loading spinners with a
  dedicated centered line-loading overlay.
- `eaa8408 fix(reader): show streamed image progress` moves the post-resolve image-loading stage
  onto NetworkKit `requestInStream`, writes chunks into a transient Reader cache file, and binds
  `dataReceiveProgress` into the centered loading line percentage.
- `7a88588 fix(reader): clarify failed image retry` replaces the post-auto-retry failed state with
  a shared centered Reader failure overlay in horizontal and vertical modes, keeping the primary
  action as manual re-source retry for the current image.
- `4ac023c fix(reader): center loading overlay` fixes the remaining layout risk from the Reader root
  `Stack({ alignContent: Alignment.Bottom })`: the Reader canvas now defaults to center alignment so
  first-paint loading overlays are centered, while the bottom chrome is explicitly anchored with
  `.align(Alignment.Bottom)`.
- Scope: Reader first-entry / jump resolving uses `reader_loading_resolving`; horizontal and vertical
  image pages show `reader_loading_image` after a real image URL is known and keep it visible until
  `Image.onComplete`.
- The implementation preserves the existing resolver, navigation, zoom, retry, and re-source paths.
- It does not couple online Reader loading to the download queue/offline library; the streamed files
  are transient Reader cache files used for local Image rendering.

Evidence:

- Deterministic contracts: `scripts/test_reader_loading_progress_contract.mjs`,
  `scripts/test_reader_byte_progress_contract.mjs`,
  `scripts/test_reader_failure_retry_ui_contract.mjs`.
- Regression contracts run in the fixing lane: `scripts/test_reader_auto_source_retry_contract.mjs`,
  `scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `scripts/test_reader_placeholder_gap_turn_contract.mjs`,
  `scripts/test_reader_precache_contract.mjs`, `scripts/test_reader_double_page_contract.mjs`,
  `scripts/test_reader_current_image_share_contract.mjs`, `scripts/test_reader_jump_contract.mjs`.
- Gates: i18n duplicate check, V1 decorator inventory, `git diff --check`, official signed Hvigor
  build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened Reader from a public 26P gallery and jumped to page 25; Reader rendered normally with no
  black-screen/dead-loading failure.
  Evidence directory: `/private/tmp/nexte_reader_loading_progress_evidence/`, especially
  `reader_initial.png`, `reader_initial_layout.json`, `reader_jump_loading.png`,
  `reader_jump_loading_layout.json`.
- Follow-up byte-progress emulator pass on `127.0.0.1:5555`, hdc outside sandbox, official signed HAP:
  opened a public 27P gallery, Reader first screen rendered normally, then a swipe advanced from
  `1 / 27` to `3 / 27`.
  Evidence directory: `/private/tmp/nexte_reader_byte_progress_evidence/`, especially
  `reader_early.png`, `reader_early_layout.json`, `reader_after_swipe.png`,
  `reader_after_swipe_layout.json`.
- Follow-up retry UI emulator smoke on `127.0.0.1:5555`, hdc outside sandbox, official signed HAP:
  opened a public gallery detail, tapped `阅读`, Reader rendered the first page normally, and a center
  tap showed chrome with `1 / 12`.
  Evidence directory: `/private/tmp/nexte_reader_retry_ui_evidence/`, especially
  `initial.png`, `detail.png`, `reader.png`, `reader_chrome.png`,
  `reader_layout.json`, `reader_chrome_layout.json`.
- Follow-up center-alignment pass on `127.0.0.1:5555`, hdc outside sandbox, official signed HAP:
  installed `4ac023c`, opened a public 216P gallery from Home -> Detail -> Reader, and verified the
  Reader main path still renders the first image with chrome/page count `1 / 216`; the centered first
  paint behavior is locked by `scripts/test_reader_loading_progress_contract.mjs`.
  Evidence directory: `/private/tmp/nexte_reader_loading_progress_2_evidence/`, especially
  `home.png`, `detail_layout.json`, `reader.png`, `reader_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance of the loading-stage screenshot behavior. The emulator network was
  fast enough that captured screenshots landed after images had loaded, so transient percentage UI is
  protected by contract/build evidence until a slow-network/manual capture is available.
- The failed-image overlay is protected by deterministic contract and official signed build; this
  lane did not force a live EH image failure on device because mutating network/source state would
  exceed the narrow non-destructive smoke scope.

Source:

- User-reported current behavior.

Observed behavior:

- On first entering Reader, the loading indicator can appear at the bottom first, then jump to the center.
- Reader loading is not visually split into the two real stages:
  1. HTML / image-page URL resolution, including possible target thumbnail-page parsing after a jump.
  2. Full image network loading after the actual image URL is known.
- During the second stage, NextE can show a plain black screen or only an undifferentiated spinner,
  with no visible image download progress.

Expected behavior:

- Initial Reader loading indicator should be stably centered from first paint.
- Stage 1 should communicate that the app is resolving/parsing the target image page, not downloading
  the full image yet.
- Stage 2 should display image download progress once the full image URL is available.
- The image loading phase should not look like a dead black screen.

eros_fe behavior:

- `ImageExt` uses `ExtendedImage.network(... handleLoadingProgress: true ...)`.
- In `LoadState.loading`, `eros_fe` reads `ImageChunkEvent` and computes progress as
  `cumulativeBytesLoaded / expectedTotalBytes`.
- `_ViewLoading` delegates to `_ViewLoadingLine`, a centered horizontal progress bar with optional
  percentage text.
- This is simple and direct: once the real image URL is being loaded, users can see progress.

Likely NextE gap:

- `ReaderViewModel` and `ReaderImagePage` already separate URL resolving (`ImageResolveService.resolve`)
  from image rendering, but the UI only exposed a generic `LoadingProgress`.
- ArkUI `Image` completion/error callbacks are used, but no image load-progress UI was surfaced in
  `ReaderImagePage` before `0bf9744`.
- The root `Stack({ alignContent: Alignment.Bottom })` contributed to loose loading indicators appearing
  at the bottom before centered content appeared.

Acceptance shape:

- First Reader entry shows a stable centered loading state; no bottom-to-center jump.
- A deep jump that requires thumbnail-page/image-page parsing clearly shows a resolving stage.
- Once image URL loading begins, loading progress is visible when supported; until then, a centered
  image-loading line is visible instead of a dead black screen.
- Existing Reader navigation, zoom, retry, and re-source behavior remain intact.

### Reader Image Zoom Uses Center-Only Double Tap And Vertical-Only Pan

Type: bug / reading UX gap

Priority suggestion: P1

Status: parked by P0 recovery / do not extend before core Reader acceptance

Implementation:

- Superseding note: `28db792 fix(reader): restore core interaction baseline` removes the complex
  `ReaderImageTransformCoordinator` path from the online Reader hot path. The accepted recovery baseline
  is reliable pinch, double tap, zoomed vertical pan, and horizontal page swipe; focal-point/pan-all
  improvements must come later behind stronger gesture contracts and device evidence.
- `e30a4ec fix(reader): improve image zoom gestures` adds `ReaderImageTransformCoordinator` and
  updates `ReaderImagePage` to zoom toward the actual tap point, apply pinch focal correction, clamp
  offsets against the fitted `ImageFit.Contain` display size, and allow zoomed panning on both axes.
- Scope is limited to online Reader per-image transform behavior. It does not change Reader resolver,
  loading/progress, retry/re-source, navigation, auto-page-turn, orientation, save-original, offline
  reading, or download executor behavior.

Evidence:

- Deterministic contract: `scripts/test_reader_zoom_quality_contract.mjs`.
- Regression contracts run in the fixing lane: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_loading_progress_contract.mjs`,
  `scripts/test_reader_byte_progress_contract.mjs`,
  `scripts/test_reader_failure_retry_ui_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, plus `git diff --check`.
- Official signed Hvigor build passed after `ohpm install` and
  `scripts/setup-local-build-profile.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened Home -> Gallery detail -> Reader, verified image rendering with page counter `1 / 38`, then
  executed image-area double-click/drag smoke and verified Reader still rendered image content with
  page counter `30 / 38` after an earlier bottom-slider misclick was excluded from the acceptance
  claim.
  Evidence directory: `/private/tmp/nexte_reader_zoom_quality_evidence/`, especially
  `reader_initial.png`, `reader_initial_layout.json`, `reader_after_image_gesture.png`,
  `reader_after_image_gesture_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance of the gesture feel on device. The device smoke verifies the
  Reader path remains stable after interaction; exact focal-point transform math is protected by the
  deterministic contract because `uitest` screenshots cannot directly prove the tap coordinate math.

Source:

- Implementation review while grounding Reader online-reading behavior against `eros_fe` product
  semantics and V2Next ArkUI image-preview transform patterns.

Observed behavior:

- Reader double-tap zoom toggled from the center of the image instead of the tapped detail.
- Zoomed pan was vertical-only, which made wide or zoomed-in details hard to inspect.
- Offset bounds were based on the whole component size, not the actual fitted `ImageFit.Contain`
  display size, so letterboxed images could clamp incorrectly.

Expected behavior:

- Double-tap should zoom toward the tapped point, matching the user's focus.
- Pinch should keep the pinch center stable while zooming.
- Once zoomed, the image should pan in both axes while still clamping so black gaps do not appear.

Reference behavior:

- `eros_fe/lib/pages/image_view/view/view_image.dart` uses `pointerDownPosition` in `_onDoubleTap`
  and passes it to `handleDoubleTap`.
- NextE should treat that as product semantics, not target architecture: the implementation follows
  HarmonyOS/ArkUI state and transform patterns from V2Next's `ImagePreviewCoordinator`.

Acceptance shape:

- Open Reader from a real gallery image.
- Double-tap a non-center detail; the image zooms toward that region rather than blindly centering.
- Drag the zoomed image horizontally and vertically; the page remains readable and does not expose
  black gaps or accidentally page-turn while zoomed.

### Reader Double-Page Mode Switch Can Desync Visible Spread And Page Counter

Type: bug / reading UX gap

Priority suggestion: P1

Status: parked by P0 recovery / do not extend before core Reader acceptance

Source:

- Implementation review while grounding Reader navigation against eros_fe.

Observed behavior:

- Switching between single page, double-page A, and double-page B could keep the old absolute image
  index without normalizing it to the target double-page spread start.
- In double-page B, the first spread could render pages 1/2, even though eros_fe treats the first
  even-left spread as the cover page alone, then pages 2/3, 4/5, and so on.
- This could make the visible spread and chrome page number feel out of sync during online reading.

Expected behavior:

- Column-mode switches should normalize the current Reader index using the target mode's spread math,
  then jump the Reader to the matching spread start.
- Double-page B should render page 1 alone on the first spread, then pair pages 2/3, 4/5, etc.
- The top/bottom page counter should continue to describe the first visible page in the current
  spread.

Implementation:

- Superseding note: `28db792 fix(reader): restore core interaction baseline` disables runtime
  double-page rendering in `ReaderPage` because a persisted double-page setting reproduced the
  user-visible failure where the main image was squeezed into the left half of the reading canvas.
  The settings model remains for a later, separately accepted double-page lane.
- `a9a0003 fix(reader): align double-page mode switches` adds mode-specific spread-index and
  spread-start helpers to `ReaderPage`, normalizes `currentIndex` before persisting a new column mode,
  and suppresses the second slot on the double-page B cover spread.
- Scope is limited to online Reader single/double A/double B mode-switch alignment. It does not add a
  thumbnail strip, auto-read controls, offline reader behavior, or download pipeline changes.

Evidence:

- Deterministic contracts: `scripts/test_reader_column_mode_switch_contract.mjs`,
  `scripts/test_reader_double_page_contract.mjs`.
- Regression contracts run in the fixing lane: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_vertical_initial_index_contract.mjs`,
  `scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `scripts/test_reader_placeholder_gap_turn_contract.mjs`.
- Gates: `scripts/test_v1_decorator_inventory_contract.mjs`, `git diff --check`, `ohpm install`,
  official signed Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  before the final fix, double-page B showed pages 1/2; after the fix, double-page B first spread
  showed page 1 alone with chrome text `1 / 16`, `左→右`, and `双页 B`.
  Evidence directory: `/private/tmp/nexte_reader_nav_quality_evidence/`, especially
  `chrome_after_b.png` for the observed pre-fix issue and `final_reader_b.png`,
  `final_reader_b_chrome.png`, `final_reader_b_chrome_layout.json` for the fixed behavior.

Remaining acceptance:

- Needs controller/user screenshot acceptance. No further device validation is required unless Reader
  double-page layout or mode-switch behavior changes again.

### Reader Right-To-Left Double-Page Spreads Kept LTR Slot Order

Type: bug / reading UX gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- Implementation review while grounding Reader double-page behavior against eros_fe.

Observed behavior:

- NextE set the horizontal `Swiper` direction to RTL, but the two images inside each double-page row
  were still rendered in LTR slot order.
- This meant manga/right-to-left double-page spreads did not match eros_fe's visual ordering, where
  the paired page list is reversed when `ViewMode.rightToLeft` is active.

Expected behavior:

- In LTR, paired spreads render lower page index on the left and higher page index on the right.
- In RTL, paired spreads reverse the visual row order so the higher page index appears on the left and
  the lower page index appears on the right.
- Double-page B cover spread keeps page 1 in the right slot under RTL.

Implementation:

- `96860ec fix(reader): reverse rtl double-page spreads` adds Reader spread-slot helpers and reverses
  the `DoublePageReader` row slot order when `ReadMode.RTL` is active.
- Scope is limited to online Reader horizontal double-page visual slot ordering. It does not change
  page resolving, image caching, tap-zone step math, vertical mode, offline reading, or download flow.

Evidence:

- Deterministic contracts: `scripts/test_reader_double_page_contract.mjs`,
  `scripts/test_reader_column_mode_switch_contract.mjs`, `scripts/test_reader_tapzone_contract.mjs`.
- Gate: `scripts/test_v1_decorator_inventory_contract.mjs` reported `0 file(s)`; `git diff --check`
  passed.
- New worktree dependency/build path: `ohpm install`, local signing profile installer, official signed
  Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Reader opened from an 18P gallery; `右→左` + `双页 B` cover spread showed a left `Blank` and right
  `Image` with chrome `1 / 18`; after advancing, paired spread showed two `Image` slots with chrome
  `2 / 18`, `右→左`, `双页 B`.
  Evidence directory: `/private/tmp/nexte_reader_rtl_spread_order_evidence/`, especially
  `rtl_b_cover.png`, `rtl_b_cover_layout.json`, `rtl_b_pair.png`, `rtl_b_pair_layout.json`.

Remaining acceptance:

- Needs controller/user screenshot acceptance of the RTL double-page visual order. No further device
  validation is required unless Reader double-page ordering changes again.

### Reader Double-Page Taps Used Fixed Page Step Instead Of Spread Step

Type: bug / reading UX gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- Implementation review after fixing RTL double-page row order.

Observed behavior:

- Reader double-page tap navigation used a fixed `currentIndex +/- 2` page step.
- That works for ordinary two-page spreads, but double-page B has a single cover spread first.
- From the cover, the next spread should start at page 2; from pages 2/3, previous should return to
  the cover. A fixed `-2` from the pages 2/3 spread can become `-1` and no-op.

Expected behavior:

- Double-page navigation should move by spread index, then map the target spread back to its first
  visible page index.
- Odd-left spreads continue to move 1/2 -> 3/4 -> 5/6.
- Even-left spreads move cover -> 2/3 -> 4/5, and can return from 2/3 to the cover.
- RTL tap inversion still applies: left tap advances, right tap returns.

Implementation:

- `678194b fix(reader): turn double pages by spread` adds spread-aware Reader movement for
  `toPrev()` / `toNext()` when double-page mode is active.
- Scope is limited to tap/center-zone double-page navigation target calculation. It does not change
  Reader resolving, image caching, row visual order, slider UI, vertical mode, offline reading, or
  download flow.

Evidence:

- Deterministic contracts: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_double_page_contract.mjs`, `scripts/test_reader_column_mode_switch_contract.mjs`.
- Gate: `scripts/test_v1_decorator_inventory_contract.mjs` reported `0 file(s)`; `git diff --check`
  passed.
- New worktree dependency/build path: `ohpm install`, local signing profile installer, official signed
  Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Reader opened from a 24P gallery in `右→左` + `双页 B`; left tap moved from cover `1 / 24` to
  paired spread `2 / 24`; right tap returned from `2 / 24` to cover `1 / 24`.
  Evidence directory: `/private/tmp/nexte_reader_rtl_interaction_evidence/`, especially
  `reader_initial_layout.json`, `after_left_layout.json`, `after_right_layout.json`,
  `reader_initial.png`, `after_left.png`, `after_right.png`.

Remaining acceptance:

- Needs controller/user screenshot acceptance of the RTL double-page tap flow. No further device
  validation is required unless Reader double-page navigation changes again.

### Reader Slider Jumps Could Land Inside A Double-Page Spread

Type: bug / reading UX gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- Implementation review after fixing double-page tap navigation.

Observed behavior:

- Reader slider commits jumped directly to the raw 1-based slider page minus one.
- In double-page modes, dragging to an image inside a spread could set `currentIndex` to the second
  image of that spread instead of the spread start.
- Double-page B is the clearest case: page 3 belongs to the 2/3 spread, so the visible spread and
  page counter should settle at page 2, not page 3.

Expected behavior:

- Slider drag preview may show the absolute page being targeted.
- On commit, single-page and vertical modes keep the absolute page target.
- On commit in double-page modes, the target is normalized to the target spread's first visible page.
- Double-page B examples: page 1 -> cover, pages 2/3 -> page 2 spread start, pages 4/5 -> page 4
  spread start.

Implementation:

- `c463098 fix(reader): align slider jumps to spreads` adds `ReaderPage.sliderTargetIndex(page)` and
  routes slider commit jumps through the same spread math used by double-page rendering.
- Scope is limited to Reader bottom slider commit target normalization. It does not change slider
  visual styling, tap-zone navigation, swipe direction, image resolving, vertical mode, offline
  reading, or download flow.

Evidence:

- Deterministic contracts: `scripts/test_reader_slider_spread_contract.mjs`,
  `scripts/test_reader_tapzone_contract.mjs`, `scripts/test_reader_double_page_contract.mjs`,
  `scripts/test_reader_column_mode_switch_contract.mjs`.
- Gate: `scripts/test_v1_decorator_inventory_contract.mjs` reported `0 file(s)`; `git diff --check`
  passed.
- New worktree dependency/build path: `ohpm install`, local signing profile installer, official signed
  Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Reader opened from a 13P gallery in `右→左` + `双页 B`; initial state was `1 / 13`; dragging the
  slider from page 1 to the page-3 position settled at `2 / 13` with two image slots visible.
  Evidence directory: `/private/tmp/nexte_reader_slider_spread_evidence/`, especially
  `reader_initial_layout.json`, `after_drag_layout.json`, `reader_initial.png`, `after_drag.png`.

Remaining acceptance:

- Needs controller/user screenshot acceptance of the double-page slider flow. No further device
  validation is required unless Reader slider or double-page target math changes again.

### Reader Double-Page Starts Could Land Inside A Spread

Type: bug / reading UX gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- Implementation review after fixing Reader double-page slider commits.

Observed behavior:

- Reader route starts, thumbnail starts, image-page URL starts, and direct non-vertical jumps could
  preserve the absolute target image index even when that image was the second page of a double-page
  spread.
- The `DoublePageReader` Swiper still rendered the containing spread, but chrome text, slider value,
  share target, and saved reading progress could describe the second image instead of the first
  visible image.
- Double-page B made the mismatch visible: opening page 3 should show the 2/3 spread with page
  counter `2 / N`, not `3 / N`.

Expected behavior:

- Single-page and vertical starts keep the exact absolute image target.
- Double-page starts and direct jumps normalize the committed `currentIndex` to the target spread's
  first visible image while still allowing the tapped/seed image to be resolved and visible.
- Existing slider, tap-zone, row order, URL/image resolving, and loading-progress behavior remain
  unchanged.

Implementation:

- `1844de0 fix(reader): normalize initial double-page targets` adds
  `ReaderPage.normalizedReaderIndex(index)` and applies it after initial `ReaderViewModel.init()`
  and after non-vertical `jumpToPage()` completion.
- Scope is limited to the committed Reader index for route starts and direct non-vertical jumps.
  It does not change double-page layout, reader settings UI, thumbnail parsing, image resolving,
  or download/offline reading.

Evidence:

- Deterministic contract: `scripts/test_reader_initial_spread_start_contract.mjs`.
- Regression contracts run in the fixing lane: `scripts/test_reader_slider_spread_contract.mjs`,
  `scripts/test_reader_column_mode_switch_contract.mjs`.
- Gate: `scripts/test_v1_decorator_inventory_contract.mjs` reported `0 file(s)`;
  `git diff --check` passed.
- Build/install: `ohpm install`, `scripts/setup-local-build-profile.sh`, and official signed
  `scripts/build_hvigor_signed.sh` passed; signed HAP installed on Mate X7 emulator target
  `127.0.0.1:5555` with hdc outside the sandbox.
- Device validation: public gallery `https://e-hentai.org/g/3989982/16600a66e8/`, detail preview
  first row, tapped the third preview image while Reader was in `右→左 + 双页 B`; Reader opened with
  two image slots and chrome/slider at `2 / 138`, proving the page-3 start normalized to the 2/3
  spread start.
  Evidence directory: `/private/tmp/nexte_reader_initial_spread_evidence/`, especially
  `reader_initial_detail.png`, `reader_initial_detail.json`, `reader_after_thumb3_hidden.json`,
  and `reader_after_thumb3_chrome.png`.

Remaining acceptance:

- Needs controller/user screenshot acceptance. No further device validation is required unless
  Reader startup, direct jump, or double-page target math changes again.

### Download Gallery Task Rows Are Hard To Read

Type: UX / information architecture cleanup

Priority suggestion: P2 / small cleanup behind online reading work

Status: implemented / needs controller acceptance

Source:

- User feedback that the Downloads tab and task rows felt like a settings shell, and that the download
  item hierarchy was too shallow: cover, title, page count, progress/status, and remove action were
  compressed into one row while the remove button consumed too much visual weight.

Implementation:

- `0e0f6ac fix(ui): ground torrent and download surfaces` moved the Gallery / Archiver selector into
  the HDS title-bar `bottomBuilder` and removed settings controls from the scrolling queue body.
- `4e1c314 fix(download): clarify gallery task cards` replaces gallery task `ConciseListRow`s with
  dedicated task cards: cover slot, two-line title, metadata row, progress bar, prominent status text,
  and a low-weight trash icon action.
- Scope stays UI/IA-only. This does not implement a deeper download executor, archive submission,
  retry/backoff, resumability, or offline reader integration.

Evidence:

- Deterministic contracts: `scripts/test_download_workbench_contract.mjs`,
  `scripts/test_download_settings_contract.mjs`, `scripts/test_ui_quality_grounding_contract.mjs`.
- Gates: `scripts/check_i18n_duplicates.py`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `git diff --check`, official signed Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Gallery download tab showed two real gallery tasks with cover/title/meta/progress/status rows, and
  Archiver tab showed the pinned segmented control plus empty queue state without settings rows.
  Evidence directory: `/private/tmp/nexte_download_workbench_ia_evidence/`, especially
  `download_initial.png`, `download_initial_layout.json`, `download_archiver.png`,
  `download_archiver_layout.json`.

Remaining acceptance:

- Needs controller/user acceptance of the task-card visual hierarchy and action weight on screenshots.
  Deeper executor/offline/archive behavior remains explicitly out of scope.
