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

ok('scope uses ArkUI TabSegmentButtonV2, not a hand-rolled Row/Text segmented control',
  /import \{ LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 \} from '@kit\.ArkUI'/.test(sheet) &&
  /TabSegmentButtonV2\(\{[\s\S]*items: this\.scopeItems[\s\S]*selectedIndex: this\.scopeIndex\(\)[\s\S]*enableStateAnimation: true[\s\S]*this\.setScope\(this\.scopeForIndex\(index\)\)/.test(sheet) &&
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
  /TabSegmentButtonV2\(\{[\s\S]*items: this\.ratingItems[\s\S]*selectedIndex: this\.ratingIndex\(\)[\s\S]*this\.setRating\(this\.ratingForIndex\(index\)\)/.test(sheet) &&
  !/SearchFilterChipButton/.test(sheet))
ok('old builder chips and stale draft selected parameters are gone',
  !/@Builder\s+Chip\(/.test(sheet) &&
  !/draftSelectedCats/.test(sheet) &&
  !/draftMinRating/.test(sheet))
ok('favorite scope is visible and explained instead of hiding the page-level filter entry',
  /filter_favorite_scope_hint/.test(sheet) &&
  !/if \(!this\.isFavoriteScope\)[\s\S]*this\.FilterTrigger\(\)/.test(page))
ok('page exposes filter as a native title-bar action, not a scrolling or overlay chip',
  /private filterMenu\(\): Record<string, Object> \{[\s\S]*'label': \$r\('app\.string\.filter'\)[\s\S]*'action': \(\) => \{[\s\S]*this\.showFilter = true/.test(page) &&
  /'icon': \$r\('sys\.symbol\.funnel'\)/.test(page) &&
  !/'icon': \$r\('sys\.symbol\.sort'\)/.test(page) &&
  /'menu': this\.filterMenu\(\)/.test(page) &&
  !/@Builder\s+FilterTrigger/.test(page) &&
  !/FilterTriggerOverlay/.test(page))
ok('search field is pinned in title-bar bottomBuilder below the scope title',
  /private searchBottomBuilder\(content: ComponentContent<Object>\): Record<string, Object> \{[\s\S]*'builderComponent': content[\s\S]*'height': SEARCH_FIELD_BOTTOM_HEIGHT[\s\S]*BottomBuilderShowType\.DIRECTLY_SHOW/.test(page) &&
  /'bottomBuilder': this\.searchBottomBuilder\(this\.ensureFieldContent\(\)\)/.test(page) &&
  !/'stackBuilderComponent': this\.ensureFieldContent\(\)/.test(page))

console.log(`✓ search filter UX contract: ${passed} assertions passed`)
