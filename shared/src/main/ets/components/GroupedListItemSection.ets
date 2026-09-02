import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * Card-styled ListItemGroup for rows that need ListItem semantics such as swipe actions or lazy reuse.
 * Ordinary non-ListItem content should continue to use GroupedListSection.
 */
@ComponentV2
export struct GroupedListItemSection {
  @BuilderParam content: () => void
  @BuilderParam headerBuilder: () => void = this.EmptyHeader;
  @Param showHeader: boolean = false;
  @Param space: number = 0;
  @Param inset: number = ThemeConstants.LIST_SECTION_INSET;
  @Param radius: number = ThemeConstants.RADIUS_CARD;

  @Builder
  private EmptyHeader() {}

  @Builder
  private Header() {
    if (this.showHeader) {
      this.headerBuilder()
    }
  }

  build() {
    ListItemGroup({ header: this.Header(), space: this.space }) {
      this.content()
    }
    .width('100%')
    .borderRadius(this.radius)
    .clip(true)
    .padding(this.inset)
    .backgroundColor($r('app.color.card_background'))
  }
}
