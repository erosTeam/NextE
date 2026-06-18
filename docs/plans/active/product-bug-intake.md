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
  `implemented / needs FE comparison`, `implemented / needs controller acceptance`, `accepted`,
  `blocked`, or `parked`.
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
- User-visible UI/interaction repair lanes must capture an Android `eros_fe` comparison before
  acceptance: device/page path, screenshot or observation notes, main information, primary/secondary
  action weight, control type, and immediate state feedback. If Android/ADB/FE evidence is unavailable,
  mark the item `implemented / needs FE comparison` or blocked instead of accepted.

## Intake Items

### Reader Starts From Wrong Image When Opening Later Thumbnail Pages

Type: bug

Priority suggestion: P0/P1

Status: parked / superseded by live-apply UX repair

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

### Detail Header Cover Flickers After Opening From List

Type: bug / UX regression

Priority suggestion: P1

Status: active / needs reproduction

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

### Gallery Detail Primary Read Action Should Move To FAB / Smart Grip Lane

Type: UX redesign / feature enhancement

Priority suggestion: P1

Status: active / design pending

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

Implementation direction to evaluate:

- Remove read/resume from the detail header card only after the replacement FAB path is ready.
- Add a primary FAB that launches Reader with the same current start/resume behavior.
- Move favorite affordances to title/menu/action semantics with clear current-state feedback.
- Add capability-checked smart grip support as an enhancement, with ordinary FAB fallback.
- Keep this separate from cover presentation, list responsive cover sizing, SearchFilter, Reader gesture, and auth-cookie-login lanes.

Acceptance shape:

- Detail first-read state: FAB launches Reader from page 1, without covering critical content or bottom gesture areas.
- Detail resume state: FAB clearly shows resume intent and opens the saved page.
- Favorited/unfavorited states remain discoverable after favorite controls leave the header card.
- Ordinary FAB layout works on devices without smart grip support.
- If smart grip is implemented, it has a capability check and does not break the ordinary FAB path.
- Device/simulator evidence covers at least first-read and resume states, plus available favorite-state evidence.

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

### Search Filter Sheet Edits Commit Before Apply

Type: bug / search workflow

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- Implementation review while validating tag-to-search and Search filter behavior.

Observed behavior:

- Opening the Search filter sheet and tapping filter controls could write directly into the shared
  `SearchFilterState` before the user pressed Apply.
- Closing the sheet without applying could leave active filters changed silently, so a later search or
  apply action could use filter state the user never committed.

Original expected behavior:

- Filter sheet edits are draft-only until Apply.
- Closing/backing out of the sheet discards uncommitted changes.
- Reset is an explicit commit of the empty filter: it closes the sheet and reapplies the current
  query with defaults.

Superseded behavior:

- Later user feedback and Android FE comparison changed the product requirement: Search filters should
  live-apply with immediate visual feedback, no primary Apply button, and Reset as the only explicit
  action. Keep the old evidence as history only; do not restore this Apply/draft model unless a new
  product decision reverses the live-apply lane.

Implementation:

- `e704771 fix(search): draft filter changes before apply` adds local draft fields to
  `SearchFilterSheet`, syncs them from the active filter on each sheet open, and confines active
  `SearchFilterState` writes to `commitDraft()`.
- `GallerySearchPage` now passes an `openSeq` signal so each new sheet open re-syncs the draft from
  the current committed filter.
- `05a9fe8 fix(search): keep filter actions reachable` moves Apply/Reset out of the scroll content
  into a fixed sheet action bar, so the default medium detent exposes commit actions without requiring
  users to expand the sheet.

Evidence:

- Deterministic contracts/gates: `scripts/test_search_filter_draft_contract.mjs`,
  `scripts/test_search_filter_action_bar_contract.mjs`,
  `scripts/test_search_input_contract.mjs`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build: `bash scripts/setup-local-build-profile.sh` and
  `bash scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened Search via detail tag query `other:"rough translation"`, selected `Manga` in the filter
  sheet, closed with Back, reopened and confirmed the list remained unfiltered; selected `Manga` again
  and tapped Apply, sheet closed and visible results became Manga; reopened and tapped Reset, sheet
  closed and visible results returned to unfiltered/Doujinshi. Evidence directory:
  `/private/tmp/nexte_search_filter_draft_evidence/`, especially
  `search_filter_draft_selected.png`, `search_filter_reopen_after_cancel.png`,
  `search_filter_after_apply.png`, `search_filter_before_reset.png`, and
  `search_filter_after_reset.png`.
- Follow-up Mate X7 emulator pass for the fixed action bar: default medium sheet detent shows
  `重置` and `应用` at bounds `[50,2268][1030,2393]`, no sheet expansion required; tapping `Manga`
  and then Apply from the medium detent closes the sheet and applies Manga results; reopening and
  tapping Reset from the same detent closes the sheet. Evidence directory:
  `/private/tmp/nexte_search_filter_action_bar_evidence/`, especially
  `search_action_bar_sheet_initial.png`, `search_action_bar_sheet_initial.json`,
  `search_action_bar_after_apply.png`, `search_action_bar_after_apply.json`,
  `search_action_bar_before_reset.json`, and `search_action_bar_after_reset.png`.

Remaining acceptance:

- Needs controller/user review of the current evidence. No further device validation is required
  unless Search filter sheet state ownership, apply sequencing, or Search filter persistence changes.

### Search Filter Sheet UX Quality And Interaction Model Are Not Acceptable

Type: UX / interaction bug

Priority suggestion: P0

Status: implemented / pending device acceptance

Source:

- User-reported current device behavior: search scope, category, and rating controls looked clickable
  but did not visibly update until another scope change forced the sheet to rebuild; the search filter
  entry was also hidden from favorite search and some action-seeded search states.
- Follow-up user feedback: the sheet is still visually low quality; category chips lack color
  semantics; FE likely supports long-press category inverse/solo behavior; rating should be a formal
  segmented/radio-like control; and the interaction model should apply filters live instead of using
  same-weight Apply and Reset actions.

Grounding:

- Required FE comparison target before more NextE product code: Android `eros_fe` search / gallery
  advanced filter surface, especially category color semantics, long-press category behavior, rating
  control shape, live-vs-Apply model, Reset placement/weight, and search-scope expression. FE is the
  product-semantics reference only; NextE should use HarmonyOS/HDS-native controls and not copy pixels.
- Primary information: selected search scope, selected category mask, selected minimum rating, and
  major active toggles should be visually scannable at first glance.
- Primary action: changing scope/category/rating/toggles should immediately update both visual state and
  the active search filter/requery. Secondary action: Reset clears filters explicitly.
- Usable loop: open Search from normal/tag/favorite paths, open filters, tap category/rating/scope,
  see immediate visual feedback and live reapplication, long-press a category for quick solo/invert,
  then Reset if needed. This lane does not change query parser correctness or favorite backend
  semantics unless FE comparison proves a search-scope behavior gap.
- HarmonyOS expression: native segmented controls for scope and rating, category-colored V2 buttons
  with long-press affordance, reset as the only explicit action, and stable title/page-level filter
  entry.

Android FE comparison evidence:

- Device: `fa967a75` (`model:22061218C`, `device:zizhan`) over ADB.
- Package: `com.honjow.fehviewer` (`eros_fe`), version `1.9.2`, foreground activity
  `com.honjow.fehviewer/.MainActivity`.
- Input method: ordinary `adb shell input` was rejected by Android `INJECT_EVENTS`; after user
  authorization, navigation used `adb -s fa967a75 shell su -c ...`.
- Evidence directory: `/private/tmp/nexte_search_filter_fe_comparison`.
- Key screenshots/layout dumps:
  `fe_home.png` / `.xml`, `fe_search.png` / `.xml`, `fe_filter_initial.png` / `.xml`,
  `fe_filter_open.png` / `.xml`, `fe_filter_after_manga_tap.png` / `.xml`,
  `fe_filter_after_doujinshi_long.png` / `.xml`, `fe_filter_rating_segment.png` / `.xml`,
  `fe_filter_rating_4_selected.png` / `.xml`, `fe_filter_favorite_scope.png` / `.xml`, and
  `fe_filter_restored.png` / `.xml`.
- Observed FE scope: a formal three-way segmented control (`Gallery`, `Watched`, `Favorite`).
- Observed FE categories: two-column, strong semantic-colored category buttons; all categories start
  selected/colored. Tapping `Manga` immediately turns it grey/off without changing scope.
- Observed FE long press: long-pressing `Doujinshi` while it is selected leaves `Doujinshi` selected
  and turns the other categories grey/off, matching the quick solo/invert mental model.
- Observed FE rating: an advanced minimum-rating switch reveals a segmented `2/3/4/5` star control;
  tapping `4` immediately selects that segment.
- Observed FE model: no primary Apply button in the filter view; state changes are immediate. Reset is
  a secondary icon action near the advanced-options switch. Favorite scope hides gallery category and
  advanced options.

Current NextE repair scope:

- Replace the old draft/Apply model with live filter edits: scope, category, rating, page range, and
  toggles update `SearchFilterState` immediately and bump `applySeq` for persist/requery.
- Use HarmonyOS `TabSegmentButtonV2` for scope and rating instead of fake Row/Text segmented controls
  or chip text blocks.
- Use a V2 category button component with `EhConstants.categoryColor(...)` semantic category colors,
  immediate selected/off state, and long-press solo/invert behavior.
- Keep the filter trigger as a native title-bar action across normal, tag/action-seeded, loading,
  error, result, and favorite search states.
- Remove the primary Apply button; keep Reset as the only explicit low-weight action.
- Queue a pending filter reapply when the user changes live filters during an in-flight search, and
  clear stale filter-only results when Reset leaves no query and no active filter.

Superseded FE/ADB preflight before the Android device was connected:

- Installed Android platform-tools through Homebrew on macOS; `adb` is available at
  `/opt/homebrew/bin/adb`.
- `adb version` reports Android Debug Bridge `1.0.41`, version `37.0.0-14910828`.
- `adb devices -l` started the ADB daemon but returned no connected Android devices:
  `List of devices attached` with no targets.
- This preflight blocker is now superseded for the Search filter lane by the connected-device evidence
  above. Keep it only as environment history, not as an active blocker for this item.
- Because no Android device is visible, NextE cannot yet run:
  `adb shell pm list packages | grep -i -E "eros|eh|hentai"`, launch `eros_fe`, capture screenshots,
  or verify FE category colors, long-press behavior, rating control shape, live-apply behavior, Reset
  weight, or search-scope expression.
- Follow-up preflight after pushing the branch briefly reported `emulator-5554 offline`; `adb reconnect
  offline` returned to no targets, so the Android target is still unavailable.
- Local Android SDK/emulator setup is also absent: no `emulator`, no `sdkmanager`, no
  `~/Library/Android`, and no existing `~/.android/avd`.
- The `emulator-5554 offline` target is not a usable Android target. Process/port inspection shows it
  comes from the running DevEco HarmonyOS Mate X7 emulator process
  `/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator ... -hvd Mate X7`, listening on
  `127.0.0.1:5555`; ADB sees that port as an offline Android emulator, while HDC is the correct tool
  for that HarmonyOS target.
- Local build/run prerequisites for installing `eros_fe` onto an Android emulator are also absent:
  `flutter` is not on `PATH`, no Java Runtime is installed, and no Android Studio app is present in
  `/Applications`. Installing the full Android/Flutter/JDK/emulator stack is a separate environment
  provisioning task and still would not replace the required connected Android FE screenshot evidence
  until an Android target and `eros_fe` install are available.

Source-only FE grounding already collected:

- `eros_fe/lib/pages/filter/gallery_filter_view.dart` uses `CupertinoSlidingSegmentedControl<SearchType>`
  for search scope (`normal`, `watched`, `favorite`).
- The same FE view hides gallery category and advanced options while `SearchType.favorite` is selected.
- `eros_fe/lib/pages/filter/filter.dart` implements `GalleryCatFilter` as a grid of
  `GalleryCatButton`s. Each button receives `ThemeColors.catColor[catName]` as the enabled category
  color, grey off state, and separate text colors.
- `GalleryCatButton` wraps the button in `GestureDetector(onLongPress: ...)`; normal press toggles the
  category and calls `onChanged`, while long press vibrates and runs the supplied `onLongPress`.
- FE long-press behavior in `GalleryCatFilter` keeps the pressed category unchanged and flips every
  other category to the inverse of the pressed category's current selected state. This provides the
  quick solo/invert mental model the NextE repair must preserve in a HarmonyOS-native way.
- FE minimum rating is not a chip row: `gallery_filter_view.dart` shows an advanced-option switch for
  minimum rating, then a `CupertinoSlidingSegmentedControl<int>` for `2`, `3`, `4`, and `5` stars.
- FE advanced options are persisted through `AdvanceSearchController.advanceSearch` and category state
  through `EhSettingService.catFilter`; `showFilterSetting()` has no dialog actions, so the filter view
  itself is not built around an Apply button. A separate clear/reset control appears only when advanced
  search is enabled.
- This source grounding does not satisfy the mandatory Android/ADB screenshot gate. It only narrows the
  FE observation checklist once a connected Android device is available.

Implementation:

- `886a38f fix(search): repair filter controls` replaces the hand-rolled scope `Row + Text` control
  with `TabSegmentButtonV2`, backed by localized `SegmentButtonV2Items`.
- The category/rating chips are now independent `@ComponentV2` controls with `@Param selected`, so
  tapping a chip updates its visual state immediately instead of relying on a sheet rebuild.
- `GallerySearchPage` now keeps the filter trigger as a native title-bar action with the correct
  `sys.symbol.funnel` icon across history, loading, error, empty, grid, list, simple-list, normal
  search, tag/action search, and favorite search states instead of hiding it when favorite scope is
  active.
- `GallerySearchPage` now uses the title bar for the current scope title and pins the search field in
  the HDS `bottomBuilder`, leaving the title action area available for filter and future actions.
- Favorite scope now keeps the sheet reachable and shows an explicit scope limitation hint for
  gallery-only filters.
- `cd798eb` superseded the earlier candidate for this item by adding category color semantics,
  long-press solo/invert, rating segmented control, and live filter application with no Apply button.
- `cd798eb fix(search): live-apply filter controls` implements the live-apply follow-up described
  above.
- `d0d09f6 fix(search): repair search chrome and clear flow` supersedes the temporary page-overlay
  trigger with title action + bottomBuilder search chrome, moves Reset beside Close in a low-weight
  sheet header, top-aligns the sheet content, fixes the SearchActionState monitor wiring for IME /
  search-button submit, and clears stale results/errors when the user clears the search field.
- Current correction branch: removes the mistakenly added funnel/filter action from
  `SearchPageField.ets`, keeps the bottomBuilder search row input-only, restores the filter entry to
  `GallerySearchPage`'s title/menu action, and disables Search title auto-hide for now so the menu
  action is not made unreachable by the previous layout workaround.
- Current correction branch also improves filter-sheet readability without shrinking text: scope/rating
  segmented controls now use explicit body-size text and bold selected state; category chips keep their
  current two-column semantic-color shape because that region was not the main visual problem; the
  sheet is now a flatter continuous filter form instead of a stack of section headers; `高级选项` is a
  normal switch row that reveals advanced fields; page range inputs are no-border pill fields with
  placeholder and bounded dimensions; advanced option rows use larger readable labels, unified row
  height, and a bounded form width so switches stay visually attached to their labels. The filter sheet
  now opens directly at the large detent instead of offering medium/large sheet stops.

Evidence:

- Deterministic contracts/gates: `scripts/test_search_filter_ux_contract.mjs`,
  `scripts/test_search_filter_draft_contract.mjs`, `scripts/test_search_filter_action_bar_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, `scripts/test_search_input_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`, and
  `git diff --check`.
- Official signed build passed with `scripts/setup-local-build-profile.sh` and
  `scripts/build_hvigor_signed.sh` on macOS; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP
  installed from `entry/build/default/outputs/default/entry-default-signed.hap`.
- NextE evidence directory: `/private/tmp/nexte_search_filter_live_apply_evidence`.
- Follow-up NextE evidence directory for `d0d09f6`:
  `/private/tmp/nexte_search_title_bottom_builder_evidence` (`search_funnel_title.png`,
  `search_funnel_sheet.png`, `search_keyboard_submit.png`, `search_clear_history.png`,
  `search_filter_sheet_topaligned.png`).
- Device observations for `d0d09f6`: title shows the active scope, search input is below the title in
  the bottomBuilder, the right action renders as a funnel and opens the filter sheet, sheet content is
  top-aligned below the header, keyboard Search submits into the search/error/results state, and
  tapping the Search clear button returns to the search-history state.
- Current correction acceptance: the filter action must stay in the title/menu/action area and must not
  be placed inside the search input row. SearchFilterSheet typography acceptance is readable 16-level
  form text and balanced control proportions, not tiny labels or mechanical section headings.
- Key NextE screenshots/layout dumps:
  `nexte_filter_sheet_open.png` / `.json` shows scope as a formal segmented control, two-column
  semantic-colored categories, fixed low-weight Reset, and no Apply button.
- `nexte_filter_manga_off.png` / `.json`: tapping `Manga` immediately changes its background to
  off/grey (`#0C000000` in layout) and the result list behind the sheet refreshes under the live
  filter.
- `nexte_filter_doujinshi_solo.png` / `.json`: long-pressing `Doujinshi` keeps only `Doujinshi`
  colored and turns other categories grey/off; the list behind refreshes to Doujinshi results.
- `nexte_filter_rating_visible.png` / `.json` and `nexte_filter_rating_4.png` / `.json`: rating is a
  segmented control, and tapping `4★` moves selected state immediately.
- `nexte_filter_after_reset.png` / `.json` and `nexte_filter_top_after_reset.png` / `.json`: Reset
  returns rating to `不限` and restores all categories colored/selected without an Apply button.
- `nexte_filter_favorite_scope.png` / `.json`: switching scope to `收藏` selects that segment and hides
  gallery-only category/rating controls behind an explicit limitation hint while the page-level filter
  entry remains visible.

Remaining acceptance:

- Needs controller/user review of the current correction evidence. FE ADB comparison for this filter
  lane is present; further Search UI/interaction work still needs a fresh FE comparison scoped to the
  changed surface.
- Required NextE correction evidence: filter icon is in title/menu/action, not in the search field row;
  category chips and rating segmented shape are preserved; page range inputs read as no-border pill
  range fields rather than blank blocks; SearchFilterSheet no longer adds section headers for every
  control type; advanced options appear as a continuous settings/form list under the ordinary
  `高级选项` switch; option rows read as compact settings rows with switch/label relationship intact;
  `f_sh` copy says `仅搜索已删除` / `Only expunged`, not "show expunged"; Reset remains low-weight next
  to Close.
- Historical NextE evidence before the current correction remains in
  `/private/tmp/nexte_search_filter_ux_repair_evidence/` and
  `/private/tmp/nexte_search_title_bottom_builder_evidence`. Current correction evidence is in
  `/private/tmp/nexte_search_filter_correction_evidence/`, especially
  `nexte_filter_sheet_final.png` and `nexte_filter_final_radius.png`.

### Search Action Routes Can Lose The Second Tag Query

Type: routing / state ownership bug

Priority suggestion: P0

Status: implemented / pending device acceptance

Source:

- User-reported route-stack scenario: open Search from detail tag A, enter another gallery detail from
  the results, then tap tag B. One run crashed; later repeats opened the second Search page without a
  query.
- Root risk: `SearchActionState` was an AppStorageV2 singleton that held live keyword, submit, seed,
  focus, and pending-query state. Multiple Search page instances could coexist, and old/non-top Search
  pages could monitor and clear `pendingQuery` before the newly pushed Search page consumed tag B.

Expected behavior:

- Action-seeded searches from tags/uploader/similar should target a concrete Search session.
- If the current stack top is not Search, push a new Search route with route/session params instead of
  relying on a shared pending keyword bus as the page source of truth.
- Multiple Search pages may coexist; Search(A) must not overwrite, consume, or clear Search(B).

Implementation:

- Pending action state is now a narrow app-wide open/search signal only. `Index.onPendingQuery()`
  consumes it, pushes `SearchPageParams(initialQuery, focusOnAppear=false, sessionId)`, then clears it.
- `GallerySearchPage` owns page-local `SearchPageFieldState` for keyword, submit, seed, filter-open,
  and focus state. It no longer imports or monitors `SearchActionState.pendingQuery`.
- Action-seeded route params seed the page-local search field and immediately run the query on the new
  Search page, so older Search instances cannot consume tag B.
- The Search filter entry belongs in the title/menu/action area so tag search, normal search, favorite
  search, loading, error, and results states keep a stable page-level filter entry without polluting the
  search input row.
- Empty ordinary search no longer implicitly re-runs a network request when filters change; live filter
  reapply requires a non-empty query or explicit favorite scope.
- Advanced options now have a master switch; disabled advanced filters do not emit `advsearch=1` or
  advanced URL params.

Evidence:

- Deterministic contract added: `scripts/test_search_route_session_contract.mjs` covers stacked
  Search(A) -> Detail -> tag B session seeding and asserts `GallerySearchPage` no longer consumes the
  global pending query.
- Related contracts updated: `scripts/test_search_input_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, `scripts/test_search_filter_draft_contract.mjs`,
  `scripts/test_search_filter_settings_contract.mjs`, `scripts/test_search_filter_ux_contract.mjs`,
  and `scripts/test_home_source_routing_contract.mjs`.
- Gates passed: all above contracts, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and `git diff --check`.
- Official signed build passed with `scripts/build_hvigor_signed.sh`; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside the sandbox, official signed HAP
  installed. Evidence directory: `/private/tmp/nexte_search_behavior_model_evidence`.
- Device route-stack check: from Search result detail, tapping the `chinese` tag opened a new Search
  page with `language:chinese` visible in the pinned search field and showed matching results; no crash
  or empty second Search query occurred. Key artifacts: `search_detail_a.png`,
  `search_tag_b.png`, and `search_tag_b.json`.

Remaining acceptance:

- Needs controller/user review before marking accepted.
- Implementation commit: `30ae664 fix(search): isolate action route state`.
- Required NextE acceptance after implementation resumes: category colors are semantically distinct,
  normal tap gives immediate feedback and live requery, long press performs the FE-equivalent quick
  solo/invert behavior with immediate feedback, rating is a formal segmented/radio-like control and
  applies immediately, Apply is absent, Reset remains available, and scope/rating are not naked
  `Row/Text` faux controls.
- Required deterministic contracts after implementation resumes: no primary Apply submit path; category,
  rating, scope, and toggle changes bump the filter reapply path; long-press handler exists for
  categories; category colors come from a semantic mapping; scope and rating use native/HDS segmented
  controls rather than hand-rolled `Row/Text`.

### Search Submit During In-Flight Request Can Drop The Latest Query

Type: search reliability bug

Priority suggestion: P1

Status: implemented / pending controller acceptance

Source:

- Implementation review of the current search input path after the SearchFilter lane was closed.

Current baseline:

- SearchFilter visual shape, filter action placement, and Search title/header auto-hide behavior are not
  part of this item and must remain unchanged.

Observed behavior:

- `GallerySearchPage.onSubmit()` sends the current field text to `SearchViewModel.search()`.
- Before this fix, `SearchViewModel.search()` returned immediately whenever `isLoading` was true.
- If a user submitted one search, quickly changed the keyword, then submitted again before the first
  request completed, the latest query could be silently dropped.

Expected behavior:

- Empty ordinary searches still return to history/blank.
- Favorite-scope empty browse still works.
- While a search is in flight, the latest non-empty submitted query should be queued and run after the
  current request completes, so the UI eventually reflects the user's final submitted keyword.

Implementation:

- `SearchViewModel` now stores a `pendingSearchQuery` while `isLoading` is true.
- When the current request completes, the VM runs the latest queued query if it differs from the
  completed query.
- Clearing the search state also clears any pending submitted query.
- If both a filter reapply and a new submitted query are pending, the new query wins because it will
  fetch with the latest filter state.

Evidence:

- Deterministic contract: `scripts/test_search_input_contract.mjs` now covers in-flight submit queuing.
- Regression contracts: `scripts/test_search_route_session_contract.mjs`,
  `scripts/test_search_scope_contract.mjs`, `scripts/test_search_filter_ux_contract.mjs`.
- Gates: `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  `git diff --check`.
- Official signed build passed with `scripts/build_hvigor_signed.sh`; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP
  installed from `entry/build/default/outputs/default/entry-default-signed.hap`: opened Search,
  submitted `test`, and verified the results page loaded normally with the query still visible.
  Evidence directory: `/private/tmp/nexte_search_pending_submit_evidence/`, especially
  `search_result.png` and `search_result.json`.

Remaining acceptance:

- Needs controller/user acceptance. The exact in-flight race is locked by deterministic contract; the
  device pass covers the changed search submission path in a running signed build.

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
- Current rerun on `origin/main@b93608f`, worktree `codex/reader-core-acceptance`, official signed
  HAP installed on Mate X7 emulator target `127.0.0.1:5555` with hdc outside the sandbox:
  one deliberate left swipe changed `1 / 216` to `2 / 216`, one deliberate right swipe returned to
  `1 / 216`, two-finger `uinput -T -m` pinch zoomed the image, zoomed vertical pan moved the image
  without changing page (`1 / 210`), double tap reset zoom, center tap showed top chrome at the top and
  bottom chrome anchored above the bottom safe area, and ready-image layouts contained no
  loading/progress text. Evidence directory:
  `/private/tmp/nexte_reader_core_acceptance_evidence/`, especially `reader_initial.png`,
  `reader_after_swipe_left_layout.json`, `reader_after_swipe_right_layout.json`,
  `reader_after_pinch.png`, `reader_after_zoom_pan.png`, `reader_after_center_tap.png`, and
  `reader_after_double_tap_reset.png`.

Remaining acceptance:

- Device acceptance is current for the core single-page Reader baseline. Needs controller/user visual
  acceptance of the attached evidence before changing the status to `accepted`.
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

Status: implemented / pending user acceptance

Implementation:

- `8b12dc3 fix(reader): restore zoom surface gestures` reopens the parked zoom-surface gap after the core
  Reader baseline was accepted enough to modify again.
- `ReaderImagePage` now records intrinsic image size from `Image.onComplete`, derives the
  `ImageFit.Contain` display size, and clamps offsets against the actual fitted image bounds rather
  than raw viewport size.
- Pinch uses two-finger `pinchCenterX/Y` and focal-point correction so the pinch center remains stable.
- Double tap is captured on the parent Reader/Swiper as a parallel gesture, then sent to the active
  `ReaderImagePage` through page-local V2 params. This avoids the unreliable child double-tap path
  inside `Swiper`.
- Zoomed pan uses two-axis `PanDirection.All`, but the recognizer distance is raised above the
  viewport while fit-scale so normal horizontal Swiper page turns still win. Once zoomed, the pan
  threshold drops and parent `.disableSwipe(this.imageZoomed)` lets image pan own the drag.
- Scope remains limited to online horizontal Reader per-image transform behavior. It does not change
  Reader resolver, loading/progress, retry/re-source, double-page, vertical-mode, offline reading, or
  download executor behavior.

Evidence:

- Deterministic contract updated: `scripts/test_reader_zoom_quality_contract.mjs` now locks contain
  display-size clamp, pinch-center correction, parent double-tap command routing, two-axis zoomed pan,
  and fit-state pan-threshold arbitration.
- Regression contracts run in the fixing lane: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_double_page_contract.mjs`, `scripts/test_reader_column_mode_switch_contract.mjs`,
  `scripts/test_reader_loading_progress_contract.mjs`,
  `scripts/test_reader_byte_progress_contract.mjs`,
  `scripts/test_reader_failure_retry_ui_contract.mjs`,
  `scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `scripts/test_image_page_reader_seed_contract.mjs`,
  `scripts/test_reader_target_preview_page_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`, and
  `git diff --check`.
- Official signed build passed with `scripts/build_hvigor_signed.sh`; no `dev.sh` was used.
- HarmonyOS Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP
  installed. Clean-branch evidence directory:
  `/private/tmp/nexte_reader_zoom_surface_clean_evidence`.
- Final device route: list -> gallery detail -> Reader. Evidence shows fit-state horizontal swipe
  advanced from `1 / 9` to `2 / 9`, double tap zoomed the image, two-axis drag moved the zoomed
  viewport, and `uinput -T -m` pinch changed the zoomed viewport again. Key artifacts:
  `reader_clean_initial.png/json`, `reader_clean_fit_swipe.png/json`,
  `reader_clean_doubletap.png/json`, `reader_clean_drag.png`, and `reader_clean_pinch.png/json`.

Remaining acceptance:

- Needs controller/user acceptance of the gesture feel on device before marking accepted.
- Implementation commit: `8b12dc3 fix(reader): restore zoom surface gestures`.

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
