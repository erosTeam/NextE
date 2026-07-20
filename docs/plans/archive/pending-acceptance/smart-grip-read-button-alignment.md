# Smart-grip (智感握姿) Read-button alignment

Status: implemented, pending build + device acceptance. Ported from V2Next's ReplyActionAlignment /
MotionHandState feature; applied to the NextE gallery-detail Read FAB.

## What

A one-handed-reachability setting that aligns the floating **Read** button on the gallery detail page to
the side that's easiest to reach. Four modes (V2Next parity):

- **smartGrip (智感握姿)** — auto-follows the holding hand via the HarmonyOS `@kit.MultimodalAwarenessKit`
  `motion.on('holdingHandChanged')` grip detector (debounced 450ms). Only offered on devices where the
  subscription succeeds.
- **followOperation (跟随操作)** — infers the side from where the user scrolls/taps (start X, 28% center
  safe-zone, 260ms throttle; a drag must be clearly vertical to count).
- **fixedLeft / fixedRight (固定左侧/右侧)** — pinned.

Default = smartGrip on grip-capable devices, else followOperation.

## Architecture (ported, NextE naming)

State (AppStorageV2):
- `ActionAlignmentState` — `alignmentMode` + `holdingHandSupported` (the user's mode + device capability).
- `ActionHandEdgeState` — the resolved `edge` ('left' | 'right'), single-writer.

Logic:
- `MotionHandStateService` — subscribes grip detection, resolves the active mode into an edge, debounces
  grip events, tracks follow-operation X. Started from `EntryAbility` after `SettingsBootstrap.loadAll`.
- `ActionAlignmentSettings` — mode constants + normalize/default/effective/options + preferences
  persistence (ListModeSettings-style, not V2Next's descriptor framework).
- `ActionFollowTouchTracker` — pure touch→report helper (vertical-dominance scroll detection).

Setting UI: `LayoutSettingsPage` dropdown selector (4 options; smartGrip hidden when unsupported) +
i18n `settings_action_alignment[_hint]`, `smart_grip`, `follow_operation`, `fixed_left`, `fixed_right`.

Consumer: `GalleryDetailPage` — the Read FAB moved from a fixed `.position({right,bottom})` to a full-width
bottom rail; the button is Start-anchored and slid with `.translate({x})` + `.animation()` driven by the
resolved edge (`@Monitor('actionEdge.edge')`). Root width (Stack `onAreaChange`) and button width (button
`onAreaChange`) convert the discrete edge into a continuous X. The Stack `onTouch` feeds followOperation.

## Files

New (shared): `state/ActionAlignmentState.ets`, `state/ActionHandEdgeState.ets`,
`settings/ActionAlignmentSettings.ets`, `services/MotionHandStateService.ets`,
`utils/ActionFollowTouchTracker.ets`.
Edited: `constants/StorageKeys.ets`, `settings/SettingsBootstrap.ets`, `Index.ets`,
`entry/.../EntryAbility.ets`, `feature/settings/.../LayoutSettingsPage.ets`, i18n ×4,
`feature/gallery/.../GalleryDetailPage.ets`.

## Notes / follow-ups

- No special permission needed for `motion.holdingHandChanged` (matches V2Next module.json5).
- smartGrip degrades to followOperation when the device lacks grip detection (subscription throws →
  holdingHandSupported=false → option hidden).
- Device acceptance: verify the Read FAB slides left/right per each mode (fixed first; smartGrip needs a
  grip-capable device/emulator; followOperation by scrolling on a side).
