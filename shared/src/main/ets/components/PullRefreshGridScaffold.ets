import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

/**
 * Grid sibling of PullRefreshListScaffold: a responsive Grid inside the same generic PullRefresh.
 * Top/bottom immersive chrome space is modeled as real full-row GridItems instead of Grid padding or
 * non-content scroll offsets. HDS title-bar auto-hide binds to the same Scroller, so the reserve must
 * be normal scroll content that contributes to the first scroll gesture.
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
      Grid(this.scroller, this.gridLayoutOptions()) {
        this.TopSpacer()
        this.content()
        this.BottomSpacer()
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
      .onScrollIndex((start: number, end: number) => {
        const adjustedStart: number = this.galleryIndex(start)
        const adjustedEnd: number = this.galleryIndex(end)
        if (this.onScrollIndex) {
          this.onScrollIndex(adjustedStart, adjustedEnd)
        }
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, ScrollState.Scroll)
        }
        this.maybeLoadNearEnd(adjustedEnd)
      })
    }
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

  private gridLayoutOptions(): GridLayoutOptions {
    return {
      regularSize: [1, 1],
      // The spacer items live at index 0 and itemCount + 1. Leaving onGetIrregularSizeByIndex unset
      // makes each irregular item span one full row in a vertical Grid, preserving native auto-fit
      // column sizing without calculating the current column count.
      irregularIndexes: [0, this.itemCount + 1],
    }
  }

  @Builder
  private TopSpacer() {
    GridItem() {
      Column() {
        Blank().height(this.topSpacerHeight())
      }
      .width('100%')
    }
    .clip(false)
  }

  @Builder
  private BottomSpacer() {
    GridItem() {
      Column() {
        Blank().height(this.bottomSpacerHeight())
      }
      .width('100%')
    }
    .clip(false)
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
