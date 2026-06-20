import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

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
  @Param controller: PullRefreshController = new PullRefreshController();
  @Event onRefresh?: () => Promise<void>;
  @Event onBottomRefresh?: () => Promise<void>;
  @Event canStartBottomRefresh?: () => boolean;
  @Event onReachEnd?: () => void;

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
      WaterFlow({ scroller: this.scroller, footer: this.BottomSpacer() }) {
        this.TopSpacer()
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
    }
  }

  private columnsTemplate(): string {
    const minWidth: number =
      this.minColumnWidth > 0 ? this.minColumnWidth : ThemeConstants.GALLERY_WATERFALL_MIN_W
    return `repeat(auto-fit, ${minWidth}vp)`
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
    Column() {
      Blank().height(this.bottomSpacerHeight())
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
