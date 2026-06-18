import {
  AppSearchField,
  AppStrings,
  ThemeConstants,
  SearchActionState,
  connectSearchAction,
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
 * Writes the shared SearchActionState
 * bus the results body reads: `keyword` on every keystroke (write-only — reading it back in build
 * would remount the field and flap the IME), `submitSeq` on Enter / search button. `fieldText` is
 * seeded on mount and via `@Monitor('seedSeq')` (cross-page Similar/uploader search, history tap).
 */
@ComponentV2
export struct SearchPageField {
  @Local actionState: SearchActionState = connectSearchAction();
  @Local private fieldText: string = '';

  aboutToAppear(): void {
    this.fieldText = this.actionState.keyword
  }

  @Monitor('actionState.seedSeq')
  onSeed(): void {
    this.fieldText = this.actionState.keyword
  }

  build() {
    Row() {
      AppSearchField({
        text: this.fieldText,
        placeholder: $r('app.string.search_placeholder'),
        // Manual Search opens focus the field; action-seeded searches render results first without IME.
        autoFocus: this.actionState.focusOnAppear,
        searchButtonText: AppStrings.get('tab_search'),
        useSystemMaterial: true,
        onTextChange: (value: string) => {
          this.actionState.keyword = value
        },
        onSubmit: (_value: string) => {
          this.actionState.submitSeq = this.actionState.submitSeq + 1
        },
      }).layoutWeight(1)
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
export function SearchPageFieldCCBuilder(_arg: Object) {
  SearchPageField()
}
