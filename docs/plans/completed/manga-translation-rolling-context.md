# Manga Translation Rolling Context

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **source**: continue V1 gallery-consistency work after generated-cache recovery

## Goal

Carry essential story and naming context beyond the two immediately preceding pages without sending an unbounded
gallery transcript or adding a second provider call.

## Boundary

- Preserve an explicit caller-provided rolling summary.
- Otherwise derive the next request's rolling summary from the newest non-empty prior-page summary before the current
  page.
- Instruct the whole-page analyzer to return a concise cumulative summary that updates prior context with the current
  page, so the next page can continue the chain.
- Bump the analysis prompt version so documents generated under the old page-local summary contract cannot hit the new
  request identity.
- Keep the existing two-page source/translation window. Do not persist raw prompts, full-gallery transcripts, provider
  responses, user-owned glossary terms, or manual edits.
- Do not add automatic translation, batch calls, OCR, backup, or sync.

## Validation

- Fake-analyzer tests prove page 2 receives page 1's summary while exact cache and downstream invalidation still work.
- Provider-protocol tests prove the cumulative-summary instruction and supplied rolling summary are present.
- V2 inventory, static contracts, signed application and `entry@ohosTest` builds, and full device tests pass.

## Exit

Move this plan to `completed/` only after request assembly, prompt versioning, cache identity, and device tests pass.

## Completion Evidence

- The orchestrator derives a missing rolling summary from the newest eligible prior page and preserves any explicit
  caller-provided summary.
- The Responses prompt now requires a short cumulative `pageSummary`; its version is
  `comic-page-responses-v2`, isolating v1 generated documents through the existing cache identity.
- `entry@ohosTest` built successfully in 14 s 110 ms. The signed application built successfully in 14 s 632 ms.
- Full Hypium on the user-selected device `237`: 145 tests run, 145 passed, 0 failures/errors/ignored,
  `OHOS_REPORT_CODE: 0`, 820 ms. The new derived-summary and explicit-summary tests passed.
- One explicit non-cache Reader request using prompt v2 returned `已完成` with six normalized blocks. Private imagery,
  source text, translations, and summary content remain outside committed evidence.

Completed: bounded rolling context now crosses the two-page detail window without another model call or a new durable
user-data surface.
