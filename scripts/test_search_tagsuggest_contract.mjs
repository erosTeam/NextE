#!/usr/bin/env node
import fs from 'node:fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
const ok = (name, cond) => {
  if (!cond) {
    console.error(`✗ ${name}`)
    process.exitCode = 1
  } else {
    console.log(`✓ ${name}`)
  }
}

const api = read('shared/src/main/ets/network/EhApiPhpService.ets')
const constants = read('shared/src/main/ets/constants/EhConstants.ets')
const vm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const field = read('feature/search/src/main/ets/components/SearchPageField.ets')

ok('EhApiPhpService exposes method=tagsuggest',
  /class TagSuggestRequest[\s\S]*method:\s*string\s*=\s*'tagsuggest'/.test(api))
ok('tagsuggest posts JSON to /api.php and parses ns/tn values',
  /postJson\([\s\S]*`\$\{base\}\/api\.php`[\s\S]*JSON\.stringify\(req\)/.test(api) &&
  /entry\.ns[\s\S]*entry\.tn/.test(api))
ok('namespace compaction mirrors eros_fe shortName query prefixes',
  /static compactNamespace\(ns: string\): string/.test(constants) &&
  /full === 'artist'[\s\S]*return 'a'/.test(constants) &&
  /full === 'female'[\s\S]*return 'f'/.test(constants) &&
  /full === 'cosplayer'[\s\S]*return 'cos'/.test(constants))

ok('SearchViewModel debounces suggestions on the last token',
  /const TAG_SUGGEST_DELAY_MS:\s*number\s*=\s*450/.test(vm) &&
  /lastSuggestToken\(query: string\)/.test(vm) &&
  /this\.suggestTimer = setTimeout\(\(\) => \{[\s\S]*this\.fetchSuggestions\(token, myEpoch\)/.test(vm))

ok('SearchViewModel last-token split uses space semicolon and quote delimiters',
  /const parts:\s*string\[\]\s*=\s*trimmed\.split\(\s*\/\[ ;"\]\/\s*\)/.test(vm))
ok('SearchViewModel does not resuggest completed exact/namespaced tokens',
  /token\.indexOf\(':'\) >= 0 \|\| token\.endsWith\('\$'\)/.test(vm))
ok('SearchViewModel clears suggestions on submit/clear',
  /this\.clearSuggestions\(\)[\s\S]*this\.query = trimmed/.test(vm) &&
  /clearSearchState\(\): void \{[\s\S]*this\.clearSuggestions\(\)/.test(vm))
ok('Search page schedules suggestions from the page-owned field state',
  /@Monitor\('fieldState\.keyword'\)[\s\S]*this\.vm\.scheduleTagSuggest\(this\.fieldState\.keyword\)/.test(page))
ok('Search page formats clicked suggestions as exact EH tag queries',
  /private formatSuggestionQuery\(s: EhTagSuggestion\): string \{[\s\S]*return EhConstants\.exactTagSearchQuery\(s\.namespace, s\.text\)[\s\S]*\}/.test(page))
ok('Search page replaces only the last token and re-seeds the input field',
  /private replaceLastToken\(query: string, replacement: string\): string/.test(page) &&
  /this\.fieldState\.seedSeq = this\.fieldState\.seedSeq \+ 1/.test(page))
ok('Search suggestions render as body content, while field stays input-only',
  /SearchSuggestionView\(\)/.test(page) &&
  /this\.vm\.suggestionCount > 0[\s\S]*this\.SearchSuggestionView\(\)/.test(page) &&
  !/sys\.symbol\.funnel|showFilter|FilterSheet|FilterTrigger/.test(field))

if (process.exitCode) {
  process.exit(process.exitCode)
}
