# Manga Translation Phase 0 Foundation

- **status**: active
- **created**: 2026-07-20
- **last reviewed**: 2026-07-20
- **source**: user requested starting the documented manga-translation work

## Goal And Non-Goals

- Goal: establish a provider-neutral structured comic-page foundation and prove that public Responses API and an
  experimental Codex OAuth path can share it without sharing credentials or transport assumptions.
- Non-goals: uploading real gallery images in this task, OCR model
  selection, page-result RDB schema, Reader integration, automatic translation, overlay/inpainting/typesetting,
  or release work.

## Grounding

- Reference workflow: [Manga Translation Workflows](../../research/manga-translation-workflows.md).
- Primary information: original text, reading order, optional translation and quality signals belong to a versioned
  page document; geometry is an optional capability.
- Primary action: validate a provider-neutral structured result against project/page/image identity and revisions.
- Current closure: production ArkTS models, parsers, both provider adapters and provider settings compile; a reviewed
  two-page original fixture now proves file identity, structural parsing and deterministic transcript/order/name-term
  scoring in Hypium without pretending it proves live-service quality.
- HarmonyOS expression: shared ArkTS classes/services, a State Management V2 settings page and `entry@ohosTest`;
  no Reader integration or device command in this lane.

## Current Evidence

- Design authority: [Manga Translation Design](../../manga-translation-design.md).
- Reader local-file seam: `feature/reader/src/main/ets/pages/ReaderPage.ets` records cached files through
  `rememberImageFile`, while cache warmers also invoke `onImageFileReady`; this lane does not attach model work there.
- Existing comment translation is string-only and remains separate.

## Work And Validation

- [x] Add versioned project/page/block/glossary value models with explicit copy semantics.
- [x] Add analyzer request/context/capability/result interfaces.
- [x] Add bounded parser/normalizer with schema, identity, ordering, geometry and quality-signal validation.
- [x] Add structural evaluation counts that do not claim OCR/translation accuracy.
- [x] Add sanitized provider-neutral JSON fixture and fake analyzer Hypium coverage.
- [x] Add a legally usable two-page original manga fixture, immutable hashes and machine-readable transcript/order/name
  references.
- [x] Add reference-based transcript, reading-order and required translation-term evaluation without fuzzy guessing.
- [x] Add a public Responses API adapter using explicit base URL, API Key and model settings.
- [x] Add an experimental Codex device-code OAuth adapter, SSE reconstruction and one-shot refresh retry.
- [x] Query the public `/models` catalog and the account-scoped Codex model catalog; keep manual model input only
  as an API-compatible-endpoint fallback.
- [x] Restore the account-scoped Codex usage cache on page entry, keep the quota row interactive, and refresh once in
  the background without clearing the cached value or showing an automatic-failure toast. Manual taps still refresh and
  surface failures. Classify 5-hour/weekly windows by actual duration, combine them into one compact `5H`/`7D` item,
  and omit missing windows.
- [x] Keep API and OAuth credentials separate; exclude rotating Codex tokens and the volatile usage cache from backup
  and sync.
- [x] Add provider settings UI and fake transport tests for prompt context, Responses output and OAuth polling.
- [x] Keep the unsupported Codex compatibility warning as secondary text directly below the provider card rather
  than inside it or in a separate settings card.
- [x] Compile the application and `entry@ohosTest` targets.
- [x] Run V2 decorator, persistence, secret-safety, settings-backup and diff checks.

## Validation Results

- `bash scripts/build_hvigor_signed.sh`: `BUILD SUCCESSFUL` in 16 s 335 ms after account-scoped quota caching and
  background refresh were added.
- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug -p module=entry@ohosTest --no-daemon`:
  `BUILD SUCCESSFUL` in 16 s 180 ms with the original image fixture, reference evaluator tests and quota-cache account
  isolation test registered.
- `node scripts/test_v1_decorator_inventory_contract.mjs`: 0 files with live V1 decorators across 450 `.ets`
  files.
- i18n parity and locale JSON validation: passed.
- Persistence inventory, secret-safety and settings-backup contracts: passed.
- `git diff --check`: passed.
- Fixture JSON parse and structural smoke check: schema 1, two blocks.
- Original evaluation fixture: two 1024 x 1536 PNG pages, manifest identities and both SHA-256 hashes verified on device.
- Full Hypium run on `192.168.50.237:12345`: 129 tests run, 129 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0` in 760 ms. This includes exact transcript success, reading-order/name-term failures, and independent
  missing/unexpected transcript findings.
- Live preflight boundary on the same device: `entry_test` retained an empty provider Preferences view even after
  starting `EntryAbility`; the attempted test-only hook was removed rather than copying OAuth tokens across module
  stores. No provider request or image upload occurred.
- Device `192.168.50.237:12345` retained its existing Codex login and `gpt-5.6-luna` selection after update install.
  The production settings page queried usage successfully, rendered only the returned `7D` window in one compact row,
  omitted the absent `5H` window, showed no refresh icon, and kept the compatibility warning outside the card.
- After the quota-cache update was installed on the same device, leaving and reopening the manga-translation page
  immediately retained the cached `7D` value instead of returning to a loading subtitle. The quota `HdsListItem`
  remained `enabled=true` and `clickable=true`; the bounded log capture contained no usage/cache failure event.
- Hypium cases are registered and compile. The 129-test device pass predates the quota-cache account-isolation case;
  that new case currently has compilation evidence only.

## Remaining Phase 0 Work

- Expand the current reviewed two-page original fixture beyond its vertical text, furigana, small text, SFX, complex
  background and multi-page name-consistency baseline to include color pages and denser multi-speaker layouts.
- Run the fixture through at least one real provider by an explicit opt-in path, then record transcript errors,
  reading-order errors, structured-output failures, latency, upload bytes and visible cost/quota impact.
- Choose the production-side trigger shape and fixture packaging, or explicitly accept a separate test-module OAuth
  login; the production option must show confirmation before consuming quota.
- Decide whether the production path may call a direct API or must use a NextE-compatible gateway, and migrate OAuth
  secrets to HUKS/system credential storage before considering the experimental path production-ready.
- Add repository/orchestrator and Reader explicit-trigger UI only after a provider passes the evaluation boundary.

## Completion

- The foundation and dual-provider spike are complete when production and ohosTest compilation pass, fake transport
  tests are registered, and credential backup/sync boundaries pass their contracts.
- Phase 0 remains active until at least one real provider is evaluated against the reviewed fixture set; the offline
  evaluator and device pass establish the measurement path, not model quality.
