# Current Dispatch State

Status: active scheduling control file.

Purpose:

- This is the short source of truth for lane selection after context compaction.
- Read this before using `product-bug-intake.md` or long active plans to choose work.
- `product-bug-intake.md` is the evidence/intake ledger; it is not the scheduling entry point.
- Each turn should select at most one item from Active Queue unless the user explicitly redirects.

## Current Baseline

These items are current behavior or visual baselines. Do not re-implement, redesign, or re-verify them
as the main output of a new turn unless fresh P0 evidence shows a regression.

- SearchFilter shape, control proportions, and current rounded treatment are baseline.
- Search filter entry belongs in the title/menu/action area, not inside the search input row.
- Search title/header may hide while scrolling, but the bottomBuilder search field remains visible.
- Gallery Grid is separated from Waterfall: Grid uses grid scaffold semantics and fixed-size cards;
  Waterfall is a separate future mode, not an alias for Grid.
- AllThumbnails later-thumbnail Reader start is implemented and should not be reopened without a new
  reproduction.
- Reader single-page core baseline is accepted. Double-page is not final architecture, but the current
  grouped-row mitigation is the shipped interim behavior until a deliberate Reader redesign lane is
  opened.

## Closed / Superseded

Historical feedback in this section must not trigger new implementation.

- SearchFilter old "rounded corner is strange" and "filter button in the wrong place" feedback is
  superseded by the current baseline above.
- Repeated SearchFilter typography/spacing micro-adjustments are closed unless the user provides a new
  current screenshot and asks to reopen that surface.
- Repeated Gallery Grid vs WaterFlow implementation work is closed. Only user acceptance or a new
  regression can reopen it.
- Repeated Reader double-page wording/contract-only cleanup is closed as a main deliverable. Docs may
  record status, but wording changes are not user-visible progress.
- Download page task workbench cleanup is implemented and pending controller acceptance: the pinned
  Gallery / Archiver selector is followed directly by task cards or empty state, without queue summary
  rows before the workbench content.
- Gallery Grid card information density repair is implemented and pending controller acceptance: Grid
  still uses real Grid scaffold and fixed-height cards, but the card info block now shows title,
  compact post-time/rating metadata, and a one-line tag sample without the previous large empty tag area.
- Gallery comment peek full-comments entry is implemented and pending controller acceptance: one/two-comment
  detail peeks expose `查看全部`, and tapping the peek header opens the full comments page.
- Search route/session state is implemented and pending controller acceptance: action-seeded tag/uploader
  searches are converted by `Index` into route/session params so old Search pages do not consume them.
- Gallery local favorite removal safety is implemented and pending controller acceptance: the existing local
  remove action now requires a native destructive confirmation before changing local state.

## Parked / Guidance Only

Items here are real concerns, but they are not active implementation lanes by default.

- Reader final double-page architecture is parked unless current behavior shows P0 reading failure.
  The current implementation is an interim grouped-row mitigation, not the final target.
- Reader double-page center gap/seam policy is parked as future redesign guidance: paired pages should
  default to a contiguous zero-gutter spread unless a deliberate display option says otherwise.
- In Reader lanes, `eros_fe` is only a feature/EH-mechanism and historical-pitfall reference. It is not
  the design or architecture benchmark.
- Mature reader architecture references, such as Tachiyomi/Mihon-style pager and zoom surface models,
  should guide future Reader redesign together with HarmonyOS-native V2Next image-preview patterns.
- Boundary handoff from zoomed pan to page turn is a future enhancement unless current zoomed pan
  blocks normal reading.

## Active Queue

Pick from here for the next user-visible bug or feature lane. Prefer items with clear user benefit and
a bounded validation path.

1. Write-operation entry and safety confirmation: remaining remote favorite/rating/comment/tag/archive
   actions should be discoverable, gated, and non-destructive in tests.
2. AllThumbnails large-gallery jump and preview-page scrolling: verify and fix high-page-count preview
   navigation around 500+ pages if current behavior fails.
3. Search submit/clear behavior: IME search must submit; clearing the query must return to history/blank
   state rather than stale results.
4. Waterfall mode proper launch: expose a distinct Waterfall mode after Grid card information density is
   repaired; do not make Grid behave like Waterfall.
5. Reader UI/chrome/loading visible issues: only reopen Reader here if the outcome is a concrete visual
   or gesture fix, not more architecture discussion.
6. Reader gesture matrix: only continue if current device evidence shows a failed basic action such as
   normal fit-scale swipe, pinch, zoomed pan, double tap, center tap, or ready-state overlay cleanup.

## Lane Selection Rule

Before editing product code, state:

1. User-visible benefit for this turn.
2. Why the item is Active Queue, not Current Baseline, Closed, or Parked.
3. Files likely to change.
4. Which baseline/closed items will not be reopened.
5. Verification that only covers this turn's risk.

If an item is fixed and verified, move it out of Active Queue in this file or mark it pending acceptance.
Do not leave completed work in Active Queue where it can be restarted after compaction.
