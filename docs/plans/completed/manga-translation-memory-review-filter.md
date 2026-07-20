# Manga Translation Memory Review Filter

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Prevent warning/error-marked generated translations from becoming trusted exact-match memory for later model requests.

## Boundary

- Exclude a whole generated page from memory when it has a page-level warning/error signal.
- Exclude only the targeted block for block-level warning/error signals; informational signals remain non-blocking.
- Keep translated blocks eligible when another block alone needs review, and keep caller-supplied memory precedence.
- Do not change glossary, manual edits, provider calls, prompt wording/version, cache persistence, backup, or sync.

## Result

- The shared review policy now exposes a bounded page-level actionable-signal check without exposing provider text.
- Generated exact memory accepts only provisional/ready/review-required documents, rejects an entire page for a
  page-level warning/error, and rejects only the targeted block for a block-level warning/error.
- Informational signals remain eligible. A translated block can still contribute when a different block on the same
  review-required page is missing, so filtering does not turn page review into an indiscriminate data loss rule.
- Caller-supplied memory precedence, prompt wording/version, effective-context fingerprinting, provider execution,
  persistence, and user-data boundaries are unchanged. Filtered prompt-visible memory naturally changes the existing
  context fingerprint where prior generated evidence was not trustworthy.

## Validation

- `entry@ohosTest` HAP build: successful in 13.050 s.
- Signed application build: successful in 13.656 s.
- Full Hypium suite on `192.168.50.237:12345`: 175 passed, 0 failures/errors/ignored, 909 ms,
  `OHOS_REPORT_CODE: 0`. The new test covers informational, block-warning, page-warning, and unrelated missing-block
  cases.
- V1 decorator inventory: 0 files across 462 ArkTS files.
- Four-locale parity/duplicate scan and `git diff --check`: passed.
