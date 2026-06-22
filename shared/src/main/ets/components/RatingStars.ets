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
  // When true the same star row becomes slide/tap-to-rate (eros_fe rate dialog parity): a touch maps to a
  // 0.5-step value reported via onRate. Default false keeps every existing display call read-only + unchanged.
  @Param interactive: boolean = false;
  @Event onRate?: (value: number) => void;
  // Five fixed cells; each star is width-locked to `starSize` so the filled overlay clips deterministically.
  private cells: number[] = [0, 1, 2, 3, 4];

  // Overlay width over the 5-star row (each cell == size) for the clamped rating fraction.
  private fillWidth(): number {
    const r: number = this.rating < 0 ? 0 : this.rating > 5 ? 5 : this.rating
    return (r / 5) * (this.starSize * 5)
  }

  // Map a touch X (relative to the star row) to a 0.5-step rating: the left half of a star fills to .5, the
  // right half to a whole star. Clamped to [0.5, 5] (EH's minimum vote is 0.5).
  private rateFromX(x: number): void {
    const width: number = this.starSize * 5
    if (width <= 0 || this.onRate === undefined) {
      return
    }
    let fraction: number = x / width
    fraction = fraction < 0 ? 0 : fraction > 1 ? 1 : fraction
    let value: number = Math.ceil(fraction * 10) / 2
    value = value < 0.5 ? 0.5 : value > 5 ? 5 : value
    this.onRate(value)
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
    // Observational only (non-consuming): display calls leave interactive=false so the parent card's own
    // tap still navigates; the rate sheet sets interactive=true to capture the slide/tap.
    .onTouch((event: TouchEvent) => {
      if (!this.interactive || event.touches.length === 0) {
        return
      }
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.rateFromX(event.touches[0].x)
      }
    })
  }
}
