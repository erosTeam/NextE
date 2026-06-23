import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

@ComponentV2
export struct PullRefreshListScaffold {
  @BuilderParam content: () => void
  // Safe-area metrics are published into AppStorageV2 by EntryAbility.
  // Reading these @Trace fields keeps padding reactive exactly like the former
  // @StorageProp(StorageKeys.*) reads did.
  layout: LayoutSafeAreaState = connectLayoutSafeArea()
  // @Param (not a plain member) because parents pass their own Scroller in by reference.
  @Param scroller: Scroller = new Scroller()
  @Param listSpace: number = ThemeConstants.SPACE_SM - 2
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD
  @Param topPadding: number = 0
  @Param bottomPadding: number = ThemeConstants.SPACE_XL
  @Param indicatorTop: number = -1
  @Param scrollEnabled: boolean = true
  @Param controller: PullRefreshController = new PullRefreshController()
  @Local measuredWidth: number = 0
  @Event onRefresh?: () => Promise<void>
  @Event onBottomRefresh?: () => Promise<void>
  @Event canStartBottomRefresh?: () => boolean
  @Event onReachEnd?: () => void
  @Event onScrollIndex?: (start: number, end: number, center: number) => void
  @Event onDidScroll?: (offset: number, state: ScrollState) => void
  @Event onScrollEnableChange?: (enabled: boolean) => void
  @Event onContentWidth?: (contentWidth: number) => void

  build() {
    PullRefresh({
      scroller: this.scroller,
      controller: this.controller,
      indicatorTop: this.resolvedIndicatorTop(),
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
      onScrollEnableChange: (enabled: boolean) => {
        if (this.onScrollEnableChange) {
          this.onScrollEnableChange(enabled)
        }
      }
    }) {
      List({ space: this.listSpace, scroller: this.scroller }) {
        ListItem() {
          Column() {
            Blank().height(this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding)
          }
          .width('100%')
        }
        .clip(false)

        this.content()

        ListItem() {
          Column() {
            Blank().height(this.layout.bottomAvoidHeight + this.bottomPadding)
          }
          .width('100%')
        }
      }
      .enableScrollInteraction(this.scrollEnabled)
      .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, scrollState)
        }
      })
      .onScrollIndex((start: number, end: number, center: number) => {
        if (this.onScrollIndex) {
          this.onScrollIndex(start, end, center)
        }
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, ScrollState.Scroll)
        }
      })
      .onReachEnd(() => {
        if (this.onReachEnd) {
          this.onReachEnd()
        }
      })
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
      .clip(false)
      // PullRefresh owns the edge drag offset; native spring would add a second movement layer.
      .edgeEffect(EdgeEffect.None)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.measuredWidth = newValue.width as number
        if (this.onContentWidth) {
          const contentWidth: number = this.measuredWidth - 2 * this.horizontalPadding
          this.onContentWidth(contentWidth > 0 ? contentWidth : 0)
        }
      })
    }
  }

  private resolvedIndicatorTop(): number {
    if (this.indicatorTop >= 0) {
      return this.indicatorTop
    }
    return this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT / 2 + this.topPadding
  }
}
