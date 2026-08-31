import {
  connectGalleryDetailTransition,
  GalleryDetailTransitionState,
} from '../state/GalleryDetailTransitionState'

/**
 * Keeps a virtualized gallery item in layout while its transition proxy owns the visible card.
 *
 * The slot subscribes to transition state itself. Putting this visibility check on GridItem,
 * FlowItem, or ListItem leaves it inside LazyForEach's cached item builder, which can miss the
 * visible -> hidden update after a rotated destination route becomes active again.
 */
@ComponentV2
export struct GalleryDetailTransitionSourceSlot {
  @Require @Param sourceComponentId: string;
  @BuilderParam content: () => void;
  @Local transitionState: GalleryDetailTransitionState = connectGalleryDetailTransition();

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .visibility(
      this.transitionState.sourceComponentId === this.sourceComponentId
        ? Visibility.Hidden
        : Visibility.Visible,
    )
  }
}
