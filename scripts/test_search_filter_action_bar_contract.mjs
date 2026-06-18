#!/usr/bin/env node
/**
 * Contract: Search filter sheet keeps Reset beside Close in the sheet header.
 *
 * FE comparison shows filter controls apply immediately. Reset is a secondary clear action, so it
 * belongs near the close/dismiss affordance rather than as a bottom primary action.
 *
 * Run: node scripts/test_search_filter_action_bar_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const src = read('feature/search/src/main/ets/components/SearchFilterSheet.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const grounding = [
  'eros_fe: lib/pages/filter/gallery_filter_view.dart GalleryFilterView.build() and lib/pages/filter/filter.dart GalleryCatFilter',
  'primary information: current scope, colored category selection, minimum rating, page range, and EH filter options',
  'primary action: changing a control live-applies; secondary action: Reset clears filters',
  'scope: keep Reset near sheet close; do not change query parser, QuickSearch, tagsuggest, image search, or backend semantics',
  'Harmony expression: custom sheet Header with title, low-weight Reset, and a system-symbol Close button; fields remain in Scroll.layoutWeight(1)',
]

ok('grounding has five lines', grounding.length === 5)
ok('grounding names concrete eros_fe filter files', grounding[0].includes('gallery_filter_view.dart') &&
  grounding[0].includes('filter.dart'))
ok('scope excludes unrelated search features', grounding[3].includes('QuickSearch') &&
  grounding[3].includes('tagsuggest') &&
  grounding[3].includes('image search'))

ok('SearchFilterSheet has a header before scroll content',
  /build\(\)\s*\{[\s\S]*Column\(\)\s*\{[\s\S]*this\.Header\(\)[\s\S]*Scroll\(\)\s*\{/.test(src))
ok('Header contains title, Reset, and system-symbol close in one row',
  /@Builder\s+Header\(\)\s*\{[\s\S]*Row\(\{ space: ThemeConstants\.SPACE_SM \}\)[\s\S]*Text\(\$r\('app\.string\.filter'\)\)[\s\S]*Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*Button\(\)\s*\{[\s\S]*SymbolGlyph\(\$r\('sys\.symbol\.xmark'\)\)/.test(src))
ok('Reset stays a low-weight secondary action beside close',
  /Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*\.type\(ButtonType\.Normal\)[\s\S]*\.backgroundColor\(Color\.Transparent\)[\s\S]*\.fontColor\(ThemeConstants\.BRAND_PRIMARY\)[\s\S]*\.height\(48\)[\s\S]*this\.resetFilter\(\)/.test(src))
ok('close button remains compact enough to sit beside Reset',
  /SymbolGlyph\(\$r\('sys\.symbol\.xmark'\)\)[\s\S]*\.type\(ButtonType\.Circle\)[\s\S]*\.width\(48\)[\s\S]*\.height\(48\)/.test(src))
ok('Close calls the sheet close event and uses a real icon, not text glyphs',
  /@Event onClose: \(\) => void = \(\) => \{\}/.test(src) &&
  /SymbolGlyph\(\$r\('sys\.symbol\.xmark'\)\)/.test(src) &&
  /this\.onClose\(\)/.test(src) &&
  !/Text\('×'\)/.test(src) &&
  !/Text\('x'\)/.test(src))
ok('bottom ActionBar is removed',
  !/@Builder\s+ActionBar\(\)/.test(src) &&
  !/this\.ActionBar\(\)/.test(src))
ok('scroll content still owns independent padding and layout weight',
  /\.padding\(\{\s*left: ThemeConstants\.SPACE_LG,[\s\S]*top: ThemeConstants\.SPACE_SM,[\s\S]*bottom: ThemeConstants\.SPACE_SM,[\s\S]*\}\)[\s\S]*\.scrollBar\(BarState\.Off\)[\s\S]*\.layoutWeight\(1\)/.test(src))
ok('scroll content is top-aligned below the sheet header',
  /\.scrollBar\(BarState\.Off\)[\s\S]*\.align\(Alignment\.Top\)[\s\S]*\.layoutWeight\(1\)/.test(src))
ok('page disables system sheet close because header owns close',
  /SearchFilterSheet\(\{[\s\S]*onClose: \(\) => \{[\s\S]*this\.showFilter = false[\s\S]*\}/.test(page) &&
  /showClose: false/.test(page) &&
  !/title: \{ title: \$r\('app\.string\.filter'\) \}/.test(page))
ok('no Apply button remains',
  !/Button\(\$r\('app\.string\.filter_apply'\)\)/.test(src) &&
  !/filter_apply/.test(src))

console.log(`✓ search filter header action contract: ${passed} assertions passed`)
