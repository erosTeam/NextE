# Manga Translation Context Review Filter

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21

## Goal

Keep warning/error-targeted generated text out of later model context so uncertain translations do not propagate across pages.

## Boundary

- Exclude generated pages with page-level warning/error signals.
- Exclude only targeted blocks for block-level warning/error signals and retain INFO metadata.
- Continue using up to two most recent eligible generated pages, backfilling past an excluded page.
- Do not reinterpret caller-supplied context, rewrite text, change persistence, add model calls, or alter user-data semantics.

## Result

- Reused the provider-neutral review policy while selecting generated prior-page prompt context.
- Page-level warning/error signals now exclude a generated page and let an earlier eligible page fill the two-page budget.
- Block-level warning/error signals remove only the targeted source/translation block; INFO and page summaries remain eligible.
- Caller-supplied context keeps its existing semantics, and model-visible context changes continue to flow through the analyzer cache fingerprint.
- Added end-to-end orchestrator coverage and updated the durable design.

## Validation

- `git diff --check`: passed.
- V1 decorator inventory: `0 file(s)` across 462 `.ets` files.
- i18n locale parity and duplicate-key check: passed across all four locales.
- `entry@ohosTest` HAP build: `BUILD SUCCESSFUL in 9 s 62 ms`.
- Signed application build: `BUILD SUCCESSFUL in 8 s 244 ms`.
- Device `192.168.50.237:12345`: 178 tests, 178 pass, 0 failure, 0 error, 0 ignored; task time 864 ms; `OHOS_REPORT_CODE: 0`.
