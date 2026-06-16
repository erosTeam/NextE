/**
 * Read-only star rating, tinted (eros_fe StaticRatingBar / GalleryRating): a colour-filled star row
 * clipped over a grey empty-star row, so a fractional rating (e.g. 4.55) shows a partial last star.
 * The fill colour is the gallery's rating colour (community orange, or the personal-rating variant) —
 * passed in by the caller via EhConstants.ratingStarColor(colorRating). No half-star glyph exists in
 * sys.symbol, so the two-layer clip is how the fractional fill is achieved (eros_fe does the same).
 *
 * star_fill (filled) is correct here — this is the rating widget, NOT the InfoBar's quiet metadata grid
 * (which stays outline); keeping it in its own component is also why the header-visual gate (no filled
 * star in the InfoBar file) holds.
 */
@ComponentV2
export struct RatingStars {
  @Param rating: number = 0;
  @Param color: ResourceColor = $r('app.color.rating_star_orange');
  @Param starSize: number = 15;
  // Five fixed cells; each star is width-locked to `starSize` so the filled overlay clips deterministically.
  private cells: number[] = [0, 1, 2, 3, 4];

  // Overlay width over the 5-star row (each cell == size) for the clamped rating fraction.
  private fillWidth(): number {
    const r: number = this.rating < 0 ? 0 : this.rating > 5 ? 5 : this.rating
    return (r / 5) * (this.starSize * 5)
  }

  @Builder
  starRow(tint: ResourceColor) {
    Row() {
      ForEach(
        this.cells,
        (_i: number) => {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(this.starSize)
            .width(this.starSize)
            .fontColor([tint])
        },
        (i: number) => i.toString(),
      )
    }
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      // Empty/base layer (muted grey), full width.
      this.starRow($r('sys.color.font_tertiary'))
      // Filled layer, clipped to the rating fraction.
      Row() {
        this.starRow(this.color)
      }
      .width(this.fillWidth())
      .clip(true)
    }
    .height(this.starSize)
  }
}
