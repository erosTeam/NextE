#!/usr/bin/env node
/**
 * Contract: action-seeded searches are route/session params, not shared singleton keyword state.
 *
 * Regression: Search(A) -> GalleryDetail -> tap tag B could let an older Search instance consume and
 * clear the app-wide pendingQuery, leaving the new Search page without B. The only global signal now
 * lives in Index; Search pages receive SearchPageParams.initialQuery and own their field state.
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

const index = read('entry/src/main/ets/pages/Index.ets')
const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const params = read('shared/src/main/ets/state/SearchPageParams.ets')
const action = read('shared/src/main/ets/state/SearchActionState.ets')
const field = read('feature/search/src/main/ets/components/SearchPageField.ets')
const appField = read('shared/src/main/ets/components/AppSearchField.ets')
const tags = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')

ok('SearchPageParams carries initial query, focus policy, and session id',
  /initialQuery: string = ''/.test(params) &&
  /focusOnAppear: boolean = true/.test(params) &&
  /sessionId: string = ''/.test(params) &&
  /constructor\([\s\S]*initialQuery: string = ''[\s\S]*focusOnAppear: boolean = true[\s\S]*sessionId: string = ''/.test(params))

ok('Index is the only pendingQuery consumer and pushes a new Search route with route params',
  /@Monitor\('searchAction\.pendingQuery'\)[\s\S]*onPendingQuery\(\): void/.test(index) &&
  /const query: string = sep >= 0 \? pq\.substring\(sep \+ 1\) : pq/.test(index) &&
  /pushPathByName\('Search', new SearchPageParams\('', 'a', query, false, token\)\)/.test(index) &&
  /this\.searchAction\.clearPending\(\)/.test(index))

ok('GallerySearchPage does not monitor or clear global pendingQuery',
  !/@Monitor\('actionState\.pendingQuery'\)/.test(page) &&
  !/consumePendingQuery/.test(page) &&
  !/clearPending\(\)/.test(page) &&
  !/connectSearchAction\(\)/.test(page))

ok('GallerySearchPage consumes route initialQuery into page-owned field state and runs it',
  /p\.initialQuery\.length > 0[\s\S]*this\.fieldState\.keyword = p\.initialQuery[\s\S]*this\.fieldState\.seedSeq = this\.fieldState\.seedSeq \+ 1[\s\S]*this\.runQuery\(p\.initialQuery\)/.test(page))

ok('action-seeded Search cannot focus before route params arrive',
  /@Trace focusOnAppear: boolean = false/.test(field) &&
  /this\.fieldState\.focusOnAppear = p\.focusOnAppear/.test(page) &&
  /\} else \{[\s\S]*this\.fieldState\.focusOnAppear = true/.test(page))

ok('manual Search can still focus after route params flip autoFocus true',
  /@Monitor\('autoFocus'\)[\s\S]*onAutoFocusChange\(\): void/.test(appField) &&
  /if \(this\.autoFocus\) \{[\s\S]*this\.requestSearchFocus\(\)/.test(appField) &&
  /private requestSearchFocus\(\): void \{[\s\S]*requestFocus\(this\.fieldId\)/.test(appField))

ok('Search input state is page-owned, not AppStorageV2 singleton keyword state',
  /@ObservedV2[\s\S]*export class SearchPageFieldState/.test(field) &&
  /@Param fieldState: SearchPageFieldState/.test(field) &&
  !/connectSearchAction\(\)/.test(field) &&
  !/@Trace keyword/.test(action) &&
  !/@Trace submitSeq/.test(action) &&
  !/@Trace seedSeq/.test(action))

ok('detail tag/uploader/similar still publish action searches for Index to route',
  /connectSearchAction\(\)\.publishQuery\(`\$\{namespace\}:\$\{this\.queryTagValue\(tag\)\}`\)/.test(tags) &&
  /connectSearchAction\(\)\.publishQuery\(`title:"\$\{short\}"`\)/.test(detail) &&
  /connectSearchAction\(\)\.publishQuery\(`uploader:"\$\{n\}"`\)/.test(detail))

console.log(`✓ search route session contract: ${passed} assertions passed`)
