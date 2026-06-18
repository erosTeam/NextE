#!/usr/bin/env node
/**
 * Contract: Search filter controls are real, immediate-feedback controls.
 *
 * FE grounding: Android eros_fe shows a segmented scope control, two-column category buttons with
 * semantic colors, long-press category solo/invert behavior, and a segmented minimum-rating control.
 * NextE may use HarmonyOS controls, but it must not regress to stale builder parameters, fake
 * Row/Text segmented controls, hidden filter entries, or a separate Apply commit model.
 *
 * Run: node scripts/test_search_filter_ux_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const sheet = read('feature/search/src/main/ets/components/SearchFilterSheet.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const zh = read('entry/src/main/resources/zh_CN/element/string.json')
const en = read('entry/src/main/resources/en_US/element/string.json')
const api = read('shared/src/main/ets/network/EhApiService.ets')

ok('scope uses ArkUI TabSegmentButtonV2, not a hand-rolled Row/Text segmented control',
  /import \{ LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 \} from '@kit\.ArkUI'/.test(sheet) &&
  /TabSegmentButtonV2\(\{[\s\S]*items: this\.scopeItems[\s\S]*selectedIndex: this\.scopeIndex\(\)[\s\S]*enableStateAnimation: true[\s\S]*itemFontSize: LengthMetrics\.vp\(FILTER_FORM_FONT_SIZE\)[\s\S]*itemSelectedFontWeight: FontWeight\.Bold[\s\S]*this\.setScope\(this\.scopeForIndex\(index\)\)/.test(sheet) &&
  !/@Builder\s+ScopeSegment/.test(sheet))
ok('scope labels come from i18n resources through AppStrings',
  /this\.scopeItems\[0\]\.text = AppStrings\.get\('search_scope_gallery'\)/.test(sheet) &&
  /this\.scopeItems\[2\]\.text = AppStrings\.get\('search_scope_favorite'\)/.test(sheet))
ok('categories are two-column semantic-color V2 buttons',
  /const CAT_ROWS: CatItem\[\]\[\]/.test(sheet) &&
  /@ComponentV2\s+struct SearchFilterCategoryButton[\s\S]*@Param selected: boolean = false[\s\S]*@Param color: ResourceColor/.test(sheet) &&
  /SearchFilterCategoryButton\(\{[\s\S]*label: c\.name[\s\S]*selected: this\.isCatSelected\(c\)[\s\S]*color: EhConstants\.categoryColor\(c\.name\)/.test(sheet))
ok('category normal tap and long press immediately mutate filter state',
  /onTap: \(\) => \{[\s\S]*this\.toggleCategory\(c\)/.test(sheet) &&
  /onLongPress: \(\) => \{[\s\S]*this\.soloOrInvertCategory\(c\)/.test(sheet) &&
  /LongPressGesture\(\{ repeat: false, duration: 500 \}\)[\s\S]*this\.onLongPress\(\)/.test(sheet))
ok('rating uses a formal segmented control, not chip text blocks',
  /@Local private ratingItems: SegmentButtonV2Items/.test(sheet) &&
  /TabSegmentButtonV2\(\{[\s\S]*items: this\.ratingItems[\s\S]*selectedIndex: this\.ratingIndex\(\)[\s\S]*itemFontSize: LengthMetrics\.vp\(FILTER_FORM_FONT_SIZE\)[\s\S]*itemSelectedFontWeight: FontWeight\.Bold[\s\S]*this\.setRating\(this\.ratingForIndex\(index\)\)/.test(sheet) &&
  !/SearchFilterChipButton/.test(sheet))
ok('filter sheet keeps normal category controls while bounding segment and form proportions',
  /const FILTER_SEGMENT_HEIGHT: number = 44/.test(sheet) &&
  /const FILTER_TOGGLE_MIN_HEIGHT: number = 44/.test(sheet) &&
  /const FILTER_TOGGLE_MAX_WIDTH: number = 520/.test(sheet) &&
  /const FILTER_FORM_FONT_SIZE: number = ThemeConstants\.FONT_SIZE_TITLE/.test(sheet) &&
  /SearchFilterCategoryButton[\s\S]*\.fontWeight\(this\.selected \? FontWeight\.Medium : FontWeight\.Regular\)[\s\S]*\.height\(42\)/.test(sheet))
ok('filter sheet is a flat form, not a stack of section headers by control type',
  !/Text\(\$r\('app\.string\.filter_scope'\)\)/.test(sheet) &&
  !/Text\(\$r\('app\.string\.filter_category'\)\)/.test(sheet) &&
  !/Text\(\$r\('app\.string\.filter_options'\)\)/.test(sheet) &&
  /this\.ToggleRow\(\s*\$r\('app\.string\.filter_advanced'\)/.test(sheet) &&
  /if \(this\.filter\.advancedEnabled\) \{[\s\S]*this\.RatingRow\(\)[\s\S]*this\.PageRangeRow\(\)[\s\S]*filter_require_torrent/.test(sheet))
ok('page range inputs look like form fields, not blank blocks',
  /const FILTER_PAGE_INPUT_WIDTH: number = 92/.test(sheet) &&
  /const FILTER_PAGE_INPUT_HEIGHT: number = 40/.test(sheet) &&
  /const FILTER_PAGE_RANGE_GROUP_WIDTH: number = 220/.test(sheet) &&
  /const FILTER_FORM_LABEL_WIDTH: number = 80/.test(sheet) &&
  !/FILTER_INPUT_BORDER_WIDTH/.test(sheet) &&
  !/\.border\(\{[\s\S]*FILTER_INPUT_BORDER_WIDTH/.test(sheet) &&
  /TextInput\(\{ text: value > 0 \? `\$\{value\}` : '', placeholder: \$r\('app\.string\.filter_any'\) \}\)[\s\S]*\.width\(FILTER_PAGE_INPUT_WIDTH\)[\s\S]*\.height\(FILTER_PAGE_INPUT_HEIGHT\)[\s\S]*\.fontSize\(FILTER_FORM_FONT_SIZE\)[\s\S]*\.placeholderColor\(\$r\('sys\.color\.font_tertiary'\)\)[\s\S]*\.borderRadius\(ThemeConstants\.RADIUS_ROUND\)/.test(sheet))
ok('rating is a compact form row with a readable full-width segmented control',
  /@Builder\s+RatingRow\(\)[\s\S]*Column\(\{ space: ThemeConstants\.SPACE_XS \}\)[\s\S]*Text\(\$r\('app\.string\.filter_rating'\)\)[\s\S]*TabSegmentButtonV2[\s\S]*\.width\('100%'\)[\s\S]*\.constraintSize\(\{ minHeight: FILTER_SEGMENT_HEIGHT \}\)/.test(sheet))
ok('page label is an inline row label and page inputs are centered in the row',
  /@Builder\s+PageRangeRow\(\)[\s\S]*Text\(\$r\('app\.string\.filter_pages'\)\)[\s\S]*\.width\(FILTER_FORM_LABEL_WIDTH\)[\s\S]*Blank\(\)\.layoutWeight\(1\)[\s\S]*\.width\(FILTER_PAGE_RANGE_GROUP_WIDTH\)[\s\S]*\.justifyContent\(FlexAlign\.Center\)[\s\S]*Blank\(\)\.layoutWeight\(1\)/.test(sheet))
ok('options rows read as compact settings rows with switch kept near the label',
  /ToggleRow\(label: ResourceStr[\s\S]*\.fontSize\(FILTER_FORM_FONT_SIZE\)[\s\S]*\.fontWeight\(FontWeight\.Medium\)[\s\S]*\.lineHeight\(ThemeConstants\.LINE_HEIGHT_TITLE\)[\s\S]*\.constraintSize\(\{ minHeight: FILTER_TOGGLE_MIN_HEIGHT, maxWidth: FILTER_TOGGLE_MAX_WIDTH \}\)/.test(sheet))
ok('expunged filter copy says only expunged, not show/include expunged',
  /"name": "filter_show_expunged",\s*"value": "仅搜索已删除"/.test(zh) &&
  /"name": "filter_show_expunged",\s*"value": "Only expunged"/.test(en) &&
  /showExpunged: boolean \/\/ f_sh: only expunged\/removed galleries/.test(api))
ok('old builder chips and stale draft selected parameters are gone',
  !/@Builder\s+Chip\(/.test(sheet) &&
  !/draftSelectedCats/.test(sheet) &&
  !/draftMinRating/.test(sheet))
ok('favorite scope is visible and explained instead of hiding the page-level filter entry',
  /filter_favorite_scope_hint/.test(sheet) &&
  !/if \(!this\.isFavoriteScope\)[\s\S]*this\.FilterTrigger\(\)/.test(page))
ok('page exposes filter as a title/menu action, not inside the search input row',
  /'menu': this\.searchMenu\(\)/.test(page) &&
  /private searchMenu\(\): Record<string, Object> \{[\s\S]*'icon': \$r\('sys\.symbol\.funnel'\)[\s\S]*'action': \(\) => \{[\s\S]*this\.showFilter = true/.test(page) &&
  !/@Monitor\('fieldState\.filterSeq'\)/.test(page) &&
  !/@Builder\s+FilterTrigger/.test(page) &&
  !/FilterTriggerOverlay/.test(page))
ok('search title hides on scroll while the bottomBuilder search field stays visible',
  /dynamicHideTitleBar\(\{[\s\S]*hideTitleArea: true[\s\S]*hideBottomBuilder: false[\s\S]*mode: HideMode\.SCROLL_UP/.test(page))
ok('search filter sheet opens at the highest sheet height without medium detents',
  /bindSheet\(\$\$this\.showFilter, this\.FilterSheet\(\), \{[\s\S]*detents: \[SheetSize\.LARGE\][\s\S]*showClose: false/.test(page) &&
  !/detents: \[SheetSize\.MEDIUM, SheetSize\.LARGE\]/.test(page))
ok('search field is pinned in title-bar bottomBuilder below the scope title',
  /private searchBottomBuilder\(content: ComponentContent<SearchPageFieldState>\): Record<string, Object> \{[\s\S]*'builderComponent': content[\s\S]*'height': SEARCH_FIELD_BOTTOM_HEIGHT[\s\S]*BottomBuilderShowType\.DIRECTLY_SHOW/.test(page) &&
  /'bottomBuilder': this\.searchBottomBuilder\(this\.ensureFieldContent\(\)\)/.test(page) &&
  !/'stackBuilderComponent': this\.ensureFieldContent\(\)/.test(page))

const field = read('feature/search/src/main/ets/components/SearchPageField.ets')
ok('pinned search field is input-only and does not own page-level filter actions',
  !/sys\.symbol\.funnel/.test(field) &&
  !/filterSeq/.test(field) &&
  !/sys\.symbol\.sort/.test(field) &&
  /@ObservedV2[\s\S]*export class SearchPageFieldState/.test(field))

console.log(`✓ search filter UX contract: ${passed} assertions passed`)
