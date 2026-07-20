# Manga Translation Quality Signal Priority

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21

## Goal

Keep a locally derived actionable consistency warning visible when provider informational metadata fills the bounded quality-signal collection.

## Boundary

- Retain the 512-signal hard limit.
- Evict only one informational signal when space is required for a derived warning.
- Never evict provider warning/error signals or mutate the input document.
- Do not change provider parsing, persistence, model calls, cache identity, settings, or user-data semantics.

## Result

- Added bounded actionable-signal insertion to the consistency audit.
- A saturated collection evicts its last INFO only after a real local conflict is found, then appends the derived warning.
- A saturated warning/error collection remains untouched, and the copied audit result never mutates its input document.
- Added regression coverage for both saturated INFO and fully actionable collections and updated the durable design.

## Validation

- `git diff --check`: passed.
- V1 decorator inventory: `0 file(s)` across 462 `.ets` files.
- i18n locale parity and duplicate-key check: passed across all four locales.
- `entry@ohosTest` HAP build: `BUILD SUCCESSFUL in 13 s 350 ms`.
- Signed application build: `BUILD SUCCESSFUL in 13 s 723 ms`.
- Device `192.168.50.237:12345`: 177 tests, 177 pass, 0 failure, 0 error, 0 ignored; task time 907 ms; `OHOS_REPORT_CODE: 0`.
