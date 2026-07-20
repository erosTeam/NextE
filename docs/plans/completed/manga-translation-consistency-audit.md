# Manga Translation Consistency Audit

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Detect repeated source text that changes translation across a gallery without rewriting provider output, adding model
calls, or creating user-owned glossary persistence before its ownership semantics are decided.

## Grounding

- The prompt intentionally carries only the latest two pages, so a repeated name can drift after it leaves that window.
- Generated page documents already support bounded warning signals and Reader already presents any signal as review
  required.
- Persisting a derived consistency signal would make a cache entry depend on older pages absent from its request
  identity.

## Result

- Audit up to 32 generated prior pages while retaining the existing two-page prompt context budget.
- Add one warning per current block when the same normalized source has a different prior translation.
- Recompute warnings on fresh and cache-hit results, but save the original provider document without derived signals.
- Never include source or translated text in the warning message or diagnostics.
- Treat malformed repository limits as zero and cap valid prior-page queries at 32.
- Keep correction, semantic alias resolution, user glossary ownership, backup, and sync outside this phase.

## Validation

- `entry@ohosTest` HAP build: successful in 13.384 s.
- Full Hypium suite on `192.168.50.237:12345`: 168 passed, 0 failures/errors/ignored, 889 ms,
  `OHOS_REPORT_CODE: 0`.
- Device test proves a page-3 conflict against page 0 is detected while only pages 1 and 2 enter the analyzer prompt;
  the derived signal is absent from the saved document and reappears on cache-hit recomputation.
- Signed application build: successful in 14.726 s.
- V1 decorator inventory: 0 files across 460 ArkTS files.
- Version/module consistency, locale parity/duplicate scan, and `git diff --check`: passed.
