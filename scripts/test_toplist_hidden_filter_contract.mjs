#!/usr/bin/env node
/**
 * Contract: Toplist My Tags hide filtering is local and independent from Advanced Search f_sft.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

const api = read('shared/src/main/ets/network/EhApiService.ets')
assert.match(api, /applyToplistHiddenUserTags: boolean \/\/ local-only: hide Toplist rows carrying My Tags hidden tags/, 'query has explicit Toplist-only field')
assert.match(api, /if \(query\.source === 'toplist'\) \{[\s\S]*return query\.applyToplistHiddenUserTags \? this\.filterHidden\(list\) : list[\s\S]*\n    \}/, 'Toplist branch applies local hidden filter only when enabled')
assert.doesNotMatch(/if \(query\.source === 'toplist'\) \{[\s\S]*?\n    \}/.exec(api)?.[0] ?? '', /disableTagFilter|f_sft/, 'Toplist branch must not reuse Advanced Search f_sft/disableTagFilter')

const homeVm = read('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets')
assert.match(homeVm, /connectToplistFilter\(\)\.applyHiddenUserTags/, 'Toplist query reads the dedicated Toplist filter state')
assert.match(homeVm, /applyToplistHiddenUserTags: this\.isToplist\(\)[\s\S]*: false/, 'Only Toplist requests enable the local hidden-filter field')

const searchVm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
assert.match(searchVm, /disableTagFilter: f\.disableTagFilter[\s\S]*applyToplistHiddenUserTags: false/, 'Search keeps f_sft separate and never enables Toplist local filtering')

const settingsState = read('shared/src/main/ets/state/ToplistFilterState.ets')
assert.match(settingsState, /@Trace applyHiddenUserTags: boolean = true/, 'Toplist hidden-filter setting defaults on')

const settings = read('shared/src/main/ets/settings/ToplistFilterSettings.ets')
assert.match(settings, /DEFAULT_APPLY_HIDDEN: boolean = true/, 'Persisted setting default is true')
assert.match(settings, /StorageKeys\.TOPLIST_APPLY_HIDDEN_USER_TAGS/, 'Setting persists under its own storage key')

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
assert.match(bootstrap, /ToplistFilterSettings\.restore\(context\)/, 'Setting is restored during bootstrap')

const page = read('feature/settings/src/main/ets/pages/EhSettingsPage.ets')
assert.match(page, /eh_settings_toplist_hidden_filter[\s\S]*hasSwitch: true[\s\S]*checked: this\.toplistFilter\.applyHiddenUserTags/, 'EH Settings exposes a switch row for Toplist hidden filtering')

const toplistPage = read('feature/home/src/main/ets/components/ToplistPeriodPage.ets')
assert.match(toplistPage, /@Monitor\('toplistFilter\.applyHiddenUserTags'\)[\s\S]*this\.vm\.reload\(\)/, 'Retained Toplist pages reload when the switch changes')

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  assert.match(strings, /"name": "eh_settings_toplist_hidden_filter"/, `${locale} has Toplist filter title`)
  assert.match(strings, /"name": "eh_settings_toplist_hidden_filter_hint"/, `${locale} has Toplist filter hint`)
}

console.log('✓ toplist hidden-tag filter contract passed')
