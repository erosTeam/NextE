# Manga Translation Phase 0 Foundation

- **status**: complete
- **created**: 2026-07-20
- **last reviewed**: 2026-07-21
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
- HarmonyOS expression: shared ArkTS classes/services, a State Management V2 settings page, `entry@ohosTest`, and a
  user-confirmed production-module fixture run; no Reader integration or real gallery upload in this lane.

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
- [x] Add one explicit provider-evaluation row to the selected provider card, package hash-verified JPEG derivatives
  of the two original samples, require native confirmation, pass page-1 context into page 2, delete temporary files,
  and retain only aggregate results.
- [x] Run the reviewed fixture through the experimental Codex OAuth path, use the returned failures to separate Codex
  and public Responses request bodies, constrain text-only output to empty geometry, and retain true transcript review
  findings instead of weakening the evaluator.
- [x] Compile the application and `entry@ohosTest` targets.
- [x] Run V2 decorator, persistence, secret-safety, settings-backup and diff checks.

## Validation Results

- `bash scripts/build_hvigor_signed.sh`: final `BUILD SUCCESSFUL` in 9 s 663 ms after the live request compatibility,
  text-only geometry and reviewed-manifest corrections.
- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug -p module=entry@ohosTest --no-daemon`:
  final `BUILD SUCCESSFUL` in 13 s 795 ms with request-body, error-classification and manifest tests registered.
- `node scripts/test_v1_decorator_inventory_contract.mjs`: 0 files with live V1 decorators across 451 `.ets`
  files.
- i18n parity and locale JSON validation: passed.
- Persistence inventory, secret-safety and settings-backup contracts: passed.
- `git diff --check`: passed.
- Fixture JSON parse and structural smoke check: schema 1, two pages, 5 + 6 reviewed blocks.
- Original evaluation fixture: two 1024 x 1536 PNG pages, manifest identities and both SHA-256 hashes verified on device.
- Final full Hypium run on `192.168.50.237:12345`: 133 tests run, 133 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0` in 748 ms. This includes the corrected 5 + 6 block manifests, separate public/Codex request
  fields, safe HTTP/local validation codes, prompt context and account-scoped quota cache.
- Live preflight boundary on the same device: `entry_test` retained an empty provider Preferences view even after
  starting `EntryAbility`; the attempted test-only hook was removed rather than copying OAuth tokens across module
  stores. No provider request or image upload occurred.
- Device `192.168.50.237:12345` retained its existing Codex login and `gpt-5.6-luna` selection after update install.
  The production settings page queried usage successfully, rendered only the returned `7D` window in one compact row,
  omitted the absent `5H` window, showed no refresh icon, and kept the compatibility warning outside the card.
- After the quota-cache update was installed on the same device, leaving and reopening the manga-translation page
  immediately retained the cached `7D` value instead of returning to a loading subtitle. The quota `HdsListItem`
  remained `enabled=true` and `clickable=true`; the bounded log capture contained no usage/cache failure event.
- On `192.168.50.237:12345`, the production evaluation row rendered at the end of the active provider card without a
  new menu or card. The native confirmation proved cancellation caused no request before the user-authorized real run.
- The selected `gpt-5.6-luna` live path first returned `HTTP 400 unsupported_max_output_tokens`; separating the current
  Codex request fields from the public API body removed that failure. A later response returned invalid geometry even
  though the adapter declares `geometry=false`; requiring `polygon=[]` closed that contract mismatch.
- Two post-fix runs returned valid documents for both pages. After adding the clearly visible page-2 station sign that
  the original manifest had omitted, the final run matched `10/11` reviewed blocks: page 1 `4/5` with one exact SFX
  mismatch, page 2 `6/6`, reading-order errors `0`, required-name errors `0`, 1,649,657 uploaded bytes and 53,638 ms.
- The UI and redacted diagnostics both kept the remaining SFX mismatch in review. The 7D remaining display moved from
  95% before the live diagnostic series to 94% afterward; the provider returned no 5H window.

## Follow-up Outside Phase 0

- Expand the current reviewed two-page original fixture beyond its vertical text, furigana, small text, SFX, complex
  background and multi-page name-consistency baseline to include color pages and denser multi-speaker layouts.
- Decide whether the production path may call a direct API or must use a NextE-compatible gateway, and migrate OAuth
  secrets to HUKS/system credential storage before considering the experimental path production-ready.
- Build the repository/orchestrator and Reader explicit-trigger path under a separate V1 plan. Public API and a
  detection/OCR route still need their own real-provider evaluations before broad quality comparisons.

## Completion

- The foundation and dual-provider spike are complete when production and ohosTest compilation pass, fake transport
  tests are registered, and credential backup/sync boundaries pass their contracts.
- Phase 0 is complete because the reviewed fixture was evaluated through a real provider, valid page documents were
  returned repeatedly, failures entered explicit failed/review states, and image/cost confirmation remained explicit.
  The retained SFX mismatch is quality evidence for later routing, not a reason to claim or manufacture a perfect score.
