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
const PROBE_PENDING_IMAGE_URL: string = 'http://10.255.255.1/nexte-never-loads.jpg'

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

          Text('Loading motion probe')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeConstants.TEXT_PRIMARY)
            .width('100%')

          Row({ space: ThemeConstants.SPACE_MD }) {
            this.nativeSpinnerProbe()
            this.thumbnailSpinnerProbe()
            this.pendingImageProbe()
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
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

  @Builder
  private nativeSpinnerProbe() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Stack({ alignContent: Alignment.Center }) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('sys.color.font_tertiary'))
      }
      .width(96)
      .height(96)
      .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
      .borderRadius(ThemeConstants.RADIUS_MD)

      Text('native')
        .fontSize(12)
        .fontColor(ThemeConstants.TEXT_SECONDARY)
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .width(96)
    }
  }

  @Builder
  private thumbnailSpinnerProbe() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Stack({ alignContent: Alignment.Center }) {
        EhThumbnail({
          url: '',
          thumbWidth: 72,
          thumbHeight: 72,
          radius: ThemeConstants.RADIUS_MD,
          visualState: THUMBNAIL_VISUAL_LOADING,
        })
      }
      .width(96)
      .height(96)
      .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
      .borderRadius(ThemeConstants.RADIUS_MD)

      Text('thumbnail')
        .fontSize(12)
        .fontColor(ThemeConstants.TEXT_SECONDARY)
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .width(96)
    }
  }

  @Builder
  private pendingImageProbe() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(PROBE_PENDING_IMAGE_URL)
          .width(72)
          .height(72)
          .objectFit(ImageFit.Cover)
          .draggable(false)
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('sys.color.font_tertiary'))
      }
      .width(72)
      .height(72)
      .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
      .borderRadius(ThemeConstants.RADIUS_MD)

      Text('pending image')
        .fontSize(12)
        .fontColor(ThemeConstants.TEXT_SECONDARY)
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .width(96)
    }
  }
}
