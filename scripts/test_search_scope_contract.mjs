#!/usr/bin/env node
/**
 * Contract for eros_fe search type parity:
 * Gallery / Watched / Favorite is a first-class search scope, surfaced in the filter sheet and
 * routed through the correct EH endpoint.
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

const state = read('shared/src/main/ets/state/SearchFilterState.ets')
ok('gallery scope constant exists', /SEARCH_SCOPE_GALLERY:\s*string\s*=\s*'gallery'/.test(state))
ok('watched scope constant exists', /SEARCH_SCOPE_WATCHED:\s*string\s*=\s*'watched'/.test(state))
ok('favorite scope constant exists', /SEARCH_SCOPE_FAVORITE:\s*string\s*=\s*'favorite'/.test(state))
ok('state carries trace searchScope defaulting to gallery', /@Trace\s+searchScope:\s*string\s*=\s*SEARCH_SCOPE_GALLERY/.test(state))
ok('scope participates in active filter state', /searchScope !== SEARCH_SCOPE_GALLERY/.test(state))

const sheet = read('feature/search/src/main/ets/components/SearchFilterSheet.ets')
ok('sheet imports scope constants', /SEARCH_SCOPE_GALLERY[\s\S]*SEARCH_SCOPE_WATCHED[\s\S]*SEARCH_SCOPE_FAVORITE/.test(sheet))
ok('sheet renders all three search scope choices', /search_scope_gallery/.test(sheet) && /search_scope_watched/.test(sheet) && /search_scope_favorite/.test(sheet))
ok('sheet uses the native segmented button for scope selection',
  /TabSegmentButtonV2\(\{[\s\S]*selectedIndex: this\.scopeIndex\(\)[\s\S]*this\.draftSearchScope = this\.scopeForIndex\(index\)/.test(sheet))
ok('sheet explains favorite scope while hiding gallery-only filters from the draft scope',
  /if \(this\.draftSearchScope === SEARCH_SCOPE_FAVORITE\)[\s\S]*filter_favorite_scope_hint/.test(sheet) &&
  /if \(this\.draftSearchScope !== SEARCH_SCOPE_FAVORITE\)[\s\S]*filter_category[\s\S]*filter_options/.test(sheet))
ok('sheet reset returns draft to gallery before committing scope',
  /private resetDraft\(\): void \{[\s\S]*this\.draftSearchScope = SEARCH_SCOPE_GALLERY/.test(sheet) &&
  /private commitDraft\(\): void \{[\s\S]*this\.filter\.searchScope = this\.draftSearchScope[\s\S]*this\.filter\.applySeq = this\.filter\.applySeq \+ 1/.test(sheet))

const settings = read('shared/src/main/ets/settings/SearchFilterSettings.ets')
ok('settings snapshot persists scope', /class SearchFilterSnapshot[\s\S]*scope:\s*string\s*=\s*SEARCH_SCOPE_GALLERY/.test(settings))
ok('settings restore writes searchScope', /f\.searchScope = snap\.scope/.test(settings))
ok('settings persist sanitizes searchScope', /snap\.scope = SearchFilterSettings\.sanitizeScope\(f\.searchScope\)/.test(settings))
ok('settings rejects unknown scopes to gallery', /scope === SEARCH_SCOPE_WATCHED \|\| scope === SEARCH_SCOPE_FAVORITE[\s\S]*return SEARCH_SCOPE_GALLERY/.test(settings))

const vm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
ok('view model imports watched/favorite scopes', /SEARCH_SCOPE_FAVORITE[\s\S]*SEARCH_SCOPE_WATCHED/.test(vm))
ok('watched scope routes gallery query to watched source', /source:\s*f\.searchScope === SEARCH_SCOPE_WATCHED \? 'watched' : ''/.test(vm))
ok('favorite scope uses favorites endpoint', /effectiveFavoriteScope\(\)[\s\S]*searchScope === SEARCH_SCOPE_FAVORITE[\s\S]*getFavoritesList/.test(vm))
ok('filter favorite searches all favorite slots', /favcat:\s*this\.isFavoriteScope \? this\.favcat : 'a'/.test(vm))

const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
ok('empty query can browse when filter scope is active', /trimmed\.length === 0 && !this\.filter\.isActive\(\)/.test(page))
ok('route favorite scope remains a hard page mode', /this\.isFavoriteScope = true[\s\S]*this\.vm\.seedFavoriteScope\(p\.favcat\)/.test(page))
ok('search page keeps filter entry visible in favorite/loading/error/result states',
  /@Builder\s+FilterTriggerOverlay\(\)[\s\S]*this\.FilterTrigger\(\)/.test(page) &&
  /Stack\(\)\s*\{[\s\S]*Column\(\)\s*\{[\s\S]*PageLoadingState\(\)[\s\S]*PageErrorState\(\{[\s\S]*CardEmptyState\(\{[\s\S]*PullRefreshGridScaffold\(\{[\s\S]*PullRefreshListScaffold\(\{[\s\S]*this\.FilterTriggerOverlay\(\)/.test(page) &&
  !/if \(!this\.isFavoriteScope\)[\s\S]*this\.FilterTrigger\(\)/.test(page))

console.log(`✓ search scope contract: ${passed} assertions passed`)
