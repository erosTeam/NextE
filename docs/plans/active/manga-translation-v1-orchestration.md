# Manga Translation V1 Orchestration And Reader Entry

- **status**: active
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **source**: continue the user-authorized manga-translation implementation after Phase 0 closure

## Goal

Build the first V1 runtime path from a provider-neutral page request to an explicitly requested Reader result. Keep
provider calls out of image loading and prefetch, preserve page ownership across navigation, and make the service layer
testable without a live provider.

## Completed Slice: Repository And Orchestrator

- Add a repository contract whose request identity includes project/page/image, provider/model/analyzer revision,
  language, document revisions, image-preparation profile, and project context revisions.
- Add a bounded in-memory implementation as the first replaceable repository. Generated documents are process-local
  regenerable cache in this slice; no RDB table, backup payload, sync dataset, or user-edit ownership is introduced.
- Add an orchestrator that performs cache lookup, exact-request in-flight de-duplication, previous-page context loading,
  provider analysis, identity validation, and save-on-success.
- Keep failed refreshes from replacing the last successful document and ensure a late result remains attached to the
  request identity that created it.
- Cover cache hit/miss, cache-key separation, concurrent calls, previous-page context, failed refresh, and changed-image
  stale-result boundaries with fake-analyzer Hypium tests.

Validation on 2026-07-21:

- signed application build: `BUILD SUCCESSFUL` in 13 s 632 ms;
- `entry@ohosTest` build: `BUILD SUCCESSFUL` in 13 s 334 ms;
- full Hypium run on the user-selected device `237`: 138 tests run, 138 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0`, 768 ms;
- the five new orchestrator tests executed through the installed test HAP; no provider request or quota consumption was
  involved;
- no RDB schema, persisted key, backup adapter, sync dataset, or Reader UI changed in this slice.

## Next Slice: Reader Explicit Entry

- Use the existing Reader current-page image-file callback; never trigger from image prefetch or page appearance.
- Add one explicit current-page action to the existing Reader more-actions surface and a compact inspectable text result.
- Keep double-page selection explicit and default to the currently indexed page.
- Show unavailable/configuration/loading/failure/review/success states without hiding the original image.
- Fence UI publication by gallery/session/page/image identity so a result returning after navigation cannot appear on the
  new current page.

## Deferred Decisions And Non-Goals

- Manual source/translation edits, glossary editing, durable app-restart recovery, backup/export, and sync are deferred
  because they introduce durable user-data ownership that must be decided as one coherent slice.
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

## Completion

This plan completes only when the repository/orchestrator contracts and the Reader explicit current-page path are both
implemented, independently validated, and committed. Static builds do not prove the Reader result is visible on the
correct page.
