# Historical Manga Translation Orchestration And Reader Text Entry

- **status**: superseded as a product milestone; retained only as historical implementation evidence
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **source**: continue the user-authorized manga-translation implementation after Phase 0 closure

> This implementation was technically validated under an incorrect product scope. Its Reader text sheet is not an
> accepted manga-translation V1 and this file cannot authorize restoring or extending that primary UI. Provider,
> orchestration, cache and page-ownership evidence may be reused only after audit under the
> [Manga Translation Product Reset](../completed/manga-translation-product-reset.md).

## Historical Goal

Build the first V1 runtime path from a provider-neutral page request to an explicitly requested Reader result. Keep
provider calls out of image loading and prefetch, preserve page ownership across navigation, and make the service layer
testable without a live provider.

## Completed Slice: Repository And Orchestrator

- Add a repository contract whose request identity includes project/page/image, provider/model/analyzer revision,
  language, document revisions, image-preparation profile, project context revisions, and a SHA-256 fingerprint of the
  actual glossary/style/previous-page context.
- Add a bounded in-memory implementation as the first replaceable repository. Generated documents are process-local
  regenerable cache in this slice; no RDB table, backup payload, sync dataset, or user-edit ownership is introduced.
- Add an orchestrator that performs cache lookup, exact-request in-flight de-duplication, previous-page context loading,
  provider analysis, identity validation, and save-on-success.
- Keep failed refreshes from replacing the last successful document and ensure a late result remains attached to the
  request identity that created it.
- Cover cache hit/miss, cache-key separation, concurrent calls, previous-page context, failed refresh, changed-image
  stale-result boundaries, and downstream invalidation after a prior-page correction with fake-analyzer Hypium tests.

Validation on 2026-07-21:

- signed application build: `BUILD SUCCESSFUL` in 13 s 632 ms;
- `entry@ohosTest` build: `BUILD SUCCESSFUL` in 13 s 334 ms;
- full Hypium run on the user-selected device `237`: 138 tests run, 138 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0`, 768 ms;
- the five new orchestrator tests executed through the installed test HAP; no provider request or quota consumption was
  involved;
- no RDB schema, persisted key, backup adapter, sync dataset, or Reader UI changed in this slice.

## Completed Slice: Reader Explicit Entry

- The existing Reader current-page image-file callback is used only after the user taps `翻译当前页`; image prefetch,
  file readiness, page appearance, and automatic warmers never trigger provider work.
- The existing Reader more-actions surface owns one explicit current-page action and a compact original/translation
  sheet with unavailable, configuration, loading, fixed-code failure, review, success, no-text, and cache states.
- Reader publication is fenced by route epoch, gallery id/token/site, zero-based page index, image file, and UI epoch.
  Page changes close and invalidate presentation while a useful late result remains owned by its original cache key.
- `ComicTranslationRuntimeService` validates and hashes the local file, derives a provider-neutral request, reads the
  configured public API or experimental Codex adapter, and never puts credentials into logs or cache keys in plaintext.
- Provider transport/protocol/output failures now carry fixed stage/detail codes. Real Reader validation exposed a
  model-generated `translationOrigin` mismatch; the parser now derives provenance from translated-text presence and
  source origin for missing/contradictory metadata while continuing to reject unknown provenance values.

## Deferred Decisions And Non-Goals

- Manual source/translation edits, glossary editing, durable app-restart recovery, backup/export, and sync remain outside
  this completed plan. Generated-document persistence can proceed separately as regenerable local cache; user edits and
  locked terms still require an explicit durable-data ownership slice.
- Automatic page translation, gallery batch translation, OCR fallback, geometry overlay, inpainting, typesetting, and
  export are not authorized by this plan.
- The experimental Codex OAuth path remains an opt-in compatibility route; this plan does not promote it to a supported
  public API contract.

## Validation

- `node scripts/test_v1_decorator_inventory_contract.mjs`
- `node scripts/test_persistence_inventory_contract.mjs`
- `node scripts/test_secret_safety_contract.mjs`
- `node scripts/test_settings_backup_contract.mjs`
- signed app build and `entry@ohosTest` build
- full Hypium device run before claiming Reader runtime behavior
- controlled real-provider request only after explicit action; cached/fake-provider paths should carry most iteration

Reader closure evidence on 2026-07-21:

- signed application build and `entry@ohosTest` build both succeeded after the final parser/runtime changes;
- full Hypium run on user-selected device `237`: 140 tests run, 140 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0`, 767 ms;
- the Reader more menu exposed an enabled `翻译当前页` action only after page 1 had a stable local file and dimensions;
- one explicit real request using the device's selected Codex model first produced the safe failure code
  `provider_output_translation_origin`; after provenance normalization, the same real page returned four inspectable
  source/translation blocks in review state;
- closing and reopening the same page result returned immediately as `缓存 · 待复核` with four blocks and no loading
  state; changing Reader from page 1 to page 2 removed the sheet and all page-1 result rows;
- screenshots/layout dumps remain local under `.hvigor/outputs/manga-reader-translation/` and are excluded from Git
  because they contain private gallery imagery/text.

## Historical Closure

The repository/orchestrator contracts and Reader text-entry path were implemented and independently validated with
static, full-device-test, real-provider, cache-hit, and page-ownership evidence. This closure proves infrastructure
behavior only. It does not prove or complete a visual translated comic page, and it is superseded as a product milestone.
