import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { ResponsiveGrid } from '../utils/ResponsiveGrid'

/**
 * WaterFlow sibling of PullRefreshGridScaffold for gallery cards: same refresh, paging, safe-area,
 * and responsive column model, but native masonry placement for variable-height cover-first cards.
 */
@ComponentV2
export struct PullRefreshWaterFlowScaffold {
  @BuilderParam content: () => void;
  layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Param scroller: Scroller = new Scroller();
  @Param columns: number = 2;
  @Param minColumnWidth: number = 0;
  @Local measuredWidth: number = 0;
  @Param gap: number = ThemeConstants.SPACE_SM;
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD;
  @Param bottomPadding: number = ThemeConstants.SPACE_XL;
  @Param topPadding: number = 0;
  @Param controller: PullRefreshController = new PullRefreshController();
  @Event onRefresh?: () => Promise<void>;
  @Event onBottomRefresh?: () => Promise<void>;
  @Event canStartBottomRefresh?: () => boolean;
  @Event onReachEnd?: () => void;
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
      WaterFlow({ scroller: this.scroller }) {
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
