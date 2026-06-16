import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { ResponsiveGrid } from '../utils/ResponsiveGrid'

/**
 * Grid sibling of PullRefreshListScaffold: a 2-column Grid inside the same generic PullRefresh
 * (pull-to-refresh + pull-up + safe-area insets). The parent supplies GridItems via `content`.
 * Top inset (status bar + title bar) and bottom inset (gesture bar) are owned here, not the page.
 */
@ComponentV2
export struct PullRefreshGridScaffold {
  @BuilderParam content: () => void;
  layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Param scroller: Scroller = new Scroller();
  // Fixed fallback column count, used only when minColumnWidth <= 0 (no responsive sizing requested).
  @Param columns: number = 2;
  // When > 0, the column count is DERIVED responsively from the measured content width and this
  // minimum comfortable column width (vp) — eros_fe max-cross-axis-extent model — instead of `columns`.
  @Param minColumnWidth: number = 0;
  // Measured grid width (vp); drives the responsive column count once laid out.
  @Local measuredWidth: number = 0;
  @Param gap: number = ThemeConstants.SPACE_SM;
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD;
  @Param bottomPadding: number = ThemeConstants.SPACE_XL;
  // Extra top inset above the status-bar + title-bar reserve (e.g. a pinned title-bar bottomBuilder).
  @Param topPadding: number = 0;
  @Param controller: PullRefreshController = new PullRefreshController();
  @Event onRefresh?: () => Promise<void>;
  @Event onBottomRefresh?: () => Promise<void>;
  @Event canStartBottomRefresh?: () => boolean;
  @Event onReachEnd?: () => void;
  // Emits the responsive column count + one cell's width (vp) whenever the grid is (re)measured, so a
  // caller can size sprite thumbnails to fill the derived cell. Only fires when minColumnWidth > 0.
  // (Named onCellSize, not onLayout — onLayout collides with the CustomComponent base member.)
  @Event onCellSize?: (columns: number, cellWidth: number) => void;

  build() {
    PullRefresh({
      scroller: this.scroller,
      controller: this.controller,
      indicatorTop:
        this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT / 2 + this.topPadding,
      bottomIndicatorBottom: this.layout.bottomAvoidHeight + this.bottomPadding,
      onRefresh: async () => {
        if (this.onRefresh) {
          await this.onRefresh()
        }
      },
      onBottomRefresh: async () => {
        if (this.onBottomRefresh) {
          await this.onBottomRefresh()
        }
      },
      canStartBottomRefresh: () => {
        if (this.canStartBottomRefresh) {
          return this.canStartBottomRefresh()
        }
        return false
      },
    }) {
      Grid(this.scroller) {
        this.content()
      }
      .columnsTemplate(this.columnsTemplate())
      .columnsGap(this.gap)
      .rowsGap(this.gap)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
        top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding,
        bottom: this.layout.bottomAvoidHeight + this.bottomPadding,
      })
      .edgeEffect(EdgeEffect.None)
      .clip(false)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.measuredWidth = newValue.width as number
        if (this.onCellSize && this.minColumnWidth > 0) {
          const content: number = this.measuredWidth - 2 * this.horizontalPadding
          const cols: number = ResponsiveGrid.columns(content, this.minColumnWidth, this.gap)
          this.onCellSize(cols, ResponsiveGrid.columnWidth(content, cols, this.gap))
        }
      })
      .onReachEnd(() => {
        if (this.onReachEnd) {
          this.onReachEnd()
        }
      })
    }
  }

  // Responsive column count: derived from the measured content width (minus horizontal padding) and
  // minColumnWidth when set; otherwise the fixed `columns` fallback. Never a hardcoded literal.
  private effectiveColumns(): number {
    if (this.minColumnWidth > 0 && this.measuredWidth > 0) {
      const content: number = this.measuredWidth - 2 * this.horizontalPadding
      return ResponsiveGrid.columns(content, this.minColumnWidth, this.gap)
    }
    return this.columns
  }

  private columnsTemplate(): string {
    const cols: number = this.effectiveColumns()
    const parts: string[] = []
    for (let i = 0; i < cols; i++) {
      parts.push('1fr')
    }
    return parts.join(' ')
  }
}
