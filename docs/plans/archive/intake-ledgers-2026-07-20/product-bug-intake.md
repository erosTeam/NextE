# ARCHIVED: Product Bug / Feature Intake And Domain Ledgers

> This append-only intake structure was retired on 2026-07-20. It is historical evidence, not a current queue.
> Current process: `docs/agent-guides/product-work.md`.

Status: index and writing rules.

Purpose:

- Keep this file as the short domain index and intake writing contract.
- Keep full evidence, reproductions, source notes, and status updates in the domain intake files below.
- Do not append long evidence blocks here.

Operating rule:

- Do not treat an entry here as immediate authorization to interrupt the user's current request.
- The user's latest explicit request decides what to do next; use this file only to find the right
  evidence ledger and writing rules.
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

## Split Writing Rules

- New bugs go first to the matching `docs/plans/active/intake/*.md` file.
- `product-bug-intake.md` should stay short; it is not a full evidence ledger.
- Accepted, superseded, parked, or historical evidence belongs in the domain file or archive, not in a
  recreated global queue.

## Domain Intake Files

- [Write Operations Intake](intake/write-operations.md) — 4 item(s).
- [Favorites Intake](intake/favorites.md) — 4 item(s).
- [Gallery List, Grid, And Thumbnails Intake](intake/gallery-list-grid.md) — 7 item(s).
- [Gallery Detail And Comments Intake](intake/gallery-detail-comments.md) — 6 item(s).
- [Search Intake](intake/search.md) — 8 item(s).
- [Reader Intake](intake/reader.md) — 16 item(s).
- [Downloads Intake](intake/downloads.md) — 2 item(s).
- [Settings And History Intake](intake/settings.md) — 11 item(s).
- [Persistence And Backup Intake](intake/persistence.md) — 1 item(s).
- [Cache Architecture Intake](intake/cache.md) — 1 item(s).
- [General Archive Intake](intake/history-archive.md) — 1 item(s).

## Current Entry

- Start from the user's latest explicit request.
- Use [EhViewer / JHenTai Feature Research](../../../research/ehviewer-jhentai-feature-comparison.md) only as a source-backed
  comparison/candidate record; verify current NextE implementation before acting from it.
- Treat the domain intake files as evidence ledgers, not direct priority queues.
