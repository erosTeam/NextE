import { ThemeConstants } from '../theme/ThemeConstants'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { isUserScrollSource } from '../utils/ScrollUserInput'

/**
 * Secondary-page list scaffold (ported verbatim from V2Next). A full-height List whose first
 * row insets past the status bar + HDS title bar and whose last row insets past the gesture
 * bar — so a routed HdsNavDestination's content scrolls UNDER the title
 * bar without any magic numbers in the page. Parents pass their own Scroller + the section
 * content builder; favorites / settings / gallery-detail all sit on top of this.
 */
@ComponentV2
export struct SecondaryListScaffold {
  @BuilderParam content: () => void
  // Safe-area metrics are published into AppStorageV2 by EntryAbility; reading this state keeps
  // the padding reactive.
  layout: LayoutSafeAreaState = connectLayoutSafeArea()
  // @Param (not a plain member) because parents pass their own Scroller in by reference.
  @Param scroller: Scroller = new Scroller()
  @Param listSpace: number = ThemeConstants.SPACE_SM - 2
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD
  @Param bottomPadding: number = ThemeConstants.SPACE_XL
  // Opt-in only for pages that emit native ListItemGroup section headers.
  @Param stickyHeaders: boolean = false
  // Local opt-in for short, non-refresh pages such as Settings. PullRefresh scaffolds keep this off.
  @Param alwaysEnableEdgeSpring: boolean = false
  // Defaults to ArkUI's API 18+ vertical behavior. Wide gallery detail passes an explicit owner gate.
  @Param backToTop: boolean = true
  @Event onReachEnd?: () => void
  @Event onDidScroll?: (offset: number, state: ScrollState) => void
  @Event onUserScroll?: () => void
  @Event onListAreaChange?: (area: Area) => void

  build() {
    List({ space: this.listSpace, scroller: this.scroller }) {
      ListItem() {
        Column() {
          Blank().height(this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT)
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
        this.maybeNotifyReachEnd()
      })
    }
    .scrollBar(BarState.Off)
    .backToTop(this.backToTop)
    .sticky(this.stickyHeaders ? StickyStyle.Header : StickyStyle.None)
    .width('100%')
    .height('100%')
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
    .clip(false)
    .edgeEffect(this.alwaysEnableEdgeSpring ? EdgeEffect.Spring : EdgeEffect.None, {
      alwaysEnabled: this.alwaysEnableEdgeSpring,
    })
    .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
      if (this.onDidScroll) {
        this.onDidScroll(this.scroller.currentOffset().yOffset, scrollState)
      }
    })
    .onWillScroll((_scrollOffset: number, _scrollState: ScrollState, source: ScrollSource) => {
      if (this.onUserScroll && isUserScrollSource(source)) {
        this.onUserScroll()
      }
    })
    .onScrollIndex((_start: number, _end: number, _center: number) => {
      if (this.onDidScroll) {
        this.onDidScroll(this.scroller.currentOffset().yOffset, ScrollState.Scroll)
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      if (this.onListAreaChange) {
        this.onListAreaChange(newValue)
      }
    })
    .onReachEnd(() => {
      if (this.onReachEnd) {
        this.onReachEnd()
      }
    })
  }

  private maybeNotifyReachEnd(): void {
    if (this.onReachEnd) {
      this.onReachEnd()
    }
  }
}
