import {
  AppStrings,
  DiagnosticLogger,
  DownloadViewState,
  DownloadViewType,
  ThemeConstants,
  connectDownloadView,
} from 'shared'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'

/**
 * Downloads tab type switcher pinned in the HDS title bar. Mirrors eros_fe's navigation-bar
 * CupertinoSlidingSegmentedControl and keeps queue type navigation out of the scrolling queue body.
 */
@ComponentV2
export struct DownloadTypeBar {
  @Local private downloadView: DownloadViewState = connectDownloadView();
  @Local private items: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '' }, { text: '' }]);

  build() {
    Row() {
      TabSegmentButtonV2({
        items: this.segmentItems(),
        selectedIndex: this.selectedIndex(),
        enableStateAnimation: true,
        itemFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
        itemSelectedFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
        itemFontWeight: FontWeight.Medium,
        itemSelectedFontWeight: FontWeight.Bold,
        itemPadding: {
          top: LengthMetrics.vp(ThemeConstants.SPACE_XS),
          bottom: LengthMetrics.vp(ThemeConstants.SPACE_XS),
          start: LengthMetrics.vp(ThemeConstants.SPACE_MD),
          end: LengthMetrics.vp(ThemeConstants.SPACE_MD),
        },
        onItemClicked: (index: number) => {
          this.setSelectedIndex(index)
        },
      })
        .width(ThemeConstants.COMPACT_SEGMENT_BUTTON_WIDTH)
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

  private segmentItems(): SegmentButtonV2Items {
    this.items = new SegmentButtonV2Items([
      { text: AppStrings.get('tab_gallery') },
      { text: AppStrings.get('download_archiver') },
    ])
    return this.items
  }

  private setSelectedIndex(index: number): void {
    const next: string = index === 1 ? DownloadViewType.ARCHIVER : DownloadViewType.GALLERY
    if (this.downloadView.viewType === next) {
      return
    }
    this.downloadView.viewType = next
    DiagnosticLogger.info('download', 'download_type_switch', `type=${next}`)
  }
}

@Builder
export function DownloadTypeBarCCBuilder(_arg: Object) {
  DownloadTypeBar()
}
