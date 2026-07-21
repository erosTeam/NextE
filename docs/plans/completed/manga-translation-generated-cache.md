# Manga Translation Generated Document Cache

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **source**: historical generated-document cache slice built after the superseded Reader text entry

## Goal

Recover the last successful generated comic page document after an app-process restart without repeating provider work.
The cache must remain bounded, identity-safe, provider-neutral, and optional to the successful translation path.

## Product And Data Boundary

- The historical reference behavior was the explicit Reader `翻译当前页` path: the user action remained the only provider
  trigger, and a durable hit was presented through the then-current text sheet. The cache evidence remains useful, but
  the sheet is superseded and does not define the current visual result.
- The primary information is the normalized `ComicPageDocument` associated with the existing exact request identity.
- This phase owns only **regenerable generated cache**. It stores no provider raw response, image bytes/path, prompt,
  credential, API token, manually edited text, locked glossary term, or user note.
- `comic_translation_document_cache` is classified as `cache`, with backup and sync both excluded.
- Manual revisions, glossary ownership, backup/export, sync, batch translation, OCR, and image rendering remain outside
  this plan.

## Implementation Slice

- Add an idempotent LocalDataStore schema migration and indexes for exact lookup, prior-page context lookup, and global
  access-order pruning.
- Add a strict document codec that reconstructs model classes, bounds payload shape, and rejects corrupt or unsupported
  rows instead of publishing them.
- Add a context-bound persistent repository with a bounded in-memory front. RDB read/write failure degrades to a cache
  miss or memory-only save so a provider success is not turned into a user-visible failure.
- Load at most the existing two prior page documents in ascending page order after a process restart.
- Wire the runtime service lazily to the persistent repository; image prefetch and page appearance remain unable to
  trigger provider work.

## Validation

- Codec round-trip, copy isolation, separate repository-instance recovery, and prior-page ordering tests.
- Persistence inventory and schema contracts, secret-safety checks, State Management V2 inventory, signed app build,
  and full `entry@ohosTest` device run.
- On the user-selected device `237`: explicitly translate one page once, restart the app process, reopen the same page,
  and prove the result is a cache hit without a loading/provider cycle.
- Private comic imagery and full source/translation text remain outside diagnostics and committed evidence.

## Exit

Move this plan to `completed/` only after the cache survives a real app-process restart and the complete validation lane
passes. Completion does not claim user-owned edits or glossary persistence.

## Completion Evidence

- LocalDataStore schema v25 creates `comic_translation_document_cache` with exact-key, previous-page, and access-order
  indexes. The cache is globally bounded to 128 generated documents.
- The strict codec round-trips model objects, rejects unsupported/corrupt rows, and never stores provider raw responses,
  image bytes/paths, prompts, credentials, manual edits, or glossary ownership.
- A new repository instance recovered exact and two prior-page fixture documents from RDB in device tests; invalid rows
  degrade to a miss, and durable write failures retain the successful result in the bounded memory front.
- Final signed app build: `BUILD SUCCESSFUL` in 10 s 57 ms. Final `entry@ohosTest` build: `BUILD SUCCESSFUL` in
  10 s 477 ms.
- Final full Hypium run on user-selected device `237`: 143 tests run, 143 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0`, 821 ms. The three new persistent-repository tests passed.
- One explicit Reader request returned seven normalized blocks. After `aa force-stop` and a fresh app process, reopening
  the same page returned `缓存 · 待复核` within the first one-second inspection; diagnostics reported
  `reader_page_ready | page=0 cache=1 blocks=7 signals=1`.
- V2 decorator inventory, persistence inventory, viewed-history RDB, secret safety, settings backup, sync design,
  Huawei Cloud exclusion, and `git diff --check` gates passed. Private layouts remain ignored under `.hvigor/outputs/`.

Completed: generated documents survive an app-process restart as bounded regenerable local cache. Backup, sync, user
edits, locked glossary terms, OCR, batch translation, and rendering remain outside this plan.
