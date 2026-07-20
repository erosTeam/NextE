# Manga Translation Reader Identity Preflight

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **completed**: 2026-07-21

## Goal

Reject non-canonical Reader project and language identifiers before reading or hashing the local image.

## Grounding

- Reference implementation: repository request identity already requires non-empty, bounded, trim-exact identifiers.
- Primary information: Reader input validation executes before `fileMetadata()` and provider construction.
- Primary action: apply the same exact identifier rule at the Reader bridge while keeping filesystem paths unchanged.
- Current closure: malformed identifiers fail before any image file access or provider work.
- Non-goals: no path canonicalization, language-code allowlist, provider call, Reader UI, or persistence change.

## Completion

- Project, source-language, and target-language identifiers with outer whitespace fail at Reader preflight.
- A deliberately missing image path proves those failures occur before filesystem access.
- Test build, full device suite on `237`, signed build, V2 inventory, and relevant static contracts pass.

## Result

- Reader project, source-language, and target-language identifiers now use the same non-empty, bounded, trim-exact
  rule as persistent request identity.
- The image path keeps separate path-safe validation, so the change does not canonicalize or rewrite valid filenames.
- Malformed identifiers stop before file stat/hash, provider construction, cache lookup, or transport.

## Validation

- `entry@ohosTest` debug HAP build: passed in 13.854 s.
- Full suite on device `237`: 156/156 passed in 852 ms; the new Reader identity test passed in 2 ms.
- Signed production HAP build: passed in 14.680 s.
- `git diff --check`, V2 decorator inventory, persistence inventory, secret safety, settings backup, sync design, and
  Huawei Cloud sync contracts: passed.
