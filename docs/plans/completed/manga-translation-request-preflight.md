# Manga Translation Request Preflight

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Reject malformed comic request identity before cache access, image reads, or provider quota can be consumed.

## Boundary

- Require finite safe integers for page, dimensions, tile count, and every revision field.
- Keep image edges and all identifier/path/language fields within existing parser limits.
- Reuse parser request validation from request identity creation and the direct Responses adapter preflight.
- Strengthen the Reader bridge before it hashes or opens an image.
- Do not alter valid request identity, add provider calls, or change persistence/backup/sync ownership.

## Result

- `ComicPageAnalysisParser.validateRequest` is now a request preflight shared by parser, request identity creation, and
  the direct Responses adapter.
- Page, image, tile, request-revision, and context-revision values reject `NaN`, infinities, fractions, and values
  outside the safe integer/image limits.
- Request identity additionally bounds provider/model/prompt/profile/language strings and verifies both SHA-256
  fingerprints.
- The Reader bridge applies equivalent page, path, language, and image-edge checks before file stat/hash work.

## Validation

- Orchestrator tests prove four malformed numeric identities are rejected with zero analyzer executions.
- Adapter tests prove an infinite page index and an oversized model identifier are rejected with zero transport
  executions and before the intentionally nonexistent image path is read.
- `entry@ohosTest` build passed in 14 s 847 ms.
- Full Hypium run on device `237`: 151 tests, 151 passed, 0 failed/errored/ignored, `OHOS_REPORT_CODE: 0`, 876 ms.
- Signed production build passed in 14 s 797 ms.
- V2 decorator inventory reported `0 file(s)` across 459 `.ets` files.
