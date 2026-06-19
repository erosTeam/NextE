#!/usr/bin/env node
/**
 * Contract for Search history retention and per-entry deletion.
 *
 * Grounding:
 * - eros_fe/lib/pages/tab/view/search_page.dart `_searchHistoryBtn*` appends on tap and opens a
 *   delete affordance on long press.
 * - eros_fe/lib/pages/tab/controller/search_page_controller.dart caps history at 100 and persists
 *   removeHistory/clearHistory.
 * - Primary information is recent search terms. Primary action is tap-to-search; secondary actions
 *   are long-press single delete and clear-all.
 * - Scope is history retention/deletion only; translated history and QuickSearch profiles are deferred.
 * - HarmonyOS expression keeps the existing chip list and adds a LongPressGesture + toast.
 *
 * Run: node scripts/test_search_history_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const settings = readFileSync(join(ROOT, 'shared/src/main/ets/settings/SearchHistorySettings.ets'), 'utf8')
const page = readFileSync(join(ROOT, 'feature/search/src/main/ets/pages/GallerySearchPage.ets'), 'utf8')
const fePage = readFileSync(join(ROOT, '../eros_fe/lib/pages/tab/view/search_page.dart'), 'utf8')
const feController = readFileSync(join(ROOT, '../eros_fe/lib/pages/tab/controller/search_page_controller.dart'), 'utf8')

const localeFiles = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('grounding: FE history chip has long-press delete affordance',
  /_searchHistoryBtn[\s\S]*onLongPress[\s\S]*removeHistory\(\)/.test(fePage))
ok('grounding: FE removeHistory persists the remaining list',
  /void removeHistory\(Object\? value\)[\s\S]*searchHistory\.remove\(value\)[\s\S]*hiveHelper\.setSearchHistory/.test(feController))
ok('grounding: FE caps search history at 100',
  /if \(searchHistory\.length > 100\)[\s\S]*removeRange\(100, searchHistory\.length\)/.test(feController))

ok('NextE caps search history at 100', /const MAX_HISTORY: number = 100/.test(settings))
ok('NextE exposes single-entry history removal',
  /static async remove\(context: common\.UIAbilityContext, query: string\): Promise<void>/.test(settings))
ok('remove preserves order and filters the target query',
  /connectSearchHistory\(\)\.items\.forEach\(\(item: string\) => \{[\s\S]*if \(item !== q && next\.length < MAX_HISTORY\)/.test(settings))
ok('remove persists the remaining history',
  /connectSearchHistory\(\)\.items = next[\s\S]*await SearchHistorySettings\.persist\(context, next\)/.test(settings))
ok('restore parse also caps stale stored history',
  /out\.length < MAX_HISTORY/.test(settings))

ok('Search page imports promptAction for delete feedback',
  /import \{ ComponentContent, promptAction \} from '@kit\.ArkUI'/.test(page))
ok('Search page has deleteSearchHistory helper',
  /private deleteSearchHistory\(query: string\): void \{[\s\S]*SearchHistorySettings\.remove\(this\.ctx\(\), query\)[\s\S]*search_history_deleted/.test(page))
ok('History chip tap still searches from history',
  /\.onClick\(\(\) => \{[\s\S]*this\.searchFromHistory\(q\)/.test(page))
ok('History chip long-press deletes one history item',
  /LongPressGesture\(\{ repeat: false, duration: 500 \}\)[\s\S]*this\.deleteSearchHistory\(q\)/.test(page))
ok('Clear-all remains available',
  /SearchHistorySettings\.clear\(this\.ctx\(\)\)/.test(page))

for (const file of localeFiles) {
  const content = readFileSync(join(ROOT, file), 'utf8')
  ok(`${file} defines search_history_deleted`, /"name": "search_history_deleted"/.test(content))
}

console.log(`✓ search history contract: ${passed} assertions passed`)
