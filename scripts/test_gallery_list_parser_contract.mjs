#!/usr/bin/env node
/**
 * Contract test for EhGalleryListParser (compact `itg gltc` layout).
 *
 * The regexes below MUST stay identical to shared/src/main/ets/parser/EhGalleryListParser.ets
 * (ArkTS and JS share RegExp syntax, so the patterns are copy-equal — this test genuinely
 * exercises the parser's logic). Two layers:
 *   1. an inline SYNTHETIC fixture → exact, deterministic assertions on the fragile bits
 *      (rating sprite math, `cta` category class, favcat border-color map). Always runs;
 *      a failure here fails the gate.
 *   2. the real e-hentai.org fixture (scripts/fixtures/gallery_list.html) → smoke assertions
 *      on live structure (≥20 rows fully parsed). Skipped with a warning if absent.
 *
 * Run: node scripts/test_gallery_list_parser_contract.mjs
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// ── parser mirror (patterns copied verbatim from EhGalleryListParser.ets) ──
const RE = {
  table: /<table class="itg[^"]*"[^>]*>([\s\S]*?)<\/table>/,
  row: /<tr[^>]*>[\s\S]*?<\/tr>/g,
  url: /href="(https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-f]+)\/)"/,
  title: /<div class="glink">([\s\S]*?)<\/div>/,
  cat: /<td class="gl1c glcat"[^>]*>\s*<div class="cn ct\w+"[^>]*>([^<]+)<\/div>/,
  thumbDataSrc: /<div class="glthumb"[^>]*>[\s\S]*?<img[^>]*?\sdata-src="([^"]+)"/,
  thumbSrc: /<div class="glthumb"[^>]*>[\s\S]*?<img[^>]*?\ssrc="([^"]+)"/,
  rating: /<div class="ir[^"]*"[^>]*background-position:\s*-?(\d+)px\s+-?(\d+)px/,
  ratingClass: /<div class="[^"]*\b(ir[a-z])\b[^"]*"[^>]*background-position/,
  favcat: /id="posted_\d+"[^>]*style="[^"]*border-color:(#\w{3})/,
  favNote: /<div class="glfnote"[^>]*>Note:\s*([^<]+)<\/div>/,
  favTitle: /id="posted_\d+"[^>]*title="([^"]+)"/,
  posted: /id="posted_\d+"[^>]*>([\s\S]*?)<\/div>/,
  tagOpen: /<div class="gt[lc]?"([^>]*)>/g,
  pages: /(\d+) pages/,
  uploader: /\/uploader\/([^"/]+)"/,
  next: /[?&]next=(\d+)/,
}
const FAVCAT = new Map([
  ['#000', '0'], ['#f00', '1'], ['#fa0', '2'], ['#dd0', '3'], ['#080', '4'],
  ['#9f4', '5'], ['#4bf', '6'], ['#00f', '7'], ['#508', '8'], ['#e8e', '9'],
])
const ISO936 = new Map([
  ['japanese', 'JP'], ['english', 'EN'], ['chinese', 'ZH'], ['dutch', 'NL'], ['french', 'FR'],
  ['german', 'DE'], ['hungarian', 'HU'], ['italian', 'IT'], ['korean', 'KR'], ['polish', 'PL'],
  ['portuguese', 'PT'], ['russian', 'RU'], ['spanish', 'ES'], ['thai', 'TH'], ['vietnamese', 'VI'],
])
const LANG_PREFIX_LEN = 9 // 'language:'.length
const languageAbbr = (name) => ISO936.get((name || '').toLowerCase().trim()) ?? ''
const g1 = (text, re) => { const m = text.match(re); return m && m[1] !== undefined ? m[1] : '' }

// mirror of HtmlSelectorUtils.htmlUnescape — EH titles carry `&amp;` etc. that must be decoded.
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

const parseTagAttrs = (row) => {
  const tags = []
  const titles = []
  for (const m of row.matchAll(RE.tagOpen)) {
    const attrs = m[1] ?? ''
    const nsTag = g1(attrs, /title="([^"]+)"/)
    if (!nsTag) continue
    titles.push(nsTag)
    const idx = nsTag.indexOf(':')
    const tag = {
      text: idx >= 0 ? nsTag.slice(idx + 1) : nsTag,
      namespace: idx >= 0 ? nsTag.slice(0, idx) : '',
      color: '',
      backgroundColor: '',
    }
    const style = g1(attrs, /style="([^"]+)"/)
    const colors = [...style.matchAll(/#[0-9a-fA-F]{6}/g)].map((x) => x[0])
    if (colors.length > 0) tag.color = colors[0]
    if (colors.length > 3) tag.backgroundColor = colors[3]
    tags.push(tag)
  }
  return { titles, tags }
}

function parse(html) {
  const list = { gallerys: [], nextGid: g1(html, RE.next), maxPage: 0 }
  // Page-number paging (table.ptt): highest ?p= link = last 0-based page (toplist). Mirror of .ets.
  const ptt = html.match(/<table class="ptt"[\s\S]*?<\/table>/)
  if (ptt) {
    const block = ptt[0].replace(/&amp;/g, '&') // EH escapes ?tl=11&amp;p=1
    let max = 0
    for (const m of block.matchAll(/[?&]p=(\d+)/g)) max = Math.max(max, +m[1])
    list.maxPage = max
  }
  const tbl = html.match(RE.table)
  if (!tbl) return list
  for (const row of tbl[1].match(RE.row) || []) {
    const u = row.match(RE.url)
    if (!u) continue
    const g = { gid: u[2], token: u[3], url: u[1] }
    g.title = htmlUnescape(g1(row, RE.title).trim())
    g.category = g1(row, RE.cat).trim()
    let thumb = g1(row, RE.thumbDataSrc)
    if (!thumb) { const s = g1(row, RE.thumbSrc); thumb = s.startsWith('data:') ? '' : s }
    g.thumbUrl = thumb
    g.fileCount = g1(row, RE.pages)
    // mirror HtmlSelectorUtils.urlDecode — EH carries the uploader in the URL path (percent-encoded).
    g.uploader = (() => {
      const raw = g1(row, RE.uploader)
      if (!raw) return raw
      try {
        return decodeURIComponent(raw)
      } catch {
        return raw
      }
    })()
    const rm = row.match(RE.rating)
    g.rating = rm ? (80 - +rm[1]) / 16 - (+rm[2] === 21 ? 0.5 : 0) : null
    const cm = row.match(RE.ratingClass)
    g.colorRating = cm && cm[1] ? cm[1].trim() : ''
    const fc = g1(row, RE.favcat)
    g.favcat = fc ? (FAVCAT.get(fc) ?? '') : ''
    g.favNote = g1(row, RE.favNote).trim()
    g.favTitle = g1(row, RE.favTitle).trim()
    const rawPosted = g1(row, RE.posted)
    g.expunged = rawPosted.indexOf('<') >= 0
    g.postTime = rawPosted.replace(/<[^>]*>/g, '').trim()
    const parsedTags = parseTagAttrs(row)
    const tagTitles = parsedTags.titles
    g.simpleTags = parsedTags.tags
    const langTitle = tagTitles.find((t) => t.startsWith('language:') && languageAbbr(t.slice(LANG_PREFIX_LEN)))
    g.language = langTitle ? langTitle.slice(LANG_PREFIX_LEN) : ''
    g.translated = langTitle ? languageAbbr(g.language) : ''
    list.gallerys.push(g)
  }
  return list
}

// ── assertions ──
let failures = 0
const eq = (actual, expected, label) => {
  if (actual !== expected) { console.error(`  ✗ ${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`); failures++ }
}

// 0) htmlUnescape unit coverage — named/decimal/hex(both cases)/no-double-decode/unknown-verbatim
console.log('— htmlUnescape unit —')
eq(htmlUnescape('a &amp; b'), 'a & b', 'unescape &amp;')
eq(htmlUnescape('2&amp;3 &lt;x&gt; &quot;q&quot; &apos;p&apos;'), `2&3 <x> "q" 'p'`, 'unescape named set')
eq(htmlUnescape('&amp;lt;'), '&lt;', 'single-pass: no double-decode')
eq(htmlUnescape('&#65;&#x42;&#X43;'), 'ABC', 'decimal + lower-hex + UPPER-hex (&#X43;)')
eq(htmlUnescape('&#128512;'), String.fromCodePoint(128512), 'astral codepoint')
eq(htmlUnescape('&unknownent; &copy;'), '&unknownent; &copy;', 'unknown entities left verbatim')
eq(htmlUnescape('plain text'), 'plain text', 'no entity → unchanged')

// 1) synthetic — exact, deterministic
const SYN = `<table class="itg gltc">
<tr><th></th><th>Published</th><th>Title</th><th class="glhide">Uploader</th></tr>
<tr>
<td class="gl1c glcat"><div class="cn cta" onclick="x">Western</div></td>
<td class="gl2c"><div class="glthumb" id="it111" style="top:0"><div><img style="height:251px;width:250px" alt="t" title="t" src="https://ehgt.org/w/aa/bb.webp" /></div>
<div><div><div class="cn cta">Western</div><div id="postedpop_111">2026-06-13 10:00</div></div>
<div><div class="ir" style="background-position:0px -21px;opacity:1"></div><div>84 pages</div></div></div></div>
<div><div id="posted_111" style="border-color:#fa0">2026-06-13 10:00</div><div class="ir" style="background-position:0px -21px"></div></div></td>
<td class="gl3c glname" onmouseover="x"><a href="https://e-hentai.org/g/111/abcd/"><div class="glink">Koumi-jima 2&amp;3 &lt;rev&gt; &#39;final&#39;</div><div><div class="gt" title="language:chinese" style="color:#112233; border-color:#223344; border-left-color:#334455; background-color:#445566;">chinese</div><div class="gtl" title="language:translated">translated</div></div></a><div class="glfnote">Note: keep for later</div></td>
<td class="gl4c glhide"><div><a href="https://e-hentai.org/uploader/marki%C3%B1o">marki&ntilde;o</a></div><div>84 pages</div></td>
</tr>
<tr>
<td class="gl1c glcat"><div class="cn ct2" onclick="x">Doujinshi</div></td>
<td class="gl2c"><div class="glthumb" id="it222"><div><img style="height:300px;width:210px;top:-9px" src="data:image/gif;base64,R0lGODlhAQABAAAA" data-src="https://ehgt.org/w/cc/dd.webp" /></div>
<div><div><div class="cn ct2">Doujinshi</div><div id="postedpop_222">2026-06-13 09:00</div></div>
<div><div class="ir" style="background-position:0px -1px;opacity:1"></div><div>46 pages</div></div></div></div>
<div><div id="posted_222" title="高分">2026-06-13 09:00</div></div></td>
<td class="gl3c glname"><a href="https://e-hentai.org/g/222/0f1e/"><div class="glink">Neutral Placeholder B</div></a></td>
<td class="gl4c glhide"><div><a href="https://e-hentai.org/uploader/bob">bob</a></div><div>46 pages</div></td>
</tr>
</table>
<a id="dnext" href="https://e-hentai.org/?next=99">Next</a>`

console.log('— synthetic fixture —')
const s = parse(SYN)
eq(s.gallerys.length, 2, 'gallery count')
eq(s.nextGid, '99', 'nextGid')

// toplist ptt page-number paging — maxPage = highest ?p= (HTML-escaped &amp;p=) in the ptt table
{
  const PTT =
    `<table class="ptt"><tr><td class="ptds"><a href="https://e-hentai.org/toplist.php?tl=11">1</a></td>` +
    `<td><a href="https://e-hentai.org/toplist.php?tl=11&amp;p=1">2</a></td>` +
    `<td><a href="https://e-hentai.org/toplist.php?tl=11&amp;p=3">4</a></td></tr></table>` +
    // Real toplist.php tag carries a `style` attr after the class — the table-open regex must
    // tolerate extra attributes (a `">`-anchored regex silently missed it → empty list on device).
    `<table class="itg gltc" style="max-width:1250px"><tr><td><p>#1</p></td><td class="gl1c glcat"><div class="cn cta">Misc</div></td>` +
    `<td class="gl2c"><div class="glthumb"><div><img src="https://ehgt.org/x/y.webp"></div></div></td>` +
    `<td class="gl3c glname"><a href="https://e-hentai.org/g/9/abc123/"><div class="glink">Top1</div></a></td></tr></table>`
  const pt = parse(PTT)
  eq(pt.maxPage, 3, 'toplist maxPage (highest escaped &amp;p=)')
  eq(pt.gallerys.length, 1, 'toplist row parses despite rank <td> prefix + style attr on table')
  if (pt.gallerys[0]) eq(pt.gallerys[0].gid, '9', 'toplist row gid (rank-prefixed row)')
}
const a = s.gallerys[0]
eq(a.gid, '111', 'A.gid'); eq(a.token, 'abcd', 'A.token')
eq(a.category, 'Western', 'A.category (cta class)')
eq(a.rating, 4.5, 'A.rating (0px -21px → 4.5, half-star)')
eq(a.favcat, '2', 'A.favcat (#fa0 → slot 2)')
eq(a.fileCount, '84', 'A.fileCount'); eq(a.uploader, 'markiño', 'A.uploader (percent-decoded, device-found bug)')
eq(a.thumbUrl, 'https://ehgt.org/w/aa/bb.webp', 'A.thumbUrl (eager src)')
eq(a.title, "Koumi-jima 2&3 <rev> 'final'", 'A.title (HTML entities &amp;/&lt;/&gt;/&#39; decoded)')
// language:chinese → ZH; the language:translated marker is not a language so it's skipped.
eq(a.language, 'chinese', 'A.language (from language: tag)')
eq(a.translated, 'ZH', 'A.translated (chinese → ZH code)')
eq(a.simpleTags[0].text, 'chinese', 'A.tag text')
eq(a.simpleTags[0].color, '#112233', 'A.tag text color (first style hex, eros_fe parity)')
eq(a.simpleTags[0].backgroundColor, '#445566', 'A.tag background color (fourth style hex, eros_fe parity)')
eq(a.simpleTags[1].text, 'translated', 'A.gtl tag still parsed')
eq(a.simpleTags[1].color, '', 'A.gtl tag without style stays neutral text')
eq(a.simpleTags[1].backgroundColor, '', 'A.gtl tag without style stays neutral bg')
eq(a.favNote, 'keep for later', 'A.favNote (glfnote)')
eq(a.postTime, '2026-06-13 10:00', 'A.postTime (plain text node)')
eq(a.expunged, false, 'A.expunged (no child tag)')
const b = s.gallerys[1]
eq(b.gid, '222', 'B.gid'); eq(b.rating, 5, 'B.rating (0px -1px → 5.0)')
eq(b.category, 'Doujinshi', 'B.category'); eq(b.favcat, '', 'B.favcat (none)')
eq(b.uploader, 'bob', 'B.uploader')
// favorites.php posted div carries the favcat NAME in title (no border-color → slot unresolved here).
eq(b.favTitle, '高分', 'B.favTitle (favorites posted title)')
eq(b.translated, '', 'B.translated (no language tag)')
// B uses lazy data-src placeholder — parser must pick the real CDN url, not the data: gif.
eq(b.thumbUrl, 'https://ehgt.org/w/cc/dd.webp', 'B.thumbUrl (lazy data-src)')

// 1b) expunged row — timestamp wrapped in <s>; postTime must still parse AND expunged must flip.
console.log('— expunged row —')
const EXP = `<table class="itg gltc"><tr><td class="gl1c glcat"><div class="cn ct2">Doujinshi</div></td>` +
  `<td class="gl3c glname"><a href="https://e-hentai.org/g/333/eeee/"><div class="glink">Expunged Gallery</div></a></td>` +
  `<td class="gl2c"><div><div id="posted_333"><s>2026-06-10 08:00</s></div></div></td></tr></table>`
const ex = parse(EXP).gallerys[0]
eq(ex.expunged, true, 'EXP.expunged (child <s> tag detected)')
eq(ex.postTime, '2026-06-10 08:00', 'EXP.postTime (recovered from <s> wrap)')

// 1c) personally-rated row — class "ir irb" must STILL parse the rating (old "ir" exact missed it) + capture color.
console.log('— personally-rated row —')
const VOTED = `<table class="itg gltc"><tr><td class="gl1c glcat"><div class="cn ct2">Doujinshi</div></td>` +
  `<td class="gl3c glname"><a href="https://e-hentai.org/g/444/ffff/"><div class="glink">Voted Gallery</div></a></td>` +
  `<td class="gl2c"><div class="ir irb" style="background-position:-16px -1px"></div></td></tr></table>`
const vt = parse(VOTED).gallerys[0]
eq(vt.rating, 4, 'VOTED.rating still parses (-16px → 4.0) despite "ir irb" class')
eq(vt.colorRating, 'irb', 'VOTED.colorRating (personal blue vote)')
const YELLOW = `<table class="itg gltc"><tr><td class="gl1c glcat"><div class="cn ct2">Doujinshi</div></td>` +
  `<td class="gl3c glname"><a href="https://e-hentai.org/g/445/ffff/"><div class="glink">Yellow Vote</div></a></td>` +
  `<td class="gl2c"><div class="ir iry" style="background-position:-8px -1px"></div></td></tr></table>`
eq(parse(YELLOW).gallerys[0].colorRating, 'iry', 'YELLOW.colorRating (personal yellow vote)')

// 2) real fixture — smoke
const fixture = join(ROOT, 'scripts/fixtures/gallery_list.html')
if (existsSync(fixture)) {
  console.log('— real e-hentai.org fixture —')
  const r = parse(readFileSync(fixture, 'utf8'))
  if (r.gallerys.length < 20) { console.error(`  ✗ expected ≥20 galleries, got ${r.gallerys.length}`); failures++ }
  const full = r.gallerys.filter((x) => x.gid && x.category && x.thumbUrl.startsWith('https://') && x.rating != null && x.fileCount && x.uploader)
  if (full.length !== r.gallerys.length) { console.error(`  ✗ ${r.gallerys.length - full.length} row(s) missing fields`); failures++ }
  else console.log(`  ✓ ${r.gallerys.length} galleries, all fields parsed; nextGid=${r.nextGid}`)
} else {
  console.log('— real fixture absent (scripts/fixtures/gallery_list.html); synthetic-only —')
}

if (failures > 0) { console.error(`\n✗ gallery-list parser contract: ${failures} failure(s)`); process.exit(1) }
console.log('\n✓ gallery-list parser contract passed')
