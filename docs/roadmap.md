# NextE Planning Index

Last reviewed: 2026-07-21.

This file is a planning index, not a priority queue. The user's latest explicit request decides what to work on.
The old milestone snapshot is archived at
[`docs/archive/legacy-parity/roadmap-2026-06.md`](archive/legacy-parity/roadmap-2026-06.md).

## Current Maintained Sources

- [Manga Translation Design](manga-translation-design.md) — product definition reset is active. The non-negotiable
  current target is lightweight Reader translation whose result is a visual translated comic page, not a text panel.
  A later production/edit/export workflow may share the document and renderer but has separate scope and acceptance.
  Existing provider-neutral documents, provider adapters, context, cache and consistency code are infrastructure
  candidates only. The historical Reader text sheet is not an accepted V1 result. The completed audit is
  [Manga Translation Product Reset](plans/completed/manga-translation-product-reset.md); current execution is
  [Manga Translation Visual Reader V1](plans/active/manga-translation-reader-visual-v1.md).
- [Shared LLM Source Profiles](plans/active/llm-source-profiles.md) — consolidate comment/comic endpoint, credential,
  Codex login, model-catalog and usage plumbing into multiple reusable source profiles while keeping per-feature model
  and policy bindings separate.
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
