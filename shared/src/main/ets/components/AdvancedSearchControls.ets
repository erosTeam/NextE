import { ThemeConstants } from '../theme/ThemeConstants'
import { AppStrings } from '../i18n/AppStrings'
import { SearchFilterState } from '../state/SearchFilterState'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'

const RATINGS: number[] = [0, 2, 3, 4, 5]
const SEGMENT_HEIGHT: number = 44
const SEGMENT_PADDING_V: number = 8
const TOGGLE_MIN_HEIGHT: number = 44
const TOGGLE_MAX_WIDTH: number = 520
const PAGE_INPUT_WIDTH: number = 92
const PAGE_INPUT_HEIGHT: number = 40
const PAGE_RANGE_GROUP_WIDTH: number = 220
const FORM_ROW_MAX_WIDTH: number = 640
const FORM_LABEL_WIDTH: number = 80
const FORM_FONT_SIZE: number = ThemeConstants.FONT_SIZE_TITLE

/**
 * EH advanced-search controls: the master 高级搜索 toggle, and — when enabled — min-rating segment,
 * page-range inputs, and the five eros_fe toggles (torrent / expunged / disable language|uploader|tag
 * filters). Reads/writes the SearchFilterState advanced fields. Extracted from SearchFilterSheet so the
 * search sheet AND the custom-tab editor share one control set. `onChanged` lets the host react (the
 * search sheet bumps applySeq; the editor passes nothing).
 */
@ComponentV2
export struct AdvancedSearchControls {
  @Param filter: SearchFilterState = new SearchFilterState();
  @Event onChanged?: () => void;
  @Local private ratingItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '' },
    { text: '2★' },
    { text: '3★' },
    { text: '4★' },
    { text: '5★' },
  ]);

  aboutToAppear(): void {
    this.ratingItems[0].text = AppStrings.get('filter_any')
  }

  private changed(): void {
    if (this.onChanged) {
      this.onChanged()
    }
  }

  private setAdvancedEnabled(on: boolean): void {
    if (this.filter.advancedEnabled === on) {
      return
    }
    this.filter.advancedEnabled = on
    this.changed()
  }

  private setRating(rating: number): void {
    if (this.filter.minRating === rating) {
      return
    }
    this.filter.minRating = rating
    this.changed()
  }

  private setPagesFrom(value: number): void {
    if (this.filter.pagesFrom === value) {
      return
    }
    this.filter.pagesFrom = value
    this.changed()
  }

  private setPagesTo(value: number): void {
    if (this.filter.pagesTo === value) {
      return
    }
    this.filter.pagesTo = value
    this.changed()
  }

  private ratingIndex(): number {
    const index: number = RATINGS.indexOf(this.filter.minRating)
    return index >= 0 ? index : 0
  }

  private ratingForIndex(index: number): number {
    if (index >= 0 && index < RATINGS.length) {
      return RATINGS[index]
    }
    return 0
  }

  build() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      this.ToggleRow($r('app.string.filter_advanced'), this.filter.advancedEnabled, (on: boolean) => {
        this.setAdvancedEnabled(on)
      })
      if (this.filter.advancedEnabled) {
        this.RatingRow()
        this.PageRangeRow()
        this.ToggleRow(
          $r('app.string.filter_require_torrent'),
          this.filter.requireTorrent,
          (on: boolean) => {
            this.filter.requireTorrent = on
            this.changed()
          },
        )
        this.ToggleRow(
          $r('app.string.filter_show_expunged'),
          this.filter.showExpunged,
          (on: boolean) => {
            this.filter.showExpunged = on
            this.changed()
          },
        )
        this.ToggleRow(
          $r('app.string.filter_disable_lang'),
          this.filter.disableLanguageFilter,
          (on: boolean) => {
            this.filter.disableLanguageFilter = on
            this.changed()
          },
        )
        this.ToggleRow(
          $r('app.string.filter_disable_uploader'),
          this.filter.disableUploaderFilter,
          (on: boolean) => {
            this.filter.disableUploaderFilter = on
            this.changed()
          },
        )
        this.ToggleRow(
          $r('app.string.filter_disable_tag'),
          this.filter.disableTagFilter,
          (on: boolean) => {
            this.filter.disableTagFilter = on
            this.changed()
          },
        )
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ToggleRow(label: ResourceStr, value: boolean, onChange: (on: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(FORM_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(ThemeConstants.BRAND_PRIMARY)
        .onChange((on: boolean) => {
          onChange(on)
        })
    }
    .width('100%')
    .constraintSize({ minHeight: TOGGLE_MIN_HEIGHT, maxWidth: TOGGLE_MAX_WIDTH })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  RatingRow() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text($r('app.string.filter_rating'))
        .fontSize(FORM_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
      TabSegmentButtonV2({
        items: this.ratingItems,
        selectedIndex: this.ratingIndex(),
        enableStateAnimation: true,
        itemFontSize: LengthMetrics.vp(FORM_FONT_SIZE),
        itemSelectedFontSize: LengthMetrics.vp(FORM_FONT_SIZE),
        itemFontWeight: FontWeight.Medium,
        itemSelectedFontWeight: FontWeight.Bold,
        onItemClicked: (index: number) => {
          this.setRating(this.ratingForIndex(index))
        },
        itemPadding: {
          top: LengthMetrics.vp(SEGMENT_PADDING_V),
          bottom: LengthMetrics.vp(SEGMENT_PADDING_V),
          start: LengthMetrics.vp(8),
          end: LengthMetrics.vp(8),
        },
      })
        .width('100%')
        .constraintSize({ minHeight: SEGMENT_HEIGHT })
    }
    .width('100%')
    .constraintSize({ maxWidth: FORM_ROW_MAX_WIDTH })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PageRangeRow() {
    Row({ space: ThemeConstants.SPACE_MD }) {
      Text($r('app.string.filter_pages'))
        .fontSize(FORM_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(ThemeConstants.LINE_HEIGHT_TITLE)
        .width(FORM_LABEL_WIDTH)
      Blank().layoutWeight(1)
      Row({ space: ThemeConstants.SPACE_SM }) {
        this.PageInput(this.filter.pagesFrom, (v: number) => {
          this.setPagesFrom(v)
        })
        Text('-')
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
        this.PageInput(this.filter.pagesTo, (v: number) => {
          this.setPagesTo(v)
        })
      }
      .width(PAGE_RANGE_GROUP_WIDTH)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      Blank().layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ maxWidth: FORM_ROW_MAX_WIDTH })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PageInput(value: number, onChange: (v: number) => void) {
    TextInput({ text: value > 0 ? `${value}` : '', placeholder: $r('app.string.filter_any') })
      .type(InputType.Number)
      .width(PAGE_INPUT_WIDTH)
      .height(PAGE_INPUT_HEIGHT)
      .backgroundColor($r('app.color.card_background'))
      .fontSize(FORM_FONT_SIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .borderRadius(ThemeConstants.RADIUS_ROUND)
      .onChange((v: string) => {
        const n: number = Number.parseInt(v, 10)
        onChange(Number.isNaN(n) ? 0 : n)
      })
  }
}
