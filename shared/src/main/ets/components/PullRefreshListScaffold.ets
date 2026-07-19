import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { isUserScrollSource } from '../utils/ScrollUserInput'

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
  // Opt-in only for ListItemGroup-based content such as viewed-history day sections.
  @Param stickyHeaders: boolean = false
  // Number of real list rows, excluding the top/bottom reserve ListItems owned by this scaffold.
  @Param itemCount: number = 0
  // Gallery callers opt in because they need indexes consistent with Grid/WaterFlow scaffolds.
  @Param normalizeContentIndexes: boolean = false
  @Param indicatorTop: number = -1
  @Param scrollEnabled: boolean = true
  // Defaults to ArkUI's API 18+ vertical behavior. Wide gallery detail passes an explicit owner gate.
  @Param backToTop: boolean = true
  @Param controller: PullRefreshController = new PullRefreshController()
  @Local measuredWidth: number = 0
  @Event onRefresh?: () => Promise<void>
  @Event onBottomRefresh?: () => Promise<void>
  @Event canStartBottomRefresh?: () => boolean
  @Event onReachEnd?: () => void
  @Event onScrollIndex?: (start: number, end: number, center: number) => void
  @Event onDidScroll?: (offset: number, state: ScrollState) => void
  @Event onUserScroll?: () => void
  @Event onScrollEnableChange?: (enabled: boolean) => void
  @Event onContentWidth?: (contentWidth: number) => void
  @Event onListAreaChange?: (area: Area) => void

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
        .onAppear(() => {
          this.maybeLoadOnTailAppear()
        })
      }
      .enableScrollInteraction(this.scrollEnabled)
      .maintainVisibleContentPosition(true)
      .backToTop(this.backToTop)
      .sticky(this.stickyHeaders ? StickyStyle.Header : StickyStyle.None)
      .onWillScroll((_scrollOffset: number, _scrollState: ScrollState, source: ScrollSource) => {
        if (this.onUserScroll && isUserScrollSource(source)) {
          this.onUserScroll()
        }
      })
      .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, scrollState)
        }
      })
      .onScrollIndex((start: number, end: number, center: number) => {
        const adjustedStart: number = this.normalizeContentIndexes ? this.galleryIndex(start) : start
        const adjustedEnd: number = this.normalizeContentIndexes ? this.galleryIndex(end) : end
        const adjustedCenter: number = this.normalizeContentIndexes ? this.galleryIndex(center) : center
        if (this.onScrollIndex) {
          this.onScrollIndex(adjustedStart, adjustedEnd, adjustedCenter)
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
        if (this.onListAreaChange) {
          this.onListAreaChange(newValue)
        }
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

  // Native List indexes include this scaffold's top reserve at 0 and the bottom reserve after the
  // final gallery. Consumers receive only the real gallery range, matching Grid/WaterFlow scaffolds.
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

  private maybeLoadOnTailAppear(): void {
    if (this.canStartBottomRefresh && !this.canStartBottomRefresh()) {
      return
    }
    if (this.onReachEnd) {
      this.onReachEnd()
    }
  }
}
