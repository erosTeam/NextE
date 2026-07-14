#!/usr/bin/env node
/**
 * Contract test for the /api.php `method=gdata` batch-metadata path (eros_fe getMoreGalleryInfo):
 *   - EhGalleryDataParser.parse        (gmetadata JSON → EhGallery[])
 *   - EhApiPhpService.galleryData      (request shape: [gid,token] pairs split into ≤25, method gdata)
 *   - GalleryDetailViewModel.enrichFromApi  (enrich-then-detail, gated on an absent seed fileCount)
 *   - GalleryDetailParams.fileCount    (list opens carry it → skip enrich; sparse opens leave it '')
 *
 * The parse mirror below is copy-equal to EhGalleryDataParser.ets (typeof guards + htmlUnescape +
 * language lookup). Two layers: a synthetic gmetadata fixture (exact assertions incl. an `error`
 * entry + entity title + numeric gid) and the real scripts/fixtures/gdata.json (smoke). Structural
 * greps lock the API/VM/params wiring. Run: node scripts/test_gallery_data_parser_contract.mjs
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// ── mirror of HtmlSelectorUtils.htmlUnescape (gdata titles are entity-escaped) ──
const NAMED = new Map([['amp', '&'], ['lt', '<'], ['gt', '>'], ['quot', '"'], ['apos', "'"], ['nbsp', ' ']])
const htmlUnescape = (s) => {
  if (!s || s.indexOf('&') < 0) return s
  return s.replace(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);/g, (match, ent) => {
    if (ent[0] === '#') {
      const isHex = ent[1] === 'x' || ent[1] === 'X'
      const code = isHex ? parseInt(ent.slice(2), 16) : parseInt(ent.slice(1), 10)
      if (Number.isNaN(code) || code <= 0 || code > 0x10ffff) return match
      return String.fromCodePoint(code)
    }
    return NAMED.get(ent) ?? match
  })
}
const ISO936 = new Map([
  ['japanese', 'JP'], ['english', 'EN'], ['chinese', 'ZH'], ['dutch', 'NL'], ['french', 'FR'],
  ['german', 'DE'], ['korean', 'KR'], ['spanish', 'ES'], ['russian', 'RU'],
])
const LANG_PREFIX_LEN = 9 // 'language:'.length
const languageAbbr = (name) => ISO936.get((name || '').toLowerCase().trim()) ?? ''

// ── mirror of EhGalleryDataParser.parse ──
function parse(body) {
  const out = []
  let raw
  try { raw = JSON.parse(body) } catch { throw new Error('gdata: invalid JSON') }
  // JSON.parse('null') returns null without throwing — guard the receiver (mirror of .ets).
  if (raw === null || typeof raw !== 'object') throw new Error('gdata: invalid JSON')
  const list = Array.isArray(raw.gmetadata) ? raw.gmetadata : []
  for (const m of list) {
    const err = typeof m.error === 'string' ? m.error : ''
    if (err.length > 0) continue
    let gid = ''
    if (typeof m.gid === 'number') gid = `${m.gid}`
    else if (typeof m.gid === 'string') gid = m.gid
    const token = typeof m.token === 'string' ? m.token : ''
    if (!gid || !token) continue
    const g = { gid, token }
    g.englishTitle = htmlUnescape(typeof m.title === 'string' ? m.title : '')
    g.japaneseTitle = htmlUnescape(typeof m.title_jpn === 'string' ? m.title_jpn : '')
    g.category = typeof m.category === 'string' ? m.category : ''
    g.thumbUrl = typeof m.thumb === 'string' ? m.thumb : ''
    g.uploader = typeof m.uploader === 'string' ? m.uploader : ''
    g.posted = typeof m.posted === 'string' ? m.posted : ''
    g.fileCount = typeof m.filecount === 'string' ? m.filecount : ''
    g.fileSize = typeof m.filesize === 'number' ? m.filesize : 0
    g.expunged = typeof m.expunged === 'boolean' ? m.expunged : false
    g.torrentCount = typeof m.torrentcount === 'string' ? m.torrentcount : ''
    const ratingStr = typeof m.rating === 'string' ? m.rating : ''
    const ratingNum = ratingStr.length > 0 ? Number.parseFloat(ratingStr) : 0
    g.rating = !Number.isNaN(ratingNum) && ratingNum > 0 ? ratingNum : 0
    const tags = Array.isArray(m.tags) ? m.tags : []
    g.simpleTags = tags.filter((t) => typeof t === 'string').map((t) => { const i = t.indexOf(':'); return i >= 0 ? t.slice(i + 1) : t })
    const langTag = tags.find((t) => typeof t === 'string' && t.startsWith('language:') && languageAbbr(t.slice(LANG_PREFIX_LEN)))
    g.language = langTag ? langTag.slice(LANG_PREFIX_LEN) : ''
    g.translated = langTag ? languageAbbr(g.language) : ''
    out.push(g)
  }
  return out
}

// ── mirror of EhApiPhpService.galleryData request builder (pairs, split into ≤25) ──
const GDATA_BATCH = 25
function buildRequests(items) {
  const pairs = []
  for (const it of items) if (it.gid && it.token) pairs.push([it.gid, it.token])
  const reqs = []
  for (let i = 0; i < pairs.length; i += GDATA_BATCH) {
    reqs.push({ method: 'gdata', gidlist: pairs.slice(i, i + GDATA_BATCH) })
  }
  return reqs
}

let failures = 0
const eq = (got, want, label) => {
  if (JSON.stringify(got) !== JSON.stringify(want)) { console.error(`  ✗ ${label}: expected ${JSON.stringify(want)}, got ${JSON.stringify(got)}`); failures++ }
}
const ok = (cond, label) => { if (!cond) { console.error(`  ✗ ${label}`); failures++ } }

// 1) synthetic gmetadata — exact assertions
console.log('— synthetic gmetadata —')
const SYN = JSON.stringify({
  gmetadata: [
    {
      gid: 3989982, token: '16600a66e8',
      title: 'Koumi-jima 2&amp;3 &lt;rev&gt;', title_jpn: 'プレースホルダ &#39;v2&#39;',
      category: 'Non-H', thumb: 'https://ehgt.org/w/02/446/x.webp', uploader: 'darumaruda',
      posted: '1781497464', filecount: '138', filesize: 1582652173, expunged: false,
      rating: '2.92', torrentcount: '0', torrents: [],
      tags: ['parody:megaman', 'language:chinese', 'other:artbook'],
    },
    { gid: 111, token: 'bad', error: 'Key missing or incorrect' }, // failed lookup → skipped
  ],
})
const gs = parse(SYN)
eq(gs.length, 1, 'error entry skipped → 1 gallery')
const a = gs[0]
eq(a.gid, '3989982', 'gid normalized from JSON number')
eq(a.token, '16600a66e8', 'token')
eq(a.englishTitle, 'Koumi-jima 2&3 <rev>', 'title HTML-entity decoded')
eq(a.japaneseTitle, "プレースホルダ 'v2'", 'title_jpn decoded (&#39;)')
eq(a.category, 'Non-H', 'category')
eq(a.thumbUrl, 'https://ehgt.org/w/02/446/x.webp', 'thumb')
eq(a.uploader, 'darumaruda', 'uploader')
eq(a.fileCount, '138', 'filecount (string)')
eq(a.fileSize, 1582652173, 'filesize (int)')
eq(a.rating, 2.92, 'rating parsed string→number')
eq(a.posted, '1781497464', 'posted (raw unix string)')
eq(a.torrentCount, '0', 'torrentcount')
eq(a.expunged, false, 'expunged')
eq(a.language, 'chinese', 'language from language: tag (find, not tags[0])')
eq(a.translated, 'ZH', 'translated chinese→ZH')
eq(a.simpleTags, ['megaman', 'chinese', 'artbook'], 'simpleTags = label after namespace')

// rating NaN / absent → 0; missing token → skipped
const edge = parse(JSON.stringify({ gmetadata: [
  { gid: 5, token: 't5', rating: 'not-a-number' },
  { gid: 6, rating: '4.0' }, // no token → skipped
] }))
eq(edge.length, 1, 'tokenless entry skipped')
eq(edge[0].rating, 0, 'unparseable rating → 0')

// malformed bodies must surface the CLEAN error, never a raw null-deref TypeError (adversarial find).
const throwsClean = (body, label) => {
  try { parse(body); console.error(`  ✗ ${label}: expected throw, got none`); failures++ }
  catch (e) { if (!String(e.message).includes('gdata: invalid JSON')) { console.error(`  ✗ ${label}: wrong error ${e.message}`); failures++ } }
}
throwsClean('null', 'body "null" → clean error (JSON.parse returns null, no throw)')
throwsClean('not json', 'body "not json" → clean error')
throwsClean('42', 'non-object body 42 → clean error')
eq(parse('{}').length, 0, 'empty object → [] (no gmetadata)')
eq(parse('{"gmetadata":42}').length, 0, 'non-array gmetadata → []')

// 2) request shape — pairs are [gid,token] strings, split into ≤25 batches, method gdata
console.log('— gdata request shape —')
const r1 = buildRequests([{ gid: '9', token: 'abc' }, { gid: '', token: 'x' }, { gid: '8', token: '' }])
eq(r1.length, 1, 'one batch')
eq(r1[0].method, 'gdata', 'method gdata')
eq(r1[0].gidlist, [['9', 'abc']], 'only complete [gid,token] pairs, both strings')
const many = Array.from({ length: 53 }, (_, i) => ({ gid: `${i}`, token: `t${i}` }))
const rN = buildRequests(many)
eq(rN.length, 3, '53 galleries → 3 batches (25/25/3)')
eq(rN[0].gidlist.length, 25, 'batch 0 = 25')
eq(rN[2].gidlist.length, 3, 'batch 2 = 3 (remainder)')

// 3) real fixture — smoke
const fixture = join(ROOT, 'scripts/fixtures/gdata.json')
if (existsSync(fixture)) {
  console.log('— real gdata.json fixture —')
  const r = parse(readFileSync(fixture, 'utf8'))
  ok(r.length >= 1, 'real fixture parses ≥1 gallery')
  if (r[0]) {
    ok(r[0].gid.length > 0 && r[0].token.length > 0, 'real: gid+token present')
    ok(r[0].fileCount.length > 0, 'real: fileCount present')
    ok(r[0].rating > 0, 'real: rating parsed')
    ok(r[0].thumbUrl.startsWith('https://'), 'real: thumb url')
    console.log(`  ✓ real gid=${r[0].gid} files=${r[0].fileCount} rating=${r[0].rating}`)
  }
} else {
  console.log('— real fixture absent (scripts/fixtures/gdata.json); synthetic-only —')
}

// 4) structural wiring
console.log('— wiring —')
const read = (f) => readFileSync(join(ROOT, f), 'utf8')
const PHP = read('shared/src/main/ets/network/EhApiPhpService.ets')
const VM = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
const PARAMS = read('shared/src/main/ets/model/RouteParams.ets')
const PARSER = read('shared/src/main/ets/parser/EhGalleryDataParser.ets')
ok(PHP.includes('static async galleryData('), 'EhApiPhpService.galleryData exists')
ok(PHP.includes('GDATA_BATCH: number = 25'), 'gdata batch cap = 25 (eros_fe splitList 25)')
ok(PHP.includes("method: string = 'gdata'"), 'gdata request method')
ok(PARSER.includes('static parse(body: string): EhGallery[]'), 'EhGalleryDataParser.parse signature')
ok(PARSER.includes('HtmlSelectorUtils.htmlUnescape'), 'parser decodes entity titles')
ok(VM.includes('this.gallery.fileCount.length === 0'), 'VM gates enrich on absent seed fileCount')
ok(VM.includes('await this.enrichFromApi('), 'VM enrich-then-detail call')
ok(VM.includes('EhApiPhpService.galleryData('), 'VM uses galleryData')
ok(PARAMS.includes('fileCount: string'), 'GalleryDetailParams carries fileCount')
if (failures > 0) { console.error(`\n✗ gdata parser contract: ${failures} failure(s)`); process.exit(1) }
console.log('\n✓ gdata parser contract passed')
