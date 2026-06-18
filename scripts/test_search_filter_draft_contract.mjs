#!/usr/bin/env node
/**
 * Contract for SearchFilterSheet's apply/cancel semantics.
 *
 * User-visible rule: editing the filter sheet is a draft interaction. The active SearchFilterState
 * changes only when Apply or Reset commits. Closing the sheet without applying must not silently
 * change the next search.
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

const draftNames = [
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

draftNames.forEach((name) => {
  ok(`${name} is local draft state`, new RegExp(`@Local ${name}:`).test(src))
})

ok('sheet syncs draft from active filter on appear',
  /aboutToAppear\(\): void \{[\s\S]*this\.syncDraftFromFilter\(\)/.test(src))
ok('sheet accepts an explicit open signal',
  /@Param openSeq: number = 0/.test(src) &&
  /@Monitor\('openSeq'\)[\s\S]*onOpenSeqChanged\(\): void \{[\s\S]*this\.syncDraftFromFilter\(\)/.test(src))
ok('sync reads active filter into draft',
  /private syncDraftFromFilter\(\): void \{[\s\S]*this\.draftSearchScope = this\.filter\.searchScope[\s\S]*this\.draftDisableTagFilter = this\.filter\.disableTagFilter/.test(src))
ok('reset clears draft only before commit',
  /private resetDraft\(\): void \{[\s\S]*this\.draftSearchScope = SEARCH_SCOPE_GALLERY[\s\S]*this\.draftDisableTagFilter = false/.test(src))
ok('commit is the only writer to active filter fields',
  /private commitDraft\(\): void \{[\s\S]*this\.filter\.searchScope = this\.draftSearchScope[\s\S]*this\.filter\.disableTagFilter = this\.draftDisableTagFilter[\s\S]*this\.filter\.applySeq = this\.filter\.applySeq \+ 1[\s\S]*this\.onApply\(\)/.test(src))
ok('apply button commits draft',
  /Button\(\$r\('app\.string\.filter_apply'\)\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.commitDraft\(\)/.test(src))
ok('reset button clears and commits draft',
  /Button\(\$r\('app\.string\.filter_reset'\)\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.resetDraft\(\)[\s\S]*this\.commitDraft\(\)/.test(src))

ok('category chips edit draft selectedCats',
  /this\.Chip\(c\.name, \(this\.draftSelectedCats & c\.bit\) !== 0[\s\S]*this\.draftSelectedCats = this\.draftSelectedCats \^ c\.bit/.test(src))
ok('rating chips edit draft minRating',
  /this\.draftMinRating === r[\s\S]*this\.draftMinRating = r/.test(src))
ok('page inputs edit draft page range',
  /this\.PageInput\(this\.draftPagesFrom[\s\S]*this\.draftPagesFrom = v[\s\S]*this\.PageInput\(this\.draftPagesTo[\s\S]*this\.draftPagesTo = v/.test(src))
ok('advanced toggles edit draft flags',
  /this\.draftRequireTorrent = on[\s\S]*this\.draftShowExpunged = on[\s\S]*this\.draftDisableLanguageFilter = on[\s\S]*this\.draftDisableUploaderFilter = on[\s\S]*this\.draftDisableTagFilter = on/.test(src))
ok('scope segmented control reads and writes draft scope',
  /this\.draftSearchScope === scope[\s\S]*this\.draftSearchScope = scope/.test(src))
ok('favorite scope hides category block based on draft scope',
  /if \(this\.draftSearchScope !== SEARCH_SCOPE_FAVORITE\)/.test(src))

const directWrites = [
  'searchScope',
  'selectedCats',
  'minRating',
  'pagesFrom',
  'pagesTo',
  'requireTorrent',
  'showExpunged',
  'disableLanguageFilter',
  'disableUploaderFilter',
  'disableTagFilter',
].flatMap((field) => {
  const re = new RegExp(`this\\.filter\\.${field}\\s*=`, 'g')
  return [...src.matchAll(re)].map((m) => ({ field, index: m.index ?? 0 }))
})
const commitStart = src.indexOf('private commitDraft(): void')
const commitEnd = src.indexOf('\n  build() {')
ok('active filter writes are confined to commitDraft',
  directWrites.length > 0 && directWrites.every((m) => m.index >= commitStart && m.index < commitEnd))

ok('SearchFilterState remains the active shared state',
  /@ObservedV2[\s\S]*export class SearchFilterState/.test(state) && /@Trace applySeq: number = 0/.test(state))
ok('search page still persists and reapplies only on applySeq',
  /@Monitor\('filter\.applySeq'\)[\s\S]*SearchFilterSettings\.persist\(this\.ctx\(\)\)[\s\S]*this\.vm\.reapplyFilters\(\)/.test(page))
ok('search page sends a new open signal each time the filter sheet opens',
  /@Local filterOpenSeq: number = 0/.test(page) &&
  /SearchFilterSheet\(\{[\s\S]*openSeq: this\.filterOpenSeq/.test(page) &&
  /this\.filterOpenSeq = this\.filterOpenSeq \+ 1[\s\S]*this\.showFilter = true/.test(page))

console.log(`✓ search filter draft contract: ${passed} assertions passed`)
