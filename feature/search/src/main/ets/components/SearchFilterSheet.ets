import {
  AppModalScaffold,
  AppStrings,
  ThemeConstants,
  SearchFilterState,
  connectSearchFilter,
  ConciseListRow,
  EhConstants,
  Favcat,
  FavSelectionState,
  GroupedListSection,
  connectFavSelection,
  CategorySelector,
  AdvancedSearchControls,
  SearchFilterSettings,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'
import { SearchSessionState } from '../state/SearchSessionState'

const SEGMENT_HEIGHT: number = 44
const SEGMENT_PADDING_V: number = 8
const FORM_FONT_SIZE: number = ThemeConstants.FONT_SIZE_TITLE

/**
 * Search filter sheet content (hosted via the search page's bindSheet). Scope and favorite folder are
 * page-session state; persisted category/advanced values remain in SearchFilterState. Every change
 * re-runs the current query through the page monitor. Favorite rows reuse the existing selector-page
 * information hierarchy, with the trailing count replaced by the native Radio control.
 */
@ComponentV2
export struct SearchFilterSheet {
  @Local filter: SearchFilterState = connectSearchFilter();
  @Local fav: FavSelectionState = connectFavSelection();
  @Param session: SearchSessionState = new SearchSessionState();
  @Local private scopeItems: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '' }, { text: '' }, { text: '' }]);
  @Event onClose: () => void = () => {};

  aboutToAppear(): void {
    this.scopeItems[0].text = AppStrings.get('search_scope_gallery')
    this.scopeItems[1].text = AppStrings.get('search_scope_watched')
    this.scopeItems[2].text = AppStrings.get('search_scope_favorite')
  }

  private bumpApplySeq(): void {
    this.filter.applySeq = this.filter.applySeq + 1
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private close(): void {
    SearchFilterSettings.flush(this.ctx())
    this.onClose()
  }

  private setScope(scope: string): void {
    this.session.setScope(scope)
  }

  private scopeIndex(): number {
    if (this.session.scope === SEARCH_SCOPE_WATCHED) {
      return 1
    }
    if (this.session.scope === SEARCH_SCOPE_FAVORITE) {
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

  private resetFilter(): void {
    this.session.reset()
    this.filter.selectedCats = 0
    this.filter.advancedEnabled = false
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

  private favoriteRows(): Favcat[] {
    const rows: Favcat[] = [new Favcat('a', AppStrings.get('favorites_all'), this.fav.remoteTotalCount())]
    this.fav.favList.forEach((fc: Favcat) => {
      if (FavSelectionState.isRemoteSlot(fc.favId)) {
        rows.push(fc)
      }
    })
    return rows
  }

  private favoriteColor(favId: string): ResourceColor {
    const color: string = EhConstants.favCatColor(favId)
    return color.length > 0 ? color : ThemeConstants.FAV_HEART_DEFAULT
  }

  @Builder
  private FavoritePrefix(favId: string) {
    SymbolGlyph($r('sys.symbol.heart_fill'))
      .fontSize(24)
      .fontColor([this.favoriteColor(favId)])
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
  }

  @Builder
  private FavoriteRadio(fc: Favcat) {
    Radio({ value: fc.favId, group: 'nexte_search_favorite_scope' })
      .checked(this.session.favoriteFavcat === fc.favId)
      .radioStyle({ checkedBackgroundColor: ThemeConstants.BRAND_PRIMARY })
      .hitTestBehavior(HitTestMode.None)
      .margin({ right: ThemeConstants.SPACE_MD })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private FavoriteFolderSelector() {
    Text($r('app.string.filter_favorite_folder'))
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor($r('sys.color.font_secondary'))
    GroupedListSection() {
      ForEach(
        this.favoriteRows(),
        (fc: Favcat, index: number) => {
          ConciseListRow({
            title: fc.favTitle,
            trailingText: '',
            showChevron: false,
            prefixBuilderParam: () => {
              this.FavoritePrefix(fc.favId)
            },
            suffixBuilderParam: () => {
              this.FavoriteRadio(fc)
            },
            action: () => {
              this.session.setFavoriteFavcat(fc.favId)
            },
          })
          if (index < this.favoriteRows().length - 1) {
            this.rowDivider()
          }
        },
        (fc: Favcat, index: number) =>
          `search_favcat_${index}_${fc.favId}_${fc.favTitle}`.replace(/[^A-Za-z0-9_]/g, '_'),
      )
    }
  }

  build() {
    AppModalScaffold({
      title: $r('app.string.filter'),
      confirmIcon: $r('sys.symbol.arrow_counterclockwise'),
      confirmText: $r('app.string.filter_reset'),
      closeAction: () => {
        this.close()
      },
      confirmAction: () => {
        this.resetFilter()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          TabSegmentButtonV2({
            items: this.scopeItems,
            selectedIndex: this.scopeIndex(),
            enableStateAnimation: true,
            itemFontSize: LengthMetrics.vp(FORM_FONT_SIZE),
            itemSelectedFontSize: LengthMetrics.vp(FORM_FONT_SIZE),
            itemFontWeight: FontWeight.Medium,
            itemSelectedFontWeight: FontWeight.Bold,
            onItemClicked: (index: number) => {
              this.setScope(this.scopeForIndex(index))
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
          if (this.session.scope === SEARCH_SCOPE_FAVORITE) {
            Text($r('app.string.filter_favorite_scope_hint'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(18)
            this.FavoriteFolderSelector()
          }
          if (this.session.scope !== SEARCH_SCOPE_FAVORITE) {
            CategorySelector({
              filter: this.filter,
              onChanged: () => {
                this.bumpApplySeq()
              },
            })
            AdvancedSearchControls({
              filter: this.filter,
              onChanged: () => {
                this.bumpApplySeq()
              },
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: ThemeConstants.SPACE_SM,
          right: ThemeConstants.SPACE_SM,
          top: ThemeConstants.SPACE_SM,
          bottom: ThemeConstants.SPACE_SM,
        })
      }
    }
  }
}
