#!/usr/bin/env node
/**
 * Contract test for search input handling (eros_fe _delayedSearch parity):
 *   feature/search/src/main/ets/pages/GallerySearchPage.ets  (runQuery: URL-jump vs search vs noop)
 *   feature/search/src/main/ets/viewmodel/SearchViewModel.ets (empty ordinary query guard)
 *
 * The functions below are copy-equal to that logic (no nav/network — pure routing decisions):
 *   • a pasted BARE gallery URL (/g/{gid}/{token}, e-/ex-hentai) jumps to the detail (no search).
 *   • a pasted BARE image-page URL (/s/{imgkey}/{gid}-{page}) resolves and jumps to Reader.
 *     Gated on a whole-string URL (eros_fe searchText.isURL) so a query that merely EMBEDS a URL
 *     still searches.
 *   • an empty ordinary query returns to history/blank; filter-only browse must be an explicit mode.
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
function route(query, _filterActive) {
  const trimmed = query.trim()
  if (looksLikeBareUrl(trimmed)) {
    const ref = parseGallery(trimmed)
    if (ref !== null) return { kind: 'gallery', ref }
    const image = parseImagePage(trimmed)
    if (image !== null) return { kind: 'imagePage', ref: image }
  }
  if (trimmed.length === 0) return { kind: 'noop' }
  return { kind: 'search', query: trimmed, recordsHistory: trimmed.length > 0 }
}

// Mirror of SearchViewModel.search() entry guard and reapplyFilters() guard.
const shouldSearch = (query, isLoading, isFavoriteScope) =>
  !isLoading && !(query.trim().length === 0 && !isFavoriteScope)
const shouldReapply = (queryLen, isFavoriteScope) => queryLen > 0 || isFavoriteScope

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

// 3. empty ordinary query never auto-browses, even when filters are active
{
  ok('empty + no filter → noop', route('', false).kind === 'noop')
  ok('whitespace + no filter → noop', route('   ', false).kind === 'noop')
  ok('empty + filter → noop', route('', true).kind === 'noop')
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

// 5. VM search guard: empty allowed only for explicit favorite-scope browse; loading always blocks
{
  ok('vm: term searches', shouldSearch('x', false, false) === true)
  ok('vm: empty ordinary blocked', shouldSearch('', false, false) === false)
  ok('vm: empty favorite browse allowed', shouldSearch('', false, true) === true)
  ok('vm: loading blocks even with favorite browse', shouldSearch('', true, true) === false)
}

// 6. reapplyFilters: re-runs on query OR explicit favorite browse, not ordinary filter-only
{
  ok('reapply with query', shouldReapply(5, false) === true)
  ok('reapply favorite browse', shouldReapply(0, true) === true)
  ok('reapply noop when neither', shouldReapply(0, false) === false)
}

// 7. structural: the wiring exists in the .ets
{
  const pageSrc = readFileSync(
    join(ROOT, 'feature/search/src/main/ets/pages/GallerySearchPage.ets'),
    'utf8',
  )
  const fieldSrc = readFileSync(
    join(ROOT, 'feature/search/src/main/ets/components/SearchPageField.ets'),
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
  ok('page clears empty query regardless of active filters', /if \(trimmed\.length === 0\) \{[\s\S]*this\.clearQueryToHistory\(\)/.test(pageSrc))
  ok('submit funnels through runQuery', /onSubmit\(\): void \{\s*this\.runQuery\(/.test(pageSrc))
  ok('page uses page-owned field state instead of shared keyword state',
    /@Local fieldState: SearchPageFieldState = new SearchPageFieldState\(\)/.test(pageSrc) &&
    /@Monitor\('fieldState\.submitSeq'\)[\s\S]*this\.runQuery\(this\.fieldState\.keyword\)/.test(pageSrc) &&
    !/@Monitor\('actionState\.submitSeq'\)/.test(pageSrc) &&
    !/connectSearchAction\(\)/.test(pageSrc))
  ok('route initial query seeds the field and runs search',
    /p\.initialQuery\.length > 0[\s\S]*this\.fieldState\.keyword = p\.initialQuery[\s\S]*this\.fieldState\.seedSeq[\s\S]*this\.runQuery\(p\.initialQuery\)/.test(pageSrc))
  ok('clearing the search field resets the page to history instead of keeping old results',
    /@Monitor\('fieldState\.keyword'\)[\s\S]*onKeywordChange\(\): void \{[\s\S]*keyword\.trim\(\)\.length === 0[\s\S]*this\.clearQueryToHistory\(\)/.test(pageSrc) &&
    /private clearQueryToHistory\(\): void \{[\s\S]*this\.imagePageErrorUrl = ''[\s\S]*this\.imagePageResolving = false[\s\S]*this\.vm\.clearSearchState\(\)/.test(pageSrc) &&
    /if \(trimmed\.length === 0\) \{[\s\S]*this\.clearQueryToHistory\(\)/.test(pageSrc))
  ok('search field is hosted in title-bar bottomBuilder, not the title stackBuilder',
    /'bottomBuilder': this\.searchBottomBuilder\(this\.ensureFieldContent\(\)\)/.test(pageSrc) &&
    !/'stackBuilderComponent': this\.ensureFieldContent\(\)/.test(pageSrc))
  ok('search page hides the title area on scroll while keeping the search field bottomBuilder visible',
    /'bottomBuilder': this\.searchBottomBuilder\(this\.ensureFieldContent\(\)\)/.test(pageSrc) &&
    /'menu': this\.searchMenu\(\)/.test(pageSrc) &&
    /dynamicHideTitleBar\(\{[\s\S]*hideTitleArea: true[\s\S]*hideBottomBuilder: false[\s\S]*mode: HideMode\.SCROLL_UP/.test(pageSrc))
  ok('bottomBuilder search field uses full content width and does not host page-level filters',
    /HDS title-bar bottomBuilder/.test(fieldSrc) &&
    /@ObservedV2[\s\S]*export class SearchPageFieldState/.test(fieldSrc) &&
    /onSubmit: \(_value: string\) => \{[\s\S]*this\.fieldState\.submitSeq = this\.fieldState\.submitSeq \+ 1/.test(fieldSrc) &&
    !/sys\.symbol\.funnel/.test(fieldSrc) &&
    !/filterSeq/.test(fieldSrc) &&
    !/BACK_BUTTON_SLOT_WIDTH/.test(fieldSrc) &&
    !/leadingReserve/.test(fieldSrc) &&
    /left: ThemeConstants\.SPACE_LG/.test(fieldSrc) &&
    /right: ThemeConstants\.SPACE_LG/.test(fieldSrc))
  const vmSrc = readFileSync(
    join(ROOT, 'feature/search/src/main/ets/viewmodel/SearchViewModel.ets'),
    'utf8',
  )
  ok(
    'vm blocks empty ordinary query even when filters are active',
    /trimmed\.length === 0 && !this\.isFavoriteScope\)/.test(vmSrc),
  )
  ok('reapplyFilters does not honor ordinary filter-only browse', /const canSearch: boolean = this\.query\.length > 0 \|\| this\.isFavoriteScope/.test(vmSrc))
  ok('reapplyFilters queues live changes during loading',
    /if \(this\.isLoading\) \{[\s\S]*this\.pendingFilterReapply = true[\s\S]*return[\s\S]*\}/.test(vmSrc) &&
    /if \(this\.pendingFilterReapply\) \{[\s\S]*this\.pendingFilterReapply = false[\s\S]*await this\.reapplyFilters\(\)/.test(vmSrc))
  ok('reapplyFilters clears stale filter-only results after reset',
    /if \(!canSearch\) \{[\s\S]*this\.dataSource\.clear\(\)[\s\S]*this\.hasSearched = false/.test(vmSrc))
  ok('vm clearSearchState clears rows, errors, paging, and searched state',
    /clearSearchState\(\): void \{[\s\S]*this\.epoch = this\.epoch \+ 1[\s\S]*this\.query = ''[\s\S]*this\.dataSource\.clear\(\)[\s\S]*this\.hasSearched = false[\s\S]*this\.errorMessage = ''/.test(vmSrc))
  ok('vm search result writes are guarded by epoch so clear cannot be overwritten by stale requests',
    /const myEpoch: number = this\.epoch/.test(vmSrc) &&
    /if \(this\.epoch === myEpoch\) \{[\s\S]*this\.dataSource\.setData\(list\.gallerys\)/.test(vmSrc) &&
    /if \(this\.epoch === myEpoch\) \{[\s\S]*this\.isLoading = false/.test(vmSrc))
  ok(
    'refresh blocks empty ordinary query',
    /this\.query\.length === 0 && !this\.isFavoriteScope\)/.test(vmSrc),
  )
}

console.log(`✓ search input contract: ${passed} assertions passed`)
