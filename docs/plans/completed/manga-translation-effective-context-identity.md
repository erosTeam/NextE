# Manga Translation Effective Context Identity

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Make comic cache identity depend on the bounded context that the selected analyzer actually sends, instead of raw
context tails and metadata that the prompt omits.

## Grounding

- Reference implementation: the current Responses prompt builder is the source of truth for visible context.
- Primary information: rolling summary, style guide, effective glossary lines, and the newest two previous pages.
- Primary action: let each analyzer supply its own deterministic SHA-256 context identity.
- Current closure: remove raw-context copies from repository hashing and bound input collection cardinality.
- Non-goals: no prompt wording, provider request, persistence ownership, backup/sync, or Reader UI changes.

## Boundary

- Reuse exactly the same bounded context lines for prompt assembly and fingerprinting.
- Keep explicit glossary/style/context revisions as independent invalidation controls.
- Reject unbounded glossary, alias, and previous-page collections before request copying, cache access, or provider work.
- Preserve locked-term priority, latest-two-page ordering, and all current valid prompt output.

## Completion

- Omitted long-text tails and non-prompt glossary metadata do not fragment the cache.
- Any context text that remains visible to the model still invalidates the cache.
- Test build, full device suite on `237`, signed build, V2 inventory, and relevant static contracts pass.

## Result

- `ComicPageAnalyzer` now owns a deterministic context fingerprint, so future analyzer protocols can define identity
  from their own effective input instead of repository-wide raw serialization.
- Responses prompt assembly and fingerprinting reuse the same bounded context lines. Omitted summary tails and
  non-prompt glossary metadata no longer change the key; visible context still does.
- Request preflight limits glossary terms to 256, aliases per term to 64, and candidate previous pages to 64 before
  the orchestrator copies any collection.
- The device-only empty-context Crypto rejection found during validation is covered by encoding the bounded line
  collection as JSON, where an empty context remains the stable non-empty payload `[]`.

## Validation

- Provider and orchestrator tests cover equal effective prompts/fingerprints, omitted-tail cache reuse, visible-text
  invalidation, oversized collection rejection, and empty-context hashing.
- `entry@ohosTest` build passed in 9 s 384 ms.
- Full Hypium run on device `237`: 154 tests, 154 passed, 0 failed/errored/ignored, `OHOS_REPORT_CODE: 0`, 880 ms.
- Signed production build passed in 15 s 416 ms.
- `git diff --check`, V2 decorator inventory (`0 file(s)` across 459 `.ets`), persistence, secret safety, settings
  backup, sync-design, and Huawei Cloud sync contracts passed.
