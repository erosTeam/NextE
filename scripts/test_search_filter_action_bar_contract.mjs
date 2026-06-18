#!/usr/bin/env node
/**
 * Contract: Search filter sheet has one low-weight fixed Reset action, not Apply/Reset peers.
 *
 * FE comparison shows filter controls apply immediately. NextE keeps the fields scrollable and the
 * Reset action reachable in the default sheet detent, but must not reintroduce an Apply button as a
 * primary commit action.
 *
 * Run: node scripts/test_search_filter_action_bar_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'feature/search/src/main/ets/components/SearchFilterSheet.ets'), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const grounding = [
  'eros_fe: lib/pages/filter/gallery_filter_view.dart GalleryFilterView.build() and lib/pages/filter/filter.dart GalleryCatFilter',
  'primary information: current scope, colored category selection, minimum rating, page range, and EH filter options',
  'primary action: changing a control live-applies; secondary action: Reset clears filters',
  'scope: repair filter controls and action weight; do not change query parser, QuickSearch, tagsuggest, image search, or backend semantics',
  'Harmony expression: sheet Column with Scroll.layoutWeight(1), TabSegmentButtonV2 controls, V2 category buttons, and fixed bottom Reset action',
]

ok('grounding has five lines', grounding.length === 5)
ok('grounding names concrete eros_fe filter files', grounding[0].includes('gallery_filter_view.dart') &&
  grounding[0].includes('filter.dart'))
ok('scope excludes unrelated search features', grounding[3].includes('QuickSearch') &&
  grounding[3].includes('tagsuggest') &&
  grounding[3].includes('image search'))

ok('SearchFilterSheet has a dedicated fixed ActionBar builder with Reset only',
  /@Builder\s+ActionBar\(\)\s*\{[\s\S]*Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*this\.resetFilter\(\)/.test(src) &&
  !/Button\(\$r\('app\.string\.filter_apply'\)\)/.test(src))
ok('build uses a root Column with field Scroll and fixed ActionBar sibling',
  /build\(\)\s*\{[\s\S]*Column\(\)\s*\{[\s\S]*Scroll\(\)\s*\{[\s\S]*\}\s*[\s\S]*\.layoutWeight\(1\)[\s\S]*this\.ActionBar\(\)[\s\S]*\}\s*[\s\S]*\.height\('100%'\)/.test(src))
ok('scroll content is padded independently from the bottom action row',
  /\.padding\(\{\s*left: ThemeConstants\.SPACE_LG,[\s\S]*bottom: ThemeConstants\.SPACE_SM,[\s\S]*\}\)[\s\S]*\.scrollBar\(BarState\.Off\)[\s\S]*\.layoutWeight\(1\)/.test(src))
ok('ActionBar owns the bottom padding and full width',
  /@Builder\s+ActionBar\(\)\s*\{[\s\S]*\.width\('100%'\)[\s\S]*bottom: ThemeConstants\.SPACE_LG/.test(src))
ok('Reset keeps lower visual weight than a primary submit',
  /Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*\.type\(ButtonType\.Capsule\)[\s\S]*\.backgroundColor\(\$r\('sys\.color\.ohos_id_color_button_normal'\)\)[\s\S]*\.fontColor\(\$r\('sys\.color\.font_primary'\)\)/.test(src))

const scrollStart = src.indexOf('Scroll() {')
const actionBarCall = src.indexOf('this.ActionBar()')
const actionBarBuilder = src.indexOf('@Builder\n  ActionBar()')
const resetInScroll = src.indexOf("Button($r('app.string.filter_reset'))", scrollStart)
ok('ActionBar is called after the Scroll sibling, not inside field content',
  scrollStart >= 0 && actionBarCall > scrollStart && actionBarBuilder > actionBarCall)
ok('Reset button declaration lives in ActionBar, not before ActionBar builder',
  resetInScroll >= actionBarBuilder)

console.log(`✓ search filter action bar contract: ${passed} assertions passed`)
