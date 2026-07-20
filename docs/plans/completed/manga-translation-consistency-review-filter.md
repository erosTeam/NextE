# Manga Translation Consistency Review Filter

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21

## Goal

Prevent warning/error-marked generated text from creating false cross-page translation conflicts.

## Boundary

- Ignore a previous page with a page-level warning/error and ignore only targeted blocks for block-level signals.
- Do not derive another conflict for a current page/block that already has an actionable review signal.
- Keep informational signals and unrelated translated blocks eligible.
- Do not rewrite text, persist derived signals, change provider calls, cache identity, settings, or user-data semantics.

## Result

- Reused the provider-neutral review policy when selecting current and historical consistency evidence.
- Kept INFO signals, translated blocks outside a review target, and compatible historical documents eligible.
- Added regression coverage for INFO, page/block warning, current warning, and unrelated missing-block cases.
- Updated the durable manga translation design.

## Validation

- `git diff --check`: passed.
- V1 decorator inventory: `0 file(s)` across 462 `.ets` files.
- i18n locale parity and duplicate-key check: passed across all four locales.
- `entry@ohosTest` HAP build: `BUILD SUCCESSFUL in 12 s 726 ms`.
- Signed application build: `BUILD SUCCESSFUL in 14 s 676 ms`.
- Device `192.168.50.237:12345`: 176 tests, 176 pass, 0 failure, 0 error, 0 ignored; task time 894 ms; `OHOS_REPORT_CODE: 0`.
