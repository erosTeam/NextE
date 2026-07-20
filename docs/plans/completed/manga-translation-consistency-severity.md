# Manga Translation Consistency Severity

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Keep the specialized cross-page consistency marker aligned with the shared review policy: an informational signal must
not become an actionable conflict or suppress a real locally derived warning.

## Boundary

- Require warning/error severity for the specialized consistency lookup.
- Preserve informational provider signals as metadata and let a real local conflict append its warning.
- Do not alter prompt, cache identity, provider calls, persistence, Reader hierarchy, or user-data semantics.

## Result

- The bounded consistency lookup now requires both the specialized code and warning/error severity before reporting an
  actionable block conflict.
- An informational provider signal with the specialized code remains metadata. If local exact-source comparison finds
  a real translation difference, the audit preserves that INFO and appends its own warning instead of being suppressed.
- Reader behavior, request/cache identity, provider execution, persistence, and settings are unchanged.

## Validation

- `entry@ohosTest` HAP build: successful in 13.421 s.
- Signed application build: successful in 13.825 s.
- Full Hypium suite on `192.168.50.237:12345`: 174 passed, 0 failures/errors/ignored, 878 ms,
  `OHOS_REPORT_CODE: 0`. The new test proves INFO is non-actionable before audit and the real local conflict becomes a
  warning afterwards.
- V1 decorator inventory: 0 files across 462 ArkTS files.
- Four-locale parity/duplicate scan and `git diff --check`: passed.
