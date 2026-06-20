#!/usr/bin/env node
/**
 * Contract: Search filter sheet uses the shared HDS modal scaffold.
 *
 * FE comparison shows filter controls apply immediately. Reset is a secondary clear action, so it
 * belongs in the modal title action area rather than as a hand-rolled text button.
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
  'Harmony expression: AppModalScaffold with HDS modal title, left xmark close, and right reset icon action',
]

ok('grounding has five lines', grounding.length === 5)
ok('grounding names concrete eros_fe filter files', grounding[0].includes('gallery_filter_view.dart') &&
  grounding[0].includes('filter.dart'))
ok('scope excludes unrelated search features', grounding[3].includes('QuickSearch') &&
  grounding[3].includes('tagsuggest') &&
  grounding[3].includes('image search'))

const modal = read('shared/src/main/ets/components/AppModalScaffold.ets')

ok('SearchFilterSheet uses AppModalScaffold for modal chrome',
  /import \{[\s\S]*AppModalScaffold[\s\S]*\} from 'shared'/.test(src) &&
  /build\(\)\s*\{[\s\S]*AppModalScaffold\(\{[\s\S]*title:\s*\$r\('app\.string\.filter'\)/.test(src))
ok('Reset is a right-side scaffold icon action',
  /confirmIcon:\s*\$r\('sys\.symbol\.arrow_counterclockwise'\)/.test(src) &&
  /confirmText:\s*\$r\('app\.string\.filter_reset'\)/.test(src) &&
  /confirmAction:\s*\(\) => \{[\s\S]*this\.resetFilter\(\)/.test(src))
ok('Close calls the sheet close event via the scaffold',
  /@Event onClose: \(\) => void = \(\) => \{\}/.test(src) &&
  /closeAction:\s*\(\) => \{[\s\S]*this\.onClose\(\)/.test(src) &&
  /closeIcon:\s*Resource\s*=\s*\$r\('sys\.symbol\.xmark'\)/.test(modal) &&
  /this\.onClose\(\)/.test(src) &&
  !/Text\('×'\)/.test(src) &&
  !/Text\('x'\)/.test(src))
ok('hand-rolled header and bottom ActionBar are removed',
  !/@Builder\s+Header\(\)/.test(src) &&
  !/this\.Header\(\)/.test(src) &&
  !/Button\(\$r\('app\.string\.filter_reset'\)\)/.test(src) &&
  !/SymbolGlyph\(\$r\('sys\.symbol\.xmark'\)\)/.test(src) &&
  !/@Builder\s+ActionBar\(\)/.test(src) &&
  !/this\.ActionBar\(\)/.test(src))
ok('AppModalScaffold owns HDS modal navigation and optional title action',
  /HdsNavigationTitleMode\.MODAL/.test(modal) &&
  /HdsNavigation/.test(modal) &&
  /showConfirmAction: boolean = true/.test(modal) &&
  /showSecondaryAction: boolean = false/.test(modal) &&
  /IconStyleMode\.SMALL/.test(modal) &&
  /maxCount: this\.actionCount\(\)/.test(modal) &&
  /private actionCount\(\): number/.test(modal))
ok('page disables system sheet close because scaffold owns close',
  /SearchFilterSheet\(\{[\s\S]*onClose: \(\) => \{[\s\S]*this\.showFilter = false[\s\S]*\}/.test(page) &&
  /showClose: false/.test(page) &&
  !/title: \{ title: \$r\('app\.string\.filter'\) \}/.test(page))
ok('no Apply button remains',
  !/Button\(\$r\('app\.string\.filter_apply'\)\)/.test(src) &&
  !/filter_apply/.test(src))

console.log(`✓ search filter header action contract: ${passed} assertions passed`)
