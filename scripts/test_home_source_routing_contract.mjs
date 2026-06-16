#!/usr/bin/env node
/**
 * Contract test for the home multi-source URL routing in
 * shared/src/main/ets/network/EhApiService.ets `getGalleryList`.
 *
 * `buildUrl` below is copy-equal to that method's URL-assembly logic (path-by-source +
 * the popular-skips-all-params short-circuit). It locks the eros_fe request.dart routes:
 *   '' (front) → `${base}/?<params>`   · 'watched' → `${base}/watched?<params>`
 *   'popular'  → `${base}/popular`     (a fixed snapshot — filters AND the next cursor dropped)
 * If the .ets routing changes, mirror it here.
 *
 * Run: node scripts/test_home_source_routing_contract.mjs
 */

const EH_BASE = 'https://e-hentai.org'
const EX_BASE = 'https://exhentai.org'
const baseUrl = (isEx) => (isEx ? EX_BASE : EH_BASE)

// Mirror of getGalleryList's URL builder (no network — pure string assembly).
function buildUrl(query) {
  const base = baseUrl(query.isEx)
  const isPopular = query.source === 'popular'
  let path = '/'
  if (query.source === 'popular') {
    path = '/popular'
  } else if (query.source === 'watched') {
    path = '/watched'
  }
  if (isPopular) {
    return `${base}${path}`
  }
  if (query.source === 'toplist') {
    // toplist.php is E-Hentai-only (exhentai 404s) — always the e-hentai host, even in 里站 mode.
    return `${baseUrl(false)}/toplist.php?tl=${query.tl}&p=${query.page}`
  }
  const params = []
  if (query.fCats > 0) params.push(`f_cats=${query.fCats}`)
  if (query.search.length > 0) params.push(`f_search=${encodeURIComponent(query.search)}`)
  // advsearch=1 must precede the advanced block or EH ignores it (mirror of EhApiService).
  const hasAdvanced =
    query.minRating >= 2 ||
    query.pagesFrom > 0 ||
    query.pagesTo > 0 ||
    query.requireTorrent ||
    query.showExpunged ||
    query.disableLanguageFilter ||
    query.disableUploaderFilter ||
    query.disableTagFilter
  if (hasAdvanced) params.push('advsearch=1')
  if (query.minRating >= 2) {
    params.push('f_sr=on')
    params.push(`f_srdd=${query.minRating}`)
  }
  if (query.pagesFrom > 0 || query.pagesTo > 0) {
    params.push('f_sp=on')
    params.push(`f_spf=${query.pagesFrom > 0 ? query.pagesFrom : ''}`)
    params.push(`f_spt=${query.pagesTo > 0 ? query.pagesTo : ''}`)
  }
  if (query.requireTorrent) params.push('f_sto=on')
  if (query.showExpunged) params.push('f_sh=on')
  if (query.disableLanguageFilter) params.push('f_sfl=on')
  if (query.disableUploaderFilter) params.push('f_sfu=on')
  if (query.disableTagFilter) params.push('f_sft=on')
  if (query.next.length > 0) params.push(`next=${query.next}`)
  const queryStr = params.length > 0 ? `?${params.join('&')}` : ''
  return `${base}${path}${queryStr}`
}

const q = (over) => ({
  isEx: false,
  source: '',
  next: '',
  tl: 0,
  page: 0,
  fCats: 0,
  search: '',
  minRating: 0,
  pagesFrom: 0,
  pagesTo: 0,
  requireTorrent: false,
  showExpunged: false,
  disableLanguageFilter: false,
  disableUploaderFilter: false,
  disableTagFilter: false,
  ...over,
})

let failures = 0
const eq = (label, got, want) => {
  if (got !== want) {
    console.error(`✗ ${label}\n    got:  ${got}\n    want: ${want}`)
    failures++
  }
}

// Front page: path '/', params appended when present.
eq('front bare', buildUrl(q({})), 'https://e-hentai.org/')
eq('front next', buildUrl(q({ next: '12345' })), 'https://e-hentai.org/?next=12345')
eq(
  'front filters',
  buildUrl(q({ fCats: 1021, search: 'naruto', next: '99' })),
  'https://e-hentai.org/?f_cats=1021&f_search=naruto&next=99',
)
eq('front ex host', buildUrl(q({ isEx: true })), 'https://exhentai.org/')

// Watched: path '/watched', supports filters + next cursor (same gltc layout as front).
eq('watched bare', buildUrl(q({ source: 'watched' })), 'https://e-hentai.org/watched')
eq('watched next', buildUrl(q({ source: 'watched', next: '77' })), 'https://e-hentai.org/watched?next=77')
eq(
  'watched filters',
  buildUrl(q({ source: 'watched', fCats: 8, requireTorrent: true })),
  'https://e-hentai.org/watched?f_cats=8&advsearch=1&f_sto=on',
)

// Toplist: /toplist.php?tl=N&p=K — page-number paging, no filters/cursor (eros_fe toplist tab).
eq('toplist page 0', buildUrl(q({ source: 'toplist', tl: 11, page: 0 })), 'https://e-hentai.org/toplist.php?tl=11&p=0')
eq('toplist page 3', buildUrl(q({ source: 'toplist', tl: 11, page: 3 })), 'https://e-hentai.org/toplist.php?tl=11&p=3')
eq('toplist period year', buildUrl(q({ source: 'toplist', tl: 12, page: 0 })), 'https://e-hentai.org/toplist.php?tl=12&p=0')
eq('toplist period month', buildUrl(q({ source: 'toplist', tl: 13, page: 1 })), 'https://e-hentai.org/toplist.php?tl=13&p=1')
eq('toplist period yesterday', buildUrl(q({ source: 'toplist', tl: 15, page: 2 })), 'https://e-hentai.org/toplist.php?tl=15&p=2')
eq('toplist ignores filters', buildUrl(q({ source: 'toplist', tl: 11, page: 0, fCats: 8, minRating: 4 })), 'https://e-hentai.org/toplist.php?tl=11&p=0')
eq('toplist in 里站 mode stays on e-hentai host (toplist.php is e-hentai-only)', buildUrl(q({ source: 'toplist', tl: 11, page: 0, isEx: true })), 'https://e-hentai.org/toplist.php?tl=11&p=0')

// Advanced filters MUST carry advsearch=1 (else EH drops the whole advanced block).
eq(
  'advanced adds advsearch=1',
  buildUrl(q({ source: 'watched', requireTorrent: true, showExpunged: true })),
  'https://e-hentai.org/watched?advsearch=1&f_sto=on&f_sh=on',
)
eq(
  'min-rating adds advsearch=1',
  buildUrl(q({ minRating: 4 })),
  'https://e-hentai.org/?advsearch=1&f_sr=on&f_srdd=4',
)
eq(
  'page-range adds advsearch=1',
  buildUrl(q({ pagesFrom: 10, pagesTo: 100 })),
  'https://e-hentai.org/?advsearch=1&f_sp=on&f_spf=10&f_spt=100',
)
eq(
  'all three disable filters → advsearch=1 + f_sfl/f_sfu/f_sft (eros_fe parity)',
  buildUrl(q({ disableLanguageFilter: true, disableUploaderFilter: true, disableTagFilter: true })),
  'https://e-hentai.org/?advsearch=1&f_sfl=on&f_sfu=on&f_sft=on',
)
// Each toggle is INDEPENDENT — only its own param is sent (the eros_fe split, not all-or-none).
eq('disable language filter alone → f_sfl only', buildUrl(q({ disableLanguageFilter: true })), 'https://e-hentai.org/?advsearch=1&f_sfl=on')
eq('disable uploader filter alone → f_sfu only', buildUrl(q({ disableUploaderFilter: true })), 'https://e-hentai.org/?advsearch=1&f_sfu=on')
eq('disable tag filter alone → f_sft only', buildUrl(q({ disableTagFilter: true })), 'https://e-hentai.org/?advsearch=1&f_sft=on')
// Basic params (cats + search) must NOT trigger advsearch=1.
eq(
  'basic params no advsearch',
  buildUrl(q({ fCats: 1021, search: 'naruto' })),
  'https://e-hentai.org/?f_cats=1021&f_search=naruto',
)

// Popular: path '/popular', a fixed snapshot — every filter AND the next cursor must be dropped.
eq('popular bare', buildUrl(q({ source: 'popular' })), 'https://e-hentai.org/popular')
eq(
  'popular drops params',
  buildUrl(q({ source: 'popular', fCats: 8, search: 'x', next: '5', requireTorrent: true })),
  'https://e-hentai.org/popular',
)
eq('popular ex host', buildUrl(q({ source: 'popular', isEx: true })), 'https://exhentai.org/popular')

// Structural: the toplist period selector must be wired end-to-end (VM setter + @Trace period +
// HomePage period chips for all four tl values), else the URLs above are unreachable from the UI.
import { readFileSync as _read } from 'node:fs'
import { join as _join, dirname as _dir } from 'node:path'
import { fileURLToPath as _f } from 'node:url'
const _root = _join(_dir(_f(import.meta.url)), '..')
const has = (file, needle, label) => {
  const src = _read(_join(_root, file), 'utf8')
  if (!src.includes(needle)) {
    console.error(`✗ ${label}\n    missing: ${needle}\n    in: ${file}`)
    failures++
  }
}
const VM = 'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets'
const PAGE = 'feature/home/src/main/ets/pages/HomePage.ets'
has(VM, '@Trace toplistTl', 'VM: toplistTl is @Trace (period chips reflect selection)')
has(VM, 'async setToplistPeriod(tl: number)', 'VM: setToplistPeriod(tl) setter exists')
has(PAGE, 'PeriodChip(11,', 'HomePage: period chip tl=11 (all-time)')
has(PAGE, 'PeriodChip(12,', 'HomePage: period chip tl=12 (year)')
has(PAGE, 'PeriodChip(13,', 'HomePage: period chip tl=13 (month)')
has(PAGE, 'PeriodChip(15,', 'HomePage: period chip tl=15 (yesterday)')
has(PAGE, 'this.vm.setToplistPeriod(tl)', 'HomePage: period chip drives setToplistPeriod')

if (failures > 0) {
  console.error(`\n✗ home source routing: ${failures} assertion(s) failed`)
  process.exit(1)
}
console.log(
  '✓ home source routing: front/watched/popular paths + advsearch=1 gate + popular param-drop locked',
)
