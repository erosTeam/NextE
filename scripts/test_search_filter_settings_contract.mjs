#!/usr/bin/env node
/**
 * Contract test for advanced-search filter persistence:
 *   shared/src/main/ets/settings/SearchFilterSettings.ets (snapshot serialize / defensive parse / restore)
 *
 * The functions below are copy-equal to that ArkTS logic (no preferences runtime — pure data). They
 * lock the eros_fe parity (advanced-search profile survives restart):
 *   • the scope + filter fields round-trip through JSON.
 *   • parse is defensive: bad JSON / shape → null; bad/negative/missing fields → safe defaults.
 *   • applySeq (a transient signal) is NOT persisted.
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_search_filter_settings_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SEARCH_SCOPE_GALLERY = 'gallery'
const SEARCH_SCOPE_WATCHED = 'watched'
const SEARCH_SCOPE_FAVORITE = 'favorite'
const sanitizeScope = (scope) =>
  scope === SEARCH_SCOPE_WATCHED || scope === SEARCH_SCOPE_FAVORITE ? scope : SEARCH_SCOPE_GALLERY

// Mirror of SearchFilterSettings: snapshot fields = the persistable subset of SearchFilterState.
const snapshotOf = (f) => ({
  scope: sanitizeScope(f.searchScope),
  cats: f.selectedCats,
  rating: f.minRating,
  pf: f.pagesFrom,
  pt: f.pagesTo,
  torrent: f.requireTorrent,
  expunged: f.showExpunged,
  // eros_fe's three independent disable-default-filter toggles (legacy `nodefault` is read-only on restore).
  sfl: f.disableLanguageFilter,
  sfu: f.disableUploaderFilter,
  sft: f.disableTagFilter,
})
const serialize = (snap) => JSON.stringify(snap)
function parse(raw) {
  let o
  try {
    o = JSON.parse(raw)
  } catch {
    return null
  }
  if (o === null || typeof o !== 'object' || Array.isArray(o)) return null
  return {
    scope: sanitizeScope(o.scope),
    cats: typeof o.cats === 'number' && o.cats >= 0 ? o.cats : 0,
    rating: typeof o.rating === 'number' && o.rating >= 0 ? o.rating : 0,
    pf: typeof o.pf === 'number' && o.pf >= 0 ? o.pf : 0,
    pt: typeof o.pt === 'number' && o.pt >= 0 ? o.pt : 0,
    torrent: o.torrent === true,
    expunged: o.expunged === true,
    sfl: o.sfl === true,
    sfu: o.sfu === true,
    sft: o.sft === true,
    nodefault: o.nodefault === true,
  }
}
// Mirror of restore(): a parsed snapshot writes back onto the filter state fields. The legacy single
// `nodefault` migrates onto all three when no per-filter key is set.
function restore(snap) {
  return {
    searchScope: snap.scope,
    selectedCats: snap.cats,
    minRating: snap.rating,
    pagesFrom: snap.pf,
    pagesTo: snap.pt,
    requireTorrent: snap.torrent,
    showExpunged: snap.expunged,
    disableLanguageFilter: snap.sfl || snap.nodefault,
    disableUploaderFilter: snap.sfu || snap.nodefault,
    disableTagFilter: snap.sft || snap.nodefault,
  }
}

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (a, b) => {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)])
  for (const key of keys) {
    if (a[key] !== b[key]) return false
  }
  return true
}

// 1. full round-trip: a populated filter state survives serialize → parse → restore
{
  const f = {
    selectedCats: 1021, // some categories excluded
    minRating: 4,
    pagesFrom: 10,
    pagesTo: 200,
    requireTorrent: true,
    showExpunged: false,
    disableLanguageFilter: true,
    disableUploaderFilter: false,
    disableTagFilter: true,
    searchScope: SEARCH_SCOPE_WATCHED,
    applySeq: 99, // transient — must NOT travel
  }
  const restored = restore(parse(serialize(snapshotOf(f))))
  ok('scope round-trip', restored.searchScope === SEARCH_SCOPE_WATCHED)
  ok('cats round-trip', restored.selectedCats === 1021)
  ok('rating round-trip', restored.minRating === 4)
  ok('pagesFrom round-trip', restored.pagesFrom === 10)
  ok('pagesTo round-trip', restored.pagesTo === 200)
  ok('torrent round-trip', restored.requireTorrent === true)
  ok('expunged round-trip', restored.showExpunged === false)
  ok('disableLanguageFilter round-trip', restored.disableLanguageFilter === true)
  ok('disableUploaderFilter round-trip (independent false)', restored.disableUploaderFilter === false)
  ok('disableTagFilter round-trip', restored.disableTagFilter === true)
  ok('applySeq not persisted', !('applySeq' in restored) && serialize(snapshotOf(f)).indexOf('applySeq') < 0)
}

// 2. defaults (empty filter) round-trip cleanly
{
  const f = {
    selectedCats: 0,
    minRating: 0,
    pagesFrom: 0,
    pagesTo: 0,
    requireTorrent: false,
    showExpunged: false,
    disableLanguageFilter: false,
    disableUploaderFilter: false,
    disableTagFilter: false,
    searchScope: SEARCH_SCOPE_GALLERY,
  }
  ok('empty filter round-trips', eq(restore(parse(serialize(snapshotOf(f)))), f))
}

// 2c. favorite scope persists, while unknown scopes fall back to gallery.
{
  const fav = restore(parse(JSON.stringify({ scope: SEARCH_SCOPE_FAVORITE })))
  ok('favorite scope restores', fav.searchScope === SEARCH_SCOPE_FAVORITE)
  const bad = restore(parse(JSON.stringify({ scope: 'archive' })))
  ok('invalid scope → gallery', bad.searchScope === SEARCH_SCOPE_GALLERY)
}

// 2b. legacy migration: an old snapshot with only `nodefault:true` restores all three toggles on.
{
  const r = restore(parse(JSON.stringify({ cats: 0, nodefault: true })))
  ok('legacy nodefault → disableLanguageFilter', r.disableLanguageFilter === true)
  ok('legacy nodefault → disableUploaderFilter', r.disableUploaderFilter === true)
  ok('legacy nodefault → disableTagFilter', r.disableTagFilter === true)
}

// 3. defensive parse: malformed / wrong shape → null (no silent coercion of non-objects)
{
  ok('bad JSON → null', parse('{not json') === null)
  ok('null literal → null', parse('null') === null)
  ok('array → null', parse('[]') === null)
  ok('primitive number → null', parse('5') === null)
  ok('primitive string → null', parse('"x"') === null)
}

// 4. defensive parse: bad / negative / missing fields → safe defaults; bools coerced strictly
{
  const s = parse(JSON.stringify({ cats: -5, rating: 'high', pf: 3, torrent: 'yes', sfl: true, sft: 'x' }))
  ok('negative cats → 0', s.cats === 0)
  ok('non-number rating → 0', s.rating === 0)
  ok('valid pf kept', s.pf === 3)
  ok('missing pt → 0', s.pt === 0)
  ok('truthy-string torrent → false (strict ===true)', s.torrent === false)
  ok('missing expunged → false', s.expunged === false)
  ok('explicit true sfl kept', s.sfl === true)
  ok('truthy-string sft → false (strict ===true)', s.sft === false)
  ok('missing sfu → false', s.sfu === false)
}

// 5. structural: the .ets wiring exists (restore at bootstrap, persist on live edit/reset, key registered)
{
  const read = (p) => readFileSync(join(ROOT, p), 'utf8')
  const boot = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
  ok('bootstrap restores filters', /SearchFilterSettings\.restore\(/.test(boot))
  const page = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
  ok('live apply persists filters', /@Monitor\('filter\.applySeq'\)[\s\S]*SearchFilterSettings\.persist\(this\.ctx\(\)\)/.test(page))
  const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
  ok('storage key registered', /SEARCH_FILTER: string = 'search\.filter'/.test(keys))
  const settings = read('shared/src/main/ets/settings/SearchFilterSettings.ets')
  ok('snapshot never carries applySeq', !/snap\.applySeq/.test(settings) && !/applySeq:/.test(settings))
  ok('persist serializes scope + three split fields', /snap\.scope[\s\S]*snap\.cats[\s\S]*snap\.sfl[\s\S]*snap\.sfu[\s\S]*snap\.sft/.test(settings))
  ok('restore migrates legacy nodefault onto the three', /disableLanguageFilter = snap\.sfl \|\| snap\.nodefault/.test(settings))
  ok('restore writes scope before filters', /f\.searchScope = snap\.scope[\s\S]*f\.selectedCats = snap\.cats/.test(settings))
  ok('parse sanitizes scope', /s\.scope = SearchFilterSettings\.sanitizeScope\(o\.scope\)/.test(settings))
  ok('parse rejects non-object blobs', /typeof parsed !== 'object' \|\| Array\.isArray\(parsed\)/.test(settings))
  // Reset must bump applySeq so disk doesn't keep a stale filter.
  const sheet = read('feature/search/src/main/ets/components/SearchFilterSheet.ets')
  ok('reset live-applies (bumps applySeq)', /private resetFilter\(\): void \{[\s\S]*selectedCats = 0[\s\S]*this\.bumpApplySeq\(\)/.test(sheet))
  ok('reset returns search scope to gallery', /private resetFilter\(\): void \{[\s\S]*searchScope = SEARCH_SCOPE_GALLERY[\s\S]*selectedCats = 0/.test(sheet))
}

console.log(`✓ search filter settings contract: ${passed} assertions passed`)
