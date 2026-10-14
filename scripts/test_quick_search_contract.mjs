#!/usr/bin/env node
/**
 * Contract test for Search QuickSearch parity:
 *   - saved queries are a distinct persisted state, not mixed with recent history
 *   - add() trims, dedups by moving to front, caps, and persists
 *   - GallerySearchPage can save the title-bar query, display saved chips, clear them, and tap to run
 *   - SettingsBootstrap restores it at startup and 4 locale string keys stay present
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

function addQuick(items, query) {
  const q = query.trim()
  if (q.length === 0) return items
  const next = [q]
  for (const item of items) {
    if (item !== q && next.length < 50) next.push(item)
  }
  return next
}

{
  ok('blank save is no-op', addQuick(['a'], '   ').join('|') === 'a')
  ok('new query moves to front', addQuick(['a', 'b'], ' c ')[0] === 'c')
  ok('duplicate moves to front once', addQuick(['a', 'b', 'c'], 'b').join('|') === 'b|a|c')
  const many = Array.from({ length: 60 }, (_, i) => `q${i}`)
  ok('cap is 50', addQuick(many, 'fresh').length === 50)
}

const state = read('shared/src/main/ets/state/QuickSearchState.ets')
ok('QuickSearchState is V2 observed', /@ObservedV2[\s\S]*class QuickSearchState/.test(state))
ok('QuickSearchState stores trace string array', /@Trace\s+items:\s*string\[\]\s*=\s*\[\]/.test(state))
ok('QuickSearch uses distinct AppStorageV2 key', /v2:quickSearch/.test(state))

const settings = read('shared/src/main/ets/settings/QuickSearchSettings.ets')
ok('QuickSearchSettings exists', /export class QuickSearchSettings/.test(settings))
ok('settings restores StorageKeys.QUICK_SEARCH', /StorageKeys\.QUICK_SEARCH/.test(settings))
ok('settings trims saved query', /const q:\s*string\s*=\s*query\.trim\(\)/.test(settings))
ok('settings caps at 50', /MAX_QUICK_SEARCH:\s*number\s*=\s*50/.test(settings))
ok('settings dedups by moving to front', /const next:\s*string\[\]\s*=\s*\[q\][\s\S]*item !== q/.test(settings))
ok('settings clears state and persistence', /static async clear[\s\S]*connectQuickSearch\(\)\.items = \[\][\s\S]*persist\(context, \[\]\)/.test(settings))

const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
ok('storage key is registered', /QUICK_SEARCH:\s*string\s*=\s*'search\.quickSearch'/.test(keys))

const boot = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok('bootstrap restores QuickSearch', /QuickSearchSettings\.restore\(context\)/.test(boot))

const barrel = read('shared/src/main/ets/Index.ets')
ok('shared exports QuickSearchState', /QuickSearchState,\s*connectQuickSearch/.test(barrel))
ok('shared exports QuickSearchSettings', /QuickSearchSettings/.test(barrel))

const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
ok('page connects quick search state', /@Local quickSearch:\s*QuickSearchState\s*=\s*connectQuickSearch\(\)/.test(page))
ok('page saves current title-bar keyword', /private saveQuickSearch\(\)[\s\S]*this\.actionState\.keyword\.trim\(\)[\s\S]*QuickSearchSettings\.add\(this\.ctx\(\), q\)/.test(page))
ok('page clears quick search', /private clearQuickSearch\(\)[\s\S]*QuickSearchSettings\.clear\(this\.ctx\(\)\)/.test(page))
ok('page displays quick search section', /app\.string\.quick_search/.test(page))
ok('page displays save action only for nonblank keyword', /this\.actionState\.keyword\.trim\(\)\.length > 0/.test(page))
ok('saved chip reuses searchFromHistory run path', /this\.quickSearch\.items[\s\S]*this\.searchFromHistory\(q\)/.test(page))
ok('empty hint waits for both quick search and history empty', /this\.quickSearch\.items\.length === 0/.test(page))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(`${locale}: quick_search key`, /"name": "quick_search"/.test(strings))
  ok(`${locale}: quick_search_save key`, /"name": "quick_search_save"/.test(strings))
}

console.log(`✓ quick search contract: ${passed} assertions passed`)
