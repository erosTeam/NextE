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
  Historical PASS logs do not imply current acceptance; use `implemented / pending device acceptance`
  until a current simulator/device/controller acceptance pass exists.

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

Evidence:

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

Evidence:

- Supporting deterministic contracts include list height/responsive cover coverage in `scripts/`.
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

Evidence:

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
