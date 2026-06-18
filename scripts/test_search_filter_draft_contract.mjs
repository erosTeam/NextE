#!/usr/bin/env node
/**
 * Contract for SearchFilterSheet's live-edit semantics.
 *
 * User-visible rule: the sheet behaves like eros_fe's filter surface. Scope/category/rating/page/toggle
 * changes update visual state immediately and bump applySeq for persistence/requery. There is no
 * primary Apply button; Reset is the only explicit action and clears the active filter.
 *
 * Run: node scripts/test_search_filter_draft_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const src = read('feature/search/src/main/ets/components/SearchFilterSheet.ets')
const state = read('shared/src/main/ets/state/SearchFilterState.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')

const forbiddenDraftNames = [
  'draftSearchScope',
  'draftSelectedCats',
  'draftMinRating',
  'draftPagesFrom',
  'draftPagesTo',
  'draftRequireTorrent',
  'draftShowExpunged',
  'draftDisableLanguageFilter',
  'draftDisableUploaderFilter',
  'draftDisableTagFilter',
]

forbiddenDraftNames.forEach((name) => {
  ok(`${name} draft state is gone`, !new RegExp(`\\b${name}\\b`).test(src))
})

ok('sheet no longer has openSeq, onApply, or commitDraft',
  !/@Param openSeq: number = 0/.test(src) &&
  !/@Monitor\('openSeq'\)/.test(src) &&
  !/@Event onApply/.test(src) &&
  !/commitDraft/.test(src))
ok('applySeq has one helper and every live setter uses it',
  /private bumpApplySeq\(\): void \{[\s\S]*this\.filter\.applySeq = this\.filter\.applySeq \+ 1/.test(src) &&
  /private setScope\(scope: string\): void \{[\s\S]*this\.filter\.searchScope = scope[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setRating\(rating: number\): void \{[\s\S]*this\.filter\.minRating = rating[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setPagesFrom\(value: number\): void \{[\s\S]*this\.filter\.pagesFrom = value[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setPagesTo\(value: number\): void \{[\s\S]*this\.filter\.pagesTo = value[\s\S]*this\.bumpApplySeq\(\)/.test(src))
ok('category tap and long press write active selectedCats and bump applySeq',
  /private toggleCategory\(c: CatItem\): void \{[\s\S]*this\.filter\.selectedCats = this\.normalizeCats\(next\)[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private soloOrInvertCategory\(c: CatItem\): void \{[\s\S]*this\.filter\.selectedCats = selected \? c\.bit : this\.normalizeCats\(ALL_CATS \^ c\.bit\)[\s\S]*this\.bumpApplySeq\(\)/.test(src))
ok('advanced toggles have typed direct setters that bump applySeq',
  /private setRequireTorrent\(on: boolean\): void \{[\s\S]*this\.filter\.requireTorrent = on[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setShowExpunged\(on: boolean\): void \{[\s\S]*this\.filter\.showExpunged = on[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setDisableLanguageFilter\(on: boolean\): void \{[\s\S]*this\.filter\.disableLanguageFilter = on[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setDisableUploaderFilter\(on: boolean\): void \{[\s\S]*this\.filter\.disableUploaderFilter = on[\s\S]*this\.bumpApplySeq\(\)/.test(src) &&
  /private setDisableTagFilter\(on: boolean\): void \{[\s\S]*this\.filter\.disableTagFilter = on[\s\S]*this\.bumpApplySeq\(\)/.test(src))
ok('reset directly clears active filter and bumps applySeq',
  /private resetFilter\(\): void \{[\s\S]*this\.filter\.searchScope = SEARCH_SCOPE_GALLERY[\s\S]*this\.filter\.disableTagFilter = false[\s\S]*this\.bumpApplySeq\(\)/.test(src))
ok('no Apply button remains in the sheet',
  !/Button\(\$r\('app\.string\.filter_apply'\)\)/.test(src) &&
  !/filter_apply/.test(src))
ok('reset button is wired to resetFilter',
  /Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.resetFilter\(\)/.test(src))
ok('page embeds the sheet without openSeq or close-on-apply callback',
  /@Builder\s+FilterSheet\(\)\s*\{[\s\S]*SearchFilterSheet\(\)[\s\S]*\}/.test(page) &&
  !/filterOpenSeq/.test(page) &&
  !/openSeq: this\.filterOpenSeq/.test(page) &&
  !/onApply:/.test(page))
ok('SearchFilterState remains the active shared state',
  /@ObservedV2[\s\S]*export class SearchFilterState/.test(state) && /@Trace applySeq: number = 0/.test(state))
ok('search page persists and reapplies on applySeq',
  /@Monitor\('filter\.applySeq'\)[\s\S]*SearchFilterSettings\.persist\(this\.ctx\(\)\)[\s\S]*this\.vm\.reapplyFilters\(\)/.test(page))

console.log(`✓ search filter live-edit contract: ${passed} assertions passed`)
