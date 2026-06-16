import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  GalleryCommentsParams,
  SecondaryListScaffold,
  CardEmptyState,
  AppStrings,
  connectSearchAction,
  immersiveTitleBar,
} from 'shared'
import { GalleryCommentsCard } from '../components/GalleryCommentsCard'

/**
 * The separate full comments page (eros_fe galleryComment). The detail page shows a 2-comment peek
 * and links here; this page renders the whole list (already parsed from the detail fetch, passed by
 * reference). Read-only; the composer / vote / reply actions belong to the deferred write-ops milestone.
 */
@ComponentV2
export struct GalleryCommentsPage {
  @Local params: GalleryCommentsParams = new GalleryCommentsParams();
  private scroller: Scroller = new Scroller();

  // Tap a comment author → search their uploads (same bus + behavior as the detail page). eros_fe
  // quotes namespaced searches so a multi-word username matches exactly.
  private searchUploader(name: string): void {
    const n: string = name.trim()
    if (n.length === 0) {
      return
    }
    connectSearchAction().publishQuery(`uploader:"${n}"`)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        if (this.params.comments.length > 0) {
          ListItem() {
            // max = 0 → show every comment (the peek on the detail page uses max = 2).
            GalleryCommentsCard({
              comments: this.params.comments,
              onAuthor: (name: string) => {
                this.searchUploader(name)
              },
            })
          }
        } else {
          ListItem() {
            CardEmptyState({ message: $r('app.string.common_no_content') })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('gallery_comments')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryCommentsParams
      if (p !== undefined) {
        this.params = p
      }
    })
  }
}
