#!/usr/bin/env node
/**
 * Contract test for search input handling (eros_fe _delayedSearch parity):
 *   feature/search/src/main/ets/pages/GallerySearchPage.ets  (runQuery: URL-jump vs search vs noop)
 *   feature/search/src/main/ets/viewmodel/SearchViewModel.ets (empty-query-allowed-when-filter guard)
 *
 * The functions below are copy-equal to that logic (no nav/network — pure routing decisions):
 *   • a pasted BARE gallery URL (/g/{gid}/{token}, e-/ex-hentai) jumps to the detail (no search).
 *   • a pasted BARE image-page URL (/s/{imgkey}/{gid}-{page}) resolves and jumps to Reader.
 *     Gated on a whole-string URL (eros_fe searchText.isURL) so a query that merely EMBEDS a URL
 *     still searches.
 *   • an empty query runs ONLY to browse by active filters (NextE enhancement, not eros_fe); else noop.
 *   • a non-empty, non-URL query records history + searches.
 * The gallery regex is the EhUrlRouter.GALLERY_RE verbatim. If the .ets logic changes, mirror here.
 *
 * Run: node scripts/test_search_input_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of EhUrlRouter route regexes.
const GALLERY_RE = /https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-z]+)/
const IMAGE_RE = /https?:\/\/(?:e-|ex)hentai\.org\/s\/([0-9a-z]+)\/(\d+)-(\d+)/
const parseGallery = (url) => {
  const m = url.match(GALLERY_RE)
  return m ? { gid: m[1], token: m[2] } : null
}
const parseImagePage = (url) => {
  const m = url.match(IMAGE_RE)
  return m ? { imgkey: m[1], gid: m[2], page: Number.parseInt(m[3], 10) } : null
}

// Mirror of GallerySearchPage.looksLikeBareUrl: whole-string URL gate (eros_fe searchText.isURL).
const looksLikeBareUrl = (s) =>
  s.length > 0 && !s.includes(' ') && (s.startsWith('http://') || s.startsWith('https://'))

// Mirror of GallerySearchPage.runQuery routing decision.
function route(query, filterActive) {
  const trimmed = query.trim()
  if (looksLikeBareUrl(trimmed)) {
    const ref = parseGallery(trimmed)
    if (ref !== null) return { kind: 'gallery', ref }
    const image = parseImagePage(trimmed)
    if (image !== null) return { kind: 'imagePage', ref: image }
  }
  if (trimmed.length === 0 && !filterActive) return { kind: 'noop' }
  return { kind: 'search', query: trimmed, recordsHistory: trimmed.length > 0 }
}

// Mirror of SearchViewModel.search() entry guard and reapplyFilters() guard.
const shouldSearch = (query, isLoading, filterActive) =>
  !isLoading && !(query.trim().length === 0 && !filterActive)
const shouldReapply = (queryLen, filterActive) => queryLen > 0 || filterActive

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// 1. pasted gallery URL → jump to detail, never a search
{
  const r = route('https://e-hentai.org/g/1234567/abcdef0123', false)
  ok('e-hentai URL → gallery', r.kind === 'gallery')
  ok('parses gid', r.ref.gid === '1234567')
  ok('parses token', r.ref.token === 'abcdef0123')
  ok('exhentai URL → gallery', route('https://exhentai.org/g/42/deadbeef', false).kind === 'gallery')
  ok('gallery token allows a-z', route('https://e-hentai.org/g/42/z9token', false).kind === 'gallery')
  // trailing path/query after the token still routes (regex is unanchored, as in EhUrlRouter)
  ok('URL with trailing junk', route('https://e-hentai.org/g/9/a0b1?p=2#x', false).kind === 'gallery')
}

// 2. plain search term → search (+ records history)
{
  const r = route('naruto parody', false)
  ok('term → search', r.kind === 'search')
  ok('term records history', r.recordsHistory === true)
  ok('term query trimmed', route('  comic  ', false).query === 'comic')
}

// 3. empty query browses ONLY when filters are active
{
  ok('empty + no filter → noop', route('', false).kind === 'noop')
  ok('whitespace + no filter → noop', route('   ', false).kind === 'noop')
  const r = route('', true)
  ok('empty + filter → search (browse)', r.kind === 'search')
  ok('empty browse records no history', r.recordsHistory === false)
}

// 4. a non-EH URL is treated as a normal search term; a bare /s/ image-page URL jumps
{
  ok('non-EH URL → search', route('https://example.com/g/1/abc', false).kind === 'search')
  const r = route('https://e-hentai.org/s/zkey/123-37', false)
  ok('e-hentai /s/ image-page URL → imagePage', r.kind === 'imagePage')
  ok('image-page imgkey allows a-z', r.ref.imgkey === 'zkey')
  ok('image-page page parsed', r.ref.page === 37)
}

// 4b. a query that merely EMBEDS a gallery URL still searches (whole-string gate, eros_fe isURL)
{
  ok(
    'embedded URL in text → search',
    route('naruto https://e-hentai.org/g/1234567/abcdef0123 parody', false).kind === 'search',
  )
  ok('quoted title w/ URL → search', route('title:"x https://e-hentai.org/g/1/abc y"', false).kind === 'search')
  ok('bare /g/ URL still jumps', route('https://e-hentai.org/g/1/abc', false).kind === 'gallery')
}

// 5. VM search guard: empty allowed only with active filter; loading always blocks
{
  ok('vm: term searches', shouldSearch('x', false, false) === true)
  ok('vm: empty+nofilter blocked', shouldSearch('', false, false) === false)
  ok('vm: empty+filter allowed', shouldSearch('', false, true) === true)
  ok('vm: loading blocks even with filter', shouldSearch('', true, true) === false)
}

// 6. reapplyFilters: re-runs on query OR filter-only browse
{
  ok('reapply with query', shouldReapply(5, false) === true)
  ok('reapply filter-only', shouldReapply(0, true) === true)
  ok('reapply noop when neither', shouldReapply(0, false) === false)
}

// 7. structural: the wiring exists in the .ets
{
  const pageSrc = readFileSync(
    join(ROOT, 'feature/search/src/main/ets/pages/GallerySearchPage.ets'),
    'utf8',
  )
  ok('page routes via runQuery', /private runQuery\(query: string\)/.test(pageSrc))
  ok('page gates URL-jump on a bare URL', /private looksLikeBareUrl\(s: string\)/.test(pageSrc))
  ok('page jump guarded by looksLikeBareUrl', /if \(this\.looksLikeBareUrl\(trimmed\)\)/.test(pageSrc))
  ok('page detects gallery URL', /EhUrlRouter\.parseGallery\(trimmed\)/.test(pageSrc))
  ok('page detects image-page URL', /EhUrlRouter\.parseImagePage\(trimmed\)/.test(pageSrc))
  ok('page jumps to detail on URL', /pushPathByName\(\s*'GalleryDetail'/.test(pageSrc))
  ok('page resolves image-page URL', /ImagePageRouteService\.resolve\(url\)/.test(pageSrc))
  ok('page jumps image-page URL to reader', /pushPathByName\(\s*'Reader'/.test(pageSrc))
  ok('page shows visible image-page failure instead of searching the URL', /image_page_jump_failed[\s\S]*this\.imagePageErrorUrl = url/.test(pageSrc))
  ok('image-page failure renders localized error copy', /imagePageErrorUrl\.length > 0[\s\S]*image_page_open_failed/.test(pageSrc))
  ok('image-page failure retry reuses the original URL', /retryAction:[\s\S]*this\.openImagePageUrl\(this\.imagePageErrorUrl\)/.test(pageSrc))
  ok('page gates empty on active filter', /trimmed\.length === 0 && !this\.filter\.isActive\(\)/.test(pageSrc))
  ok('submit funnels through runQuery', /onSubmit\(\): void \{\s*this\.runQuery\(/.test(pageSrc))
  ok('pending query seeds the field', /this\.actionState\.keyword = query\s*\n\s*this\.actionState\.seedSeq/.test(pageSrc))
  const vmSrc = readFileSync(
    join(ROOT, 'feature/search/src/main/ets/viewmodel/SearchViewModel.ets'),
    'utf8',
  )
  ok(
    'vm allows empty with active filter or favorite scope',
    /trimmed\.length === 0 && !this\.isFavoriteScope && !connectSearchFilter\(\)\.isActive\(\)/.test(vmSrc),
  )
  ok('reapplyFilters honors filter-only', /this\.query\.length > 0 \|\| connectSearchFilter\(\)\.isActive\(\)/.test(vmSrc))
  ok(
    'refresh allows filter-only or favorite-scope browse',
    /this\.query\.length === 0 && !this\.isFavoriteScope && !connectSearchFilter\(\)\.isActive\(\)/.test(vmSrc),
  )
}

console.log(`✓ search input contract: ${passed} assertions passed`)
