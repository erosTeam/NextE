# Tablet Adaptive Layout

Status: implemented candidate on `codex/tablet-adaptive-layout`; targeted IP 103 regression complete,
broader compact/orientation matrix still pending.

## Five-line grounding

1. Product references: `eros_fe/lib/pages/tab/view/home_page_large.dart:44-104` keeps one stable large-screen shell; `eros_n_ohos/lib/pages/gallery/gallery_view.dart:437-488` places gallery metadata and the complete thumbnail browser side by side.
2. Primary information: an expanded window keeps the active root tab in a stable primary pane and shows only that tab's detail or a contextual placeholder in the secondary pane; a sufficiently wide gallery detail shows metadata/comments beside the complete thumbnail browser.
3. Primary actions: selecting a gallery replaces the secondary root detail and tapping a thumbnail opens the full-window Reader. Secondary actions are preview paging, jump-to-page, retry, and existing per-thumbnail menus.
4. Usable loop: Home/Favorites/Toplist and Settings use the stable split shell; Download keeps the same primary-pane geometry and shows a passive placeholder. Compact behavior and the standalone AllThumbnails route remain available. Download task detail redesign is out of scope.
5. HarmonyOS expression: use API 23 `HdsNavigation` Auto mode plus `splitPlaceholder` for the root shell, existing HDS title/menu/sheet primitives, and a responsive content layout inside GalleryDetail. Do not introduce custom-drawn controls or a second nested navigation stack.

## Technical validation facts

- Worktree: `/Users/honjow/git/NextE-wt/tablet-adaptive-layout`.
- Device target: `192.168.50.103:12345`, model `MLR-AL00`, API 23 tablet.
- Landscape display: `2560 x 1600 px`, density `2.375`, approximately `1077 x 673 vp`.
- Baseline signed build succeeds and the current app renders one full-width root surface on the tablet.
- `HdsNavigation.splitPlaceholder(ComponentContent)` is available on API 23 and is passive UI only.
- IP 103 proved the HDS default 240vp primary pane truncates the title actions, source selector, cards,
  and five-tab bar. A fixed 320vp primary pane renders all five tabs and preserves usable list cards;
  the measured bounds are `[0,105][760,1600]` at 2.375 density.
- Root `NavPathStack.setInterception(...)` compiled but caused a cold-start `TypeError` on this API 23
  device. The production candidate does not depend on that runtime path: mounted Reader destinations
  publish a V2 full-window anchor, and the root uses HDS `hideNavBar` while that anchor exists.
- Before the gallery refactor, prove that detail routes occupy the secondary pane, full-window routes keep their semantics, and root-tab changes never resize the primary pane or expose another tab's stale detail.

## Presentation rules

- Root split mode depends only on the HdsNavigation's actual width, never on the active tab.
- The active root tab owns the visible secondary stack. A tab with no owned destination shows the placeholder.
- In this first production slice, switching root tabs clears the shared secondary stack. The newly
  selected tab and a later return to the old tab both show the placeholder until the user selects a
  new item. Per-tab destination-instance restoration would require a different nested-stack root and
  is intentionally outside this lane; the shell must never collapse or reuse another tab's stale page.
- A list selection replaces that tab's secondary root detail; detail-internal routes may push above it.
- Download shows the placeholder in this lane. It must not collapse the split shell or inherit a Gallery/Settings destination.
- GalleryDetail performs its own width measurement. It only shows metadata and complete previews side by side when the allocated detail width can satisfy both panes.
- Because `onAreaChange` arrives after the first build, GalleryDetail must show a neutral bootstrap surface
  until its detail width is known; it must never assume compact mode from a zero-width initial value and
  then remount into split mode.
- Complete previews mean the existing lazy/sparse AllThumbnails paging capability, not eager loading of every preview page.
- Width/orientation changes alter presentation only. They must not automatically push or pop routes, and the preview session must retain loaded pages and scroll state.
- Re-selecting the gallery already visible in the secondary pane is a no-op. Selecting a different
  gallery atomically replaces the complete secondary branch, with the framework transition enabled.
- Explicit GalleryDetail Back uses `NavPathStack.pop(true)` so compact Navigation retains its standard
  back transition; it must not suppress animation merely because expanded screens keep the master pane.
- A detail refresh updates the wide full-preview session from one completed detail revision. Same-context
  refreshes retain compatible sparse pages, while account/site changes discard them and fence stale
  thumbnail requests before a fresh seed arrives.

## Validation path

1. Cold-start on IP 103 landscape: stable split shell and passive secondary placeholder.
2. Switch across all five root tabs: primary pane and tab bounds stay fixed; Download shows the placeholder; no cross-tab stale detail appears.
3. Home/Favorites/Toplist list item: selected GalleryDetail appears in the secondary pane and a later selection replaces its secondary root.
4. Settings category: settings destination appears in the secondary pane and is isolated from gallery-tab state.
5. Gallery detail with sufficient allocated width: metadata/comments and complete preview surface scroll independently; first-page teaser and View All transition are not duplicated.
6. Preview tail, previous-page load, jump, retry, long-press menu, and exact thumbnail-to-Reader seed remain functional.
7. Reader covers the whole window; returning restores the same root tab, secondary detail, loaded preview pages, and scroll position.
8. Portrait/landscape transition: layout adapts without a navigation push/pop and without terminal-empty flashes.

## Targeted regression evidence (2026-07-12)

- `git diff --check`, `node scripts/test_v1_decorator_inventory_contract.mjs`,
  `node scripts/test_gallery_detail_context_contract.mjs`, `node scripts/test_gallery_data_parser_contract.mjs`,
  and `node scripts/test_gallery_paging_contract.mjs` pass.
- Signed HAP build passes (`scripts/build_hvigor_signed.sh`).
- On IP 103 landscape, first gallery selection loads the split detail; immediately re-tapping the same
  left list card leaves its metadata and full-preview grid intact (no loading/remount frame observed).
- On the same device, both the detail title Back action and system Back return to the right-pane
  placeholder while keeping the application and primary list active.
- On the same device, the first captured detail frame already has the metadata pane and a separate
  right preview-loading pane; the following frame fills that same right pane with thumbnails, without
  an intermediate full-width compact-detail tree.
- The device is landscape-only evidence for this pass. Compact visual animation still needs a portrait or
  narrow-window run; its route call is verified against the API contract as `setPathStack(..., true)` /
  `pop(true)`.

## Evidence locations

- Baseline: `.hvigor/outputs/tablet-adaptive-layout/baseline-103/` (local raw screenshot/layout/log evidence; do not publish without redaction).
- Fixed 320vp split shell: `.hvigor/outputs/tablet-adaptive-layout/root-split-320-103-fixed/`.
- Download placeholder and invariant Tab bounds: `.hvigor/outputs/tablet-adaptive-layout/tab-download-103/`.
- Gallery list to secondary detail: `.hvigor/outputs/tablet-adaptive-layout/gallery-detail-open-103/`.
- Full-window Reader and restored split detail: `.hvigor/outputs/tablet-adaptive-layout/reader-full-window-103/`
  and `.hvigor/outputs/tablet-adaptive-layout/reader-back-detail-103/`.
- Repeat-selection / Back regression: `.hvigor/outputs/tablet-adaptive-layout/repeat-select-back-regression-103/`.
- Detail first-layout bootstrap: `.hvigor/outputs/tablet-adaptive-layout/detail-layout-bootstrap-103/`.
