# Manga Translation Cache Safe Integers

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **completed**: 2026-07-21

## Goal

Reject persisted comic document integers that cannot be represented exactly by JavaScript.

## Grounding

- Reference implementation: live request identity and Reader preflight already require finite safe integers.
- Primary information: the strict generated-document codec is the trust boundary for local RDB payloads.
- Primary action: make the codec's shared integer decoder require the full safe-integer range.
- Current closure: corrupt page and revision values cannot enter cache comparison or previous-page ordering.
- Non-goals: no RDB schema/migration, eviction, cache identity, backup/sync, or normal document change.

## Completion

- Persisted page and revision values above Number.MAX_SAFE_INTEGER are rejected by the codec.
- Normal generated-document round trips and repository restart recovery remain intact.
- Test build, full device suite on 237, signed build, V2 inventory, and relevant static contracts pass.

## Result

- The codec's shared integer decoder now accepts only finite integral values within the JavaScript safe-integer range.
- This covers page indexes, document and block revisions, reading order, schema version, dimensions, and tile counts
  before their field-specific constraints run.
- Existing invalid-cache cleanup remains the owner of discarding corrupt RDB rows; no migration is needed.

## Validation

- entry@ohosTest debug HAP build: passed in 9.718 s.
- Full suite on device 237: 157/157 passed in 839 ms; the new codec test passed in 1 ms.
- Signed production HAP build: passed in 9.501 s.
- git diff --check, V2 decorator inventory, persistence inventory, secret safety, settings backup, sync design, and
  Huawei Cloud sync contracts: passed.
