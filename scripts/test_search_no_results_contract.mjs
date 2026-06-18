#!/usr/bin/env node
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

const classifier = read('shared/src/main/ets/network/EhErrorClassifier.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const baseStrings = read('entry/src/main/resources/base/element/string.json')
const zhStrings = read('entry/src/main/resources/zh_CN/element/string.json')
const enStrings = read('entry/src/main/resources/en_US/element/string.json')
const jaStrings = read('entry/src/main/resources/ja_JP/element/string.json')

ok(/private static looksListNoResults\(body: string\): boolean/.test(classifier), 'classifier has narrow list no-results detector')
ok(/page === 'list' && EhErrorClassifier\.looksListNoResults\(body\)[\s\S]*return null/.test(classifier), 'list no-results is accepted as usable empty page')
ok(/hasMarker\(body, page\)[\s\S]*return null[\s\S]*looksListNoResults\(body\)[\s\S]*return null[\s\S]*looksLogin\(body\)/.test(classifier), 'no-results check runs before logged-out topbar login sniff')
ok(/no hits found/.test(classifier) && /no matching galleries/.test(classifier), 'classifier recognizes EH no-hit wording')
ok(/CardEmptyState\(\{ message: \$r\('app\.string\.search_no_results'\) \}\)/.test(page), 'Search empty result uses search-specific no-results copy')

for (const source of [baseStrings, zhStrings, enStrings, jaStrings]) {
  ok(source.includes('"name": "search_no_results"'), 'search_no_results i18n key exists in one locale file')
}

if (failures > 0) {
  console.error(`\n✗ search no-results contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ search no-results contract passed')
