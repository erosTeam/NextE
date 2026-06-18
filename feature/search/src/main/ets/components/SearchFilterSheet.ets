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
  @Param openSeq: number = 0;
  @Local draftSearchScope: string = SEARCH_SCOPE_GALLERY;
  @Local draftSelectedCats: number = 0;
  @Local draftMinRating: number = 0;
  @Local draftPagesFrom: number = 0;
  @Local draftPagesTo: number = 0;
  @Local draftRequireTorrent: boolean = false;
  @Local draftShowExpunged: boolean = false;
  @Local draftDisableLanguageFilter: boolean = false;
  @Local draftDisableUploaderFilter: boolean = false;
  @Local draftDisableTagFilter: boolean = false;
  @Event onApply: () => void = () => {};

  aboutToAppear(): void {
    this.syncDraftFromFilter()
  }

  @Monitor('openSeq')
  onOpenSeqChanged(): void {
    this.syncDraftFromFilter()
  }

  private syncDraftFromFilter(): void {
    this.draftSearchScope = this.filter.searchScope
    this.draftSelectedCats = this.filter.selectedCats
    this.draftMinRating = this.filter.minRating
    this.draftPagesFrom = this.filter.pagesFrom
    this.draftPagesTo = this.filter.pagesTo
    this.draftRequireTorrent = this.filter.requireTorrent
    this.draftShowExpunged = this.filter.showExpunged
    this.draftDisableLanguageFilter = this.filter.disableLanguageFilter
    this.draftDisableUploaderFilter = this.filter.disableUploaderFilter
    this.draftDisableTagFilter = this.filter.disableTagFilter
  }

  private resetDraft(): void {
    this.draftSearchScope = SEARCH_SCOPE_GALLERY
    this.draftSelectedCats = 0
    this.draftMinRating = 0
    this.draftPagesFrom = 0
    this.draftPagesTo = 0
    this.draftRequireTorrent = false
    this.draftShowExpunged = false
    this.draftDisableLanguageFilter = false
    this.draftDisableUploaderFilter = false
    this.draftDisableTagFilter = false
  }

  private commitDraft(): void {
    this.filter.searchScope = this.draftSearchScope
    this.filter.selectedCats = this.draftSelectedCats
    this.filter.minRating = this.draftMinRating
    this.filter.pagesFrom = this.draftPagesFrom
    this.filter.pagesTo = this.draftPagesTo
    this.filter.requireTorrent = this.draftRequireTorrent
    this.filter.showExpunged = this.draftShowExpunged
    this.filter.disableLanguageFilter = this.draftDisableLanguageFilter
    this.filter.disableUploaderFilter = this.draftDisableUploaderFilter
    this.filter.disableTagFilter = this.draftDisableTagFilter
    this.filter.applySeq = this.filter.applySeq + 1
    this.onApply()
  }

  build() {
    Column() {
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
          if (this.draftSearchScope !== SEARCH_SCOPE_FAVORITE) {
            Text($r('app.string.filter_category'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(
                CATS,
                (c: CatItem) => {
                  this.Chip(c.name, (this.draftSelectedCats & c.bit) !== 0, () => {
                    this.draftSelectedCats = this.draftSelectedCats ^ c.bit
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
                    this.draftMinRating === r,
                    () => {
                      this.draftMinRating = r
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
              this.PageInput(this.draftPagesFrom, (v: number) => {
                this.draftPagesFrom = v
              })
              Text('-').fontColor($r('sys.color.font_secondary'))
              this.PageInput(this.draftPagesTo, (v: number) => {
                this.draftPagesTo = v
              })
            }.alignItems(VerticalAlign.Center)
            Text($r('app.string.filter_options'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            this.ToggleRow(
              $r('app.string.filter_require_torrent'),
              this.draftRequireTorrent,
              (on: boolean) => {
                this.draftRequireTorrent = on
              },
            )
            this.ToggleRow(
              $r('app.string.filter_show_expunged'),
              this.draftShowExpunged,
              (on: boolean) => {
                this.draftShowExpunged = on
              },
            )
            // eros_fe's three independent "ignore my default <X> filter" toggles (f_sfl/f_sfu/f_sft).
            this.ToggleRow(
              $r('app.string.filter_disable_lang'),
              this.draftDisableLanguageFilter,
              (on: boolean) => {
                this.draftDisableLanguageFilter = on
              },
            )
            this.ToggleRow(
              $r('app.string.filter_disable_uploader'),
              this.draftDisableUploaderFilter,
              (on: boolean) => {
                this.draftDisableUploaderFilter = on
              },
            )
            this.ToggleRow(
              $r('app.string.filter_disable_tag'),
              this.draftDisableTagFilter,
              (on: boolean) => {
                this.draftDisableTagFilter = on
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
    Row({ space: ThemeConstants.SPACE_MD }) {
      Button($r('app.string.filter_reset'))
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .onClick(() => {
          // Reset is a commit of the empty filter, so it closes the sheet and re-runs like Apply.
          this.resetDraft()
          this.commitDraft()
        })
      Button($r('app.string.filter_apply'))
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .onClick(() => {
          this.commitDraft()
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

  @Builder
  ScopeSegment(label: ResourceStr, scope: string) {
    Text(label)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontWeight(this.draftSearchScope === scope ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(
        this.draftSearchScope === scope ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'),
      )
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(this.draftSearchScope === scope ? ThemeConstants.BRAND_PRIMARY : Color.Transparent)
      .borderRadius(ThemeConstants.RADIUS_SM)
      .padding({ left: ThemeConstants.SPACE_XS, right: ThemeConstants.SPACE_XS })
      .onClick(() => {
        this.draftSearchScope = scope
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
