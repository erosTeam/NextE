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

Primary device:

```text
192.168.50.197:12345
```

Reference sources:

```text
/home/gamer/git/eros_fe   # product/UX semantics
/home/gamer/git/V2Next    # retained/navigation architecture where relevant
```

## Current gate queue

### Gate V1 — Real thumbnail / cover presentation

Status: OPEN
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

### Gate V2 — Subtab never-loaded empty-state flash

Status: OPEN
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

### Gate V3 — Existing active visual/navigation items re-audit

Status: OPEN
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

Completion rule:

```text
Each subitem must be either ACCEPTED with evidence, OPEN with next action, or explicitly OUT_OF_SCOPE with reason. Do not archive the active plan while any subitem is OPEN.
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
