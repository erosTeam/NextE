# Slide-to-rate gallery rating (replace tap-a-number picker)

Status: implemented, pending build + device acceptance.

## What

The gallery rating SUBMIT sheet was a clumsy list of 10 tap-a-number rows (0.5…5). Replace it with a single
slide/tap star bar (eros_fe rate-dialog parity): drag or tap across the stars to pick a 0.5-step rating,
with the value shown live below. Keeps the existing ROUNDED `sys.symbol.star_fill` look + dynamic per-rating
color (orange / personal red·green·blue) — so no pointy system-Rating stars and no new image assets.

## Why this approach (over the system Rating component)

The HarmonyOS `Rating` component supports slide-to-rate but its default star is sharp/pointy; matching the
current rounded look needs custom star PNGs, and it has no built-in color tint (a per-color asset per rating
color). Extending the existing `RatingStars` (which already renders rounded SymbolGlyph stars with dynamic
`.fontColor`) with a touch→value gesture keeps the look + dynamic color with zero assets, and the same
component serves both display (read-only) and submit (interactive).

## How

- `RatingStars`: add `@Param interactive` + `@Event onRate`. When interactive, an observational `.onTouch`
  maps the touch X (relative to the `starSize*5` row) to a 0.5-step value (left half of a star → .5, right
  half → whole), clamped [0.5, 5], reported via `onRate`. Display calls (cards, detail info bar) leave
  `interactive=false` → unchanged, non-consuming (the card's own tap still navigates).
- `GalleryDetailPage` rate sheet: the preview row + 10-row `ForEach`/`RatingOption` picker → one big
  (`starSize 40`) interactive `RatingStars` bound to `ratingSelected` + a live "X.X / 5" label, disabled
  while submitting. Removed the now-dead `RatingOption` builder, `ratingOptions`, and the two
  `ratingOption*` helpers. Submit flow (`submitRating` → `vm.rateGallery`) unchanged.

## Files

Edited: `shared/.../components/RatingStars.ets`, `feature/gallery/.../pages/GalleryDetailPage.ets`,
`scripts/test_detail_header_visual_contract.mjs`.

## Note: detail-header contract fix (smart-grip follow-up)

`test_detail_header_visual_contract.mjs` (a blocking harness gate) still asserted the OLD Read-FAB position
`.position({ right, bottom })`. The earlier smart-grip lane moved the FAB to a full-width rail
(`.position({ left: 0, bottom })` + `.translate({ x: readFabVisualX() })`) but that gate wasn't in the set
re-run then, so it went stale/red on main. Updated the assertion to the rail position + a guard for the
smart-grip slide. (The `gallery_grid_card_visual` contract errors only from a worktree because it reads
`../eros_fe`; it passes from the main tree — unrelated to this change.)
