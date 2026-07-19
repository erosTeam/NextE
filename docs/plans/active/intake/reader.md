# Reader Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- This file is an evidence ledger, not a priority queue. Start from the user's latest request and use `../product-bug-intake.md` for intake writing rules.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Reader Super-Resolution Model Management And Candidate Registry

Type: Reader image enhancement / settings subflow

Priority suggestion: P1 / experimental reading enhancement

Status: implemented / device smoke and integration complete

Grounding:

1. NextE references are `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets` for grouped
   settings, `shared/src/main/ets/components/AppModalScaffold.ets` for sheet presentation,
   `feature/download/src/main/ets/pages/DownloadQueuePage.ets` for circular symbol actions and loading
   state, and `entry/src/main/ets/pages/Index.ets` for full-screen versus Reader-overlay navigation.
   Aidoku is capability reference only; its screen structure and selection treatment are not a UI
   source for NextE.
2. The active reading image is primary. Reader settings only expose the enhancement switch, selected
   installed model, and maximum input height; runtime backend selection remains automatic.
   Model-management rows expose local file identity and download or installed size.
3. The switch is the primary enable/disable control. Model choice is a secondary installed-model menu.
   The management-page row action is a native circular download/delete symbol and becomes an in-place
   `LoadingProgress` while the file is being fetched.
4. The usable loop is: open Reader settings, optionally enter model management without leaving the
   current sheet context, download a model, return, select an installed model, and enable enhancement.
   This lane does not claim Reader-ready performance; representative-page latency remains governed by
   the separate performance incident.
5. HarmonyOS expression uses `@ComponentV2`, one typed downloadable-model registry, routed
   `HdsNavDestination` for the full settings entry, and the Huawei component UX example's one-sheet
   clipped-`Stack` plus horizontal `translate` transition for the Reader-sheet entry. Rows and actions
   remain `ConciseListRow`, native `Menu`/`Switch`, `SymbolGlyph`, and `LoadingProgress`.

State semantics:

- Enhancement enabled/disabled is owned only by the independent switch.
- The model menu contains installed runnable models only; it has no `none` entry.
- If no model is installed, enhancement cannot be enabled and the settings row reports that no local
  model is available.
- Installing the first model selects it without enabling enhancement. Deleting the selected model
  selects another installed model; deleting the last installed model disables enhancement.
- Model management has no selected-row color, checkmark, pressed-state imitation, or text action.
- Backend selection is runtime-owned: an available published NNRT asset is attempted first, then ncnn
  automatically tries Vulkan and falls back to CPU. The retired CPU/Vulkan preference is ignored on
  restore so an old hidden value cannot disable NPU execution.

Candidate boundary:

- Shared-ncnn registry set: ESPCN 2x, Real-ESRGAN x2plus photo, Real-ESRGAN animevideov3 2x,
  waifu2x photo noise0 2x, waifu2x art noise0 2x, waifu2x CUNet noise0 2x, and Real-CUGAN SE
  2x conservative.
- Anime4K remains a shader pipeline rather than a downloadable ncnn model.
- IMDN, RFDN, ECBSR, and FSRCNN require audited converted weights and output contracts before they
  can enter the downloadable registry.
- SwinIR, HAT, and OmniSR require a separately validated mobile graph/runtime and are not allowed to
  appear as nonfunctional placeholders.

Model subtitle extension grounding, 2026-07-19:

1. `eros_fe` has no local super-resolution model-file manager. This extension therefore stays inside
   NextE's existing `ReaderSuperResolutionModelsPage.ModelRow` and reuses the established
   `ConciseListRow` model-management pattern rather than inventing an Aidoku-style screen.
2. The model name remains the primary row information. The first scan should distinguish the seven
   technical model identities; applicability, a device-dependent 800p time tier, and explicitly
   labelled approximate download or installed size remain one subordinate line. Exact test seconds
   are evidence only and never presented as a portable estimate across devices.
3. Download/delete remains the only row action and keeps its existing icon weight. The subtitle is
   informational only; it does not become a picker, badge, selected state, or hit target.
4. The usable loop is model-management entry -> compare scope/performance/size -> download or delete ->
   return to the existing installed-model selector. This extension does not change enablement,
   selection, download state, routing, or the same-panel transition.
5. HarmonyOS expression remains the existing HDS/project list stack: `GroupedListSection`,
   `ConciseListRow.subtitle`, native `SymbolGlyph`, and `LoadingProgress`; no custom-drawn component or
   extra control is introduced.

Model subtitle validation, 2026-07-19:

- Device selector `103` resolved live to `192.168.50.103:12345`. The signed HAP was installed and the
  full-screen user path `Settings -> Reader -> Model management` displayed all six rows with one-line
  `scope · 800p reference · size` subtitles. The longest model titles and subtitles remained intact,
  and every existing download/delete symbol retained its trailing action space. Evidence:
  `.hvigor/outputs/reader-super-resolution-model-subtitles-20260719/03-model-management/`.
- The signed application build passed, the V1 decorator inventory reported `0 file(s)`, i18n parity
  reported identical keys across all four locales, and `git diff --check` passed. This lane did not
  change selection, model download state, routing, or the Reader-sheet same-panel transition.

Acceptance:

- Settings > Reader opens the routed management destination and returns through the normal app stack.
- Reader's medium/large settings sheet transitions between the complete settings and model-management
  pages inside the same panel. Back reverses the horizontal transition without opening a second panel
  or moving to a full-screen overlay.
- Every registered model row has neutral styling, ASCII model punctuation, file size, icon-only
  download/delete action, and an in-place loading indicator during download.
- Model selection, first-install, selected-delete, last-delete, and enhancement-switch guards follow the
  state semantics above.
- Build and static checks pass, then device selector `103` verifies both entry paths and file-state
  transitions. Model quality and representative-page performance remain a separate validation matrix.

Validation, 2026-07-18:

- Device selector `103` resolved live to `192.168.50.103:12345`. Full-page and Reader-sheet entry,
  the original embedded-navigation behavior, download loading state, completed-download action, and
  delete confirmation were verified on the device. After replacing the embedded navigation with the
  Huawei-example same-panel transition, Reader-sheet `阅读 -> 模型管理 -> 阅读` was verified again on
  the same target: the floating sheet remained a single panel, the reverse transition returned to the
  existing Reader settings scroll position, and the bounded after-action hilog contained no crash or
  fatal signal.
- The signed application build and the `entry@ohosTest` HAP build passed. The device test run reported
  `96` tests passed with `0` failures and `0` errors; the six registry models each completed download,
  checksum validation, model load, and Vulkan processing on the small integration fixture.
- The fixture proves model/runtime connectivity only. It does not establish 800p Reader latency or
  perceptual quality; those remain the separate representative-page evaluation requested by the user.

Backend and download-size correction, 2026-07-19:

- The user-facing Auto/Vulkan/CPU row was removed. `ReadModeSettings.restore` now always publishes the
  automatic backend, so a previously persisted CPU or Vulkan choice cannot silently bypass the
  published Real-ESRGAN x2plus NNRT asset. Internal backend values remain available for runtime
  fallback, cache identity, diagnostics, and controlled tests.
- Model rows now label their final segment as approximate download or installed size. ESPCN uses its
  approximately 79 KB source ZIP rather than its approximately 42 KB generated runtime pair;
  Real-ESRGAN x2plus uses its approximately 96 MB complete first-install transfer and reports only the
  remaining approximately 32 MB NNRT asset when the compatible ncnn pair already exists.
- Applied-image information now names ESPCN correctly and reports `NPU` for cached or freshly processed
  NNRT results. The signed application build passed; the V1 decorator inventory reported `0 file(s)`,
  the persistence inventory and four-locale i18n checks passed, and `git diff --check` passed. Current
  device screenshots remain a separate visual acceptance step.

Runtime-asset release integration, 2026-07-19:

- ESPCN, the three waifu2x variants, and Real-CUGAN now request the checked
  `erosTeam/NextE-Models` `ncnn-runtime-assets-v1` Release first. Their pinned official upstream
  locations remain ordered fallbacks. Real-ESRGAN x2plus keeps its separate NNRT Release plus its
  existing compatible-runtime source path, and animevideov3 remains on its existing pinned source.
- Every successful asset transfer records only whether it used the primary or fallback slot, the slot
  index, and byte count; complete URLs are not retained in diagnostics. Downloaded content still has
  to pass the existing exact byte-size and SHA-256 checks before installation.
- Device selector `103` resolved live to `192.168.50.103:12345`. A targeted test deleted the installed
  waifu2x photo pair, downloaded it again, and reported `source=primary index=0` for both the 1,047-byte
  parameter file and the 1,106,248-byte model file. Hypium reported 1 pass, 0 failures, and 0 errors in
  approximately three seconds. The signed `entry@ohosTest` HAP build passed before installation.

Maximum-height contract correction, 2026-07-18:

- The prior service caps made the displayed source-height limit misleading: a hidden 3200 output-edge
  cap rejected every 2x source taller than 1600, and the menu still exposed unsupported values up to
  4000. The service now derives its 2x output guards from the shared 2000 source-height maximum, treats
  exactly 2000 as eligible, and the settings menu exposes only 1000, 1500, and 2000.
- Device selector `103` resolved live to `192.168.50.103:12345`. A targeted test created an exact
  1280 x 1837 source and produced a 2560 x 3674 waifu2x Vulkan output in 21,405 ms. Hypium reported 1
  pass, 0 failures, and 0 errors. This proves the height-limit path for that representative dimension;
  it does not change the separate model-quality or general performance assessment.

Reader status and foreground-contention grounding, 2026-07-18:

1. `../eros_fe/lib/pages/image_view/view/view_widget.dart` establishes the existing centered page
   counter plus already-constrained top and bottom Reader chrome. It has no super-resolution status
   treatment; the requested indicator is grounded in NextE's existing
   `ReaderPersistentPageNumber` and top-bar counter instead of adding another controller button.
2. The reading image remains primary. The first supporting information is the page counter; when
   enhancement is enabled, a subordinate adjacent symbol reports the current page's enhancement state.
3. The settings-sheet switch remains the primary control. The Reader indicator is passive and has no
   hit target; no new top-bar or bottom-bar quick action is added in this lane.
4. The usable loop covers enabled/unprocessed or queued, processing, and enhanced states for the current
   page, plus lower-priority native scheduling so inference does not compete at the default UI QoS.
   Model quality, tile tuning, and a new quick-control interaction remain outside this lane.
5. HarmonyOS expression reuses the existing centered page-status rows, native `SymbolGlyph` with
   `sys.symbol.AI_hd_rectangle`, native `LoadingProgress`, theme tokens, and Node-API background QoS.

Validation, 2026-07-18:

- Device selector `103` resolved live to `192.168.50.103:12345`. On a real 800 x 1148 source page,
  the Reader showed a white `AI_hd_rectangle` while queued, native loading progress while processing,
  and the theme-colored symbol after the 1600 x 2296 result was applied. The same status was visible
  beside the persistent page counter and the expanded top-bar counter.
- The signed application build passed, the V1 decorator inventory reported `0 file(s)`, and a current
  trace recorded `Native async work queueWithQos` before the Vulkan inference callback. During that
  active inference, the measured Reader page-jump frame was 20.447 ms. Opening Reader settings had one
  263.868 ms actual frame; the same sheet opening without active inference reproduced a 223.787 ms
  actual frame, so the dominant remaining settings stall is sheet construction/layout rather than
  continuous inference contention. This trace does not provide a pre-change A/B measurement.
- Real-ESRGAN still took 109.286 seconds for the representative page. Background QoS protects
  foreground scheduling; it does not reduce model inference latency.

Performance continuation, 2026-07-18:

- The accepted waifu2x path now caches the ncnn network and Vulkan pipelines, keeps preprocessing and
  output conversion on Vulkan, uses 128-pixel FP16 tiles with a one-millisecond scheduling gap, runs
  one inference at a time, prioritizes the visible page, preempts stale prefetch, and prepares the
  configured forward preload range. On selector `103`, a warm 800 x 1182 page reported 4,939 ms native
  inference and 5,229 ms end to end. The matching Reader trace had no application or RenderService
  actual frame above 16.67 ms; an auxiliary `rmrenderservice` process had one 33.376 ms sample.
- Larger tiles were evaluated and rejected rather than shipped on timing alone. A 192-pixel tile
  reduced a warm 800 x 1145 inference to 4,538 ms but introduced one 17.199 ms application actual
  frame; a 160-pixel tile measured 4,758 ms and did not retain a meaningful speed advantage. The
  accepted runtime remains at 128 pixels.
- When enhancement is enabled and its selected model is installed, Gallery detail now starts one
  delayed background model preparation after the detail transition settles. On selector `103`,
  waifu2x preparation loaded the Vulkan runtime in 2,502 ms. The next 800 x 1149 Reader page reused
  it with `modelLoadMs=0` and completed in 5,158 ms, versus 8,008 ms for the same cold page without
  preparation. During the preparation interval, the only application actual frame above 16.67 ms was
  22.789 ms and its main-thread trace was `FlushDirtyNodeUpdate` / `Default DecodeInterceptor`; the
  native preparation worker remained on background QoS.
- A repeatable ohosTest benchmark now accepts a selected registry model and processes the same
  synthetic 800 x 1149 input after Vulkan preparation. All six original registry runs passed on
  selector `103`. Native
  inference / end-to-end process times were: waifu2x photo 4,611 / 6,605 ms; waifu2x art 4,616 /
  7,643 ms; Real-ESRGAN animevideov3 8,832 / 10,597 ms; waifu2x CUNet 10,700 / 11,882 ms;
  Real-CUGAN SE conservative 10,863 / 11,598 ms; Real-ESRGAN x2plus photo 87,987 / 88,766 ms.
  Model-load preparation remained outside those process times and returned `modelLoadMs=0` during
  every measured inference.
- ESPCN 2x now enters the registry as the lightweight first option. Installation downloads the checked
  copy of the pinned official Hailo Model Zoo ZIP from the project model Release, with the official
  location retained as fallback, verifies the ZIP and ONNX hashes, deterministically converts the
  three convolution tensors to the matching ncnn FP16 runtime pair, verifies the generated pair, and
  removes the temporary ZIP/ONNX. Nothing is added to the application package; the installed runtime
  pair is about 42 KB. Its full 800 x 1149 Reader process passed on selector `103` in the seconds tier;
  after consolidating RGB reconstruction into one bilinear sample, the recorded run moved from
  7,625 ms to 3,171 ms. Those exact figures remain device evidence only, while the management UI
  reports `800p 数秒级`.
- The downloadable registry and selected-model fallback order now put ESPCN and the two measured
  lightweight waifu2x models first and the Real-ESRGAN x2plus path last. All seven candidates remain
  downloadable and selectable; the management rows keep their existing neutral name/size/action
  presentation. This latency matrix does not replace real-page perceptual-quality comparison.

### Reader Display And Page-Turn Preferences

Type: Reader settings expansion

Priority suggestion: P1 / reading comfort

Status: implemented / device smoke complete

Grounding:

1. `eros_fe/lib/pages/setting/read_setting_page.dart`,
   `features/reader_input_preferences/presentation/reader_interaction_preference_tiles.dart`, and
   `pages/image_view/controller/view_controller.dart` provide the existing fullscreen and page-turn
   animation semantics; background color and persistent page number are NextE additions requested by
   the user.
2. The primary information remains the gallery image; background and page number are supporting
   presentation, and the page number must never intercept Reader gestures.
3. Settings rows are the primary controls. The live Reader sheet provides immediate preview; no new
   Reader chrome action or navigation entry is added.
4. This lane adds black/gray/white/automatic background, page number, fullscreen, keep-screen-on, and
   adjacent programmatic page-turn animation. It does not redesign Reader gestures, image geometry,
   thumbnail geometry, or long-distance seek behavior.
5. HarmonyOS expression uses existing grouped `ConciseListRow` settings, native `Menu`/`Switch`,
   window system-bar and keep-screen-on APIs, API 20+ `TextStyle` filled-text stroke through
   `MutableStyledString`, and native `SwiperController` animation.

Requested defaults:

- Background: black.
- Show page number: enabled.
- Fullscreen: enabled.
- Keep screen on: enabled.
- Page-turn animation: enabled.

Acceptance path:

- Open Reader settings from the live sheet, change each display/screen setting, and see the active
  Reader update without losing the page.
- With chrome hidden, the page number remains readable on black, gray, white, and automatic canvas
  colors and does not intercept tap zones.
- Adjacent tap-zone page turns animate when enabled and change immediately when disabled; swipe
  remains native, while thumbnail/slider long-distance jumps remain non-animated.
- Leaving or covering Reader restores system-bar visibility and releases keep-screen-on.

Evidence:

- `git diff --check`, V1 decorator inventory (`0 file(s)`), four-locale i18n parity, and the official
  signed Hvigor build all pass.
- The signed HAP was installed on `192.168.50.103:12345` and `192.168.50.237:12345`. Both devices
  opened the same real 138-page gallery in Reader with fullscreen black background and the persisted
  page number visible; the user accepted the final lower-opacity native-stroke page-number treatment.

### Reader Settings Live-Preview Sheet

Type: Reader settings presentation improvement

Priority suggestion: P1 / interaction foundation

Status: implemented / pending device acceptance

Source:

- User request, 2026-07-16: replace Reader chrome's pushed settings page with a half-height sheet that
  can expand to full height, so settings effects can be previewed against the active Reader.

Implementation boundary:

- Keep Settings > Reader as the existing routed page.
- Reuse the exact same settings-row content and `ReadModeSettings` writers in both hosts.
- Reader chrome opens a native sheet with `[SheetSize.MEDIUM, SheetSize.LARGE]`; no custom
  gesture, copied settings state, new preference, or Reader rendering redesign.
- The Reader gear button itself owns the sheet visibility and `bindSheet` host; entry only supplies
  the shared settings content through a builder parameter.

Acceptance:

- Phone and tablet layouts both open at the medium detent and can drag to large.
- The medium sheet scrolls the full settings list without moving or closing the Reader.
- Direction and double-page changes update the visible Reader immediately; native picker menus remain
  usable inside both detents.
- Back/down-dismiss and the close action return to the same gallery and reading position.
- Settings > Reader still opens the full routed settings page with the same rows.

Evidence, 2026-07-16:

- Signed build, V1 inventory `0 file(s)`, read-progress contracts, and `git diff --check` passed.
- `192.168.50.237:12345` phone layout: gear opened `SheetPage [0,848][1320,2120]`, drag reached
  `[0,141][1320,2120]`, and close returned to Reader page `103 / 138`.
- `192.168.50.103:12345` tablet layout: gear opened the platform floating sheet at
  `[230,615][1370,1945]`; changing double-page mode updated the visible Reader immediately and the
  test restored the setting. Dragging did not produce a verified large detent on this platform form,
  so tablet large-height acceptance remains open.

### Double-Page Toggle Shifts When The One-Page Step Action Appears

Type: Reader chrome / layout stability bug

Priority suggestion: P2 / narrow interaction polish

Status: implemented candidate / needs device acceptance

Source:

- User report, 2026-07-10: enabling double-page mode inserts the one-page step action between the
  double-page toggle and reading-mode action, causing the double-page toggle to jump horizontally.

Implementation:

- Preserve the right-edge control order as `double-page toggle -> reading mode` in both states.
- Render the conditional one-page step action to the left of the double-page toggle, so enabling
  double-page mode only consumes space from the flexible center gap and does not move the toggle the
  user just pressed.
- Scope is limited to control order; button capability, icon, enabled state, and page-turn behavior
  are unchanged.

Evidence:

- Source order review, V1 decorator inventory, signed Hvigor build, and `git diff --check`.
- Device acceptance must confirm the double-page toggle stays in the same position when switching
  single-page -> double-page -> single-page with Reader chrome visible.

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

### Reader Layout, Gesture, And Loading Stack Is Broken

Type: P0 incident / reading core usability

Priority suggestion: P0

Status: accepted

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
- Current-main contract recheck, 2026-06-19: `scripts/test_reader_loading_progress_contract.mjs`,
  `scripts/test_reader_byte_progress_contract.mjs`, `scripts/test_reader_zoom_quality_contract.mjs`,
  `scripts/test_reader_double_page_contract.mjs`,
  `scripts/test_reader_column_mode_switch_contract.mjs`,
  `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `scripts/test_reader_slider_spread_contract.mjs`,
  `scripts/test_reader_initial_spread_start_contract.mjs`,
  `scripts/test_reader_failure_retry_ui_contract.mjs`, and
  `scripts/test_v1_decorator_inventory_contract.mjs` all passed.
- Android FE reference for this acceptance update: ADB target `fa967a75`, `su` launched
  `com.honjow.fehviewer/.MainActivity`, foreground confirmed by `dumpsys window`, screenshot
  captured at `/private/tmp/nexte_reader_core_acceptance_fe_reference/fe_foreground.png`.

Closure:

- Accepted for the core single-page Reader baseline. Runtime double-page/spread slider refinements
  and determinate byte progress remain parked in separate lanes. Do not re-enable them until their
  lanes preserve the accepted Reader interaction baseline above.

### Reader Loading Indicator Must Not Overlay A Visible Image

Type: visual state regression / reading core polish

Priority suggestion: P1

Status: reopened / needs state-model correction

Source:

- User feedback, 2026-06-21: Reader can show a loading indicator stacked on top of an already visible image.
- User feedback, 2026-06-22: the issue still occurs. The user again observed "正在解析图片" over the current
  displayed image, and cached/pre-resolved forward page turns can still black-flash before the image appears.
  This is not acceptable in any loading scenario.
- User feedback, 2026-06-22 follow-up: normal swipe navigation can stop at EH preview-page boundaries such
  as page 40 or 80. The user cannot swipe to the next page, but tapping the right-side page-turn area triggers
  a resolving/loading state and then enters the next page. This means swipe and tap navigation are using
  different data-loading paths.

Research:

- Current Reader image surfaces render through `Stack` branches. In `ReaderImagePage`,
  `ReaderVerticalImage`, and `ReaderSpreadImageLayer`, the `Image` is rendered when `imageUrl.length > 0`,
  and `ReaderLoadingStage` is also rendered while `imageLoaded` is false.
- That shape is vulnerable to a visible-image/loading-state mismatch: a bitmap can be painted while the
  component still believes `imageLoaded` is false, leaving the spinner/text over the reading image.
- User follow-up clarified this is a design error, not just a missing state reset: normal Reader loading
  should not be modeled as a `Stack` overlay on the image surface. The loading stage should be a mutually
  exclusive placeholder/replacement before the image branch becomes visible.
- Existing Reader recovery evidence claimed "no loading/progress residue after ready", but this user repro
  shows the state model still needs a direct no-overlay contract.
- Current source still has the problematic shape. The root `ReaderPage` uses a bottom-aligned `Stack` and
  can mount `ReaderLoadingStage(reader_loading_resolving)` above ready content for `vm.jumping`; image
  surfaces still use `Stack { Image(...).opacity(this.imageLoaded ? 1 : 0); ReaderLoadingStage(...) }` or a
  resolving branch in the same visual surface. Gating the image with opacity is not the same as separating
  the states; it can hide a valid image and create the black-flash transition.
- The preview-page boundary report points to the deeper model issue: the pager's reachable item set has been
  coupled to the currently loaded preview/image array. Swipe navigation can only move across items already
  present in the `Swiper` data source, while tap navigation can route through `jumpToPage()` and load the
  next preview page. Total gallery page count, preview metadata availability, resolved image URL, and bitmap
  presentation state must be separate concepts.

Expected behavior:

- Resolving/loading states may occupy the page before the image is visible.
- Once a page image is visibly painted, no normal loading/resolving indicator may appear on top of it.
  This applies to HTML parsing, image source resolving, image bitmap loading, far jump resolving, cached
  forward turns, horizontal mode, vertical mode, and double-page/spread mode.
- Prefer a branch structure where loading/resolving content replaces the image until the page is ready,
  instead of placing `ReaderLoadingStage` as a sibling overlay above `Image` in a `Stack`.
- A cached or pre-resolved next page must not be forced through a black/invisible image phase solely while
  waiting for that component instance's `Image.onComplete`.
- Swiping forward at preview-page boundaries such as 40 -> 41 or 80 -> 81 must work the same as tap
  navigation. The pager must have a stable placeholder/reachable item for known total pages even before that
  page's preview metadata or image URL has been loaded.
- Failure/retry UI may replace the image, but loading must not sit on top of readable content.
- Keep the fix narrow: do not reintroduce streamed byte progress, cache-file loading, double-page redesign, or
  broad gesture rewrites for this bug.

Acceptance shape:

- Open Reader on a slow or freshly resolved image and observe the transition from loading to visible image.
- After the image becomes visible, there is no centered `LoadingProgress` or "loading image" text over it.
- Repeat for horizontal single-page, vertical mode, and double-page/spread image layer if that mode is active.
- Add or tighten a runnable contract so the loaded-image branch cannot also render `ReaderLoadingStage` as an
  overlay on the same visible image. Ideally the contract should fail if normal loading is represented as
  `Stack { Image; ReaderLoadingStage }` rather than an exclusive loading-vs-image branch. A source grep that
  only proves `LoadingProgress` exists is insufficient.
- Contract must also fail if a resolved/cached URL path sets the visible image surface back to an invisible
  or black/loading presentation before page turn paint.
- Add or tighten a contract for preview-page boundaries: known `fileCount`/`perPage` must allow the pager to
  expose the next page past loaded preview chunks, and loading placeholders must not make `images.length`
  falsely mean "all previews are loaded".

Implementation:

- Horizontal `ReaderImagePage`, vertical `ReaderVerticalImage`, and double-page `ReaderSpreadImageLayer`
  now render pending images with `.opacity(this.imageLoaded ? 1 : 0)`.
- The existing loading stage remains visible only while `imageLoaded` is false, so it covers an invisible
  pending image instead of readable content.
- Contract: `scripts/test_reader_loading_progress_contract.mjs` now requires the pending-image opacity gate.
- Evidence: official signed build passed; simulator `127.0.0.1:5555` evidence in
  `.hvigor/outputs/reader-loading-overlay/` shows Reader ready state with one Image and no loading/resolving
  text in the layout.

Follow-up, 2026-06-22:

- User reports a forward page turn can still visibly jump/flash black even when the next page has already
  been cached/resolved. If the user then goes back to the previous page and forward again, the second
  forward transition does not show the same loading gap.
- Source evidence: `ReaderViewModel.precacheAhead()` only pre-resolves the next pages' full image URLs.
  In `ReaderImagePage.resolve()`, `ReaderSpreadImageLayer.resolve()`, and `ReaderVerticalImage.resolve()`,
  the fast path for `image.imageUrl.length > 0` still sets `imageLoaded = false` before assigning
  `imageUrl`. The render branch then sets `Image(...).opacity(this.imageLoaded ? 1 : 0)` and shows
  `ReaderLoadingStage` until `Image.onComplete` fires for that component instance.
- This explains the asymmetric behavior: first forward into a pre-resolved page skips network resolve but
  still hides the image while ArkUI completes the `Image`; going back and forward again reuses the cached
  Swiper child whose `imageLoaded` has already become true.
- Expected behavior: a pre-resolved/cached next page should not be forced through a visible black/loading
  transition solely because the component has not fired `onComplete` yet. Keep failure retry and source
  changing intact, but separate "URL is resolved" from "new uncached bitmap must hide readable content."
  Prefer a narrow fix that preserves the previous visible page or treats an already-resolved cached URL as
  ready enough for page-turn presentation; do not reintroduce streamed byte progress or broad Reader
  loading-stack redesign.
- Acceptance: forward page turn to a pre-resolved next page has no black flash/loading jump; returning to
  the previous page and going forward again behaves the same as the first forward transition.

Status, 2026-06-22: reopened after failed controller/user runtime acceptance.

- Correction: user testing showed the first implementation's static proof was incomplete. It warmed
  URLs and hidden `Image` nodes, but each visible Reader surface could still adopt a resolved URL and
  keep `imageLoaded=false` until that specific surface's `Image.onComplete`, causing a visible blank
  transition.
- Scope: horizontal `ReaderImagePage`, vertical `ReaderVerticalImage`, and `ReaderSpreadImageLayer`
  now present any concrete resolved image URL immediately. Resolve-stage loading, `Image.onError`,
  bounded automatic re-source retry, and manual retry remain unchanged.
- Verified: `node scripts/test_reader_loading_progress_contract.mjs`,
  `node scripts/test_reader_precache_contract.mjs`, `node scripts/test_reader_tapzone_contract.mjs`,
  `node scripts/test_reader_seeded_thumbnail_start_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/build_hvigor_signed.sh`, and local
  emulator `127.0.0.1:5555` install/open/turn evidence in
  `.hvigor/outputs/reader-cached-forward-presented-url/`.
- Reopen reason: the previous correction did not prove the actual runtime invariant. User feedback still
  reports loader-over-image and cached forward black-flash. Static contracts that accept opacity-hidden
  images or `ReaderLoadingStage` siblings in normal image surfaces are insufficient and must be replaced with
  a state isolation contract.
- Additional reopen reason: the 40/80 boundary failure shows Reader still treats loaded preview/image array
  length as the pager's reachability model. That is structurally wrong; the user-visible pager range must be
  driven by total page count, with preview metadata/image URL/bitmap display resolved lazily per page.

Reader state-model audit required before closure:

- Core invariant: total page count, pager reachability, loaded preview metadata, resolved image URL, bitmap
  presentation readiness, loading UI, and failure UI are separate states. `images.length` must not be used as
  a proxy for total pages or for "all preview pages are loaded" once placeholders exist.
- Swipe path: horizontal `Swiper.onChange`, double-page `Swiper.onChange`, and vertical `List` scroll must
  be able to reach known pages across preview-page boundaries and must load missing preview metadata through
  the same target-loading path as tap navigation.
- Tap path: left/right tap zones must not have privileged loading behavior that swipe lacks. If tap can reach
  page 41/81, swipe must be able to reach the same target without a separate manual fallback.
- Slider and thumbnail path: slider commits and thumbnail taps must normalize double-page targets, load
  missing preview metadata, and never make placeholder count look like completed preview data.
- Auto-read path: auto-read must wait on the same page-readiness definition used by manual navigation; it
  must not skip, stall, or turn into a black/loading page at preview boundaries.
- Presentation path: a cached or already painted page must not be hidden behind opacity, black frame, or
  normal loading overlay while a new component instance waits for `Image.onComplete`.
- Failure/retry path: failure overlay may replace the failed page, but retry/source resolving must not cover
  another readable page, and auto re-source must not clear pager reachability.
- Mode coverage: the proof must cover horizontal single-page, vertical mode, and double-page/spread mode, at
  least by deterministic contracts plus one installed-device smoke path. If device automation cannot observe
  a mode, mark that mode as not accepted instead of claiming full closure.

### Reader Auto-Read Page Turn Is Missing

Type: feature gap / reading UX

Priority suggestion: P1

Status: implemented / needs controller acceptance

Grounding:

- `eros_fe` reference: `/Users/honjow/git/eros_fe/lib/pages/image_view/view/view_widget.dart`
  `ControllerButtonBar` renders the Auto button; `/Users/honjow/git/eros_fe/lib/pages/image_view/controller/view_controller.dart`
  `tapAutoRead()`, `_startAutoRead()`, `onLoadCompleted()`, and `_autoTunToPage()` implement timer
  advance with `loadCompleMap` gating; `/Users/honjow/git/eros_fe/lib/common/service/ehsetting_service.dart`
  persists `turnPageInv`.
- Product semantics: auto-read is a secondary reader utility. The main information remains the current
  image and page counter; auto-read must not turn into a primary mode switch or separate page.

Implementation:

- Reader bottom chrome now includes a secondary clock control beside Save. Tapping it starts/stops
  auto-read; active state is shown with the brand color.
- Auto-read uses a timer based on the persisted Reader Settings interval and advances only when the
  target page has a preview slot and is real-image ready (`Image.onComplete` or a resolved full
  `imageUrl`). Missing/unresolved targets pause the timer and warm the target instead of jumping to a
  blank page.
- Reader Settings now exposes `自动翻页间隔` / `Auto page interval` with 2s/3s/5s/8s/10s choices,
  persisted via `ReadModeSettings` and `StorageKeys.READING_AUTO_PAGE_SEC`.

Evidence:

- Android FE source grounding above. ADB target `fa967a75`, `su` launched
  `com.honjow.fehviewer/.MainActivity`; current FE device screenshot/layout were captured at
  `/private/tmp/nexte_fe_reader_autoread_current.png` and `.xml`, but automation was still on the FE
  Search page, not Reader, so FE Reader device evidence is not claimed.
- Deterministic contract: `scripts/test_reader_auto_read_contract.mjs`.
- Gates: `scripts/test_reader_auto_read_contract.mjs`, `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_precache_contract.mjs`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `scripts/check_i18n_duplicates.py`, and official signed Hvigor build through
  `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  public gallery `https://e-hentai.org/g/3989982/16600a66e8/` opened Reader from `继续 P3`. Evidence
  directory: `/private/tmp/nexte_reader_auto_read_evidence/`. `chrome_before.png` shows the new clock
  control at `3 / 138`; the first run `after.png` showed the clock active but still stuck at `3 / 138`,
  which exposed an offscreen `Image.onComplete` wait bug. After fixing readiness to include resolved
  `imageUrl`, `after_fixed.png` shows active auto-read advanced to `10 / 138`; `settings.png` shows
  Reader Settings with `自动翻页间隔 3s`.

Remaining acceptance:

- Needs controller/user acceptance of the Reader bottom chrome control and interval settings row. FE
  Reader-page device screenshot remains optional reference material; the implementation is grounded in
  FE source and verified on HarmonyOS runtime.

### Reader Volume-Key Page Turn May Only Be Partially Wired

Type: reading UX / settings behavior gap

Priority suggestion: P1

Status: implemented / pending device acceptance

User feedback:

- 2026-06-20 side conversation: the Reader Settings "音量键翻页" option appears to exist, but the user
  suspects the actual volume-key page turn is not implemented or behaves like a placeholder.

Read-only NextE inspection:

- `feature/settings/src/main/ets/pages/ReaderSettingsPage.ets` exposes a switch row bound to
  `readMode.volumeKeyTurn`.
- `shared/src/main/ets/settings/ReadModeSettings.ets` restores and persists
  `StorageKeys.READING_VOLUME_KEY`.
- `feature/reader/src/main/ets/pages/ReaderPage.ets` contains two volume-key handling paths:
  focused `.onKeyEvent()` on `READER_KEY_SURFACE_ID`, and `inputConsumer.on('keyPressed')` consumers
  for `KEYCODE_VOLUME_DOWN` / `KEYCODE_VOLUME_UP`.
- `volume down` maps to `toNext()`, and `volume up` maps to `toPrev()`.
- `scripts/test_reader_volume_key_contract.mjs` currently passes, but it is a static source-shape
  contract. It proves the code path exists; it does not prove hardware keys page on device.

Likely risk:

- `registerVolumeKeyConsumer()` is called during Reader `onReady()` only if `readMode.volumeKeyTurn`
  is already enabled. If the user enables the setting while Reader is already open or after navigating
  through Reader Settings, there is no visible `@Monitor('readMode.volumeKeyTurn')` path that registers
  or unregisters the `inputConsumer` dynamically.
- If HarmonyOS does not deliver volume keys through the focused `.onKeyEvent()` path, and the
  `inputConsumer` was never registered because the setting changed later, the UI will look like a real
  setting while volume buttons still change system volume.

Expected behavior:

- When the setting is enabled before opening Reader, pressing volume down/up on device should reliably
  page next/previous without showing or changing system volume.
- Toggling the setting while Reader is open should take effect without leaving and reopening the Reader.
- Disabling the setting should unregister the key consumer so volume buttons return to system volume.
- If HarmonyOS cannot intercept volume keys in this app context, the setting must be hidden or marked as
  unsupported instead of presented as a working feature.

Acceptance:

- Implemented in `codex/reader-volume-key-live`: `ReaderPage` now monitors `readMode.volumeKeyTurn`.
  Enabling the setting while Reader is already open requests key focus and registers the InputKit
  volume-key consumers; disabling it unregisters them so volume keys return to the system.
- Deterministic coverage: `scripts/test_reader_volume_key_contract.mjs` now locks the live
  `@Monitor('readMode.volumeKeyTurn')` path in addition to the existing startup/on-close registration.
- Gates run: `node scripts/test_reader_volume_key_contract.mjs`,
  `node scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/build_hvigor_signed.sh`.
- Device smoke: signed HAP installed and app started on local Mate X7 emulator target
  `127.0.0.1:5555`; smoke screenshot:
  `.hvigor/outputs/reader-volume-key-live/app-start.jpeg`.
- Still pending device acceptance: with the setting enabled before Reader entry, volume down/up should
  change page number; toggling the setting while Reader is already open should take effect immediately.
- Device evidence with the setting disabled: volume keys no longer trigger reader page turns.
- Static `scripts/test_reader_volume_key_contract.mjs` remains useful as a floor, but it cannot be used
  as final acceptance for this feature.

### Reader Image Failure States Are Generic

Type: reading UX / error handling gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

Implementation:

- `b7ef697 fix(reader): distinguish image failure states` adds a Reader image failure taxonomy for
  `Generic`, `Quota`, and `RateLimited`.
- `ImageResolveService` already throws `image509` for EH 509 placeholder GIFs; Reader now preserves
  that class through bounded re-source retries and shows distinct quota/rate-limit title and hint text
  in the shared black-canvas failure overlay.
- Both paged `ReaderImagePage` and vertical `ReaderVerticalImage` pass the classified failure kind to
  `ReaderFailureOverlay`.
- Non-scope: eros_fe's pHash/QR `ViewAD` content-hide subsystem remains deferred.

Grounding:

- FE source: `../eros_fe/lib/pages/image_view/view/view_widget.dart` has `ViewErr509`, `ViewErr429`,
  and `ViewError`; `../eros_fe/lib/pages/image_view/view/view_image.dart` maps
  `EhErrorType.image509` to `ViewErr509` and HTTP 429 to `ViewErr429`.
- FE Android device evidence: ADB target `fa967a75`, package `com.honjow.fehviewer`, launched with
  `su -c am start`; screenshot saved at
  `/private/tmp/nexte_reader_error_state_evidence/fe_reference.png`. The screenshot only proves FE
  device/app availability; the 509/429 behavior grounding is source-level because live quota/rate-limit
  reproduction is not deterministic.

Evidence:

- Contracts: `node scripts/test_reader_error_state_contract.mjs`,
  `node scripts/test_reader_failure_retry_ui_contract.mjs`,
  `node scripts/test_image_resolve_showpage_contract.mjs`,
  `node scripts/test_reader_auto_source_retry_contract.mjs`.
- Required gates: `node scripts/test_v1_decorator_inventory_contract.mjs` reported 0 V1 decorator
  files; `python3 scripts/check_i18n_duplicates.py`; `git diff --check`.
- Build: `scripts/build_hvigor_signed.sh` completed `BUILD SUCCESSFUL` on macOS signed Hvigor path.
- HarmonyOS smoke: installed `entry/build/default/outputs/default/entry-default-signed.hap` on Mate X7
  emulator `127.0.0.1:5555` via hdc outside sandbox, opened public gallery
  `https://e-hentai.org/g/3989982/16600a66e8/`, tapped `继续 P138`, and verified Reader rendered an
  image with `138 / 138` chrome and no LoadingProgress/error overlay residue.
  Evidence directory: `/private/tmp/nexte_reader_error_state_evidence/`, especially `detail.png`,
  `detail_layout.json`, `reader.png`, `reader_layout.json`, and `fe_reference.png`.

Remaining acceptance:

- Needs controller/user acceptance of the distinct wording when a real 509/429 is encountered. Live
  509/429 was not forced in this lane to avoid manipulating EH rate-limit/quota state.

### Reader Loading State Is Unstable And Lacks Image Download Progress

Type: bug / reading UX gap

Priority suggestion: P0/P1

Status: implemented / needs controller acceptance

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
- After the core Reader baseline was accepted, this lane was safely reopened without changing gesture
  handling. Current implementation keeps streamed byte-progress/file-cache parked, but restores
  lightweight two-stage centered loading text: `reader_loading_resolving` while preview/image-page URLs are
  being resolved, and `reader_loading_image` after the full image URL is mounted but before
  `Image.onComplete`. The image-loading stage is hit-test disabled and conditionally removed after
  `imageLoaded = true`, so it does not stay over ready images or compete with Reader gestures.
- Current-main verification, 2026-06-19: Android FE reference via ADB target `fa967a75`, `su`-started
  `com.honjow.fehviewer/.MainActivity`, screenshot at
  `/private/tmp/nexte_reader_loading_stage_fe_reference/fe_detail_or_reader.png`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed: opened
  `https://e-hentai.org/g/3989982/16600a66e8/`, tapped the detail FAB `继续 P2`, captured an early Reader
  layout containing centered `正在加载图片` plus page `2 / 138`, and a settled layout with only `2 / 138`
  and no loading text. Evidence directory: `/private/tmp/nexte_reader_loading_stage_acceptance/`
  (`detail.png/json`, `reader_early.png/json`, `reader_settled.png/json`).

Remaining acceptance:

- Needs controller/user acceptance of the lightweight stage behavior on a visibly slow image. True byte
  percentage remains intentionally parked; do not reintroduce stream-to-file image loading without a
  separate Reader interaction risk review.
- The failed-image overlay is protected by deterministic contract and official signed build; this lane did
  not force a live EH image failure on device because mutating network/source state would exceed the narrow
  non-destructive smoke scope.

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

Status: implemented / pending controller acceptance

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
- Current-main acceptance rerun on Mate X7 simulator `127.0.0.1:5555`, signed HAP installed with hdc
  outside sandbox: Reader opened from the public Rockman gallery in double-page mode, center tap showed
  chrome without changing page/zoom, left-page double tap zoomed without chrome, zoomed horizontal pan
  moved the image instead of turning the page, fit-state swipe turned to the next spread, and two-finger
  `uinput -T -m` pinch changed the viewport. Android `eros_fe` was launched with ADB `su` on
  `fa967a75`; the same gallery detail and Reader reference were captured for product-behavior context.
  Evidence directory: `.hvigor/outputs/reader-current-acceptance/`, especially `ready.png`,
  `center.png`, `left_zoom.png`, `zoom_pan.png`, `after_swipe.png`, `pinch.png`,
  `fe_reference.png`, and `fe_reader_try.png`.

Remaining acceptance:

- Controller/user acceptance is still required before marking this accepted. Do not reopen the old
  center-only / vertical-only-pan baseline unless new current-main device evidence contradicts the
  acceptance rerun above.
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

### Reader Gesture Arena Conflicts Need PhotoView-Like Rework

Type: P0 bug / reading core usability

Priority suggestion: P0

Status: implemented / pending controller acceptance

Source:

- `a04a88f fix(reader): arbitrate tap gestures` repaired the concrete double-tap/chrome conflict by
  replacing the horizontal and double-page Reader `Swiper` `onClick` + parallel double-tap mix with
  `GestureGroup(GestureMode.Exclusive, TapGesture({ count: 2 }), TapGesture({ count: 1 }))`, with
  double-tap first as required by ArkUI gesture guidance. It also animates double-tap zoom transitions.
  This does not close the full gesture lane yet: fast swipe feel, pinch feel, zoomed pan feel, and
  controller acceptance remain active.
- Validation for `a04a88f`: Android `eros_fe` was launched via `adb su` on `fa967a75` for Reader product
  reference, deterministic Reader contracts and the full `scripts/test_*contract.mjs` suite passed, V1
  inventory reported `0 file(s)`, i18n parity and `git diff --check` passed, official signed build
  passed via `scripts/build_hvigor_signed.sh`, and Mate X7 simulator `127.0.0.1:5555` installed the
  signed HAP with hdc outside sandbox. Device evidence:
  `.hvigor/outputs/reader-gesture-arena/reader_ready_exclusive.png` and
  `.hvigor/outputs/reader-gesture-arena/reader_doubletap_exclusive.png` show Reader ready with chrome
  hidden, then double-tap zoomed without top/bottom chrome appearing. Earlier failed evidence
  `.hvigor/outputs/reader-gesture-arena/reader_doubletap_current.png` and
  `.hvigor/outputs/reader-gesture-arena/reader_doubletap_consume_tap.png` documents why the previous
  timeout/consume-tap patch was insufficient.
- `fix(reader): reset zoom state on page changes` closes a narrower state-leak subproblem: parent
  `imageZoomed` is cleared before programmatic page navigation, Swiper page changes, double-page spread
  changes, and column-mode changes; cached inactive `ReaderImagePage` instances also reset and notify
  after leaving the active page. This prevents a zoomed old surface from keeping the next fit-scale
  page's Swiper disabled. This does not close the full PhotoView-like gesture lane.
- Validation for the zoom-state reset follow-up: `scripts/test_reader_zoom_quality_contract.mjs` now
  asserts the page-change zoom gate and cached-page reset guards; full deterministic contracts,
  `scripts/test_v1_decorator_inventory_contract.mjs`, i18n duplicate check, `git diff --check`, and
  `scripts/build_hvigor_signed.sh` passed. Mate X7 simulator `127.0.0.1:5555` installed the signed HAP
  with hdc outside sandbox, opened Reader at `3 / 138`, double-tapped to zoom, switched double-page
  column mode back to fit state (`2 / 138`), then performed a horizontal page swipe to `4 / 138`.
  Evidence: `.hvigor/outputs/reader-zoom-gate/reader.png`,
  `.hvigor/outputs/reader-zoom-gate/zoomed.png`,
  `.hvigor/outputs/reader-zoom-gate/after_mode.png`, and
  `.hvigor/outputs/reader-zoom-gate/after_swipe.png`.
- `fix(reader): target double-tap to tapped spread page` closes another narrow double-page gesture
  subproblem: the parent double-tap bridge now routes by the tapped visual half of the spread instead of
  always commanding `activeIndex + 1`. This makes double-tap on the right/second visible page zoom that
  page's image surface rather than the active spread-start page. This still does not close the broader
  PhotoView-like gesture lane or claim full pinch/pan acceptance.
- Validation for the double-page double-tap target follow-up: Android `eros_fe` was launched with
  `adb shell su -c 'am start -n com.honjow.fehviewer/.MainActivity'` and current Reader/all-thumbnails
  screenshots were captured for product-behavior grounding. V2Next `ImagePreviewPage.ets` /
  `ImagePreviewCoordinator.ets` were re-read for HarmonyOS transform/clamp gesture reference. NextE
  deterministic contracts, V1 inventory, i18n duplicate check, `git diff --check`, and signed macOS
  build passed. Mate X7 simulator `127.0.0.1:5555` installed the signed HAP with hdc outside sandbox,
  opened the public Rockman gallery Reader in `双页 B`, and double-tapped the right visible page; the
  right page zoomed into the full reading canvas. Evidence:
  `.hvigor/outputs/reader-gesture-next/fe_reader_ready_su.png`,
  `.hvigor/outputs/reader-doubletap-target/reader_ready.png`, and
  `.hvigor/outputs/reader-doubletap-target/right_zoom.png`.
- `fix(reader): use one surface for double-page spreads` is an interim mitigation, not the final ideal
  double-page architecture: double-page mode now renders each visible spread through one
  `ReaderSpreadSurface` gesture owner and applies zoom/pan to a grouped `Row` containing one or two
  `ReaderSpreadImageLayer` children. The image layers only resolve/load/render images and no longer own
  independent double-page transforms. This lowers the split-surface z-order/clipping risk, but it is not
  the same as resolving two image sources into a single visual spread render object. The broader Reader
  lane remains active until single-page and double-page gesture acceptance is complete and the final
  spread renderer boundary is decided.
- Validation for the spread-surface follow-up: Android `eros_fe` was launched with `adb su` and
  captured for Reader product-behavior context; V2Next image preview was used as the HarmonyOS transform
  reference. Full deterministic contracts passed, including double-page and zoom contracts that now
  require `ReaderSpreadSurface` and forbid split `SpreadImage` double-page rendering. V1 inventory
  stayed at `0 file(s)`, i18n/diff gates passed, and `scripts/build_hvigor_signed.sh` passed. Mate X7
  simulator `127.0.0.1:5555` installed the signed HAP with hdc outside sandbox, opened the public
  Rockman gallery in `双页 B`, double-tapped the left visible page, panned the zoomed spread, then
  double-tapped to reset and swiped from `6 / 138` to `8 / 138`. Evidence:
  `.hvigor/outputs/reader-spread-surface/fe_reference.png`,
  `.hvigor/outputs/reader-spread-surface/ready.png`,
  `.hvigor/outputs/reader-spread-surface/left_zoom.png`,
  `.hvigor/outputs/reader-spread-surface/left_pan.png`, and
  `.hvigor/outputs/reader-spread-surface/after_swipe.png`.
- Current follow-up (commit pending): tap recognition has been moved off the pager `Swiper` into a
  transparent `ReaderTapOverlay`. The overlay uses an exclusive double-tap-before-single-tap gesture
  group, routes double tap to the active image/spread surface through the existing command bridge, and
  routes single tap to tap-zone/chrome behavior. Horizontal and double-page `Swiper` branches no longer
  bind tap recognizers. This is a first-stage gesture-arena repair; it does not claim the larger
  `ReaderPager` rewrite or boundary handoff from zoomed pan to page turn.
- Validation for the tap-overlay follow-up: `scripts/test_reader_zoom_quality_contract.mjs`,
  `scripts/test_reader_tapzone_contract.mjs`, `scripts/test_reader_double_page_contract.mjs`, full
  `scripts/test_*contract.mjs`, V1 inventory, and `scripts/build_hvigor_signed.sh` passed. Mate X7
  simulator `127.0.0.1:5555` installed the signed HAP with hdc outside sandbox, opened the public
  Rockman gallery Reader, then verified: center tap toggles chrome, left-page double tap zooms without
  showing chrome, zoomed pan moves the image instead of turning the page, reset returns to fit scale, and
  fit-state horizontal swipe turns to the next spread. Evidence:
  `.hvigor/outputs/reader-tap-overlay/ready3.png`,
  `.hvigor/outputs/reader-tap-overlay/center3.png`,
  `.hvigor/outputs/reader-tap-overlay/left_zoom3.png`,
  `.hvigor/outputs/reader-tap-overlay/zoom_pan3.png`, and
  `.hvigor/outputs/reader-tap-overlay/after_swipe3.png`. Earlier failed evidence
  `.hvigor/outputs/reader-tap-overlay/left_doubletap.png` and
  `.hvigor/outputs/reader-tap-overlay/left_doubletap2.png` records why a pure pass-through/no-op overlay
  and delayed-single-tap-only overlay were insufficient on device.
- Android `eros_fe` comparison for this follow-up is incomplete: ADB target `fa967a75` launched
  `com.honjow.fehviewer/.MainActivity` through `su`, and detail-page product context was captured at
  `.hvigor/outputs/reader-tap-overlay/fe_reference.png`; attempts to enter FE Reader through `su input
  tap` did not navigate on that Android target, so this follow-up should remain pending controller/device
  acceptance rather than accepted.
- Current-main acceptance rerun after `fa42941`: Android `eros_fe` did enter Reader after an ADB `su`
  tap on the same gallery; FE evidence is `.hvigor/outputs/reader-current-acceptance/fe_reference.png`
  and `.hvigor/outputs/reader-current-acceptance/fe_reader_try.png`. NextE Mate X7 simulator evidence in
  the same directory covers ready state, center tap, left-page double tap, zoomed pan, fit-state page
  swipe, and `uinput -T -m` pinch. This supports moving the item to implemented / pending controller
  acceptance, not accepted.
- Current-main grouped-row spread mitigation rerun after user-reported left-page overlap: ADB target `fa967a75` launched
  `com.honjow.fehviewer/.MainActivity` through `su` and captured FE reference at
  `.hvigor/outputs/reader-spread-surface-current/fe_reference.png`. NextE was installed from the
  official signed HAP on Mate X7 simulator `127.0.0.1:5555` with hdc outside sandbox, opened the public
  Rockman gallery, entered Reader in double-page mode, then verified left-page double tap, zoomed pan,
  double-tap reset, long-distance fit-state swipe to the next spread, and right-page double tap. Evidence:
  `.hvigor/outputs/reader-spread-surface-current/reader_ready.png`,
  `.hvigor/outputs/reader-spread-surface-current/left_zoom.png`,
  `.hvigor/outputs/reader-spread-surface-current/left_pan.png`,
  `.hvigor/outputs/reader-spread-surface-current/reset.png`,
  `.hvigor/outputs/reader-spread-surface-current/long_swipe1.png`, and
  `.hvigor/outputs/reader-spread-surface-current/right_zoom.png`. The left-page zoom evidence shows the
  left spread content enlarged with the right page only as a clipped adjacent strip, not covering the
  left content under the current transformed-row mitigation. This does not prove the final ideal spread
  render architecture. Status remains implemented / pending controller acceptance, not accepted.
- Deterministic contract was tightened so `DoublePageReader` cannot instantiate `ReaderImagePage` and
  `ReaderSpreadImageLayer` must stay a passive image/loading layer without independent transform or
  z-order. This prevents the old split-surface double-page model from returning as an apparent fix, but
  it intentionally does not claim that two source images have been composited into one final visual
  spread object.
- User-reported current device behavior after the zoom-surface follow-up: Reader gestures still conflict
  enough to affect normal reading.
- Current short-swipe follow-up (commit pending): fit-scale page turns now have an overlay `onTouch`
  fallback that tracks the touch down/move/up delta and routes only bounded horizontal drags through
  the existing Reader page-turn helpers. This is a user-visible reliability fix for ordinary short/mid
  swipes; it is not the final ReaderPager / single visual spread architecture.
- Validation for the short-swipe follow-up: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_zoom_quality_contract.mjs`, `scripts/test_reader_double_page_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, and official signed Hvigor build through
  `scripts/build_hvigor_signed.sh` passed. Mate X7 simulator `127.0.0.1:5555` installed the signed HAP
  with hdc outside sandbox, opened the public Rockman gallery, entered Reader at `15/16`, then a
  mid-distance left swipe turned to `17/18`. A left-page double tap zoomed the spread, and a zoomed pan
  moved the image without turning pages. Evidence:
  `.hvigor/outputs/reader-short-swipe-current/ready_touch.png`,
  `.hvigor/outputs/reader-short-swipe-current/after_touch.png`,
  `.hvigor/outputs/reader-short-swipe-current/zoom_touch.png`, and
  `.hvigor/outputs/reader-short-swipe-current/zoom_pan_touch.png`. Status remains implemented /
  pending controller acceptance, not accepted.
- Current-main behavior matrix rerun on Mate X7 simulator `127.0.0.1:5555` after the Reader standard
  was tightened: `eros_fe` screenshots were kept only as feature/EH-context artifacts and are not used
  as Reader UI or architecture proof. NextE opened the public Rockman gallery from the real detail
  route, entered Reader in `双页 B`, and captured ready state with no loading text or middle chrome
  residue. Center tap showed top/bottom chrome anchored at the screen edges. A fit-scale left swipe
  advanced from `16 / 138` to `18 / 138`. Double tap zoomed the spread without page turn. Zoomed pan
  moved the viewport and stayed on `18 / 138`. A two-finger `uinput -T -m` pinch from fit scale visibly
  zoomed the spread and still stayed on `18 / 138`. Evidence:
  `.hvigor/outputs/reader-matrix-current/nexte_reader_ready.png`,
  `.hvigor/outputs/reader-matrix-current/nexte_reader_chrome.png`,
  `.hvigor/outputs/reader-matrix-current/nexte_after_swipe.png`,
  `.hvigor/outputs/reader-matrix-current/nexte_zoom.png`,
  `.hvigor/outputs/reader-matrix-current/nexte_zoom_pan.png`, and
  `.hvigor/outputs/reader-matrix-current/nexte_fit_after_pinch2.png`. This is current-main behavior
  evidence for the interim grouped-row mitigation only; it does not mark the final Reader double-page
  architecture accepted.
- Previous read-only code inspection found double-tap captured on the parent Reader/Swiper via
  `TapGesture({ count: 2 })` and forwarded through `doubleTapSeq`; the tap-overlay follow-up above
  removes tap recognizers from the `Swiper` branches, but still uses the command bridge because device
  testing showed that a transparent overlay alone did not allow reliable child-surface double tap inside
  the pager.
- Local HarmonyOS technical reference: `../V2Next/entry/src/main/ets/pages/ImagePreviewPage.ets` and
  `../V2Next/entry/src/main/ets/model/ImagePreviewCoordinator.ets`.
- Product behavior reference: `eros_fe` Reader uses mature PhotoView-style behavior (`photo_view` /
  `PhotoViewGallery` / `ExtendedImage` patterns). Treat it as user-behavior and EH-mechanism reference,
  not as target architecture.

Observed / acceptance risk:

- The tap-overlay follow-up has current device evidence that double-tap zoom no longer summons top/bottom
  chrome, zoomed pan does not turn pages, pinch changes the viewport, and fit-state horizontal swipe still
  turns pages, but this is pending controller acceptance and broader ReaderPager architecture review.
- Gesture ownership can still be fragile across page swipe, double tap, pinch, pan, and center tap until
  accepted on more Reader scenarios.
- Zoomed-image interaction still needs broader PhotoView-like acceptance, especially pinch feel and any
  future boundary handoff from zoomed pan to page turn.
- Reader bottom chrome/action styling is a separate bounded UI bug: the download action is a large
  filled blue circular button, while neighboring Reader controls are neutral line/outline controls. This
  is visually out of line with the rest of the Reader chrome and has been repeatedly reported by the
  user. It should be handled as a chrome IA/style lane, not folded into gesture, pager, loading, or
  double-page architecture work.

Expected behavior:

- The image surface should own double tap, pinch, zoomed pan, offset clamp, and animated zoom.
- Single tap / center tap chrome toggle must be mutually exclusive with double tap; double tap must not
  show or hide chrome.
- Fast horizontal swipes at fit scale should turn pages, not trigger double-tap zoom.
- Zoomed state should prioritize panning the image. To reduce risk, disable outer Swiper page-turns
  while zoomed; boundary handoff from zoomed pan to page turn can be a later enhancement.
- Double-tap should animate between fit and target scale, centered on the tap location.
- Pinch should keep the pinch center stable and clamp offsets using the actual `ImageFit.Contain`
  displayed image size.
- Reader chrome/menu styling can be handled in a separate follow-up after gesture reliability is
  restored.

Likely root cause:

- Parent-level double-tap capture was introduced to work around child double-tap unreliability inside
  `Swiper`, but it leaves double tap, single tap/chrome, and page swipe competing in the same gesture
  arena.
- `doubleTapSeq` command routing makes the active image react after the parent has already recognized
  the gesture, so it cannot fully prevent parent tap/chrome behavior or fast-swipe misclassification.
- The current implementation changes zoom/offset state directly; it does not use a PhotoView-style
  animated state machine for double-tap zoom.

Implementation direction:

- Do not keep patching one recognizer. Extract or rewrite a `ReaderZoomSurface` based on the V2Next
  image-preview coordinator model.
- Move double-tap recognition back into the image-owned zoom surface if possible. If ArkUI/Swiper still
  blocks child double-tap, isolate the parent bridge so it suppresses chrome toggles and swipe conflicts
  deterministically.
- Treat outer `Swiper` as page navigation only when the active surface is at fit scale and the gesture is
  confidently a horizontal page-turn.
- Keep the first repair scoped to online horizontal Reader single-page behavior. Do not reintroduce
  streamed byte-progress, broad double-page refactors, offline download pipeline changes, or Reader chrome
  menu redesign in the same lane.

Acceptance shape:

- A normal fast left/right swipe at fit scale reliably turns one page and never zooms.
- Double tap reliably zooms in/out with animation and does not show/hide Reader chrome.
- Pinch zoom remains usable.
- While zoomed, one-finger pan moves the image in both axes and does not accidentally turn pages.
- Center tap at fit scale still toggles chrome.
- Ready images have no loading/progress overlay residue.
- Android `eros_fe` Reader comparison and HarmonyOS device/emulator video or screenshot evidence must
  be attached before marking accepted.

### Reader Bottom Chrome Download Button Has Wrong Visual Weight

Type: Reader chrome IA/style bug

Priority suggestion: P1

Status: implemented / pending controller acceptance

Source:

- User-reported repeatedly; latest screenshot evidence:
  `/var/folders/d_/2b_g_3tx1y97s_s1lks2_v1c0000gp/T/codex-clipboard-54c5876c-7071-4741-9de0-452fb247b10d.png`.
- In the screenshot, the bottom Reader toolbar uses a prominent filled blue circular download button,
  while the adjacent history, thumbnail/grid, page count, direction, and double-page mode controls are
  neutral outline/line controls. The blue button dominates the bottom chrome and reads as a primary FAB,
  even though download is not the main reading action on this surface.

Expected behavior:

- Reader bottom chrome should use one coherent action-weight system.
- Download should be available, but its visual weight should match the toolbar action family unless a
  deliberate primary-action design says otherwise.
- Use existing HDS/NextE icon/action primitives or a narrow shared Reader toolbar action wrapper; do not
  hand-roll another large filled button.

Implementation boundary:

- This lane is only about Reader bottom chrome action weight and visual consistency.
- Do not change Reader gestures, double-page spread architecture, loading/progress, page resolving,
  download executor, offline library, or image pipeline.
- Acceptance should be a Reader screenshot showing the bottom toolbar with the download action aligned
  to neighboring controls in size, color, and weight.

Handled:

- Commit: `56747e6 fix(reader): cache session image resolves`.
- Scope: bottom save action now uses the same neutral toolbar weight as adjacent Reader controls;
  current-image save uses the HarmonyOS system save flow; Reader thumbnail strip/slider remain linked to
  the current page; same-process Reader session cache and `/s/` resolve cache prevent repeated preview
  page and image-page parsing on reopen.
- Historical checks: `scripts/test_reader_tapzone_contract.mjs`, `scripts/test_reader_thumbnail_filmstrip_contract.mjs`,
  `scripts/test_reader_slider_spread_contract.mjs`, `scripts/test_reader_precache_contract.mjs`,
  `scripts/test_image_resolve_showpage_contract.mjs`, and V1 inventory `0 file(s)`.
- Device evidence: signed HAP on local emulator `127.0.0.1:5555`; second same-gallery Reader open logged
  `session_cache_hit` and `resolve_memory_cache`, with no repeated `resolve_spage` or
  `merge_preview_page`. Evidence log:
  `/private/tmp/nexte_reader_cache_second_pass_hilog.txt`.

### Reader Intermittent Short Swipe Jumps Pages Too Early

Type: P0/P1 intermittent Reader gesture bug / page-turn threshold

Priority suggestion: P0/P1

Status: implemented / pending controller acceptance

Source:

- User-reported current device behavior: while reading at fit scale, a very small left/right drag can
  intermittently jump directly to the previous or next page. The visible page only moves a short distance,
  the page-turn animation does not appear to complete normally, and then the page index has already
  changed. It can happen for several consecutive pages, then disappear, and is difficult to reproduce on
  demand.
- Dispatch correction, 2026-06-20: this feedback should not be used as the default next implementation
  lane. It is real and should remain recorded, but current scheduling parks it until the user explicitly
  authorizes Reader gesture work or fresh P0 evidence makes normal reading broadly unusable. If reopened,
  it must start from measured gesture trace evidence, not another recognizer patch from static reasoning.
- Fresh user feedback, 2026-06-21: the problem is still present and severe during normal reading. It is
  not only early page commits from tiny drags; the opposite failure also happens frequently, where the user
  swipes repeatedly or for a long distance and the Reader does not move. This makes normal Reader use
  unreliable enough to reopen the lane at high priority.
- Fresh user diagnosis, 2026-06-21: one concrete "swipe does not move" cause is hidden Reader chrome that
  is visually transparent but still interactive. When the bottom control layer is hidden only by opacity,
  the user can still blindly drag the slider or tap buttons, so page swipes in that region are stolen by
  invisible controls. Treat this as a deterministic hit-test bug, not a QA flake.

Why this is separate from generic gesture acceptance:

- Prior device evidence proves some deliberate long swipes can turn pages and some zoom/pan paths work.
  That does not cover this failure class because the bug is about accidental early commit from a short or
  partial drag, and about rejected/ignored intentional swipes.
- A screenshot, video, or automated repeated swipe after the page changes is not sufficient proof. This
  failure class can pass many happy-path runs and still fail in normal hands. The primary proof must be
  static: the code architecture must make gesture conflict impossible by construction.

Likely risk areas to inspect:

- Fit-scale page-turn threshold and any custom `onTouch` / touch-gate logic added to reject short
  swipes.
- ArkUI `Swiper` page-change timing versus overlay gesture recognition. The page index may update on
  an internal threshold that is lower than the app's expected swipe threshold.
- Interaction between tap overlay, double-tap exclusive gesture, page `Swiper`, and any code that clears
  zoom state or programmatically normalizes the current index.
- Double-page spread mode can amplify the symptom because each visual page turn may represent two source
  indices, but the same issue should be checked in single-page mode as well.
- Current static conflict evidence, 2026-06-21: horizontal and double-page `Swiper.onChange` handlers can
  directly mutate page state through `vm.onPageChange(...)`, while `ReaderTapOverlay.onTouch` can also
  call `onReaderHorizontalSwipe(...) -> turnTo(...) -> vm.onPageChange(...)`. The existing contract even
  leaves "very long swipe" to Swiper while shorter bounded swipes are handled by the overlay fallback.
  That split-owner design cannot strictly prove conflict freedom.
- Current hit-test risk evidence, 2026-06-21: any Reader top/bottom chrome, thumbnail strip, slider, or
  button layer that uses `opacity(0)` while keeping default hit testing can steal gestures from the reader
  canvas. Hidden chrome should be removed from the interactive tree or translated out of the reader
  gesture area; `HitTestMode.None` is only a defensive backstop while an exit animation is mounted. A
  component sitting in the original place at opacity 0 is not truly hidden.

Investigation direction:

- First produce a static gesture-ownership proof before attempting another visual rewrite or threshold
  tweak. The proof should identify exactly one page-turn owner at fit scale and exactly one function that
  commits page index changes for user swipes.
- The next design should remove the split between "some swipes handled by overlay onTouch" and "some
  swipes handled by Swiper onChange". Pick one owner. A custom `ReaderPager` / gesture state machine is
  acceptable if it is smaller and more provable than mixing native Swiper recognition with a fallback.
- Page commits must be classified before mutation: below-threshold drag, valid page swipe, zoomed pan,
  double tap, single tap/chrome, slider jump, and programmatic sync should be mutually exclusive paths.
- Deterministic contracts should assert the absence of competing commit paths, not merely that a param or
  threshold exists. For example, fail if both `Swiper.onChange` and `ReaderTapOverlay.onTouch` can commit
  normal horizontal page turns.
- Deterministic contracts should also assert hidden chrome cannot intercept touches: top bar, bottom bar,
  thumbnail strip, slider, and toolbar buttons must not remain mounted in-place as interactive controls
  when `showChrome` is false. Prefer conditional mount/unmount or offscreen translation; if fade-out keeps
  a layer mounted briefly, it must be non-hit-testable for the hidden/transitioning-out state. A
  hidden-by-opacity in-place layer is a blocker even if ordinary screenshot QA looks correct.
- A QA-only gesture trace is still useful after the static design is repaired: record pointer down/up
  coordinates, max horizontal delta, duration, active zoom state, current page before/after, and which
  single handler accepted or rejected the gesture. Treat this as smoke evidence, not the main proof.
- Do not reopen Reader chrome styling, loading progress, or double-page visual seam in this lane unless
  the trace proves they directly affect the early page commit.

Handled update, 2026-06-22:

- Current main no longer has the split-owner short-swipe architecture described above. Static inspection
  and `scripts/test_reader_tapzone_contract.mjs` show horizontal page turns are owned by native
  `Swiper.onChange`; the old transparent overlay touch fallback, custom swipe thresholds, and
  `onReaderHorizontalSwipe` / touch-tracking path are absent.
- Hidden Reader chrome is no longer mounted in-place as opacity-only interactive UI. The chrome is
  conditionally mounted only when `readerContentReady() && showChrome`, while thumbnail strip hidden
  state uses `HitTestMode.None`.
- Zoom/pan gesture ownership remains covered by `scripts/test_reader_zoom_quality_contract.mjs`: parent
  Swiper owns fit-state page turns and disables swipe only while the image/spread surface reports zoomed.
- This closes the stale active scheduling candidate. Future Reader work should only reopen this with a
  fresh reproduction that contradicts the single-owner/static hit-test proof.

### Reader Architecture Should Use Mature Pager And Spread Surface References

Type: architecture guidance / future Reader repair

Priority suggestion: P1

Status: active guidance / apply before new Reader gesture or double-page implementation

Source:

- User clarification: `eros_fe` Reader contains substantial historical compromises and immature design
  decisions. It should not be treated as the target Reader architecture or UI design for NextE.
  From 2026-06-20 onward, `eros_fe` is downgraded in Reader lanes to a source for user-visible feature
  coverage and EH mechanism pitfalls only: reading entry, page/jump semantics, single/double page,
  direction, zoom, pan, preload, and error recovery. `eros_fe` screenshots or interaction similarity
  are not acceptance proof for NextE Reader architecture or UI quality.
- Read-only `eros_fe` inspection:
  - `eros_fe/lib/pages/image_view/view/image_page_view.dart` wraps double-page mode in
    `PhotoViewGalleryPageOptions.customChild`, but the custom child is still a `DoublePageView`.
  - `eros_fe/lib/pages/image_view/view/view_page.dart` implements `DoublePageView` by resolving
    `serFirst` / `serFirst + 1`, building two `ViewImage` children, and composing them in a `Row` with
    ratio math.
  - `eros_fe` comments explicitly note gesture problems around `PhotoViewGallery`, child zoom, direct
    page turns after child double-tap, and `ExtendedImageGesturePageView` double-page mode being hard to
    make reliable.
- Read-only NextE inspection:
  - Older NextE double-page mode rendered as `Swiper -> Row -> SpreadImage(start) / SpreadSecondSlot(start)`,
    where each visible page could become its own `ReaderImagePage` with separate loading and zoom surface
    state.
  - Current NextE has moved to an interim `ReaderSpreadSurface` that owns gestures and transforms a
    grouped `Row` of passive `ReaderSpreadImageLayer` children. This is safer than two independent
    `ReaderImagePage` surfaces, but still not the final ideal architecture because the two pages remain
    separate image layers inside a row instead of being composed into a single visual spread render
    object with unified draw/composite/clamp/hit-test semantics.
- User-reported double-page visual issue to preserve for the future redesign: current double-page layout
  appears to insert a visible center gap between the two pages. That is not the expected default for a
  manga/spread use case, where double-page mode often exists to restore art that was originally one
  continuous spread split into two image files. Future Reader redesign should treat the seam/gutter as a
  spread-layout policy, and the default paired-page mode should not insert decorative spacing between the
  two images. Do not reopen Reader immediately for this alone; keep it as parked architecture guidance
  unless the user explicitly starts a Reader redesign lane or current reading becomes P0 unusable.
- Mature reader references to investigate before a larger rewrite:
  - Mihon / Tachiyomi pager architecture: pager holder owns page navigation and load states, while the
    image view owns zoom/pan capabilities such as pan-left / pan-right boundary checks.
  - V2Next `ImagePreviewPage.ets` and `ImagePreviewCoordinator.ets`: HarmonyOS-native transform,
    clamp, double-tap, pinch, and pan implementation patterns.

Guidance:

- Use `eros_fe` for EH mechanisms, product semantics, and historical pitfalls only. Do not copy its
  Reader structure, visual design, or interaction surface as target architecture.
- Do not keep adding recognizer-level patches on top of a split surface if the feature needs a broader
  Reader repair.
- Prefer a mature separation:
  - `ReaderPager` owns page/spread navigation, preload window, and page-turn direction.
  - `ReaderSpreadResolver` owns single/double spread math, LTR/RTL, cover-page behavior, odd/even
    pairing, current-index normalization, and mode switching.
  - `ReaderSpreadSurface` owns one visual reading surface for the current spread.
  - The final spread surface should resolve one or two image sources into a single spread visual object
    with source rects/layout, unified draw/composite, zoom, pan, clamp, clipping, and hit testing. A
    transformed `Row` of two image layers is only an interim mitigation, not the final target.
  - Double-page spread layout should support a zero-gutter/default-contiguous pairing policy; any center
    gap should be an explicit display option, not an accidental default caused by row spacing.
  - Per-image resolving/loading/error states may stay per source, but user interaction should be
    coordinated at the spread level.

Implementation direction:

- Before any new Reader double-page or gesture lane, perform a short architecture grounding pass:
  `eros_fe` pitfalls, V2Next HarmonyOS implementation pattern, and at least one mature open-source reader
  reference such as Mihon/Tachiyomi.
- Follow-up implementation in progress: `ReaderSpreadResolver` now centralizes the existing
  single/double spread calculations inside `ReaderPage.ets`: double-page eligibility, odd/even pairing,
  cover-page start index, slider target normalization, spread count, spread starts, and second-page
  visibility. `ReaderPage` delegates these calculations instead of scattering formula copies across
  chrome, slider, mode-switch, and `DoublePageReader` paths. This is an architecture containment step,
  not final Reader acceptance.
- Validation for the spread-resolver follow-up: full deterministic contract sweep passed, including
  Reader double-page, initial/jump spread start, slider spread, column-mode switch, zoom quality, and V1
  inventory `0 file(s)`. `scripts/build_hvigor_signed.sh` passed on macOS. Android `eros_fe` was launched
  with ADB `su` and captured as product-context evidence. Mate X7 simulator `127.0.0.1:5555` installed
  the signed HAP with hdc outside sandbox, opened the public Rockman gallery, entered Reader from
  `继续 P8`, confirmed ready state `8 / 138 / 双页 B`, swiped horizontally to `10 / 138 / 双页 B`, then
  cycled column mode to `10 / 138 / 关闭`. Evidence:
  `.hvigor/outputs/reader-spread-resolver/fe_reference.png`,
  `.hvigor/outputs/reader-spread-resolver/ready.png`,
  `.hvigor/outputs/reader-spread-resolver/after_swipe.png`, and
  `.hvigor/outputs/reader-spread-resolver/mode_cycle.png`.
- Follow-up implementation in progress: `ReaderZoomCoordinator` now owns shared zoom math for
  single-page and double-page spread surfaces: scale clamping, contain-fit sizing, offset clamping,
  pan activation distance, double-tap target/offset, and pinch-center offset correction. Double-page
  `ReaderSpreadSurface` now records child image metrics from `ReaderSpreadImageLayer` and clamps zoomed
  pan against the contain-fitted spread content instead of the raw viewport. This narrows the remaining
  PhotoView-like gesture work without changing Reader chrome or download/offline behavior.
- Validation for the zoom-coordinator follow-up: full deterministic contract sweep passed, including
  Reader zoom quality requiring `ReaderZoomCoordinator` and double-page child image metrics; V1 inventory
  stayed at `0 file(s)`, i18n parity and `git diff --check` passed, and `scripts/build_hvigor_signed.sh`
  passed. Android `eros_fe` was launched with ADB `su` and captured as product-context evidence. Mate X7
  simulator `127.0.0.1:5555` installed the signed HAP with hdc outside sandbox, opened the public Rockman
  gallery, entered Reader from `继续 P10`, confirmed single-page ready `10 / 138 / 关闭`, double-tapped to
  zoom, panned the zoomed single-page image, reset and swiped to `11 / 138 / 关闭`, then switched to
  `双页 B`, double-tapped and panned the spread, reset and swiped from `10 / 138 / 双页 B` to
  `12 / 138 / 双页 B`. Evidence:
  `.hvigor/outputs/reader-zoom-coordinator/fe_reference.png`,
  `.hvigor/outputs/reader-zoom-coordinator/single_zoom.png`,
  `.hvigor/outputs/reader-zoom-coordinator/single_pan.png`,
  `.hvigor/outputs/reader-zoom-coordinator/single_after_swipe.png`,
  `.hvigor/outputs/reader-zoom-coordinator/double_zoom.png`,
  `.hvigor/outputs/reader-zoom-coordinator/double_pan.png`, and
  `.hvigor/outputs/reader-zoom-coordinator/double_after_swipe.png`.
- If double-page is repaired, do not implement it as two sibling independent `ReaderImagePage` surfaces
  that each own zoom/pan/loading. Introduce `ReaderSpreadSurface` or an equivalent single-surface model.
- Keep first implementation narrow: online horizontal Reader, single spread surface, current `ReaderParams`
  and `ReaderViewModel` data flow, no offline executor or download-pipeline changes.
- Boundary handoff from zoomed pan to page turn can be deferred. It is acceptable to disable pager swipes
  while zoomed for the first stable implementation.

Acceptance shape:

- A future Reader lane must explicitly state whether it touches pager, spread resolver, spread surface,
  image resolving, or chrome; do not hide architecture changes inside visual tweaks.
- Double-page mode is not marked accepted if it is only two independent image containers side by side.
- Spread math is not considered contained unless deterministic contracts require `ReaderSpreadResolver`
  ownership and `ReaderPage` delegation for double-page eligibility, route/jump normalization, slider
  commits, spread counts, and second-page visibility.
- In double-page mode, pinch, double tap, pan, loading overlay, and chrome tap arbitration behave as if
  the visible spread is one reading surface.
- Single-page mode remains stable: fast page swipe, double tap, pinch, zoomed pan, and center tap chrome
  must still pass device validation.
- Reader acceptance should be grounded in NextE/HarmonyOS behavior and the mature manga reader model.
  Android `eros_fe` may be recorded as feature/EH-context only, not as architecture/UI proof.
  HarmonyOS simulator/device evidence must cover the changed interaction risk directly.

### Reader Double-Page Mode Switch Can Desync Visible Spread And Page Counter

Type: bug / reading UX gap

Priority suggestion: P1

Status: implemented / needs controller acceptance

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
  The settings model remained for a later, separately accepted double-page lane.
- This lane restores runtime double-page rendering after the core Reader baseline was accepted:
  `ReaderPage` routes horizontal non-single column modes to `DoublePageReader`, keeps vertical mode
  and single-column horizontal mode on their existing renderers, and lets the bottom chrome cycle
  `关闭 -> 双页 A -> 双页 B -> 关闭`.
- The runtime switch now normalizes `currentIndex` and `sliderValue` through the existing spread math
  before persisting the new column mode, so switching to double-page A/B lands on the visible spread
  start instead of an interior page.
- `SpreadImage` now reports `onImageLoaded` back to the parent Reader page, preserving loaded-state
  bookkeeping for double-page slots.
- `a9a0003 fix(reader): align double-page mode switches` adds mode-specific spread-index and
  spread-start helpers to `ReaderPage`, normalizes `currentIndex` before persisting a new column mode,
  and suppresses the second slot on the double-page B cover spread.
- Scope is limited to online Reader single/double A/double B mode-switch alignment. It does not add a
  thumbnail strip, auto-read controls, offline reader behavior, or download pipeline changes.

Evidence:

- Deterministic contracts: `scripts/test_reader_column_mode_switch_contract.mjs`,
  `scripts/test_reader_double_page_contract.mjs`.
- Regression contracts run in the fixing lane: `scripts/test_reader_tapzone_contract.mjs`,
  `scripts/test_reader_zoom_quality_contract.mjs`, `scripts/test_reader_slider_spread_contract.mjs`,
  `scripts/test_reader_initial_spread_start_contract.mjs`,
  `scripts/test_reader_loading_progress_contract.mjs`.
- Gates: `scripts/test_v1_decorator_inventory_contract.mjs`, `git diff --check`, `ohpm install`,
  official signed Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  before the final fix, double-page B showed pages 1/2; after the fix, double-page B first spread
  showed page 1 alone with chrome text `1 / 16`, `左→右`, and `双页 B`.
  Evidence directory: `/private/tmp/nexte_reader_nav_quality_evidence/`, especially
  `chrome_after_b.png` for the observed pre-fix issue and `final_reader_b.png`,
  `final_reader_b_chrome.png`, `final_reader_b_chrome_layout.json` for the fixed behavior.
- Current runtime restoration smoke on Mate X7 emulator target `127.0.0.1:5555`: public gallery
  `https://e-hentai.org/g/3989982/16600a66e8/` opened in NextE, Reader showed two-page canvas in
  `双页 B` with chrome `8 / 138`; tapping the bottom column pill changed to `关闭` while keeping
  `8 / 138`; tapping again changed to `双页 A` and normalized to `7 / 138`; horizontal swipe then
  advanced to `9 / 138`. Evidence directory:
  `.hvigor/outputs/reader-double-page-runtime-smoke/`.

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

### Settings Root Missing Reader Settings Entry

Type: feature gap / settings reachability

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- `docs/ui-architecture-audit.md` H5/F6: `ReaderSettingsPage` was built and route-registered, but
  the settings tree still lacked the top-level Read/Reader settings entry from `eros_fe`.

Grounding:

- `eros_fe` settings root exposes `Read` as a first-level settings row in
  `/Users/honjow/git/eros_fe/lib/pages/tab/controller/setting_controller.dart`, routing to
  `EHRoutes.readSetting`; the reader top menu opens the same route in
  `/Users/honjow/git/eros_fe/lib/pages/image_view/view/view_widget.dart`.
- NextE already has `ReaderSettingsPage` and the `ReaderSettings` route; the missing user-visible
  loop was Settings root -> Reader settings.

Implementation:

- Added a `settings_reader` `ConciseListRow` to `SettingsPage.MainSection` before Download settings.
- The row uses the existing HDS grouped-list pattern and pushes `ReaderSettings`.
- Scope is limited to Settings root reachability. It does not change Reader gestures, Reader loading,
  SearchFilter, title/menu/search-field layout, or the ReaderSettings page contents.

Evidence:

- Android FE comparison: ADB target `fa967a75`, launched with
  `/opt/homebrew/bin/adb shell su -c 'am start -n com.honjow.fehviewer/.MainActivity'`; foreground
  confirmed by `dumpsys window`; screenshot captured at
  `/private/tmp/nexte_settings_reader_entry_fe_reference/fe_settings_foreground.png`.
- Deterministic contract: `scripts/test_settings_reader_entry_contract.mjs`.
- Gates: `scripts/test_settings_reader_entry_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  `git diff --check`, and official signed Hvigor build through `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Settings root showed the new `阅读` row above `下载`; clicking it opened ReaderSettingsPage with
  `翻页方向` and `双页模式`.
  Evidence directory: `/private/tmp/nexte_settings_reader_entry_acceptance/`, especially
  `settings_root.png`, `settings_root.json`, `reader_settings_page.png`, and
  `reader_settings_page.json`.

Remaining acceptance:

- Needs controller/user acceptance of the Settings root screenshot and ReaderSettings navigation
  evidence. No further device validation is required unless Settings root or ReaderSettings routing
  changes again.

### Reader Lacks Current Image Save Action

Type: feature gap / reader utility

Priority suggestion: P1

Status: implemented / needs controller acceptance

Source:

- `eros_fe` Reader bottom controls include a Save action; NextE Reader had current-image sharing but no
  current-image save-to-gallery action.

Grounding:

- `eros_fe` reference: `/Users/honjow/git/eros_fe/lib/pages/image_view/view/view_widget.dart`
  `ControllerButtonBar` renders Save/Double/Auto/Thumb controls; Save calls
  `/Users/honjow/git/eros_fe/lib/pages/image_view/controller/view_controller.dart` `tapSave()`.
- `tapSave()` passes the current `GalleryImage` URLs/file path to
  `/Users/honjow/git/eros_fe/lib/pages/image_view/view/view_widget.dart` `showSaveActionSheet()`,
  which calls `/Users/honjow/git/eros_fe/lib/network/api.dart` `saveNetworkImageToPhoto()` /
  `saveLocalImageToPhoto()`.
- Product semantics: Reader's primary action remains reading/turning pages; Save is a secondary bottom
  chrome utility for the current visible image.

Implementation:

- Added `shared/src/main/ets/utils/ImageSaveUtil.ets` to download the current resolved image into the
  app sandbox, convert it with `fileUri.getUriFromPath()`, and commit it to the media library through
  `photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest()` + `applyChanges()`.
- Reader bottom chrome now exposes a compact HarmonyOS `SaveButton`, so the system grants short-term
  media-library write access through the platform safety control without turning Save into the primary
  Reader action.
- Save prefers `originImageUrl`, falls back to `imageUrl`, and resolves the current `/s/` image page
  through `ImageResolveService` when the current image is not yet resolved.
- Added i18n feedback strings for save success, failure, and no-current-image cases.
- Scope is limited to saving the current visible image. It does not add batch save, download queue
  execution, auto-read, thumbnail strip controls, or double-page behavior.

Evidence:

- Android FE comparison: ADB target `fa967a75`, launched `com.honjow.fehviewer/.MainActivity`
  with `su`, opened a gallery detail, tapped the real `阅读` button with `su -c input tap`, then
  center-tapped the Reader to show chrome. FE Reader page showed `2/74`, thumbnail strip, slider,
  and the bottom controller button row. Source grounding maps the first bottom controller button to
  `ControllerButtonBar` -> `controller.tapSave(context)`. Evidence directory:
  `/Users/honjow/git/NextE/.hvigor/outputs/reader-save-fe-comparison/`, especially
  `fe-current.png/xml`, `fe-after-second-read-tap.png/xml`, and `fe-reader-chrome.png/xml`.
- Source grounding above confirms FE Reader Save behavior and save-to-album implementation path.
- Reader save UI validation: signed build plus the captured device path.
- Gates: `scripts/test_reader_current_image_share_contract.mjs`,
  `scripts/test_v1_decorator_inventory_contract.mjs`, `scripts/check_i18n_duplicates.py`,
  `git diff --check`, and official signed Hvigor build through `scripts/build_hvigor_signed.sh`.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  opened public gallery `https://e-hentai.org/g/3989982/16600a66e8/`, entered Reader via the real
  `继续 P2` action, center-tapped chrome, confirmed a bottom SaveButton, tapped it, and saw the
  system "安全保存图片和视频" authorization dialog. After allowing, the dialog dismissed and no
  `save_image_failed` / `save_image_resolve_failed` hilog entries were observed. Evidence directory:
  `/private/tmp/nexte_reader_save_acceptance/`, especially `detail.jpeg`, `reader_initial.jpeg`,
  `reader_chrome.jpeg`, `reader_after_save_click.jpeg`, and `reader_after_allow.jpeg`.
- After reducing the SaveButton to a compact icon control and rebuilding/reinstalling the signed HAP,
  `reader_compact_chrome.jpeg` confirms the lower-weight bottom action; a follow-up click produced
  MediaLibrary `CreateImageAssetRequest` / `ApplyChanges` hilog entries with no NextE save-failure log,
  and `reader_compact_after_click.jpeg` captured the final Reader state.

Remaining acceptance:

- Needs controller/user acceptance of the NextE Reader save button placement, authorization dialog,
  and save behavior. No further NextE device validation is required unless Reader chrome or image-save
  logic changes again.
