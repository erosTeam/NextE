import {
  AppStrings,
  EhConstants,
  ThemeConstants,
  SearchFilterState,
  connectSearchFilter,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
} from 'shared'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'

interface CatItem {
  name: string
  bit: number
}

const ALL_CATS: number = 1023
const CATS: CatItem[] = [
  { name: 'Misc', bit: 1 },
  { name: 'Doujinshi', bit: 2 },
  { name: 'Manga', bit: 4 },
  { name: 'Artist CG', bit: 8 },
  { name: 'Game CG', bit: 16 },
  { name: 'Western', bit: 512 },
  { name: 'Non-H', bit: 256 },
  { name: 'Image Set', bit: 32 },
  { name: 'Cosplay', bit: 64 },
  { name: 'Asian Porn', bit: 128 },
]
const CAT_ROWS: CatItem[][] = [
  [CATS[0], CATS[1]],
  [CATS[2], CATS[3]],
  [CATS[4], CATS[5]],
  [CATS[6], CATS[7]],
  [CATS[8], CATS[9]],
]
const RATINGS: number[] = [0, 2, 3, 4, 5]

/**
 * Advanced-search filter sheet content (hosted via the search page's bindSheet). Mirrors eros_fe's
 * direct-editing model: category/rating/scope/toggle changes update SearchFilterState immediately and
 * bump applySeq so the search page re-runs the current query. Reset is the only explicit action.
 */
@ComponentV2
export struct SearchFilterSheet {
  @Local filter: SearchFilterState = connectSearchFilter();
  @Local private scopeItems: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '' }, { text: '' }, { text: '' }]);
  @Local private ratingItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '' },
    { text: '2★' },
    { text: '3★' },
    { text: '4★' },
    { text: '5★' },
  ]);

  aboutToAppear(): void {
    this.syncSegmentLabels()
  }

  private syncSegmentLabels(): void {
    this.scopeItems[0].text = AppStrings.get('search_scope_gallery')
    this.scopeItems[1].text = AppStrings.get('search_scope_watched')
    this.scopeItems[2].text = AppStrings.get('search_scope_favorite')
    this.ratingItems[0].text = AppStrings.get('filter_any')
  }

  private bumpApplySeq(): void {
    this.filter.applySeq = this.filter.applySeq + 1
  }

  private normalizeCats(cats: number): number {
    return cats === ALL_CATS ? 0 : cats
  }

  private visibleCatMask(): number {
    return this.filter.selectedCats === 0 ? ALL_CATS : this.filter.selectedCats
  }

  private isCatSelected(c: CatItem): boolean {
    return (this.visibleCatMask() & c.bit) !== 0
  }

  private toggleCategory(c: CatItem): void {
    const next: number = this.visibleCatMask() ^ c.bit
    this.filter.selectedCats = this.normalizeCats(next)
    this.bumpApplySeq()
  }

  private soloOrInvertCategory(c: CatItem): void {
    const current: number = this.visibleCatMask()
    const selected: boolean = (current & c.bit) !== 0
    this.filter.selectedCats = selected ? c.bit : this.normalizeCats(ALL_CATS ^ c.bit)
    this.bumpApplySeq()
  }

  private setScope(scope: string): void {
    if (this.filter.searchScope === scope) {
      return
    }
    this.filter.searchScope = scope
    this.bumpApplySeq()
  }

  private setRating(rating: number): void {
    if (this.filter.minRating === rating) {
      return
    }
    this.filter.minRating = rating
    this.bumpApplySeq()
  }

  private setPagesFrom(value: number): void {
    if (this.filter.pagesFrom === value) {
      return
    }
    this.filter.pagesFrom = value
    this.bumpApplySeq()
  }

  private setPagesTo(value: number): void {
    if (this.filter.pagesTo === value) {
      return
    }
    this.filter.pagesTo = value
    this.bumpApplySeq()
  }

  private setRequireTorrent(on: boolean): void {
    if (this.filter.requireTorrent === on) {
      return
    }
    this.filter.requireTorrent = on
    this.bumpApplySeq()
  }

  private setShowExpunged(on: boolean): void {
    if (this.filter.showExpunged === on) {
      return
    }
    this.filter.showExpunged = on
    this.bumpApplySeq()
  }

  private setDisableLanguageFilter(on: boolean): void {
    if (this.filter.disableLanguageFilter === on) {
      return
    }
    this.filter.disableLanguageFilter = on
    this.bumpApplySeq()
  }

  private setDisableUploaderFilter(on: boolean): void {
    if (this.filter.disableUploaderFilter === on) {
      return
    }
    this.filter.disableUploaderFilter = on
    this.bumpApplySeq()
  }

  private setDisableTagFilter(on: boolean): void {
    if (this.filter.disableTagFilter === on) {
      return
    }
    this.filter.disableTagFilter = on
    this.bumpApplySeq()
  }

  private resetFilter(): void {
    this.filter.searchScope = SEARCH_SCOPE_GALLERY
    this.filter.selectedCats = 0
    this.filter.minRating = 0
    this.filter.pagesFrom = 0
    this.filter.pagesTo = 0
    this.filter.requireTorrent = false
    this.filter.showExpunged = false
    this.filter.disableLanguageFilter = false
    this.filter.disableUploaderFilter = false
    this.filter.disableTagFilter = false
    this.bumpApplySeq()
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: ThemeConstants.SPACE_LG }) {
          Text($r('app.string.filter_scope'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          TabSegmentButtonV2({
            items: this.scopeItems,
            selectedIndex: this.scopeIndex(),
            enableStateAnimation: true,
            onItemClicked: (index: number) => {
              this.setScope(this.scopeForIndex(index))
            },
            itemPadding: {
              top: LengthMetrics.vp(7),
              bottom: LengthMetrics.vp(7),
              start: LengthMetrics.vp(8),
              end: LengthMetrics.vp(8),
            },
          })
          .width('100%')
          .constraintSize({ minHeight: 40 })
          if (this.filter.searchScope === SEARCH_SCOPE_FAVORITE) {
            Text($r('app.string.filter_favorite_scope_hint'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(18)
          }
          if (this.filter.searchScope !== SEARCH_SCOPE_FAVORITE) {
            Text($r('app.string.filter_category'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Column({ space: ThemeConstants.SPACE_XS }) {
              ForEach(
                CAT_ROWS,
                (row: CatItem[]) => {
                  Row({ space: ThemeConstants.SPACE_XS }) {
                    ForEach(
                      row,
                      (c: CatItem) => {
                        SearchFilterCategoryButton({
                          label: c.name,
                          selected: this.isCatSelected(c),
                          color: EhConstants.categoryColor(c.name),
                          onTap: () => {
                            this.toggleCategory(c)
                          },
                          onLongPress: () => {
                            this.soloOrInvertCategory(c)
                          },
                        })
                        .layoutWeight(1)
                      },
                      (c: CatItem) => c.name,
                    )
                  }
                  .width('100%')
                },
                (row: CatItem[]) => row[0].name,
              )
            }.width('100%')
            Text($r('app.string.filter_rating'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            TabSegmentButtonV2({
              items: this.ratingItems,
              selectedIndex: this.ratingIndex(),
              enableStateAnimation: true,
              onItemClicked: (index: number) => {
                this.setRating(this.ratingForIndex(index))
              },
              itemPadding: {
                top: LengthMetrics.vp(7),
                bottom: LengthMetrics.vp(7),
                start: LengthMetrics.vp(8),
                end: LengthMetrics.vp(8),
              },
            })
            .width('100%')
            .constraintSize({ minHeight: 40 })
            Text($r('app.string.filter_pages'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Row({ space: ThemeConstants.SPACE_SM }) {
              this.PageInput(this.filter.pagesFrom, (v: number) => {
                this.setPagesFrom(v)
              })
              Text('-').fontColor($r('sys.color.font_secondary'))
              this.PageInput(this.filter.pagesTo, (v: number) => {
                this.setPagesTo(v)
              })
            }.alignItems(VerticalAlign.Center)
            Text($r('app.string.filter_options'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            this.ToggleRow(
              $r('app.string.filter_require_torrent'),
              this.filter.requireTorrent,
              (on: boolean) => {
                this.setRequireTorrent(on)
              },
            )
            this.ToggleRow(
              $r('app.string.filter_show_expunged'),
              this.filter.showExpunged,
              (on: boolean) => {
                this.setShowExpunged(on)
              },
            )
            // eros_fe's three independent "ignore my default <X> filter" toggles (f_sfl/f_sfu/f_sft).
            this.ToggleRow(
              $r('app.string.filter_disable_lang'),
              this.filter.disableLanguageFilter,
              (on: boolean) => {
                this.setDisableLanguageFilter(on)
              },
            )
            this.ToggleRow(
              $r('app.string.filter_disable_uploader'),
              this.filter.disableUploaderFilter,
              (on: boolean) => {
                this.setDisableUploaderFilter(on)
              },
            )
            this.ToggleRow(
              $r('app.string.filter_disable_tag'),
              this.filter.disableTagFilter,
              (on: boolean) => {
                this.setDisableTagFilter(on)
              },
            )
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: ThemeConstants.SPACE_LG,
          right: ThemeConstants.SPACE_LG,
          top: ThemeConstants.SPACE_LG,
          bottom: ThemeConstants.SPACE_SM,
        })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      this.ActionBar()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ActionBar() {
    Row() {
      Blank()
      Button($r('app.string.filter_reset'))
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .fontColor($r('sys.color.font_primary'))
        .constraintSize({ minWidth: 112 })
        .onClick(() => {
          this.resetFilter()
        })
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_LG,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_LG,
    })
    .backgroundColor($r('sys.color.ohos_id_color_dialog_bg'))
  }

  private scopeIndex(): number {
    if (this.filter.searchScope === SEARCH_SCOPE_WATCHED) {
      return 1
    }
    if (this.filter.searchScope === SEARCH_SCOPE_FAVORITE) {
      return 2
    }
    return 0
  }

  private scopeForIndex(index: number): string {
    if (index === 1) {
      return SEARCH_SCOPE_WATCHED
    }
    if (index === 2) {
      return SEARCH_SCOPE_FAVORITE
    }
    return SEARCH_SCOPE_GALLERY
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

  @Builder
  ToggleRow(label: ResourceStr, value: boolean, onChange: (on: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(ThemeConstants.BRAND_PRIMARY)
        .onChange((on: boolean) => {
          onChange(on)
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PageInput(value: number, onChange: (v: number) => void) {
    TextInput({ text: value > 0 ? `${value}` : '' })
      .type(InputType.Number)
      .width(90)
      .height(36)
      .backgroundColor($r('app.color.card_background'))
      .onChange((v: string) => {
        const n: number = Number.parseInt(v, 10)
        onChange(Number.isNaN(n) ? 0 : n)
      })
  }
}

@ComponentV2
struct SearchFilterCategoryButton {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param color: ResourceColor = ThemeConstants.BRAND_PRIMARY;
  @Event onTap: () => void = () => {};
  @Event onLongPress: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'))
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height(42)
      .width('100%')
      .backgroundColor(this.selected ? this.color : $r('sys.color.ohos_id_color_button_normal'))
      .borderRadius(ThemeConstants.RADIUS_MD)
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
      })
      .onClick(() => {
        this.onTap()
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            this.onLongPress()
          }),
      )
  }
}
