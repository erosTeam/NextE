import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

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
  // Measured grid width (vp); used only to emit cell sizing for callers that need it.
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
      })
      .contentStartOffset(this.topSpacerHeight())
      .contentEndOffset(this.bottomSpacerHeight())
      .edgeEffect(EdgeEffect.None)
      .clip(false)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.measuredWidth = this.parseAreaWidth(newValue)
        if (this.onCellSize && this.minColumnWidth > 0) {
          const content: number = this.contentWidth()
          const cols: number = this.estimatedColumns(content)
          this.onCellSize(cols, this.estimatedColumnWidth(content, cols))
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

  private parseAreaWidth(value: Area): number {
    const parsed: number = Number.parseFloat(`${value.width}`)
    return parsed > 0 ? parsed : 0
  }

  private contentWidth(): number {
    const content: number = this.measuredWidth - 2 * this.horizontalPadding
    return content > 0 ? content : 0
  }

  private columnsTemplate(): string {
    if (this.minColumnWidth > 0) {
      return `repeat(auto-fit, ${this.minColumnWidth}vp)`
    }
    const cols: number = this.columns
    const parts: string[] = []
    for (let i = 0; i < cols; i++) {
      parts.push('1fr')
    }
    return parts.join(' ')
  }

  private estimatedColumns(content: number): number {
    if (content <= 0 || this.minColumnWidth <= 0) {
      return this.columns
    }
    const n: number = Math.floor((content + this.gap) / (this.minColumnWidth + this.gap))
    return n > 0 ? n : 1
  }

  private estimatedColumnWidth(content: number, columns: number): number {
    if (columns <= 0) {
      return content
    }
    return (content - (columns - 1) * this.gap) / columns
  }

  private topSpacerHeight(): number {
    return this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding
  }

  private bottomSpacerHeight(): number {
    return this.layout.bottomAvoidHeight + this.bottomPadding
  }

  private galleryIndex(rawIndex: number): number {
    const index: number = rawIndex
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
