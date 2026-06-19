#!/usr/bin/env node
/**
 * Contract: tab title-bars keep FE's browsing utility action semantics in HDS menu form.
 *
 * FE reference:
 * - eros_fe/lib/pages/tab/view/tabbar/custom_tabbar_page.dart trailing cluster:
 *   search + jump helpers.
 * - eros_fe/lib/pages/tab/controller/group/custom_tabbar_controller.dart:
 *   current sub-list handles jumpToTop/showJumpDialog.
 * - eros_fe/lib/pages/tab/controller/favorite/favorite_tabbar_controller.dart:
 *   delegates jumpToTop to the active favorite sub-list.
 * - eros_fe/lib/pages/tab/view/toplist_page.dart:
 *   exposes title tap and trailing jump-to-top behavior for the active toplist.
 *
 * NextE slice:
 * - Search remains a title-bar action where that scope supports search.
 * - Back-to-top is a reliable utility against the active retained tab Scroller.
 * - Page jump is intentionally not exposed until the EH jump/seek query model exists.
 *
 * Run: node scripts/test_home_title_actions_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const index = read('entry/src/main/ets/pages/Index.ets')
const searchField = read('feature/search/src/main/ets/components/SearchPageField.ets')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const grounding = [
  'eros_fe: custom_tabbar_page.dart, favorite_tabbar_controller.dart, and toplist_page.dart expose scroll-to-top for active list tabs',
  'primary information: the active gallery/favorites/toplist rows remain the first thing users read',
  'actions: search/sort/selector stay primary per tab; back-to-top is a secondary browsing utility; arbitrary page jump waits for EH jump/seek support',
  'scope: active retained Home/Favorites/Toplist scrollers only; no SearchFilter, Reader, Download, or network jump model changes',
  'Harmony expression: HdsNavigation title-bar menu item using sys.symbol.arrow_up and Scroller.scrollToIndex(0)',
]

ok('grounding has five lines', grounding.length === 5)
ok('grounding names concrete eros_fe tab files', grounding[0].includes('custom_tabbar_page.dart') &&
  grounding[0].includes('favorite_tabbar_controller.dart') &&
  grounding[0].includes('toplist_page.dart'))
ok('scope explicitly excludes stale closed lanes', grounding[3].includes('SearchFilter') &&
  grounding[3].includes('Reader') &&
  grounding[3].includes('Download'))

ok('Index defines a single active-scroller back-to-top helper',
  /private\s+scrollActiveTabToTop\(\): void \{\s*this\.titleScroller\.scrollToIndex\(0\)\s*\}/.test(index))
ok('Index wraps back-to-top in one reusable title-menu item',
  /private\s+backToTopMenuItem\(\): Record<string, Object> \{[\s\S]*'label': \$r\('app\.string\.common_back_to_top'\)[\s\S]*'icon': \$r\('sys\.symbol\.arrow_up'\)[\s\S]*this\.scrollActiveTabToTop\(\)[\s\S]*return \{ 'content': topInner \}/.test(index))
ok('Home menu still opens search from the title/menu action area',
  /private\s+searchMenu\(\): Record<string, Object> \{[\s\S]*'label': \$r\('app\.string\.tab_search'\)[\s\S]*this\.openSearch\(\)/.test(index))
ok('Home menu includes a back-to-top action with a system arrow symbol',
  /'label': \$r\('app\.string\.common_back_to_top'\)[\s\S]*'icon': \$r\('sys\.symbol\.arrow_up'\)[\s\S]*this\.scrollActiveTabToTop\(\)/.test(index))
ok('Home menu exposes search and back-to-top inline, not as list content',
  /private\s+searchMenu\(\): Record<string, Object> \{[\s\S]*const items: Record<string, Object>\[\] = \[\s*\{ 'content': searchInner \},\s*this\.backToTopMenuItem\(\),\s*\][\s\S]*return \{ 'value': items, 'maxCount': 2 \}/.test(index))
ok('Favorites logged-in menu preserves search/order/selector and adds back-to-top after them',
  /private\s+favoritesMenu\(\): Record<string, Object> \{[\s\S]*const items: Record<string, Object>\[\] = \[\s*\{ 'content': searchInner \},\s*\{ 'content': orderInner \},\s*\{ 'content': selectorInner \},\s*this\.backToTopMenuItem\(\),\s*\][\s\S]*return \{ 'value': items, 'maxCount': 3 \}/.test(index))
ok('Local Favorites menu keeps selector and adds back-to-top without remote actions',
  /private\s+localFavoritesMenu\(\): Record<string, Object> \{[\s\S]*const items: Record<string, Object>\[\] = \[\s*\{ 'content': selectorInner \},\s*this\.backToTopMenuItem\(\),\s*\][\s\S]*return \{ 'value': items, 'maxCount': 2 \}/.test(index))
ok('Toplist wires a top-only title menu while keeping its period bottomBuilder',
  /if \(this\.currentTab === 2\) \{[\s\S]*content\['bottomBuilder'\] = this\.bottomBuilder\(this\.periodBarContent\)[\s\S]*content\['menu'\] = this\.topOnlyMenu\(\)/.test(index))
ok('Home tab wires the menu through titleBarOpts only',
  /if \(this\.currentTab === 0\) \{[\s\S]*content\['bottomBuilder'\] = this\.bottomBuilder\(this\.sourceBarContent\)[\s\S]*content\['menu'\] = this\.searchMenu\(\)/.test(index))
ok('Search input component does not host the Home filter or navigation action',
  !/common_back_to_top/.test(searchField) &&
  !/scrollToIndex\(0\)/.test(searchField) &&
  !/sys\.symbol\.arrow_up/.test(searchField))
ok('No fake Home page jump dialog is exposed in this slice',
  !/home.*jump/i.test(index) &&
  !/showJumpDialog/.test(index))

console.log(`✓ home title actions contract: ${passed} assertions passed`)
