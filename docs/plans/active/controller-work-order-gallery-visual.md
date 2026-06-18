# Controller Work Order — Gallery Visual Re-QA and Fix Queue

Status: ACTIVE
Owner: controller
Scope: gallery detail page visual regressions only
Created: 2026-06-17

## Why this exists

The previous workflow failed: active issues were treated as completed without item-by-item controller acceptance, and visual fixes were repeatedly reported as done while user screenshots still showed the same class of defects.

This document is the executable control plane for the next work. It is not a post-hoc summary and not a completion claim.

## Hard rules

1. User screenshots and observed product behavior are ground truth.
2. No active item is accepted by default. User silence is not acceptance.
3. Claude/worker self-report is not acceptance evidence.
4. Contracts and source assertions are not sufficient for visual acceptance.
5. A visual item is accepted only with all of:
   - current source diff reviewed by controller,
   - deterministic contract/gate where applicable,
   - build/install on the selected device,
   - device screenshot/video evidence for the affected surface,
   - controller comparison against the product semantics written in this work order.
6. Do not invent product semantics. If the user says “real thumbnail ratio + rounded image,” do not translate that into “fill,” “cover,” “crop,” or “force full tile.”
7. Layout slots may reserve space, but loaded image presentation must not expose a fake grey container as if it were part of the image.
8. Rounded corners must be applied to the visible image content, not merely to a wrapper/background behind it.
9. After a gate is completed and pushed, controller must automatically continue to the next OPEN gate in this document. Do not stop just because one gate was committed.
10. Stop only for: destructive cleanup, external account/secret risk, incompatible product choices, unavailable device/tooling, or an explicit user stop.

## Device and reference

Current Mac migration note:

```text
Primary repo:      /Users/honjow/git/NextE
Reference sources: /Users/honjow/git/eros_fe   # product/UX semantics
                   /Users/honjow/git/V2Next    # HarmonyOS/HDS/state/navigation architecture
```

Do not use historical `/home/gamer/...` paths as local paths on this Mac. They refer to the old desktop (`gamer@itx.local`) unless explicitly accessed over SSH/rsync.

Current local emulator/hdc state is summarized in `docs/agent-guides/current-mac-codex-handoff.md`. For ordinary responsive-layout QA, prefer the local Mate X7 foldable emulator matrix before falling back to a physical device. For real-device-only QA, still follow `docs/device-lease.md` and verify the target is currently connected before install/screenshot work.

## Current gate queue

### Gate V1 — Real thumbnail / cover presentation

Status: MERGED_CANDIDATE_REVIEW
Priority: P0

User-observed failures:

```text
/home/gamer/.hermes/image_cache/img_ce52e06cb803.jpg
- middle preview thumbnail appears as a horizontal strip inside a tall grey tile.

/home/gamer/.hermes/image_cache/img_a786e7aab70e.jpg
- gallery header cover appears as a horizontal image inside a large grey cover container.

/home/gamer/.hermes/image_cache/img_89de92d7263e.jpg
- one side rounded and one side square, proving the rounded layer and visible image layer are not the same.
```

Required product semantics:

```text
- Use the real thumbnail/cover image.
- Preserve the real image ratio.
- Apply rounded corners to the visible image content itself.
- Do not force blanket fill/cover/crop.
- Do not expose a fake grey container around a loaded image.
- Loading/error placeholders may have a placeholder surface, but loaded image state must not keep placeholder grey as visible padding.
```

Surfaces to verify before accepting:

```text
- gallery detail header cover
- detail preview grid
- horizontal preview row
- all-thumbnails page
```

Out of scope for this gate:

```text
- gallery list page cards / GalleryCard / list-card covers
- home/favorites/toplist list cards
- any list-page thumbnail/card rewrite
```

Implementation mode (changed after repeated patch-loop failures):

```text
Rewrite the shared thumbnail/cover presentation primitive instead of continuing per-surface patches.
Do not build on top of the rejected patch-loop WIP; it is preserved in stash:
  stash@{0}: paused rejected thumbnail/list-cover patch-loop before presentation primitive rewrite

The new primitive must separate:
- layout slot: reserves alignment/row/card space and is transparent in loaded state
- visible image/sprite: owns its own computed size, real ratio, radius, and clip
- loading/error placeholder: may have placeholder surface only before image loads or on error
```

Known compression/flattening root causes to eliminate:

```text
- Setting both width and height from the target frame on Image content when those dimensions do not match the actual image/sprite ratio.
- Using ImageFit.Fill/Cover/Contain as a substitute for computing the visible image box.
- Sprite rendering that scales the whole sprite sheet to frame dimensions instead of to the sprite sheet's real pixel dimensions and then clips the requested source rect.
- A layout slot/frame such as PreviewThumbTile FRAME_ASPECT=1.4 may remain for alignment; the slot itself must be transparent/card-surface in loaded state and must not appear as a grey thumbnail body.
```

Clarification from user (2026-06-17):

```text
FRAME_ASPECT=1.4 is the container/layout slot; do not remove it just to make the slot follow content.
Figure 3's shape/proportion is acceptable; the defect is the grey background/placeholder showing around loaded image.
Therefore: keep layout slot semantics, keep real image ratio, remove visible grey loaded container, and ensure the image content itself is rounded.
```

Acceptance evidence required:

```text
- before/after device screenshots for at least one failing wide-ratio example if reproducible
- proof screenshots sent into the chat, not only local paths
- device screenshots for each affected surface above
- source diff showing loaded image and wrapper/background layers are separated correctly
- gates for parser/dimensions and thumbnail presentation contracts
- build/install proof
```

Current controller evidence status (2026-06-17):

```text
Verified candidate evidence sent to chat:
- /tmp/nexte_v1/header.jpeg: header cover appears fixed enough to continue monitoring, but still requires final controller/user acceptance.

Still failing / not accepted:
- /tmp/nexte_v1/tile_zoom.png: user says this is a different class of failure: the visible detail-preview sprite image itself is wrong/distorted/compressed, not merely a grey-slot problem. Diagnose sprite/source-rect/display-size math.

Out-of-scope / frozen for this gate:
- /tmp/nexte_v1/list_cover_zoom.png: this is a gallery list-card surface, not the detail page. Do not work on it in this gate; prior list-card WIP was reverted.

Implication:
- Gate V1 remains OPEN.
- Gate V1 is detail-page only: header cover + preview grid + horizontal preview row + all-thumbnails.
- Do not touch GalleryCard/list-page cover code for this gate.
```

Completion rule:

```text
Do not mark accepted until the controller can point to the screenshots and say the visible image itself is rounded and ratio-correct, with no fake grey loaded container.
User-visible screenshot feedback overrides prior worker self-PASS and contract-only PASS.
```

Current Mac re-QA evidence checkpoint (2026-06-18):

```text
Target: 127.0.0.1:5555 Mate X7 emulator.
Build: a253aff, installed signed HAP from the official DevEco/Hvigor signing flow.
Device command boundary: every hdc command ran outside the Codex sandbox.

Default grid / 90vp token:
- /private/tmp/nexte_preview_min90_evidence/nexte_preview_min90_detail.png
- /private/tmp/nexte_preview_min90_evidence/nexte_preview_min90_detail_layout.json
- /private/tmp/nexte_preview_min90_evidence/nexte_preview_min90_grid.png
- /private/tmp/nexte_preview_min90_evidence/nexte_preview_min90_grid_layout.json

Horizontal mode:
- /private/tmp/nexte_preview_min90_horizontal_evidence/horizontal_preview_row.png
- /private/tmp/nexte_preview_min90_horizontal_evidence/horizontal_preview_row_layout.json
- /private/tmp/nexte_preview_min90_horizontal_evidence/horizontal_all_thumbnails.png
- /private/tmp/nexte_preview_min90_horizontal_evidence/horizontal_all_thumbnails_layout.json
- /private/tmp/nexte_preview_min90_horizontal_evidence/settings_layout_after_toggle.json
- /private/tmp/nexte_preview_min90_horizontal_evidence/settings_layout_restored.json

Hidden-inline mode:
- /private/tmp/nexte_preview_min90_hidden_evidence/settings_after_toggle.json
- /private/tmp/nexte_preview_min90_hidden_evidence/hidden_preview_entry.png
- /private/tmp/nexte_preview_min90_hidden_evidence/hidden_preview_entry_layout.json
- /private/tmp/nexte_preview_min90_hidden_evidence/hidden_all_thumbnails.png
- /private/tmp/nexte_preview_min90_hidden_evidence/hidden_all_thumbnails_layout.json
- /private/tmp/nexte_preview_min90_hidden_evidence/settings_restored.json

Observed:
- `横向缩略图` was temporarily enabled for QA (`checked=true`) and restored to off (`checked=false`).
- Horizontal preview row retained the visible `查看全部` entry.
- Tapping `查看全部` opened the AllThumbnails route and rendered the 3-column grid.
- `隐藏画廊缩略图` was temporarily enabled for QA (`checked=true`) while `横向缩略图` remained off.
- Hidden-inline preview hid inline thumbnails, retained `查看全部`, retained `更多预览`, and `更多预览` opened the AllThumbnails route.
- Both thumbnail-mode toggles were restored to off after QA.

This is PARTIAL_REQA only. It does not cover loading/error/light/dark matrices or final controller visual acceptance.
```

### Gate V2 — Subtab never-loaded empty-state flash

Status: PARTIAL_REQA
Priority: P0

User-observed failure:

```text
When switching to a subtab, the UI briefly flashes “没有数据” or “没有更多了” before entering loading.
```

Required product semantics:

```text
- A never-loaded key may show content-area loading.
- A never-loaded key must not flash terminal empty/no-more copy.
- Empty/no-more copy is allowed only after that key has completed at least one load and is actually empty/exhausted.
```

Likely root area:

```text
GalleryListBody / PullRefresh scaffold / GalleryListViewModel loaded-state semantics.
```

Acceptance evidence required:

```text
- deterministic contract proving never-loaded key dispatches to loading, not empty/footer
- device rapid-capture or video evidence on Home/Toplist/Favorites if affected
- build/install proof
```

Current evidence checkpoint:

```text
2026-06-18 08:03 +0800, Mate X7 emulator 127.0.0.1:5555.
Every hdc command was run outside the Codex sandbox.

PASS-like reachable evidence, still pending controller visual acceptance:
- Home default -> popular subtab: immediate and settled screenshots captured; settled layout has rows and
  no "没有数据/没有更多了".
- Toplist all -> year period: immediate and settled screenshots captured; settled layout has rows and
  no "没有数据/没有更多了".

Evidence directory:
/private/tmp/nexte_lane_continuation_probe/

Relevant files:
- nexte_req_home.png
- nexte_req_home_hot_immediate.png
- nexte_req_home_hot_after.png
- nexte_req_home_hot_layout.json
- nexte_req_toplist.png
- nexte_req_toplist_year_immediate.png
- nexte_req_toplist_year_after.png
- nexte_req_toplist_year_layout.json

Still open / blocked:
- Search/filter visual re-QA: blocked by the system Xiaoyi IME first-run privacy page; Codex did not
  click "同意" or type text.
- Favorites favcat/order: still needs a safe logged-in app state.
- Site 表/里 switch: still needs safe auth/ExHentai state.
```

### Gate V3 — Existing active visual/navigation items re-audit

Status: ACTIVE_REQA_AFTER_MERGED_CANDIDATES
Priority: P1

This is the original gallery visual/navigation active plan. Every prior PASS is invalid unless re-backed by current controller evidence under this work order.

Items to audit from `gallery-visual-navigation-regression-contract.md`:

```text
- detail preview semantics
- detail header action sizing/state matrix
- long-title stress cases
- tag chips including usertag/vote/color states
- cover presentation loading/error/light/dark matrix
- list-card fixed/adaptive height modes across retained pages
```

Current Mac partial evidence checkpoint (2026-06-18):

```text
Detail header/action sizing:
- Target: 127.0.0.1:5555 Mate X7 emulator.
- Build: a253aff signed HAP already installed.
- Detail: https://e-hentai.org/g/3989982/16600a66e8/
- State covered: not favorited, first-read only.
- Evidence:
  - /private/tmp/nexte_detail_header_action_evidence/detail_header_action.png
  - /private/tmp/nexte_detail_header_action_evidence/detail_header_action_layout.json
- Observed: cover/title/JP title/uploader stay inside the header card; `阅读` is a compact
  right-bottom capsule; page count stays in InfoBar; no fake favcat heart/title block is shown.
- Still open: favorited header, resume label, read/unread/resume matrix, and controller visual acceptance.

List-card fixed/adaptive height modes:
- Target: 127.0.0.1:5555 Mate X7 emulator.
- Build: a253aff signed HAP already installed.
- Surface covered: Home default list only.
- Evidence:
  - /private/tmp/nexte_list_height_mode_evidence/settings_fixed_on.json
  - /private/tmp/nexte_list_height_mode_evidence/list_fixed_default.png
  - /private/tmp/nexte_list_height_mode_evidence/list_fixed_default_layout.json
  - /private/tmp/nexte_list_height_mode_evidence/settings_fixed_off.json
  - /private/tmp/nexte_list_height_mode_evidence/list_adaptive.png
  - /private/tmp/nexte_list_height_mode_evidence/list_adaptive_layout.json
  - /private/tmp/nexte_list_height_mode_evidence/settings_fixed_restored.json
- Observed: default fixed=true keeps a regular row rhythm and clips overflow chips; adaptive=false grows
  the same rows to show more chips; setting was restored to fixed=true.
- Still open: Favorites/Toplist retained pages, logged-in favorites variants, and controller visual acceptance.

Detail tag chips:
- Target: 127.0.0.1:5555 Mate X7 emulator.
- Build: a253aff signed HAP already installed.
- Detail: https://e-hentai.org/g/3989982/16600a66e8/
- State covered: normal non-usertag/non-vote tag chips only.
- Evidence:
  - /private/tmp/nexte_detail_tag_chip_evidence/detail_tag_chips.png
  - /private/tmp/nexte_detail_tag_chip_evidence/detail_tag_chips_layout.json
  - /private/tmp/nexte_detail_tag_chip_evidence/tag_top_probe_layout.json
- Observed: namespace chips `原作` / `角色` / `其他` and member chips `megaman | rockman`,
  `roll`, `artbook` render as rounded, comfortable chips with visible namespace/member distinction.
- Still open: usertag-fill chips, vote-coloured member chips, dense multi-namespace/current controller
  visual acceptance.

Gallery cover presentation:
- Target: 127.0.0.1:5555 Mate X7 emulator.
- Build: a253aff signed HAP already installed.
- Detail: https://e-hentai.org/g/3989982/16600a66e8/
- Surfaces covered: loaded/light detail header cover, loaded/light Home default list covers,
  loaded/light Home default grid-card covers, loaded/dark detail header cover, and loaded/dark Home
  default list covers, and loaded/dark Home default grid-card covers only.
- Evidence:
  - /private/tmp/nexte_cover_presentation_evidence/cover_detail_header.png
  - /private/tmp/nexte_cover_presentation_evidence/cover_detail_header_layout.json
  - /private/tmp/nexte_cover_presentation_evidence/cover_home_list.png
  - /private/tmp/nexte_cover_presentation_evidence/cover_home_list_layout.json
  - /private/tmp/nexte_cover_presentation_evidence/nav_probe_layout.json
  - /private/tmp/nexte_cover_gridcard_evidence/settings_initial.json
  - /private/tmp/nexte_cover_gridcard_evidence/settings_grid.json
  - /private/tmp/nexte_cover_gridcard_evidence/grid_home.png
  - /private/tmp/nexte_cover_gridcard_evidence/grid_home_layout.json
  - /private/tmp/nexte_cover_gridcard_evidence/settings_restored.json
  - /private/tmp/nexte_cover_darkmode_evidence/system_restore_probe.json
  - /private/tmp/nexte_cover_darkmode_evidence/dark_home_list.png
  - /private/tmp/nexte_cover_darkmode_evidence/dark_home_list_layout.json
  - /private/tmp/nexte_cover_darkmode_evidence/dark_detail_header.png
  - /private/tmp/nexte_cover_darkmode_evidence/dark_detail_header_layout.json
  - /private/tmp/nexte_cover_darkmode_evidence/system_display_light_restored.json
  - /private/tmp/nexte_cover_dark_grid_evidence/system_dark.json
  - /private/tmp/nexte_cover_dark_grid_evidence/settings_initial.json
  - /private/tmp/nexte_cover_dark_grid_evidence/settings_grid.json
  - /private/tmp/nexte_cover_dark_grid_evidence/dark_grid_home.png
  - /private/tmp/nexte_cover_dark_grid_evidence/dark_grid_home_layout.json
  - /private/tmp/nexte_cover_dark_grid_evidence/settings_restored.json
  - /private/tmp/nexte_cover_dark_grid_evidence/system_light_restored.json
- Current candidate structural fallback hardening:
  - `EhThumbnail` now separates `loaded` and `failed` state.
  - URL reuse resets both states.
  - Loading shows the existing distinct cover placeholder plus centered `LoadingProgress`.
  - Error shows the same distinct cover placeholder plus a tertiary `sys.symbol.picture` marker, so a failed
    remote cover no longer looks like an intentionally blank loaded card.
  - All thumbnail branches use the combined loading/error overlay.
- Structural/device smoke evidence:
  - `scripts/test_cover_presentation_contract.mjs` now gates explicit loading/error fallback behavior.
  - Official signed HAP was installed on Mate X7 emulator `127.0.0.1:5555`; all `hdc` commands ran outside
    the Codex sandbox.
  - /private/tmp/nexte_cover_fallback_evidence/nexte_cover_fallback_loaded_smoke.png
  - /private/tmp/nexte_cover_fallback_evidence/nexte_cover_fallback_loaded_smoke_layout.json
  - /private/tmp/nexte_cover_fallback_evidence/nexte_cover_fallback_post_reinstall.png
  - /private/tmp/nexte_cover_fallback_evidence/nexte_cover_fallback_post_reinstall_layout.json
  - Layout confirms foreground `com.erosteam.nexte` / `EntryAbility` / `pages/Index`, Home `E-Hentai` default
    list, and real gallery rows after launch.
- Loading/error visual probe evidence:
  - Current signed build adds an internal-only QA URI `nexte://qa/cover-fallback`. It is not declared in
    `module.json5` skills and is only launched explicitly by `aa start` for device evidence.
  - The probe page renders the real `EhThumbnail` component in forced loading and forced error states.
  - /private/tmp/nexte_cover_fallback_probe_evidence/nexte_cover_fallback_probe.png
  - /private/tmp/nexte_cover_fallback_probe_evidence/nexte_cover_fallback_probe_layout.json
  - Layout confirms foreground `com.erosteam.nexte` / `EntryAbility` / `pages/Index`, `Cover fallback probe`,
    `Loading`, `Error`, one `LoadingProgress`, and one error-side `SymbolGlyph`.
  - Both forced-state cover slots use `#FFE6E8EB` in light mode, matching the distinct cover placeholder.
- Observed: detail header cover fits the real cover over a distinct grey backdrop with header content
  intact; Home list covers fit over the same distinct light grey backdrop. Layout confirms Home
  `E-Hentai` default list and cover Image backgrounds at `#FFE6E8EB`. Home grid mode was temporarily
  enabled and restored; the grid evidence shows two visible grid-card cover Image nodes filling their
  grid cells over `#FFE6E8EB`, which is the intentional grid-card behavior and is distinct from the
  list/detail containFit treatment. Dark-mode evidence was captured by switching system Settings
  `浅色` -> `深色` through visible UI, then restoring `浅色`; Home list cover Image backgrounds are
  `#FF2E2E30`, and the detail header cover renders as a complete cover inside the dark card, not as a
  thin strip inside a grey block. Home grid mode was also temporarily enabled under dark mode and restored
  to `列表`; the dark grid evidence shows two visible grid-card cover Image nodes filling their grid cells
  over `#FF2E2E30`, matching the intentional grid-card behavior in dark theme. The fallback probe supplies
  deterministic device screenshots for the component's loading/error visual states; it is not a claim that a
  live network timeout/error path was naturally reproduced in a gallery list/detail surface.
- Still open: controller visual acceptance; live network-triggered loading/error screenshots only if controller
  requires natural network reproduction instead of the deterministic component probe.
```

Completion rule:

```text
Each subitem must be either ACCEPTED with evidence, OPEN with next action, or explicitly OUT_OF_SCOPE with reason. Do not archive the active plan while any subitem is OPEN.
```

### Gate V4 — Detail primary actions redesign

Status: DESIGN_PENDING_LOGIN_REQA
Priority: P0/P1 boundary, depends on controller product decision after login-state evidence

Problem:

```text
The current detail header action area still has a product mismatch:
- the `阅读` action is too visually dominant/wide for some states and may need to shrink if it stays inline;
- the favorite action needs logged-in evidence and may need a larger, clearer affordance;
- fixing only button dimensions risks preserving a cramped header-card action model.
```

Current design direction:

```text
Do not treat this as a simple eros_fe copy task.
Use eros_fe as behavior/source grounding, but evaluate a NextE-native design:
- move favorite/favcat action into the title-bar menu or another title-area affordance;
- make read/resume the primary action as a floating action button;
- use V2Next / Next2V reply-FAB patterns as the closest HarmonyOS-native reference;
- consider smart grip / 智感握姿 as an enhancement after ordinary FAB behavior works.
```

Required first stage before implementation:

```text
- Capture current logged-in favorite states: not-favorited, favorited, favcat title, favorite move/remove path.
- Capture read states: first-read, resume-read, after-read if reachable.
- Inspect current NextE `GalleryHeaderCard` and navigation/title menu primitives.
- Inspect V2Next / Next2V reply FAB and title/menu interaction patterns.
- Check HarmonyOS smart grip / 智感握姿 capability through the harmony-next skill or official docs before using any API.
```

Acceptance shape:

```text
- The read/resume primary action remains obvious and reachable without covering content or the bottom gesture area.
- Favorite state and favorite actions remain discoverable after leaving the header card.
- Logged-out state gives a clear non-secret prompt instead of a dead action.
- Mate X7 outer/inner layouts are both verified.
- If smart grip support is unavailable or disabled, the ordinary FAB layout still works.
- No State Management V1 decorators or key-churn workaround.
```

Out of scope:

```text
- Gate V1 thumbnail/cover presentation.
- auth-cookie-login implementation.
- false-404/auth matrix diagnostics.
- one-off padding/height tweaks that pre-empt the redesign decision.
```

## Current dispatch lanes

```text
2026-06-17 19:15 +0800
Base commit: 751d396
Claude lane: auth-cookie-login — safe manual Cookie login/import; logic-subtab-loading worktree exists but is paused unused.
U1 Codex lane: ui-detail-preview-audit — current screenshot/UI audit for detail preview/header/all-thumbnails/horizontal; do not touch GalleryListViewModel or retained-state logic.
Device rule: agent-controlled .197 operations must use docs/device-lease.md.
Interrupt rule: new user bug/UI feedback is classified by controller as regression/acceptance miss/new scope before any worker changes scope.
```

## Execution protocol

For each gate:

1. Read relevant source and reference implementation.
2. State the exact product semantics in code comments/contracts only if needed.
3. Make the minimal implementation change.
4. Run targeted contracts.
5. Build/install on `.197`.
6. Capture device evidence.
7. Controller reviews diff and evidence.
8. Commit and push only if accepted.
9. Update this document’s gate status.
10. Continue to the next OPEN gate automatically.

## Current merge checkpoint

```text
2026-06-18 07:22 +0800
origin/main before this Gate V2 re-QA docs update:
7b99bf5 docs(project): record false 404 smoke status

Merged/pushed since the Mac handoff:
- 11069a5 fix(list): make gallery card covers pane-responsive
- 4ab2367 chore(mac): use official hvigor signing in harness
- b3d9e5d fix(search): keep reload footer in loading state
- 0652a05 fix(gallery): restore comfortable preview grid width
- 58e48ba fix(auth): sync logout state before persistence cleanup
- 38a04b4 docs(project): record auth cookie lane merge status
- 7b99bf5 docs(project): record false 404 smoke status

These merges do not close the active visual/navigation plans by themselves. Controller re-QA and
item-by-item acceptance are still required.
```

## Prohibited shortcuts

```text
- “borderRadius exists” as acceptance
- “clip(true) exists” as acceptance
- worker says it looks good
- one screenshot from one surface used to pass all surfaces
- changing product semantics to make implementation easier
- filling/cropping images when requirement is real ratio
- archiving active docs without item-by-item acceptance
- stopping after push when another OPEN gate remains
```
