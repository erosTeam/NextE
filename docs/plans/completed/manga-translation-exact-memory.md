# Manga Translation Exact Memory

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Carry stable exact source-to-translation pairs beyond the two-page prompt window without guessing glossary terms,
persisting new user data, or increasing model calls.

## Boundary

- Derive entries only when the same normalized source has the same non-empty translation on at least two distinct
  generated prior pages.
- Exclude conflicting mappings, long entries, and same-page repetition; cap scanning at 32 pages and output at 64
  entries.
- Label the prompt section as exact-match translation memory, keep glossary terms authoritative, and retain the
  existing two-page full-context budget.
- Include only prompt-visible memory in the context fingerprint and bump the Responses prompt version.
- Do not claim term, name, alias, lock, manual correction, backup, or sync semantics.

## Result

- Added a provider-neutral transient memory entry, deep-copy behavior, and bounded request validation for count,
  unique source, field sizes, prior-page ownership, and occurrence count.
- Orchestration deterministically rebuilds memory from prior generated documents; supplied entries remain ahead of
  generated duplicates.
- The prompt uses an independently bounded 1,800-character exact-match section. Prompt-visible memory participates
  in the context fingerprint while budget-omitted tails do not.
- Responses prompt version `comic-page-responses-v3` isolates previous v2 generated cache entries.

## Validation

- `entry@ohosTest` HAP build: successful in 9.026 s.
- Full Hypium suite on `192.168.50.237:12345`: 170 passed, 0 failures/errors/ignored, 893 ms,
  `OHOS_REPORT_CODE: 0`.
- Device tests cover a stable mapping beyond the two-page window, supplied-entry precedence, oversized input
  rejection before analyzer work, bounded prompt assembly, and visible-versus-omitted fingerprint behavior.
- Signed application build: successful in 9.122 s.
- V1 decorator inventory: 0 files across 461 ArkTS files.
- Version/module consistency, four-locale parity/duplicate scan, and `git diff --check`: passed.
