import { ThemeConstants } from 'shared'

/**
 * Bottom tab item (V2Next MainTabIcon): filled system symbol + label, brand color when
 * active. A 3vp leading spacer compensates for SymbolGlyph's on-device centering offset
 * inside the 28vp icon area (real-device layout dumps put centered placement +9px right).
 */
const TAB_SYMBOL_LAYOUT_OFFSET_VP: number = 3
@ComponentV2
export struct MainTabIcon {
  @Param title: ResourceStr = '';
  @Param idx: number = 0;
  @Param currentIndex: number = 0;

  // Bottom-tab glyphs: 画廊 / 收藏 / 排行 / 下载 / 设置 (eros_fe IA order). All FILLED variants for a
  // consistent visual weight under SINGLE rendering. 排行 wants list_checkmask but that glyph has no
  // _fill variant (and trophy_fill / square_stack_fill are compile-invalid despite being in the SDK
  // registry), so list_bullet_square_fill is the closest filled "ranked list" equivalent.
  private symbol(): Resource {
    if (this.idx === 0) {
      return $r('sys.symbol.square_fill_grid_2x2')
    }
    if (this.idx === 1) {
      return $r('sys.symbol.heart_fill')
    }
    if (this.idx === 2) {
      return $r('sys.symbol.list_bullet_square_fill')
    }
    if (this.idx === 3) {
      return $r('sys.symbol.arrow_down_to_line_circle_fill')
    }
    return $r('sys.symbol.gearshape_fill')
  }

  build() {
    Column() {
      Row() {
        Blank().width(TAB_SYMBOL_LAYOUT_OFFSET_VP)
        SymbolGlyph(this.symbol())
          .fontSize(ThemeConstants.INDICATOR_SIZE - 6)
          // Monochrome (single-color) rendering: the layered MULTIPLE_OPACITY made icon visual weight
          // inconsistent across the 5 tabs; SINGLE renders every glyph in one flat brand/secondary color.
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontColor([
            this.currentIndex === this.idx
              ? ThemeConstants.BRAND_PRIMARY
              : $r('sys.color.font_secondary'),
          ])
      }
      .width(ThemeConstants.INDICATOR_SIZE)
      .height(ThemeConstants.INDICATOR_SIZE - 2)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      Text(this.title)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontColor(
          this.currentIndex === this.idx
            ? ThemeConstants.BRAND_PRIMARY
            : $r('sys.color.font_secondary'),
        )
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ top: ThemeConstants.SPACE_SM - 2, bottom: ThemeConstants.SPACE_XS })
  }
}
