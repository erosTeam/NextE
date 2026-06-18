import { TabSegmentButtonV2, SegmentButtonV2Items, LengthMetrics } from '@kit.ArkUI'
import {
  AppStrings,
  DownloadViewState,
  DownloadViewType,
  ThemeConstants,
  connectDownloadView,
} from 'shared'

/**
 * Downloads tab type switcher pinned in the HDS title bar. Mirrors eros_fe's navigation-bar
 * CupertinoSlidingSegmentedControl and keeps queue type navigation out of the scrolling queue body.
 */
@ComponentV2
export struct DownloadTypeBar {
  @Local private downloadView: DownloadViewState = connectDownloadView();
  @Local private tabItems: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '' }, { text: '' }]);

  aboutToAppear(): void {
    this.syncLabels()
  }

  build() {
    Row() {
      TabSegmentButtonV2({
        items: this.tabItems,
        selectedIndex: this.selectedIndex(),
        enableStateAnimation: true,
        onItemClicked: (index: number) => {
          this.downloadView.viewType =
            index === 1 ? DownloadViewType.ARCHIVER : DownloadViewType.GALLERY
        },
        itemPadding: {
          top: LengthMetrics.vp(6),
          bottom: LengthMetrics.vp(6),
          start: LengthMetrics.vp(8),
          end: LengthMetrics.vp(8),
        },
      })
        .width(ThemeConstants.COMPACT_SEGMENT_BUTTON_WIDTH)
        .constraintSize({
          minWidth: ThemeConstants.COMPACT_SEGMENT_BUTTON_WIDTH,
          maxWidth: ThemeConstants.COMPACT_SEGMENT_BUTTON_WIDTH,
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({
      top: ThemeConstants.SPACE_XS,
      bottom: ThemeConstants.SPACE_XS,
      left: ThemeConstants.SPACE_SM,
      right: ThemeConstants.SPACE_SM,
    })
  }

  private selectedIndex(): number {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER ? 1 : 0
  }

  private syncLabels(): void {
    this.tabItems[0].text = AppStrings.get('tab_gallery')
    this.tabItems[1].text = AppStrings.get('download_archiver')
  }
}

@Builder
export function DownloadTypeBarCCBuilder(_arg: Object) {
  DownloadTypeBar()
}
