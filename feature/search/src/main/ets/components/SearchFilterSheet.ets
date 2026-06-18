import {
  ThemeConstants,
  SearchFilterState,
  connectSearchFilter,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
} from 'shared'

interface CatItem {
  name: string
  bit: number
}

const CATS: CatItem[] = [
  { name: 'Doujinshi', bit: 2 },
  { name: 'Manga', bit: 4 },
  { name: 'Artist CG', bit: 8 },
  { name: 'Game CG', bit: 16 },
  { name: 'Western', bit: 512 },
  { name: 'Non-H', bit: 256 },
  { name: 'Image Set', bit: 32 },
  { name: 'Cosplay', bit: 64 },
  { name: 'Asian Porn', bit: 128 },
  { name: 'Misc', bit: 1 },
]
const RATINGS: number[] = [0, 2, 3, 4, 5]

/**
 * Advanced-search filter sheet content (hosted via the search page's bindSheet). Edits the shared
 * SearchFilterState directly (category SHOW bitmask, min rating, page range); Apply bumps applySeq
 * so the search page re-runs the current query with the new filters, Reset clears them.
 */
@ComponentV2
export struct SearchFilterSheet {
  @Local filter: SearchFilterState = connectSearchFilter();
  @Event onApply: () => void = () => {};

  build() {
    Scroll() {
      Column({ space: ThemeConstants.SPACE_LG }) {
        Text($r('app.string.filter_scope'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Row({ space: ThemeConstants.SPACE_XS }) {
          this.ScopeSegment($r('app.string.search_scope_gallery'), SEARCH_SCOPE_GALLERY)
          this.ScopeSegment($r('app.string.search_scope_watched'), SEARCH_SCOPE_WATCHED)
          this.ScopeSegment($r('app.string.search_scope_favorite'), SEARCH_SCOPE_FAVORITE)
        }
        .width('100%')
        .height(40)
        .padding(ThemeConstants.SPACE_XS)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(ThemeConstants.RADIUS_MD)
        if (this.filter.searchScope !== SEARCH_SCOPE_FAVORITE) {
          Text($r('app.string.filter_category'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(
              CATS,
              (c: CatItem) => {
                this.Chip(c.name, (this.filter.selectedCats & c.bit) !== 0, () => {
                  this.filter.selectedCats = this.filter.selectedCats ^ c.bit
                })
              },
              (c: CatItem) => c.name,
            )
          }.width('100%')
          Text($r('app.string.filter_rating'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Row({ space: ThemeConstants.SPACE_SM }) {
            ForEach(
              RATINGS,
              (r: number) => {
                this.Chip(
                  r === 0 ? '' : `${r}★`,
                  this.filter.minRating === r,
                  () => {
                    this.filter.minRating = r
                  },
                  r === 0,
                )
              },
              (r: number) => `${r}`,
            )
          }
          Text($r('app.string.filter_pages'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Row({ space: ThemeConstants.SPACE_SM }) {
            this.PageInput(this.filter.pagesFrom, (v: number) => {
              this.filter.pagesFrom = v
            })
            Text('-').fontColor($r('sys.color.font_secondary'))
            this.PageInput(this.filter.pagesTo, (v: number) => {
              this.filter.pagesTo = v
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
              this.filter.requireTorrent = on
            },
          )
          this.ToggleRow(
            $r('app.string.filter_show_expunged'),
            this.filter.showExpunged,
            (on: boolean) => {
              this.filter.showExpunged = on
            },
          )
          // eros_fe's three independent "ignore my default <X> filter" toggles (f_sfl/f_sfu/f_sft).
          this.ToggleRow(
            $r('app.string.filter_disable_lang'),
            this.filter.disableLanguageFilter,
            (on: boolean) => {
              this.filter.disableLanguageFilter = on
            },
          )
          this.ToggleRow(
            $r('app.string.filter_disable_uploader'),
            this.filter.disableUploaderFilter,
            (on: boolean) => {
              this.filter.disableUploaderFilter = on
            },
          )
          this.ToggleRow(
            $r('app.string.filter_disable_tag'),
            this.filter.disableTagFilter,
            (on: boolean) => {
              this.filter.disableTagFilter = on
            },
          )
        }
        Row({ space: ThemeConstants.SPACE_MD }) {
          Button($r('app.string.filter_reset'))
            .type(ButtonType.Capsule)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
            .onClick(() => {
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
              // Reset is itself a commit of the empty filter: bump applySeq so the page persists the
              // cleared state (else disk keeps the old filter and it resurrects on restart) + reapplies.
              this.filter.applySeq = this.filter.applySeq + 1
            })
          Button($r('app.string.filter_apply'))
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .onClick(() => {
              this.filter.applySeq = this.filter.applySeq + 1
              this.onApply()
            })
        }
        .width('100%')
        .margin({ top: ThemeConstants.SPACE_SM })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(ThemeConstants.SPACE_LG)
    }.scrollBar(BarState.Off)
  }

  @Builder
  ScopeSegment(label: ResourceStr, scope: string) {
    Text(label)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontWeight(this.filter.searchScope === scope ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(
        this.filter.searchScope === scope ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'),
      )
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(this.filter.searchScope === scope ? ThemeConstants.BRAND_PRIMARY : Color.Transparent)
      .borderRadius(ThemeConstants.RADIUS_SM)
      .padding({ left: ThemeConstants.SPACE_XS, right: ThemeConstants.SPACE_XS })
      .onClick(() => {
        this.filter.searchScope = scope
      })
  }

  @Builder
  Chip(label: string, selected: boolean, onTap: () => void, isAny: boolean = false) {
    Text(isAny ? $r('app.string.filter_any') : label)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(selected ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'))
      .backgroundColor(selected ? ThemeConstants.BRAND_PRIMARY : $r('app.color.card_background'))
      .borderRadius(ThemeConstants.RADIUS_ROUND)
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_XS,
        bottom: ThemeConstants.SPACE_XS,
      })
      .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
      .onClick(onTap)
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
