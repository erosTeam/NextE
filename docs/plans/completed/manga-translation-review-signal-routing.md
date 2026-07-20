# Manga Translation Review Signal Routing

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Make Reader review state actionable by marking the specific blocks referenced by warning/error quality signals, while
keeping provider-authored signal messages out of the UI.

## Boundary

- Treat only warning/error signals as review requirements; informational signals remain non-blocking metadata.
- Preserve the existing specialized cross-page consistency label and use one fixed localized label for other blocks.
- Do not display signal codes/messages, add provider calls, alter cache identity, or persist derived Reader markers.
- Do not change manual translation, glossary, backup, sync, OCR, or settings semantics.

## Result

- Added one provider-neutral review policy for page and block decisions. `REVIEW_REQUIRED` still marks a page; only
  warning/error quality signals add review state, and informational signals alone remain non-blocking.
- A warning/error with a `blockId` marks that exact block. A `REVIEW_REQUIRED` document also marks blocks whose
  translation is empty; page-level signals do not invent block ownership.
- Reader retains the specialized cross-page consistency marker as the first choice and otherwise renders one fixed
  localized generic marker. Provider signal codes and messages are never rendered or persisted.
- The existing cache identity, provider execution, result sheet hierarchy, settings, and user-data boundaries are
  unchanged.

## Validation

- `entry@ohosTest` HAP build: successful in 15.059 s.
- Signed application build: successful in 15.547 s.
- Full Hypium suite on `192.168.50.237:12345`: 173 passed, 0 failures/errors/ignored, 870 ms,
  `OHOS_REPORT_CODE: 0`.
- Device `237` cached-result check: the existing six-block page returned immediately as `缓存 · 待复核`, retained all
  six source/target rows, rendered two generic block-review markers, rendered no consistency marker, and never entered
  a translation/refresh running state. No new model request was made.
- V1 decorator inventory: 0 files across 462 ArkTS files.
- Four-locale parity/duplicate scan, JSON parsing, and `git diff --check`: passed.
