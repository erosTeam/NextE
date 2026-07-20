# Manga Translation Context Budget

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Keep dense prior pages, long summaries, and large glossaries from turning the next explicit page translation into a
prompt-size failure.

## Boundary

- Keep identity fields exact; if those alone are invalid or oversized, fail rather than alter page ownership.
- Bound optional rolling summary, style guide, glossary, and at most two previous-page records with deterministic,
  valid JSON string encoding.
- Prioritize locked glossary terms over provisional terms and retain both source and translated prior-page context.
- Mark omitted glossary entries without logging or persisting the omitted content.
- Do not add model calls, automatic page translation, OCR, user-owned persistence, backup, or sync.

## Result

- Exact project, page, image, dimension, and language identity fields remain unchanged.
- Optional summary, style, glossary, and previous-page fields have independent deterministic limits under the existing
  48,000-character total prompt invariant.
- Locked glossary terms are emitted before provisional terms, and only the newest two supplied previous-page records
  are retained.
- Truncated values remain valid JSON string or array encodings and omitted source content is never logged.

## Validation

- Protocol tests construct quote/backslash/newline-heavy context far beyond the limit and prove the final prompt stays
  within 48,000 characters, retains the locked anchor and page indexes 1 and 2, and omits page index 0.
- `entry@ohosTest` build passed in 14 s 94 ms.
- Full Hypium run on device `237`: 146 tests, 146 passed, 0 failed/errored/ignored, `OHOS_REPORT_CODE: 0`, 824 ms;
  the adversarial prompt-budget test completed in 6 ms.
- Signed production build passed in 16 s 260 ms.
- V2 decorator inventory reported `0 file(s)`.
