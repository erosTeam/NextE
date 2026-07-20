# Manga Translation Reader Safe Refresh

- **status**: completed
- **created**: 2026-07-21
- **completed**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Let a Reader user explicitly regenerate the current page while keeping the last successful translation visible until
the replacement succeeds. A failed regeneration must leave that prior document inspectable and retryable.

## Boundary

- Reuse the existing current-page translation sheet and explicit single-page provider action.
- Do not add automatic translation, background prefetch, settings hierarchy, batch calls, or cost confirmation policy.
- Do not change generated-cache identity, provider protocol, manual translations, glossary ownership, backup, or sync.
- Keep route/page/image publication fences unchanged; a retained document must never cross those boundaries.

## Result

- Successful and review-required Reader results expose one explicit `Retranslate` action.
- A forced refresh retains the current document and cache state, disables duplicate refreshes, and shows a compact
  progress notice above the still-inspectable blocks.
- A failed forced refresh now has a retained-result presentation with its fixed error code and retry action; the
  existing orchestrator test continues to prove that the last successful generated document is not replaced.
- A new result still publishes only through the existing route, gallery, page, image-file, and UI-epoch fences.

## Validation

- `entry@ohosTest` HAP build: successful in 12.498 s.
- Signed application build: successful in 12.264 s.
- Full Hypium suite on `192.168.50.237:12345`: 172 passed, 0 failures/errors/ignored, 893 ms,
  `OHOS_REPORT_CODE: 0`.
- Device `237` Reader check: an explicit real current-page request returned six visible blocks and enabled
  `重新翻译`; the explicit refresh disabled that action, displayed `正在重新翻译，完成前继续显示上次结果`, and
  kept all six prior blocks visible. The second real request completed and restored the action with a review result.
- V1 decorator inventory: 0 files across 461 ArkTS files.
- Four-locale parity/duplicate scan, resource JSON parsing, and `git diff --check`: passed.
