# NextE Planning Index

Last reviewed: 2026-07-21.

This file is a planning index, not a priority queue. The user's latest explicit request decides what to work on.
The old milestone snapshot is archived at
[`docs/archive/legacy-parity/roadmap-2026-06.md`](archive/legacy-parity/roadmap-2026-06.md).

## Current Maintained Sources

- [Manga Translation Design](manga-translation-design.md) — provider-neutral page documents, gallery context,
  progressive multimodal/OCR integration and staged acceptance; Phase 0 is closed with a real two-page Codex fixture
  run and explicit review boundary. The V1 in-memory repository/orchestrator is implemented; Reader entry, durable
  recovery, manual revisions and consistency workflow remain open.
- [Sync Design](plans/active/sync-design.md) — provider-neutral sync, Huawei Cloud and WebDAV protocol.
- [Persistence Dataset Inventory](plans/active/persistence-dataset-inventory.md) — owner/backup/sync classification
  used by the persistence contract.
- [Image Block Community Rules](plans/active/image-block-community-rules.md) — current client protocol and open
  follow-ups; full implementation ledger is archived.
- [Tablet Adaptive Layout](plans/active/tablet-adaptive-layout.md) — recent implementation candidate with a
  remaining broader device/orientation matrix.

Product gaps and reference research live under [`docs/research/`](research/). Historical, parked and replaced
plans live under [`docs/plans/archive/`](plans/archive/); they do not create work or authorization.

## Planning Rule

Use [Plan Lifecycle](plans/README.md). Create a bounded active plan only for a current non-trivial request, and move
it when completed or no longer active. Do not recreate global dispatch queues, append-only grounding ledgers or
device-specific handoff snapshots.
