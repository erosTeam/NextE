#!/usr/bin/env node
/**
 * Contract: viewed-history data must have a reachable user surface.
 *
 * NextE already records viewed galleries after the detail-page debounce. This locks the missing
 * History page + Settings entry so the data is not orphaned.
 *
 * Run: node scripts/test_viewed_history_surface_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
let failures = 0

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

const historyPage = read('feature/user/src/main/ets/pages/ViewedHistoryPage.ets')
const userIndex = read('feature/user/src/main/ets/Index.ets')
const settings = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const index = read('entry/src/main/ets/pages/Index.ets')
const stringsBase = read('entry/src/main/resources/base/element/string.json')
const stringsZh = read('entry/src/main/resources/zh_CN/element/string.json')
const stringsEn = read('entry/src/main/resources/en_US/element/string.json')
const stringsJa = read('entry/src/main/resources/ja_JP/element/string.json')

ok(/export struct ViewedHistoryPage/.test(historyPage), 'ViewedHistoryPage exists')
ok(/@Local history: ViewedHistoryState = connectViewedHistory\(\)/.test(historyPage),
  'History page reads the V2 viewed-history state')
ok(/CardEmptyState\(\{ message: \$r\('app\.string\.history_empty'\) \}\)/.test(historyPage),
  'History page renders an explicit empty state')
ok(/ForEach\(\s*this\.history\.items/.test(historyPage), 'History page renders stored history items')
ok(/new GalleryDetailParams\(item\.gid,\s*item\.token,\s*item\.thumbUrl,\s*this\.titleFor\(item\)\)/.test(historyPage),
  'History item click routes back to GalleryDetail with thumb/title seed in constructor order')
ok(/ViewedHistorySettings\.clear\(this\.ctx\(\)\)/.test(historyPage),
  'History page exposes a clear-history action')
ok(/history_clear/.test(historyPage) && /sys\.symbol\.trash/.test(historyPage),
  'Clear action is in the HDS title-bar menu')

ok(/export \{ ViewedHistoryPage \}/.test(userIndex), 'user module exports ViewedHistoryPage')
ok(/import \{[^}]*ViewedHistoryPage[^}]*\} from 'user'/.test(index),
  'Index imports ViewedHistoryPage')
ok(/name === 'History'[\s\S]*ViewedHistoryPage\(\)/.test(index), 'Index registers the History route')
ok(/title:\s*\$r\('app\.string\.tab_history'\)[\s\S]*pushPathByName\('History',\s*null\)/.test(settings),
  'Settings root exposes a History row that pushes History route')

for (const text of [stringsBase, stringsZh, stringsEn, stringsJa]) {
  ok(/"name": "tab_history"/.test(text), 'locale includes tab_history')
  ok(/"name": "history_empty"/.test(text), 'locale includes history_empty')
  ok(/"name": "history_clear"/.test(text), 'locale includes history_clear')
}

if (failures > 0) {
  console.error(`\n✗ viewed-history surface contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ viewed-history surface contract passed')
