#!/usr/bin/env node
/**
 * Contract: Settings exposes a native Search settings/data-management page for existing NextE search
 * state. This is not a QuickSearch expansion lane.
 *
 * Run: node scripts/test_settings_search_entry_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const grounding = [
  'eros_fe: lib/pages/tab/controller/setting_controller.dart routes search to EHRoutes.searchSetting; lib/pages/setting/search_setting_page.dart renders a grouped Search settings child page',
  'primary information: Search settings manages existing search data/profile state, not a new search box',
  'primary actions: clear search history and reset saved filter profile; back is secondary',
  'scope: Settings entry + HDS page for persisted history/filter management; no QuickSearch expansion, image search, parser changes, or search algorithm changes',
  'Harmony expression: HdsNavDestination + SecondaryListScaffold + GroupedListSection + ConciseListRow, matching existing Settings child pages',
]

ok(grounding.length === 5, 'search settings lane has five-line grounding')
ok(grounding[0].includes('setting_controller.dart') && grounding[0].includes('search_setting_page.dart'),
  'grounding names concrete eros_fe Settings files')
ok(grounding[3].includes('no QuickSearch expansion') && grounding[4].includes('HdsNavDestination'),
  'grounding limits scope and names Harmony expression')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const searchPage = read('feature/settings/src/main/ets/pages/SearchSettingsPage.ets')
const filterSettings = read('shared/src/main/ets/settings/SearchFilterSettings.ets')

ok(/export \{ SearchSettingsPage \}/.test(settingsIndex), 'settings module exports SearchSettingsPage')
ok(/SearchSettingsPage/.test(entry) && /name === 'SearchSettings'[\s\S]*SearchSettingsPage\(\)/.test(entry),
  'entry registers SearchSettings route')
ok(/settings_search/.test(settingsRoot) && /pushPathByName\('SearchSettings', null\)/.test(settingsRoot),
  'Settings root exposes a Search row that pushes SearchSettings')

ok(/export struct SearchSettingsPage/.test(searchPage) && /HdsNavDestination/.test(searchPage),
  'SearchSettingsPage is a native HDS destination')
ok(/@Local history: SearchHistoryState = connectSearchHistory\(\)/.test(searchPage),
  'page reads V2 search history state')
ok(/@Local filter: SearchFilterState = connectSearchFilter\(\)/.test(searchPage),
  'page reads V2 search filter state')
ok(/SearchHistorySettings\.clear\(this\.ctx\(\)\)/.test(searchPage),
  'page clears history through SearchHistorySettings')
ok(/confirmClearHistory\(\): void[\s\S]*showAlertDialog[\s\S]*search_history_clear_confirm[\s\S]*common_cancel[\s\S]*action: \(\) => \{[\s\S]*this\.clearHistory\(\)/.test(searchPage),
  'clearing search history is gated by a native confirmation dialog')
ok(/title: \$r\('app\.string\.search_history_clear'\)[\s\S]*action: \(\) => \{[\s\S]*this\.confirmClearHistory\(\)/.test(searchPage),
  'clear-history row opens the confirmation instead of deleting immediately')
ok(/SearchFilterSettings\.reset\(this\.ctx\(\)\)/.test(searchPage),
  'page resets filters through SearchFilterSettings')
ok(!/QuickSearch|quickSearch|ImageSearch|SearchPageField/.test(searchPage),
  'Search settings page does not expand QuickSearch, image search, or embed a search field')

ok(/static async reset\(context: common\.UIAbilityContext\)/.test(filterSettings),
  'SearchFilterSettings exposes reset single-writer')
ok(/f\.searchScope = SEARCH_SCOPE_GALLERY[\s\S]*f\.selectedCats = 0[\s\S]*f\.advancedEnabled = false/.test(filterSettings),
  'reset returns scope/category/advanced switch to defaults')
ok(/f\.disableLanguageFilter = false[\s\S]*f\.disableUploaderFilter = false[\s\S]*f\.disableTagFilter = false[\s\S]*f\.applySeq = f\.applySeq \+ 1/.test(filterSettings),
  'reset clears split advanced toggles and bumps applySeq')
ok(/await SearchFilterSettings\.persist\(context\)/.test(filterSettings),
  'reset persists the clean filter profile')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'settings_search',
    'search_history_clear_confirm',
    'search_settings_history_count',
    'search_settings_history_hint',
    'search_settings_filter_profile',
    'search_settings_filter_hint',
    'search_settings_filter_active',
    'search_settings_filter_clean',
    'search_settings_filter_reset',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ settings search entry contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ settings search entry contract: Search settings route and data actions locked')
