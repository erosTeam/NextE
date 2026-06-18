import {
  AppSearchField,
  AppStrings,
  ThemeConstants,
  SearchActionState,
  connectSearchAction,
} from 'shared'

/**
 * Title-bar layout reserves (ported from V2Next IndexTitleBarComponents:343-383). The search field is
 * hosted as the HdsNavDestination title-area stackBuilderComponent, which spans the FULL bar width —
 * so it must leave a left slot for the auto-rendered back button and a right edge gap, otherwise the
 * field sits flush to both edges and covers (hides + blocks) the back button.
 */
const TITLE_BAR_COMPACT_WIDTH: number = 600
const TITLE_BAR_EXPANDED_WIDTH: number = 840
const LEADING_EDGE_COMPACT: number = 16
const LEADING_EDGE_MEDIUM: number = 24
const LEADING_EDGE_EXPANDED: number = 32
const BACK_BUTTON_SLOT_WIDTH: number = 48
const TRAILING_EDGE_RESERVE: number = LEADING_EDGE_COMPACT

function edgeReserve(titleBarWidth: number): number {
  if (titleBarWidth >= TITLE_BAR_EXPANDED_WIDTH) {
    return LEADING_EDGE_EXPANDED
  }
  if (titleBarWidth >= TITLE_BAR_COMPACT_WIDTH) {
    return LEADING_EDGE_MEDIUM
  }
  return LEADING_EDGE_COMPACT
}

function leadingReserve(titleBarWidth: number): number {
  return BACK_BUTTON_SLOT_WIDTH + edgeReserve(titleBarWidth)
}

function lengthToNumber(value: Length | undefined): number {
  if (typeof value === 'number') {
    return value
  }
  if (typeof value === 'string') {
    const parsed: number = Number.parseFloat(value)
    return Number.isNaN(parsed) ? 0 : parsed
  }
  return 0
}

/**
 * Search input hosted in the pushed search page's HDS title bar (eros_fe pushes a dedicated search
 * page from an appbar icon — custom_tabbar_page.dart:219-229; V2Next's search destination hosts its
 * field the same way, IndexTitleBarComponents SearchTitleField). Writes the shared SearchActionState
 * bus the results body reads: `keyword` on every keystroke (write-only — reading it back in build
 * would remount the field and flap the IME), `submitSeq` on Enter / search button. `fieldText` is
 * seeded on mount and via `@Monitor('seedSeq')` (cross-page Similar/uploader search, history tap).
 */
@ComponentV2
export struct SearchPageField {
  private actionState: SearchActionState = connectSearchAction();
  @Local private fieldText: string = '';
  @Local private titleBarWidth: number = 0;

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
    .height(ThemeConstants.TITLE_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    // Left clears the auto back-button slot; right keeps an edge gap (no menu on this page).
    .padding({ left: leadingReserve(this.titleBarWidth), right: TRAILING_EDGE_RESERVE })
    // None so the empty leading region (the back-button slot) stays tappable; the AppSearchField child
    // still hit-tests normally (HitTestMode.None is per-node, not subtree).
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.titleBarWidth = lengthToNumber(newValue?.width)
    })
  }
}
@Builder
export function SearchPageFieldCCBuilder(_arg: Object) {
  SearchPageField()
}
