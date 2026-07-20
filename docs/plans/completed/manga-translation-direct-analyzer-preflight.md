# Manga Translation Direct Analyzer Preflight

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Reject malformed direct analyzer requests before local image access or provider transport.

## Grounding

- Reference implementation: Reader and cache identity already require canonical project/language/profile identifiers
  and a lowercase 64-character SHA-256.
- Primary information: the Responses analyzer is exported and can be invoked without the Reader bridge or orchestrator.
- Primary action: enforce canonical identity, hash shape, and raw path length in shared request preflight.
- Current closure: requests that cannot form a valid cache identity never read a file or consume provider quota.
- Non-goals: no path canonicalization, MIME policy change, language allowlist, provider call, or cache-key change.

## Completion

- Non-canonical project/language/profile identifiers and malformed image hashes fail before file access.
- Raw image paths over the existing 4096-character bound fail even when trimming would make them short.
- Valid direct provider and Reader requests retain their current behavior.
- Test build, full device suite on 237, signed build, V2 inventory, and relevant static contracts pass.

## Result

- `ComicPageAnalysisParser.validateRequest` now requires exact project/language/profile identifiers and a
  lowercase 64-character SHA-256 before a direct analyzer can read the image.
- Image paths retain their original spelling, including legitimate leading or trailing spaces, while the raw
  value remains bounded to 4096 characters.
- Provider and Phase 0 fixtures now use canonical hashes so identity checks exercise the production contract.
- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug -p module=entry@ohosTest --no-daemon`:
  successful in 9.781 seconds.
- Full `entry_test` suite on `237`: 158 tests, 0 failures, 0 errors, 158 passes in 871 ms.
- `scripts/build_hvigor_signed.sh`: successful in 15.392 seconds.
- V2 inventory: 0 live V1 files across 459 ETS files; version consistency, i18n parity, and `git diff --check`
  also passed.
