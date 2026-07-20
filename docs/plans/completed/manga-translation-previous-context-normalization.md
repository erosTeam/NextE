# Manga Translation Previous Context Normalization

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Ensure only the newest two real predecessor pages can influence a comic translation request and its cache identity.

## Boundary

- Omit optional previous-page records whose index is negative, fractional, current, or future.
- Deduplicate by page index with the latest caller-supplied value winning.
- Merge repository documents and caller context before selecting the newest two pages in ascending page order.
- Apply the same defensive policy in the provider prompt path.
- Do not add provider calls, automatic translation, persistence ownership, backup, sync, or UI changes.

## Result

- `ComicPreviousPageContextPolicy` is the single predecessor-only normalization boundary used by both the production
  orchestrator and Responses prompt assembly.
- Repository context is merged before recency selection, while a caller value wins when both sources describe the
  same page.
- The final cache fingerprint is built only after normalization and merge, so omitted stale/current/future context
  cannot fragment or poison the generated-document cache.

## Validation

- Orchestrator tests cover stale, duplicate, negative, current/future, and out-of-order caller context, repository
  merge priority, rolling-summary selection, and cache reuse when only omitted context changes.
- Protocol tests prove direct analyzer requests cannot send current/future/fractional pages and use the newest
  duplicate value.
- `entry@ohosTest` build passed in 10 s 221 ms.
- Full Hypium run on device `237`: 148 tests, 148 passed, 0 failed/errored/ignored, `OHOS_REPORT_CODE: 0`, 835 ms.
- Signed production build passed in 9 s 755 ms.
- V2 decorator inventory reported `0 file(s)` across 459 `.ets` files.
