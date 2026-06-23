import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { LoadingFooter } from './LoadingFooter'

/**
 * WaterFlow sibling of PullRefreshGridScaffold for gallery cards: same refresh, paging, safe-area,
 * and responsive column model, but native masonry placement for variable-height cover-first cards.
 * The top reserve is real scroll content so HDS title-bar auto-hide sees the first scroll gesture;
 * the bottom reserve uses WaterFlow's native footer instead of a non-content end offset.
 */
@ComponentV2
export struct PullRefreshWaterFlowScaffold {
  @BuilderParam content: () => void;
  layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Param scroller: Scroller = new Scroller();
  @Param minColumnWidth: number = 0;
  @Local measuredWidth: number = 0;
  @Param gap: number = ThemeConstants.SPACE_SM;
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD;
  @Param bottomPadding: number = ThemeConstants.SPACE_XL;
  @Param topPadding: number = 0;
  @Param itemCount: number = 0;
  @Param showFooter: boolean = false;
  @Param footerIsLoading: boolean = false;
  @Param footerHasMore: boolean = true;
  @Param footerIsError: boolean = false;
  @Param controller: PullRefreshController = new PullRefreshController();
  @Event onRefresh?: () => Promise<void>;
  @Event onBottomRefresh?: () => Promise<void>;
  @Event canStartBottomRefresh?: () => boolean;
  @Event onReachEnd?: () => void;
  @Event onFooterRetry?: () => void;
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;

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
      WaterFlow({ scroller: this.scroller, sections: this.waterFlowSections() }) {
        this.TopSpacer()
        this.content()
        this.BottomSpacer()
      }
      .columnsGap(this.gap)
      .rowsGap(this.gap)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
      })
      // PullRefresh owns the edge drag offset; native spring would add a second movement layer.
      .edgeEffect(EdgeEffect.None)
      .clip(false)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.measuredWidth = this.parseAreaWidth(newValue)
      })
      .onReachEnd(() => {
        if (this.onReachEnd) {
          this.onReachEnd()
        }
      })
      .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, scrollState)
        }
      })
      .onScrollIndex((_start: number, _end: number) => {
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, ScrollState.Scroll)
        }
      })
    }
  }

  private waterFlowSections(): WaterFlowSections {
    const sections: WaterFlowSections = new WaterFlowSections()
    const opts: SectionOptions[] = []
    opts.push({
      itemsCount: 1,
      crossCount: 1,
      rowsGap: 0,
      columnsGap: 0,
    })
    if (this.itemCount > 0) {
      opts.push({
        itemsCount: this.itemCount,
        crossCount: this.contentColumnCount(),
        rowsGap: this.gap,
        columnsGap: this.gap,
      })
    }
    opts.push({
      itemsCount: 1,
      crossCount: 1,
      rowsGap: 0,
      columnsGap: 0,
    })
    sections.splice(0, 0, opts)
    return sections
  }

  private contentColumnCount(): number {
    const minWidth: number =
      this.minColumnWidth > 0 ? this.minColumnWidth : ThemeConstants.GALLERY_WATERFALL_MIN_W
    if (this.measuredWidth <= 0) {
      return 2
    }
    const contentWidth: number = Math.max(minWidth, this.measuredWidth - this.horizontalPadding * 2)
    const count: number = Math.floor((contentWidth + this.gap) / (minWidth + this.gap))
    return Math.max(1, count)
  }

  @Builder
  private TopSpacer() {
    FlowItem() {
      Column() {
        Blank().height(this.topSpacerHeight())
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private BottomSpacer() {
    FlowItem() {
      Column() {
        if (this.showFooter) {
          LoadingFooter({
            isLoading: this.footerIsLoading,
            hasMore: this.footerHasMore,
            isError: this.footerIsError,
            onRetry: () => {
              if (this.onFooterRetry) {
                this.onFooterRetry()
              }
            },
          })
        }
        Blank().height(this.bottomSpacerHeight())
      }
      .width('100%')
    }
    .width('100%')
  }

  private parseAreaWidth(value: Area): number {
    const parsed: number = Number.parseFloat(`${value.width}`)
    return parsed > 0 ? parsed : 0
  }

  private topSpacerHeight(): number {
    return this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding
  }

  private bottomSpacerHeight(): number {
    return this.layout.bottomAvoidHeight + this.bottomPadding
  }
}
