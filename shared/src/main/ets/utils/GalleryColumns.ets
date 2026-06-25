import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * Single source of truth for the gallery WaterFlow column count, shared by PullRefreshWaterFlowScaffold
 * and the settings-page live preview so the preview can never drift from what the list actually renders.
 * (The Grid path uses native `repeat(auto-fit, <minW>vp)` and derives its own count, so the preview
 * mirrors it by using the identical Grid template rather than re-deriving an integer here.)
 */
export function galleryWaterfallColumnCount(
  measuredWidth: number,
  minWidth: number,
  gap: number,
  horizontalPadding: number,
): number {
  if (measuredWidth <= 0) {
    return 2
  }
  const contentWidth: number = Math.max(minWidth, measuredWidth - horizontalPadding * 2)
  const count: number = Math.floor((contentWidth + gap) / (minWidth + gap))
  return Math.max(1, count)
}

/** Clamp a pinch/slider column min-width to the supported range. */
export function clampColumnWidth(width: number): number {
  return Math.min(
    ThemeConstants.GALLERY_COL_MIN_W_CEIL,
    Math.max(ThemeConstants.GALLERY_COL_MIN_W_FLOOR, width),
  )
}
