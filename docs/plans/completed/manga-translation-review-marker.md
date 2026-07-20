# Manga Translation Review Marker

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Make a detected cross-page translation conflict actionable in the existing Reader result sheet without adding a new
entrypoint, setting, hierarchy, model call, or persisted user data.

## Boundary

- Mark only the current text block referenced by `translation_consistency_conflict`.
- Use a localized fixed label and never display historical source or translation text.
- Keep unrelated provider quality signals represented by the existing page-level review state.
- Do not add automatic correction, glossary editing, OCR, backup, or sync.

## Result

- The consistency service exposes a bounded positive/negative conflict lookup.
- The existing Reader source/translation card conditionally renders a concise localized marker for the referenced
  block; no entrypoint, setting, or sheet hierarchy changed.
- Base, English, Simplified Chinese, and Japanese resources carry the same key set.

## Validation

- `entry@ohosTest` HAP build: successful in 14.591 s.
- Full Hypium suite on `192.168.50.237:12345`: 168 passed, 0 failures/errors/ignored, 906 ms,
  `OHOS_REPORT_CODE: 0`; the consistency test covers both matching and unrelated block IDs.
- Signed application build: successful in 15.715 s.
- Signed HAP installed on `192.168.50.237:12345`; `EntryAbility` started successfully and the application process
  was present as PID 34053.
- V1 decorator inventory: 0 files across 460 ArkTS files.
- Version/module consistency, four-locale parity/duplicate scan, and `git diff --check`: passed.
