import {
  connectGalleryDetailTransition,
  GalleryDetailTransitionState,
} from '../state/GalleryDetailTransitionState'
import { connectNavStack, NavStackHolder } from '../state/NavStackHolder'

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
  @Local navStackHolder: NavStackHolder = connectNavStack();

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .visibility(
      this.transitionState.hidesSource(this.sourceComponentId, this.navStackHolder.isSplitMode)
        ? Visibility.Hidden
        : Visibility.Visible,
    )
  }
}
