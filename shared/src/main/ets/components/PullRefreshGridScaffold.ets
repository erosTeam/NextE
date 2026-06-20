import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { ResponsiveGrid } from '../utils/ResponsiveGrid'

/**
 * Grid sibling of PullRefreshListScaffold: a responsive Grid inside the same generic PullRefresh.
 * Top/bottom immersive chrome space is modeled as real full-row GridItems instead of Grid padding:
 * HarmonyOS Grid does not render children that are fully inside the padding region, which makes cards
 * vanish while they are still visually expected under translucent chrome.
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
  @Param itemCount: number = 0;
  @Param nearEndThreshold: number = 0;
  @Param controller: PullRefreshController = new PullRefreshController();
  @Event onRefresh?: () => Promise<void>;
  @Event onBottomRefresh?: () => Promise<void>;
  @Event canStartBottomRefresh?: () => boolean;
  @Event onReachEnd?: () => void;
  @Event onNearEnd?: () => void;
  @Event onScrollIndex?: (start: number, end: number) => void;
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
        GridItem() {
          Column() {
            Blank()
              .height(this.topSpacerHeight())
          }
          .width('100%')
        }
        .columnStart(0)
        .columnEnd(this.effectiveColumns() - 1)
        .selectable(false)

        this.content()

        GridItem() {
          Column() {
            Blank()
              .height(this.bottomSpacerHeight())
          }
          .width('100%')
        }
        .columnStart(0)
        .columnEnd(this.effectiveColumns() - 1)
        .selectable(false)
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
      .onScrollIndex((start: number, end: number) => {
        const adjustedStart: number = this.galleryIndex(start)
        const adjustedEnd: number = this.galleryIndex(end)
        if (this.onScrollIndex) {
          this.onScrollIndex(adjustedStart, adjustedEnd)
        }
        this.maybeLoadNearEnd(adjustedEnd)
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

  private topSpacerHeight(): number {
    return this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding
  }

  private bottomSpacerHeight(): number {
    return this.layout.bottomAvoidHeight + this.bottomPadding
  }

  private galleryIndex(rawIndex: number): number {
    const index: number = rawIndex - 1
    if (index < 0) {
      return 0
    }
    if (this.itemCount > 0 && index >= this.itemCount) {
      return this.itemCount - 1
    }
    return index
  }

  private maybeLoadNearEnd(end: number): void {
    if (this.itemCount <= 0 || this.nearEndThreshold <= 0) {
      return
    }
    if (end < this.itemCount - 1 - this.nearEndThreshold) {
      return
    }
    if (this.canStartBottomRefresh && !this.canStartBottomRefresh()) {
      return
    }
    if (this.onNearEnd) {
      this.onNearEnd()
      return
    }
    if (this.onReachEnd) {
      this.onReachEnd()
    }
  }
}
