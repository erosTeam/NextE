import { ThemeConstants } from '../theme/ThemeConstants'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

/**
 * Secondary-page list scaffold (ported verbatim from V2Next). A full-height List whose first
 * row insets past the status bar + HDS title bar and whose last row insets past the gesture
 * bar (+ optional keyboard) — so a routed HdsNavDestination's content scrolls UNDER the title
 * bar without any magic numbers in the page. Parents pass their own Scroller + the section
 * content builder; favorites / settings / gallery-detail all sit on top of this.
 */
@ComponentV2
export struct SecondaryListScaffold {
  @BuilderParam content: () => void
  // Safe-area / keyboard metrics are published into AppStorageV2 by EntryAbility; reading
  // these @Trace fields keeps the padding reactive.
  layout: LayoutSafeAreaState = connectLayoutSafeArea()
  // @Param (not a plain member) because parents pass their own Scroller in by reference.
  @Param scroller: Scroller = new Scroller()
  @Param listSpace: number = ThemeConstants.SPACE_SM - 2
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD
  @Param bottomPadding: number = ThemeConstants.SPACE_XL
  @Param includeKeyboardPadding: boolean = false
  @Event onReachEnd?: () => void
  @Event onDidScroll?: (offset: number, state: ScrollState) => void

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
          Blank().height(this.layout.bottomAvoidHeight + this.bottomPadding + this.keyboardPadding())
        }
        .width('100%')
      }
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
    .clip(false)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
      if (this.onDidScroll) {
        this.onDidScroll(this.scroller.currentOffset().yOffset, scrollState)
      }
    })
    .onScrollIndex((_start: number, _end: number, _center: number) => {
      if (this.onDidScroll) {
        this.onDidScroll(this.scroller.currentOffset().yOffset, ScrollState.Scroll)
      }
    })
    .onReachEnd(() => {
      if (this.onReachEnd) {
        this.onReachEnd()
      }
    })
  }

  private keyboardPadding(): number {
    if (!this.includeKeyboardPadding) {
      return 0
    }
    return Math.max(0, this.layout.keyboardHeight)
  }
}
