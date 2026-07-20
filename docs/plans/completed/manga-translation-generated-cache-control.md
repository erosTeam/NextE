# Manga Translation Generated Cache Control

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Expose the existing regenerable comic translation document cache in Storage so its size is visible, it can be
cleared independently, and the existing clear-all action does not leave it behind.

## Boundary

- Count only generated comic page documents in the existing local cache table and process memory front.
- Reuse the existing Storage cache card; do not add a translation setting, submenu, or provider control.
- Clearing this cache must drop only regenerable documents and runtime orchestrators.
- Do not introduce or claim manual translation, glossary, backup, or sync ownership.

## Result

- Repository and runtime now expose generated-document count and payload size, with durable statistics and a
  bounded process-memory fallback.
- Storage shows a peer `Comic translations` cache row, includes its bytes in the total, supports independent
  clearing, and includes it in clear-all.
- The cache action clears only generated page documents and process-local orchestrators. It does not touch or
  claim future manual translations or glossary data.
- Explicit clear invalidates older orchestrator cache writes, serializes persistent mutations, and fences cache
  reads during clearing so prior work cannot repopulate the cache afterward.

## Validation

- `entry@ohosTest` HAP build: successful in 8.800 s.
- Full Hypium suite on `192.168.50.237:12345`: 172 passed, 0 failures/errors/ignored, 893 ms,
  `OHOS_REPORT_CODE: 0`.
- Signed application build: successful in 8.989 s.
- Device `237` visual check: Storage displayed `漫画翻译缓存`, `2 项 · 8.6 KB`, and an enabled independent clear
  action inside the existing cache card. The action was not invoked, so existing real generated results remained.
- V1 decorator inventory: 0 files across 461 ArkTS files.
- Version/module consistency, four-locale parity/duplicate scan, and `git diff --check`: passed.
