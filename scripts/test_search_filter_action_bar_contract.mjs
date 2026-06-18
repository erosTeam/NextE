#!/usr/bin/env node
/**
 * Contract: Search filter sheet actions stay reachable in the default sheet detent.
 *
 * The filter fields may scroll, but Apply and Reset must not live at the end of the scroll content.
 * They are explicit commit actions for the draft filter state, so the sheet needs a fixed action bar.
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
  'eros_fe: lib/pages/filter/gallery_filter_view.dart GalleryFilterView.build() and _getColumnNormal()',
  'primary information: current search scope, gallery categories, rating, page range, and EH filter options',
  'primary action: Apply commits the draft; secondary action: Reset commits the empty filter; close/back cancels',
  'scope: keep Apply/Reset reachable in the sheet default detent; do not change filter fields, query parsing, QuickSearch, tagsuggest, or image search',
  'Harmony expression: sheet Column with Scroll.layoutWeight(1) for fields plus a fixed bottom ActionBar for commit actions',
]

ok('grounding has five lines', grounding.length === 5)
ok('grounding names concrete eros_fe filter file', grounding[0].includes('gallery_filter_view.dart') &&
  grounding[0].includes('GalleryFilterView.build'))
ok('scope excludes unrelated search features', grounding[3].includes('QuickSearch') &&
  grounding[3].includes('tagsuggest') &&
  grounding[3].includes('image search'))

ok('SearchFilterSheet has a dedicated fixed ActionBar builder',
  /@Builder\s+ActionBar\(\)\s*\{[\s\S]*Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*Button\(\$r\('app\.string\.filter_apply'\)\)/.test(src))
ok('build uses a root Column with field Scroll and fixed ActionBar sibling',
  /build\(\)\s*\{[\s\S]*Column\(\)\s*\{[\s\S]*Scroll\(\)\s*\{[\s\S]*\}\s*[\s\S]*\.layoutWeight\(1\)[\s\S]*this\.ActionBar\(\)[\s\S]*\}\s*[\s\S]*\.height\('100%'\)/.test(src))
ok('scroll content is padded independently from the bottom action row',
  /\.padding\(\{\s*left: ThemeConstants\.SPACE_LG,[\s\S]*bottom: ThemeConstants\.SPACE_SM,[\s\S]*\}\)[\s\S]*\.scrollBar\(BarState\.Off\)[\s\S]*\.layoutWeight\(1\)/.test(src))
ok('ActionBar owns the bottom padding and full width',
  /@Builder\s+ActionBar\(\)\s*\{[\s\S]*\.width\('100%'\)[\s\S]*bottom: ThemeConstants\.SPACE_LG/.test(src))
ok('Reset still clears draft before committing',
  /Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*this\.resetDraft\(\)[\s\S]*this\.commitDraft\(\)/.test(src))
ok('Apply still commits draft without reset',
  /Button\(\$r\('app\.string\.filter_apply'\)\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.commitDraft\(\)/.test(src))

const scrollStart = src.indexOf('Scroll() {')
const actionBarCall = src.indexOf('this.ActionBar()')
const actionBarBuilder = src.indexOf('@Builder\n  ActionBar()')
const applyInScroll = src.indexOf("Button($r('app.string.filter_apply'))", scrollStart)
const resetInScroll = src.indexOf("Button($r('app.string.filter_reset'))", scrollStart)
ok('ActionBar is called after the Scroll sibling, not inside field content',
  scrollStart >= 0 && actionBarCall > scrollStart && actionBarBuilder > actionBarCall)
ok('Apply/Reset button declarations live in ActionBar, not before ActionBar builder',
  applyInScroll >= actionBarBuilder && resetInScroll >= actionBarBuilder)

console.log(`✓ search filter action bar contract: ${passed} assertions passed`)
