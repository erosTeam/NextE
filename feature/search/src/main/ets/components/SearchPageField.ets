import {
  AppSearchField,
  AppStrings,
  ThemeConstants,
} from 'shared'

/**
 * Search input hosted in the pushed search page's HDS title-bar bottomBuilder. The title area keeps
 * the native back button, scope title, and actions; this bottom slot can use the full content width
 * without reserving a fake back-button gap.
 */
const SEARCH_FIELD_BOTTOM_HEIGHT: number = ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_SM

/**
 * Search input hosted in the pushed search page's HDS title bar bottom area (eros_fe pushes a dedicated search
 * page from an appbar icon — custom_tabbar_page.dart:219-229; V2Next's search destination hosts its
 * field in a title chrome area, while NextE keeps actions in the native title and the field below).
 * Writes the page-owned SearchPageFieldState the results body reads. This is deliberately NOT the
 * app-wide SearchActionState: multiple Search pages can coexist in the navigation stack
 * (Search(A) -> Detail -> Search(B)), so keyword/submit/filter state must be per page session.
 */
@ObservedV2
export class SearchPageFieldState {
  @Trace keyword: string = ''
  @Trace submitSeq: number = 0
  @Trace seedSeq: number = 0
  @Trace filterSeq: number = 0
  @Trace focusOnAppear: boolean = true
}

@ComponentV2
export struct SearchPageField {
  @Param fieldState: SearchPageFieldState = new SearchPageFieldState();
  @Local private fieldText: string = '';

  aboutToAppear(): void {
    this.fieldText = this.fieldState.keyword
  }

  @Monitor('fieldState.seedSeq')
  onSeed(): void {
    this.fieldText = this.fieldState.keyword
  }

  build() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      AppSearchField({
        text: this.fieldText,
        placeholder: $r('app.string.search_placeholder'),
        // Manual Search opens focus the field; action-seeded searches render results first without IME.
        autoFocus: this.fieldState.focusOnAppear,
        searchButtonText: AppStrings.get('tab_search'),
        useSystemMaterial: true,
        onTextChange: (value: string) => {
          this.fieldState.keyword = value
        },
        onSubmit: (_value: string) => {
          this.fieldState.submitSeq = this.fieldState.submitSeq + 1
        },
      }).layoutWeight(1)
      Button() {
        SymbolGlyph($r('sys.symbol.funnel'))
          .fontSize(22)
          .fontColor([$r('sys.color.font_primary')])
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .accessibilityText($r('app.string.filter'))
      .onClick(() => {
        this.fieldState.filterSeq = this.fieldState.filterSeq + 1
      })
    }
    .width('100%')
    .height(SEARCH_FIELD_BOTTOM_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_LG,
      bottom: ThemeConstants.SPACE_SM,
    })
  }
}
@Builder
export function SearchPageFieldCCBuilder(state: SearchPageFieldState) {
  SearchPageField({ fieldState: state })
}
