import {
  ThemeConstants,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  CardEmptyState,
} from 'shared'

const DOWNLOAD_VIEW_GALLERY: string = 'gallery'
const DOWNLOAD_VIEW_ARCHIVER: string = 'archiver'

/**
 * Downloads (下载) bottom tab — plain tab content hosted under Index's shared HDS title bar (no
 * NavDestination wrapper). Mirrors eros_fe's first-level split: Gallery downloads and Archiver
 * downloads are separate retained queues. This lane intentionally stops at the non-destructive
 * workbench surface; the background download service, archive submit, and offline-reader source
 * resolver land in later lanes.
 */
@ComponentV2
export struct DownloadQueuePage {
  // Accepted for the Index tab-scroller handoff (this placeholder doesn't scroll, so it's unused).
  @Param scroller: Scroller = new Scroller();
  @Local viewType: string = DOWNLOAD_VIEW_GALLERY;

  private selectedTitle(): Resource {
    return this.viewType === DOWNLOAD_VIEW_ARCHIVER
      ? $r('app.string.download_archiver_queue')
      : $r('app.string.download_gallery_queue')
  }

  private selectedEmptyText(): Resource {
    return this.viewType === DOWNLOAD_VIEW_ARCHIVER
      ? $r('app.string.download_archiver_empty')
      : $r('app.string.download_gallery_empty')
  }

  private selectedNextStep(): Resource {
    return this.viewType === DOWNLOAD_VIEW_ARCHIVER
      ? $r('app.string.download_archiver_next_step')
      : $r('app.string.download_gallery_next_step')
  }

  private tabTextColor(viewType: string): ResourceColor {
    return this.viewType === viewType ? Color.White : $r('sys.color.font_primary')
  }

  private tabBackground(viewType: string): ResourceColor {
    return this.viewType === viewType ? ThemeConstants.BRAND_PRIMARY : Color.Transparent
  }

  @Builder
  private QueueSwitcher() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      this.SwitchButton($r('app.string.tab_gallery'), DOWNLOAD_VIEW_GALLERY)
      this.SwitchButton($r('app.string.download_archiver'), DOWNLOAD_VIEW_ARCHIVER)
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_XS)
    .borderRadius(ThemeConstants.RADIUS_MD)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
  }

  @Builder
  private SwitchButton(label: ResourceStr, viewType: string) {
    Button() {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.tabTextColor(viewType))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .height(40)
    .borderRadius(ThemeConstants.RADIUS_SM)
    .backgroundColor(this.tabBackground(viewType))
    .onClick(() => {
      this.viewType = viewType
    })
  }

  @Builder
  private SummarySection() {
    GroupedListSection() {
      ConciseListRow({
        title: this.selectedTitle(),
        leadingIcon: this.viewType === DOWNLOAD_VIEW_ARCHIVER
          ? $r('sys.symbol.square_grid_2x2')
          : $r('sys.symbol.picture'),
        trailingText: $r('app.string.download_status_empty'),
        showChevron: false,
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.download_active_tasks'),
        leadingIcon: $r('sys.symbol.arrow_down_to_line_circle_fill'),
        trailingText: '0',
        showChevron: false,
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.download_finished_tasks'),
        leadingIcon: $r('sys.symbol.checkmark'),
        trailingText: '0',
        showChevron: false,
      })
    }
  }

  @Builder
  private EmptyQueueSection() {
    GroupedListSection() {
      CardEmptyState({ message: this.selectedEmptyText(), expand: false })
      Text(this.selectedNextStep())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({
          left: ThemeConstants.SPACE_LG,
          right: ThemeConstants.SPACE_LG,
          bottom: ThemeConstants.SPACE_LG,
        })
    }
  }

  @Builder
  private SettingsPreviewSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.download_concurrency'),
        leadingIcon: $r('sys.symbol.sort'),
        trailingText: $r('app.string.download_not_configured'),
        showChevron: false,
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.download_original_images'),
        leadingIcon: $r('sys.symbol.picture'),
        trailingText: $r('app.string.download_not_configured'),
        showChevron: false,
      })
    }
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
      }) {
        ListItem() {
          this.QueueSwitcher()
        }
        ListItem() {
          this.SummarySection()
        }
        ListItem() {
          this.EmptyQueueSection()
        }
        ListItem() {
          this.SettingsPreviewSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
