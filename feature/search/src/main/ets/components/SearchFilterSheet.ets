import {
  AppModalScaffold,
  AppStrings,
  ThemeConstants,
  SearchFilterState,
  connectSearchFilter,
  CategorySelector,
  AdvancedSearchControls,
  SearchFilterSettings,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'

const SEGMENT_HEIGHT: number = 44
const SEGMENT_PADDING_V: number = 8
const FORM_FONT_SIZE: number = ThemeConstants.FONT_SIZE_TITLE

/**
 * Advanced-search filter sheet content (hosted via the search page's bindSheet). Mirrors eros_fe's
 * direct-editing model: scope/category/advanced changes update SearchFilterState immediately and bump
 * applySeq so the search page re-runs the current query. The category grid + advanced controls are the
 * shared CategorySelector / AdvancedSearchControls components (also used by the custom-tab editor).
 */
@ComponentV2
export struct SearchFilterSheet {
  @Local filter: SearchFilterState = connectSearchFilter();
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
    if (this.filter.searchScope === scope) {
      return
    }
    this.filter.searchScope = scope
    this.bumpApplySeq()
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

  private resetFilter(): void {
    this.filter.searchScope = SEARCH_SCOPE_GALLERY
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
          if (this.filter.searchScope === SEARCH_SCOPE_FAVORITE) {
            Text($r('app.string.filter_favorite_scope_hint'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(18)
          }
          if (this.filter.searchScope !== SEARCH_SCOPE_FAVORITE) {
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
