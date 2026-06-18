#!/usr/bin/env node
/**
 * Contract: Search filter controls must behave like real controls.
 *
 * The sheet uses a native segmented control for scope and V2 child chips for category/rating
 * selection so draft state changes repaint immediately. The page owns one fixed filter entry
 * instead of hiding branch-local triggers in favorite/loading/error/result states.
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
  /TabSegmentButtonV2\(\{[\s\S]*items: this\.scopeItems[\s\S]*selectedIndex: this\.scopeIndex\(\)[\s\S]*enableStateAnimation: true/.test(sheet) &&
  !/@Builder\s+ScopeSegment/.test(sheet))
ok('scope labels come from i18n resources through AppStrings',
  /this\.scopeItems\[0\]\.text = AppStrings\.get\('search_scope_gallery'\)/.test(sheet) &&
  /this\.scopeItems\[2\]\.text = AppStrings\.get\('search_scope_favorite'\)/.test(sheet))
ok('category and rating chips are V2 child components with selected Param',
  /@ComponentV2\s+struct SearchFilterChipButton[\s\S]*@Param selected: boolean = false/.test(sheet) &&
  /SearchFilterChipButton\(\{[\s\S]*label: c\.name[\s\S]*selected: \(this\.draftSelectedCats & c\.bit\) !== 0/.test(sheet) &&
  /SearchFilterChipButton\(\{[\s\S]*label: this\.ratingLabel\(r\)[\s\S]*selected: this\.draftMinRating === r/.test(sheet))
ok('old builder chip with stale selected parameter is gone',
  !/@Builder\s+Chip\(/.test(sheet) &&
  !/Text\(isAny \? \$r\('app\.string\.filter_any'\) : label\)/.test(sheet))
ok('favorite scope is visible and explained instead of hiding the entry',
  /filter_favorite_scope_hint/.test(sheet) &&
  !/if \(!this\.isFavoriteScope\)[\s\S]*this\.FilterTrigger\(\)/.test(page))
ok('page has one fixed filter trigger overlay for all body states',
  /@Builder\s+FilterTriggerOverlay\(\)[\s\S]*this\.FilterTrigger\(\)/.test(page) &&
  /FilterTriggerOverlay\(\)[\s\S]*\.position\(\{[\s\S]*y: this\.layout\.topAvoidHeight \+ ThemeConstants\.TITLE_BAR_HEIGHT \+ ThemeConstants\.SPACE_SM/.test(page) &&
  /Stack\(\)\s*\{[\s\S]*Column\(\)\s*\{[\s\S]*this\.FilterTriggerOverlay\(\)[\s\S]*\.bindSheet/.test(page))

console.log(`✓ search filter UX contract: ${passed} assertions passed`)
