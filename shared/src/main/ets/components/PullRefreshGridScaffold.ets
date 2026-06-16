import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

/**
 * Grid sibling of PullRefreshListScaffold: a 2-column Grid inside the same generic PullRefresh
 * (pull-to-refresh + pull-up + safe-area insets). The parent supplies GridItems via `content`.
 * Top inset (status bar + title bar) and bottom inset (gesture bar) are owned here, not the page.
 */
@ComponentV2
export struct PullRefreshGridScaffold {
  @BuilderParam content: () => void
  layout: LayoutSafeAreaState = connectLayoutSafeArea()
  @Param scroller: Scroller = new Scroller()
  @Param columns: number = 2
  @Param gap: number = ThemeConstants.SPACE_SM
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD
  @Param bottomPadding: number = ThemeConstants.SPACE_XL
  // Extra top inset above the status-bar + title-bar reserve (e.g. a pinned title-bar bottomBuilder).
  @Param topPadding: number = 0
  @Param controller: PullRefreshController = new PullRefreshController()
  @Event onRefresh?: () => Promise<void>
  @Event onBottomRefresh?: () => Promise<void>
  @Event canStartBottomRefresh?: () => boolean
  @Event onReachEnd?: () => void

  build() {
    PullRefresh({
      scroller: this.scroller,
      controller: this.controller,
      indicatorTop: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT / 2 + this.topPadding,
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
      .onReachEnd(() => {
        if (this.onReachEnd) {
          this.onReachEnd()
        }
      })
    }
  }

  private columnsTemplate(): string {
    const parts: string[] = []
    for (let i = 0; i < this.columns; i++) {
      parts.push('1fr')
    }
    return parts.join(' ')
  }
}
