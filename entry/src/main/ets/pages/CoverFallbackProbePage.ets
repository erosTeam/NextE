import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  EhThumbnail,
  THUMBNAIL_VISUAL_LOADING,
  THUMBNAIL_VISUAL_ERROR,
  ThemeConstants,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  immersiveTitleBar,
} from 'shared'

const PROBE_THUMB_W: number = 132
const PROBE_THUMB_H: number = 190

@ComponentV2
export struct CoverFallbackProbePage {
  @Local layout: LayoutSafeAreaState = connectLayoutSafeArea();

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: ThemeConstants.SPACE_LG }) {
          Text('Cover fallback probe')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeConstants.TEXT_PRIMARY)

          Row({ space: ThemeConstants.SPACE_XL }) {
            this.stateCard('Loading', THUMBNAIL_VISUAL_LOADING)
            this.stateCard('Error', THUMBNAIL_VISUAL_ERROR)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .padding({
          top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_XL,
          left: ThemeConstants.SPACE_LG,
          right: ThemeConstants.SPACE_LG,
          bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_XL,
        })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBar('Cover fallback probe'))
    .backgroundColor(ThemeConstants.BG_PRIMARY)
  }

  @Builder
  private stateCard(label: string, state: number) {
    Column({ space: ThemeConstants.SPACE_SM }) {
      EhThumbnail({
        url: '',
        thumbWidth: PROBE_THUMB_W,
        thumbHeight: PROBE_THUMB_H,
        radius: ThemeConstants.RADIUS_MD,
        containFit: true,
        visualState: state,
      })

      Text(label)
        .fontSize(14)
        .fontColor(ThemeConstants.TEXT_SECONDARY)
    }
  }
}
