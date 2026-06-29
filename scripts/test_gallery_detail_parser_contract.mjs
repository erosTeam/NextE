#!/usr/bin/env node
/**
 * Contract test for EhGalleryDetailParser + EhGalleryImageParser.
 * Patterns mirror shared/src/main/ets/parser/EhGalleryDetailParser.ets and
 * EhGalleryImageParser.ets. Synthetic case = hard gate; the real e-hentai.org detail
 * fixture (scripts/fixtures/gallery_detail.html) adds a live smoke check when present.
 *
 * Run: node scripts/test_gallery_detail_parser_contract.mjs
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const g1 = (h, re) => { const m = h.match(re); return m && m[1] !== undefined ? m[1] : '' }
// mirror of HtmlSelectorUtils.htmlUnescape — detail titles are entity-escaped like list titles.
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

const RE = {
  en: /<h1 id="gn">([\s\S]*?)<\/h1>/,
  jp: /<h1 id="gj">([\s\S]*?)<\/h1>/,
  cat: /<div id="gdc"><div class="cs ct\w+"[^>]*>([^<]+)<\/div>/,
  uploader: /<div id="gdn"[^>]*><a href="[^"]*\/uploader\/([^"]+)"/,
  cover: /<div id="gd1">[\s\S]*?url\((https:\/\/[^)]+)\)/,
  coverStyle: /<div id="gd1">[\s\S]*?<div[^>]*style="([^"]*url\((https:\/\/[^)]+)\)[^"]*)"/,
  styleW: /width:\s*(\d+)px/,
  styleH: /height:\s*(\d+)px/,
  length: /Length:<\/td><td class="gdt2">(\d+)/,
  favcount: /id="favcount">([^<]+)</,
  lang: /Language:<\/td><td class="gdt2">([^<&]+)/,
  fileSize: /File Size:<\/td><td class="gdt2">([^<]+)</,
  ratingCount: /id="rating_count"[^>]*>(\d+)</,
  posted: /Posted:<\/td><td class="gdt2">([^<]+)</,
  torrent: /Torrent Download \((\d+)\)/,
  archiverUrl: /popUp\('([^']*archiver\.php\?[^']*)'/,
  archiverOr: /\bor=([^'"]*)/,
  visible: /Visible:<\/td><td class="gdt2">([^<]+)</,
  parent: /Parent:<\/td><td class="gdt2"><a href="(https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-f]+)\/)">([\s\S]*?)<\/a>/,
  newerBlock: /<div id="gnd">([\s\S]*?)<\/div>/,
  newerLink: /<a href="https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-f]+)\/">([\s\S]*?)<\/a>/g,
  newerDate: /<td class="gdt1">([^<]+)<\/td>/g,
  rating: /var average_rating\s*=\s*([\d.]+)/,
  ratingAttrs: /<div\b(?=[^>]*\bid="rating_image")[^>]*>/,
  ratingClass: /class="[^"]*\b(ir[a-z])\b[^"]*"/,
  ratingPos: /background-position:\s*-?(\d+)px\s+-?(\d+)px/,
  apikey: /var apikey\s*=\s*"([0-9a-f]+)"/,
  // The user's own favorite: #fav inner sprite (favorited only). Match the div blob, then read Y +
  // title independently (attribute-order-independent, per the adversarial-review hardening).
  favDiv: /id="fav">\s*<div([^>]*)>/,
  favY: /background-position:\s*-?\d+px\s+-?(\d+)px/,
  favTitle: /title="([^"]*)"/,
  tagRow: /<tr><td class="tc">([^:]+):<\/td><td>([\s\S]*?)<\/td><\/tr>/g,
  tagA: /<a ([^>]*id="ta_[^"]*"[^>]*)>([^<]+)<\/a>/g,
  preview: /<a href="(https:\/\/e[-x]?hentai\.org\/s\/([0-9a-f]+)\/(\d+)-(\d+))">(?:<div[^>]*>)?<div title="Page \d+[^"]*" style="(?:width:(\d+)px;\s*height:(\d+)px;\s*)?background:[^;]*?url\((https:\/\/[^)]+)\)(?:\s*-?(\d+)px)?/g,
  smallPreview: /<div class="gdtm"[\s\S]*?<div[^>]*style="(?:width:(\d+)px;\s*height:(\d+)px;\s*)?background:[^;]*?url\((https:\/\/[^)]+)\)(?:\s*-?(\d+)px)?[\s\S]*?<a href="(https:\/\/e[-x]?hentai\.org\/s\/([0-9a-f]+)\/(\d+)-(\d+))"[\s\S]*?<img[^>]*alt="(\d+)"/g,
  largePreview: /<div class="gdtl"[\s\S]*?<a href="(https:\/\/e[-x]?hentai\.org\/s\/([0-9a-f]+)\/(\d+)-(\d+))"[\s\S]*?<img[^>]*alt="(\d+)"[^>]*src="(https:\/\/[^"]+)"/g,
}

function parseTags(html) {
  const list = html.match(/<div id="taglist">([\s\S]*?)<\/table>/)
  if (!list) return []
  const groups = []
  for (const r of list[1].matchAll(RE.tagRow)) {
    const tags = [...r[2].matchAll(RE.tagA)].map((m) => {
      const attrs = m[1] || ''
      const vote = attrs.includes('class="tup"') ? 1 : attrs.includes('class="tdn"') ? -1 : 0
      return { text: rawTagText(r[1].trim(), attrs, m[2]), vote }
    })
    if (r[1].trim() && tags.length) groups.push({ ns: r[1].trim(), tags })
  }
  return groups
}
function rawTagText(ns, attrs, displayText) {
  const href = attrs.match(/href="([^"]*)"/)?.[1] ?? ''
  const fromHref = rawTagFromHref(ns, htmlUnescape(href))
  if (fromHref) return fromHref
  const id = attrs.match(/id="ta_([^"]*)"/)?.[1] ?? ''
  const fromId = rawTagFromFullTag(ns, id)
  if (fromId) return fromId
  return htmlUnescape((displayText || '').trim())
}
function rawTagFromHref(ns, href) {
  const tagPath = '/tag/'
  const tagIdx = href.indexOf(tagPath)
  if (tagIdx >= 0) return rawTagFromFullTag(ns, href.slice(tagIdx + tagPath.length))
  const q = 'f_search='
  const qIdx = href.indexOf(q)
  if (qIdx < 0) return ''
  let value = href.slice(qIdx + q.length)
  const amp = value.indexOf('&')
  if (amp >= 0) value = value.slice(0, amp)
  return rawTagFromFullTag(ns, value)
}
function rawTagFromFullTag(ns, value) {
  let raw = (value || '').trim()
  const slash = raw.indexOf('/')
  if (slash >= 0) raw = raw.slice(0, slash)
  let full = safeDecode(raw.replace(/\+/g, '%20')).trim()
  const colon = full.indexOf(':')
  if (colon < 0) return full
  const gotNs = full.slice(0, colon).trim().toLowerCase()
  if (gotNs && gotNs !== ns.toLowerCase().trim()) return ''
  return full.slice(colon + 1).trim()
}
function safeDecode(value) {
  try { return decodeURIComponent(value) } catch { return value }
}
function parseImages(html) {
  const imgs = [...html.matchAll(RE.preview)].map((m) => ({
    page: +m[4], imgkey: m[2], sUrl: m[1], thumb: m[7],
    thumbWidth: m[5] ? +m[5] : 0, thumbHeight: m[6] ? +m[6] : 0, offsetX: m[8] ? +m[8] : 0,
    spriteWidth: 0, spriteHeight: 0,
  }))
  for (const m of html.matchAll(RE.smallPreview)) {
    if (!imgs.some((img) => img.sUrl === m[5])) {
      imgs.push({
        page: +m[9] || +m[8], imgkey: m[6], sUrl: m[5], thumb: m[3],
        thumbWidth: m[1] ? +m[1] : 0, thumbHeight: m[2] ? +m[2] : 0, offsetX: m[4] ? +m[4] : 0,
        spriteWidth: 0, spriteHeight: 0,
      })
    }
  }
  for (const m of html.matchAll(RE.largePreview)) {
    const parts = m[6].split('-')
    const w = parts.length >= 3 ? Number.parseInt(parts[parts.length - 3], 10) : 0
    const h = parts.length >= 3 ? Number.parseInt(parts[parts.length - 2], 10) : 0
    imgs.push({
      page: +m[5] || +m[4], imgkey: m[2], sUrl: m[1], thumb: m[6],
      thumbWidth: Number.isNaN(w) ? 0 : w, thumbHeight: Number.isNaN(h) ? 0 : h, offsetX: 0,
      spriteWidth: 0, spriteHeight: 0,
    })
  }
  // Mirror fillSpriteExtents: full sheet extent = max right-edge / height across a sprite URL.
  const w = new Map(), h = new Map(), count = new Map(), hasOffset = new Map()
  for (const i of imgs) {
    count.set(i.thumb, (count.get(i.thumb) ?? 0) + 1)
    if (i.offsetX > 0) hasOffset.set(i.thumb, true)
    w.set(i.thumb, Math.max(w.get(i.thumb) ?? 0, i.offsetX + i.thumbWidth))
    h.set(i.thumb, Math.max(h.get(i.thumb) ?? 0, i.thumbHeight))
  }
  for (const i of imgs) {
    if ((count.get(i.thumb) ?? 0) > 1 || hasOffset.get(i.thumb) === true) {
      i.spriteWidth = w.get(i.thumb)
      i.spriteHeight = h.get(i.thumb)
    }
  }
  return imgs
}
// Mirror EhGalleryDetailParser colorRating: #rating_image class "ir" -> '' (community), "ir irX" -> 'irX'.
function parseRatingColor(html) {
  const attrs = html.match(RE.ratingAttrs)?.[0] ?? ''
  const m = attrs.match(RE.ratingClass)
  return m && m[1] ? m[1].trim() : ''
}
function parseRatingFallBack(html) {
  const attrs = html.match(RE.ratingAttrs)?.[0] ?? ''
  const m = attrs.match(RE.ratingPos)
  if (!m) return 0
  return (80 - Number.parseFloat(m[1])) / 16 - (m[2] === '21' ? 0.5 : 0)
}
// Mirror EhGalleryImageParser.parsePageCount: max page LABEL in the `ptt` nav (1 if absent).
function parsePageCount(html) {
  const ptt = html.match(/<table class="ptt"[^>]*>([\s\S]*?)<\/table>/)
  if (!ptt) return 1
  let max = 1
  for (const m of ptt[1].matchAll(/<a[^>]*>(\d+)<\/a>/g)) { const n = +m[1]; if (n > max) max = n }
  return max
}

function parseArchiverLink(html) {
  const fullUrl = htmlUnescape(g1(html, RE.archiverUrl).trim())
  if (fullUrl) return fullUrl
  return g1(html, RE.archiverOr).trim()
}

function parseNewerVersions(html) {
  const block = html.match(RE.newerBlock)?.[1] ?? ''
  if (!block) return []
  const dates = [...block.matchAll(RE.newerDate)].map((m) => (m[1] ?? '').trim())
  return [...block.matchAll(RE.newerLink)].map((m, index) => ({
    gid: m[1] ?? '',
    token: m[2] ?? '',
    title: htmlUnescape((m[3] ?? '').trim()),
    posted: dates[index] ?? '',
  }))
}

let failures = 0
const eq = (a, e, label) => { if (a !== e) { console.error(`  ✗ ${label}: expected ${JSON.stringify(e)}, got ${JSON.stringify(a)}`); failures++ } }
const ok = (c, label) => { if (!c) { console.error(`  ✗ ${label}`); failures++ } }

// synthetic
const SYN = `<h1 id="gn">Placeholder &amp; Title &#39;v2&#39;</h1><h1 id="gj">プレースホルダ</h1>
<div id="gdc"><div class="cs ct3" onclick="x">Artist CG</div></div>
<div id="gdn"><a href="https://e-hentai.org/uploader/alice">alice</a></div>
<div id="gd1"><div style="width:320px;height:180px;background:transparent url(https://ehgt.org/w/aa/bb.webp) 0 0 no-repeat"></div></div>
<div id="gdd"><table><tr><td class="gdt1">Posted:</td><td class="gdt2">2026-06-13 15:31</td></tr><tr><td class="gdt1">Parent:</td><td class="gdt2"><a href="https://e-hentai.org/g/999/abcd1234/">Parent &amp; Gallery</a></td></tr><tr><td class="gdt1">Visible:</td><td class="gdt2">Yes</td></tr><tr><td class="gdt1">Language:</td><td class="gdt2">Japanese &nbsp;</td></tr><tr><td class="gdt1">File Size:</td><td class="gdt2">123.4 MiB</td></tr><tr><td class="gdt1">Length:</td><td class="gdt2">42 pages</td></tr><tr><td class="gdt1">Favorited:</td><td class="gdt2" id="favcount">7 times</td></tr></table></div>
<div id="gnd"><table>
<tr><td class="gdt1">2026-06-14 10:00</td><td><a href="https://e-hentai.org/g/1000/aaa111/">Newer &amp; One</a></td></tr>
<tr><td class="gdt1">2026-06-15 11:00</td><td><a href="https://exhentai.org/g/1001/bbb222/">Newer Two</a></td></tr>
</table></div>
<div id="gdr"><td id="rating_count">128</td></div>
<div id="rating_image" class="ir irg" style="background-position:-16px -21px"></div>
<a onclick="return popUp('archiver.php?gid=12345&amp;token=abcdef')">Archive Download</a>
<p class="g2"><a onclick="return popUp('...')">Torrent Download (5)</a></p>
<div id="taglist"><table><tr><td class="tc">artist:</td><td><div class="gtl"><a id="ta_artist:x" href="#">someone</a></div></td></tr><tr><td class="tc">female:</td><td><div class="gtl"><a id="ta_female:a" href="#">tag a</a></div><div class="gtw"><a id="ta_female:b" href="#">tag b</a></div></td></tr></table></div>
<script>var average_rating = 4.33; var apiuid = -1; var apikey = "abcd1234ef";</script>
<table class="ptt"><tr><td class="ptds"><a href="#">1</a></td><td><a href="#?p=1">2</a></td><td><a href="#?p=2">3</a></td></tr></table>
<div id="gdt" class="gt200"><a href="https://e-hentai.org/s/0508455a59/12345-1"><div title="Page 1: 0.jpg" style="width:200px;height:200px;background:transparent url(https://x.hath.network/c/12345-0.webp) -0px 0 no-repeat"></div></a><a href="https://e-hentai.org/s/9672d3f5b9/12345-2"><div title="Page 2: 1.jpg" style="background:transparent url(https://x.hath.network/c/12345-1.webp) 0 0 no-repeat"></div></a></div>`

console.log('— synthetic —')
eq(htmlUnescape(g1(SYN, RE.en).trim()), "Placeholder & Title 'v2'", 'enTitle (HTML entities decoded)')
eq(htmlUnescape(g1(SYN, RE.jp).trim()), 'プレースホルダ', 'jpTitle')
eq(g1(SYN, RE.cat).trim(), 'Artist CG', 'category')
eq(g1(SYN, RE.uploader), 'alice', 'uploader')
eq(g1(SYN, RE.cover), 'https://ehgt.org/w/aa/bb.webp', 'cover')
const coverStyle = SYN.match(RE.coverStyle)
eq(coverStyle && coverStyle[2], 'https://ehgt.org/w/aa/bb.webp', 'cover style URL')
eq(coverStyle && coverStyle[1].match(RE.styleW)?.[1], '320', 'cover style width')
eq(coverStyle && coverStyle[1].match(RE.styleH)?.[1], '180', 'cover style height')
eq(g1(SYN, RE.length), '42', 'length')
eq(g1(SYN, RE.favcount).trim(), '7 times', 'favcount')
eq(g1(SYN, RE.lang).trim(), 'Japanese', 'language')
eq(g1(SYN, RE.fileSize).trim(), '123.4 MiB', 'fileSize')
eq(g1(SYN, RE.ratingCount), '128', 'ratingCount')
eq(g1(SYN, RE.posted).trim(), '2026-06-13 15:31', 'posted')
eq(g1(SYN, RE.torrent), '5', 'torrentCount')
eq(parseArchiverLink(SYN), 'archiver.php?gid=12345&token=abcdef', 'archiver full URL without legacy or token')
eq(parseArchiverLink(`<a onclick="return popUp('archiver.php?gid=1&amp;token=t&amp;or=abc123or')">Archive Download</a>`),
  'archiver.php?gid=1&token=t&or=abc123or', 'legacy archiver URL with or token stays usable')
eq(parseArchiverLink(`onclick="return popUp('x')" data-old="or=abc123or'"`), 'abc123or',
  'older or-only fallback remains supported')
eq(g1(SYN, RE.visible).trim(), 'Yes', 'visible')
const pm = SYN.match(RE.parent); eq(pm && pm[2], '999', 'parentGid'); eq(pm && pm[3], 'abcd1234', 'parentToken'); eq(pm && htmlUnescape(pm[4].trim()), 'Parent & Gallery', 'parentTitle')
const nv = parseNewerVersions(SYN)
eq(nv.length, 2, 'newerVersions count')
eq(nv[0].gid, '1000', 'newerVersions[0] gid')
eq(nv[0].token, 'aaa111', 'newerVersions[0] token')
eq(nv[0].title, 'Newer & One', 'newerVersions[0] title')
eq(nv[0].posted, '2026-06-14 10:00', 'newerVersions[0] posted')
eq(nv[1].gid, '1001', 'newerVersions[1] gid')
eq(nv[1].token, 'bbb222', 'newerVersions[1] token')
eq(g1(SYN, RE.rating), '4.33', 'rating (inline avg)')
eq(g1(SYN, RE.apikey), 'abcd1234ef', 'apikey')
const st = parseTags(SYN)
eq(st.length, 2, 'tag groups')
eq(st[0].ns, 'artist', 'group0 ns'); eq(st[1].tags.length, 2, 'female tag count')
eq(st[0].tags[0].text, 'x', 'detail tags use raw id/href tag text instead of visible display text')
eq(st[0].tags[0].vote, 0, 'unvoted tag (no class) → vote 0')

const RAW_TAG = `<div id="taglist"><table><tr><td class="tc">artist:</td><td>` +
  `<div class="gt"><a id="ta_artist:fallback" href="https://e-hentai.org/tag/artist:raw%20artist" class="">Pretty Artist</a></div>` +
  `<div class="gt"><a id="ta_artist:q" href="https://e-hentai.org/?f_search=artist%3Aquery+artist&f_apply=Apply+Filter" class="">Query Artist</a></div>` +
  `<div class="gt"><a id="ta_artist:entity" href="#" class="">A&amp;B</a></div>` +
  `</td></tr></table></div>`
const rt = parseTags(RAW_TAG)
eq(rt[0].tags[0].text, 'raw artist', 'detail tag raw text comes from /tag/ns:raw href')
eq(rt[0].tags[1].text, 'query artist', 'detail tag raw text comes from f_search=ns:raw query')
eq(rt[0].tags[2].text, 'entity', 'detail tag falls back to id raw text before display text')

// Tag vote state: EH marks a logged-in user's voted tag <a> with class "tup" (+1) / "tdn" (-1); an
// unvoted tag stays class="" (0). Real EH markup shape (id ta_*, href, class, onclick) — the captured
// fixtures all have class="" (no votes), so this synthetic row is the parser contract for the data path.
const VOTE = `<div id="taglist"><table><tr><td class="tc">female:</td><td>` +
  `<div class="gt"><a id="ta_female:up" href="https://e-hentai.org/tag/female:up" class="tup" onclick="return toggle_tagmenu(1,'female:up',this)">up tag</a></div>` +
  `<div class="gt"><a id="ta_female:down" href="https://e-hentai.org/tag/female:down" class="tdn" onclick="return toggle_tagmenu(1,'female:down',this)">down tag</a></div>` +
  `<div class="gt"><a id="ta_female:plain" href="https://e-hentai.org/tag/female:plain" class="" onclick="return toggle_tagmenu(1,'female:plain',this)">plain tag</a></div>` +
  `</td></tr></table></div>`
const vt = parseTags(VOTE)
eq(vt.length, 1, 'vote: one tag group')
eq(vt[0].tags.length, 3, 'vote: three tags')
eq(vt[0].tags[0].text, 'up', 'vote: upvoted tag keeps raw href tag text')
eq(vt[0].tags[0].vote, 1, 'vote: class="tup" → +1')
eq(vt[0].tags[1].vote, -1, 'vote: class="tdn" → -1')
eq(vt[0].tags[2].vote, 0, 'vote: class="" → 0')

// Rating colour variant: #rating_image class "ir" = community (orange, colorRating ''); "ir irb" etc =
// personally rated (blue/green/red). Captured fixtures are all plain "ir"; this synthetic covers the variant.
eq(parseRatingColor('<div id="rating_image" class="ir" style="background-position:0px -1px">'), '', 'ratingColor: plain ir → "" (community/orange)')
eq(parseRatingColor('<div id="rating_image" class="ir irb" style="background-position:0px -1px">'), 'irb', 'ratingColor: ir irb → irb (personal blue)')
eq(parseRatingColor('<div id="rating_image" class="ir irg" style="background-position:0px -21px">'), 'irg', 'ratingColor: ir irg → irg (personal green)')
eq(parseRatingColor('<div id="rating_image" class="ir irr">'), 'irr', 'ratingColor: ir irr → irr (personal red)')
eq(parseRatingColor('<div style="background-position:0px -1px" class="ir iry" id="rating_image">'), 'iry', 'ratingColor: attr-order variant + iry → iry (personal yellow)')
eq(parseRatingFallBack('<div id="rating_image" class="ir" style="background-position:0px -1px">'), 5, 'ratingFallBack: x=0,y=1 → 5')
eq(parseRatingFallBack('<div id="rating_image" class="ir" style="background-position:-16px -21px">'), 3.5, 'ratingFallBack: x=16,y=21 → 3.5')
eq(parsePageCount(SYN), 3, 'preview page count (ptt max label)')
const si = parseImages(SYN)
eq(si.length, 2, 'preview count')
// ExHentai wraps the preview anchor in an extra <div>; the parser must handle both variants.
const EX_PREVIEW = '<div id="gdt" class="gt200"><a href="https://exhentai.org/s/5e5314359b/3970138-1"><div><div title="Page 1: x.gif" style="width:200px;height:155px;background:transparent url(https://s.exhentai.org/t/aa.jpg) 0 0 no-repeat"></div></div></a></div>'
eq(parseImages(EX_PREVIEW).length, 1, 'EX preview (extra <div> wrapper)')
eq(si[0].page, 1, 'preview0 page'); eq(si[0].sUrl, 'https://e-hentai.org/s/0508455a59/12345-1', 'preview0 sUrl')
ok(si[0].thumb.startsWith('https://'), 'preview0 thumb is https')
eq(si[0].thumbWidth, 200, 'preview0 thumbWidth (sprite sub-rect width)')
eq(si[1].thumbWidth, 0, 'preview1 no width/height → sprite fallback')

// Sprite sheet: 3 previews sharing one sheet at offsets 0/200/400 — the crop fields + derived extent.
const SPRITE = '<div id="gdt" class="gt200">' +
  '<a href="https://e-hentai.org/s/aaa/9-1"><div title="Page 1" style="width:200px;height:290px;background:transparent url(https://h.net/9-0.webp) -0px 0 no-repeat"></div></a>' +
  '<a href="https://e-hentai.org/s/bbb/9-2"><div title="Page 2" style="width:200px;height:290px;background:transparent url(https://h.net/9-0.webp) -200px 0 no-repeat"></div></a>' +
  '<a href="https://e-hentai.org/s/ccc/9-3"><div title="Page 3" style="width:200px;height:290px;background:transparent url(https://h.net/9-0.webp) -400px 0 no-repeat"></div></a></div>'
const sp = parseImages(SPRITE)
eq(sp.length, 3, 'sprite previews count')
eq(sp[1].offsetX, 200, 'sprite page2 offsetX')
eq(sp[1].thumb, 'https://h.net/9-0.webp', 'sprite URL shared across the sheet')
eq(sp[0].spriteWidth, 600, 'sprite full width = max(offset+width) = 400+200')
eq(sp[2].spriteWidth, 600, 'sprite width assigned to every thumb on the sheet')
eq(sp[0].spriteHeight, 290, 'sprite height = max thumb height')
eq(sp[0].thumbHeight, 290, 'sprite page1 thumbHeight (drives true-aspect sizing)')

// Legacy small-thumb layout (`#gdt > div.gdtm`) puts the /s/ link inside a sprite-styled child.
// The parser must keep the serial from img alt, the image-page URL, and the sprite crop metadata.
const SMALL = '<div id="gdt">' +
  '<div class="gdtm"><div style="width:200px;height:290px;background:transparent url(https://ehgt.org/t/sheet.webp) -0px 0 no-repeat"><a href="https://e-hentai.org/s/aaa111/77-1"><img alt="1"/></a></div></div>' +
  '<div class="gdtm"><div style="width:200px;height:290px;background:transparent url(https://ehgt.org/t/sheet.webp) -200px 0 no-repeat"><a href="https://e-hentai.org/s/bbb222/77-2"><img alt="2"/></a></div></div>' +
  '</div>'
const sm = parseImages(SMALL)
eq(sm.length, 2, 'gdtm small-thumb previews count')
eq(sm[0].page, 1, 'gdtm page from img alt')
eq(sm[0].imgkey, 'aaa111', 'gdtm imgkey')
eq(sm[0].sUrl, 'https://e-hentai.org/s/aaa111/77-1', 'gdtm sUrl')
eq(sm[0].thumb, 'https://ehgt.org/t/sheet.webp', 'gdtm sprite URL')
eq(sm[0].thumbWidth, 200, 'gdtm thumb width from style')
eq(sm[0].thumbHeight, 290, 'gdtm thumb height from style')
eq(sm[1].offsetX, 200, 'gdtm second thumb offset')
eq(sm[0].spriteWidth, 400, 'gdtm sprite width from max right edge')
eq(sm[1].spriteHeight, 290, 'gdtm sprite height shared')

// Legacy large-thumb layout (`#gdt > div.gdtl`) has one whole thumbnail image per page, not a sprite
// sheet. It must still feed Reader with the /s/ URL + imgkey and feed PreviewThumbTile with dimensions
// parsed from the thumbnail filename tail.
const LARGE = '<div id="gdt">' +
  '<div class="gdtl"><a href="https://e-hentai.org/s/abc123/55-1"><img alt="1" src="https://ehgt.org/t/aa/bb/55-780-1200-0001.jpg"/></a></div>' +
  '<div class="gdtl"><a href="https://e-hentai.org/s/def456/55-2"><img alt="2" src="https://ehgt.org/t/aa/bb/55-1600-900-0002.jpg"/></a></div>' +
  '</div>'
const lg = parseImages(LARGE)
eq(lg.length, 2, 'gdtl large-thumb previews count')
eq(lg[0].page, 1, 'gdtl page from img alt')
eq(lg[0].imgkey, 'abc123', 'gdtl imgkey')
eq(lg[0].sUrl, 'https://e-hentai.org/s/abc123/55-1', 'gdtl sUrl')
eq(lg[0].thumb, 'https://ehgt.org/t/aa/bb/55-780-1200-0001.jpg', 'gdtl thumb URL')
eq(lg[0].thumbWidth, 780, 'gdtl thumb width from URL tail')
eq(lg[0].thumbHeight, 1200, 'gdtl thumb height from URL tail')
eq(lg[0].spriteWidth, 0, 'gdtl is whole-image fallback, not sprite')
eq(lg[1].thumbWidth, 1600, 'gdtl landscape width from URL tail')
eq(lg[1].thumbHeight, 900, 'gdtl landscape height from URL tail')

// Preview tile sizing (EhSpriteThumbnail fitHeight): a fixed row HEIGHT, the WIDTH follows each thumb's
// true aspect. This is the no-white-border contract — the box matches the thumb exactly, never a fixed
// tile that letterboxes short/landscape thumbs. EH preview heights are NOT uniform across a page
// (cover/landscape pages differ), so a fixed tile height WOULD pad; fit-height never does.
const previewBox = (thumbW, thumbH, H) => ({ w: (thumbW * H) / thumbH, h: H })
const VARYING = '<div id="gdt" class="gt200">' +
  '<a href="https://e-hentai.org/s/aaa/9-1"><div title="Page 1" style="width:200px;height:250px;background:transparent url(https://h.net/9-0.webp) -0px 0 no-repeat"></div></a>' +
  '<a href="https://e-hentai.org/s/bbb/9-2"><div title="Page 2" style="width:200px;height:111px;background:transparent url(https://h.net/9-0.webp) -200px 0 no-repeat"></div></a></div>'
const vimg = parseImages(VARYING)
ok(vimg[0].thumbHeight !== vimg[1].thumbHeight, 'real EH pages have differing thumb heights (250 vs 111) → fixed-tile height would white-border')
const H = 150
const b0 = previewBox(vimg[0].thumbWidth, vimg[0].thumbHeight, H)
const b1 = previewBox(vimg[1].thumbWidth, vimg[1].thumbHeight, H)
eq(b0.h, H, 'fit-height: tall thumb box height == row height (no overhang)')
eq(b1.h, H, 'fit-height: short/landscape thumb box height == row height (no overhang)')
ok(Math.abs(b0.w / b0.h - vimg[0].thumbWidth / vimg[0].thumbHeight) < 1e-9, 'fit-height: box keeps thumb0 true aspect (no white padding)')
ok(Math.abs(b1.w / b1.h - vimg[1].thumbWidth / vimg[1].thumbHeight) < 1e-9, 'fit-height: box keeps thumb1 true aspect (no white padding)')
ok(b0.w !== b1.w, 'fit-height: differing aspects → differing widths (portrait vs landscape sit side by side)')

// favorite state (#fav sprite): favorited → favcat slot (Y-2)/19 + favTitle; not favorited → empty.
console.log('— favorite state (#fav sprite) —')
const parseFav = (html) => {
  const dm = html.match(RE.favDiv)
  if (!dm) return { favcat: '', favTitle: '' }
  const ym = dm[1].match(RE.favY)
  const tm = dm[1].match(RE.favTitle)
  if (!ym || !tm) return { favcat: '', favTitle: '' }
  const y = parseInt(ym[1], 10)
  const slot = Math.floor((y - 2) / 19)
  return { favcat: slot >= 0 && slot <= 9 ? `${slot}` : '', favTitle: htmlUnescape(tm[1].trim()) }
}
// Favorited: inner sprite div with background-position Y → slot, title = favcat name.
const FAV_ON = `<div id="fav"><div class="i" style="background-image:url(https://ehgt.org/g/fav.png); background-position:0px -116px; margin-left:26px" title="普通"></div></div><a id="favoritelink" href="#">普通</a>`
eq(parseFav(FAV_ON).favcat, '6', 'favorited Y=116 → favcat slot (116-2)/19 = 6')
eq(parseFav(FAV_ON).favTitle, '普通', 'favorited → favTitle from sprite title')
// Attribute order independence (title BEFORE background-position) — hardening per adversarial review.
const FAV_REORDERED = `<div id="fav"><div class="i" title="普通" style="background-position:0px -116px"></div></div>`
eq(parseFav(FAV_REORDERED).favcat, '6', 'favorited still parses with title before style (order-independent)')
eq(parseFav(FAV_REORDERED).favTitle, '普通', 'favTitle still parses when reordered')
// Slot 0 (Y=2) and slot 9 (Y=173) bounds.
eq(parseFav(`<div id="fav"><div style="background-position:0px -2px" title="A"></div></div>`).favcat, '0', 'Y=2 → slot 0')
eq(parseFav(`<div id="fav"><div style="background-position:0px -173px" title="J"></div></div>`).favcat, '9', 'Y=173 → slot 9')
// Not favorited: empty #fav, no inner sprite → no favcat/favTitle.
eq(parseFav(`<div id="fav"></div><a id="favoritelink" href="#"><img src="x"/> Add to Favorites</a>`).favcat, '', 'not favorited → empty favcat')
eq(parseFav(`<div id="fav"></div>`).favTitle, '', 'not favorited → empty favTitle')

// real fixture
const fx = join(ROOT, 'scripts/fixtures/gallery_detail.html')
if (existsSync(fx)) {
  console.log('— real e-hentai.org detail fixture —')
  const h = readFileSync(fx, 'utf8')
  ok(g1(h, RE.en).length > 0, 'real enTitle present')
  ok(/^[0-9a-f]+$/.test(g1(h, RE.apikey)), 'real apikey hex')
  ok(+g1(h, RE.length) > 0, 'real length > 0')
  ok(+g1(h, RE.rating) > 0, 'real rating > 0')
  ok(parseRatingColor(h) === '', 'real fixture: not personally rated → colorRating "" (orange)')
  ok(parseRatingFallBack(h) >= 0 && parseRatingFallBack(h) <= 5, 'real ratingFallBack in 0..5')
  ok(g1(h, RE.lang).trim().length > 0, 'real language present')
  ok(/MiB|KiB|GiB|B/.test(g1(h, RE.fileSize)), 'real fileSize unit')
  ok(+g1(h, RE.ratingCount) > 0, 'real ratingCount > 0')
  ok(/\d{4}-\d{2}-\d{2}/.test(g1(h, RE.posted)), 'real posted date')
  ok(/^\d+$/.test(g1(h, RE.torrent)), 'real torrentCount numeric')
  const tg = parseTags(h), im = parseImages(h)
  ok(tg.length >= 1, 'real tag groups >= 1')
  ok(im.length >= 1 && im.every((x) => x.thumb.startsWith('https://') && x.sUrl.includes('/s/')), 'real previews valid')
  ok(parsePageCount(h) >= 1, 'real preview page count >= 1')
  // gallery_detail.html is a NOT-favorited gallery (empty #fav) → no spurious favorite state.
  const fv = parseFav(h)
  ok(fv.favcat === '' && fv.favTitle === '', 'real (not-favorited) fixture → no favorite state')
  if (!failures) console.log(`  ✓ title/apikey/length/rating, ${tg.length} tag groups, ${im.length} previews`)
} else {
  console.log('— real fixture absent; synthetic-only —')
}

// A real FAVORITED fixture (authed) → valid favcat slot + non-empty favTitle.
const favFx = join(ROOT, 'scripts/fixtures/gdetail_real.html')
if (existsSync(favFx)) {
  console.log('— real favorited detail fixture (gdetail_real.html) —')
  const fv = parseFav(readFileSync(favFx, 'utf8'))
  ok(/^[0-9]$/.test(fv.favcat), `real favorited → favcat slot 0-9 (got ${JSON.stringify(fv.favcat)})`)
  ok(fv.favTitle.length > 0, `real favorited → favTitle (got ${JSON.stringify(fv.favTitle)})`)
  if (!failures) console.log(`  ✓ favcat=${fv.favcat} favTitle=${fv.favTitle}`)
}

// Structural guards for the ArkTS model/parser path.
const modelSrc = readFileSync(join(ROOT, 'shared/src/main/ets/model/EhGallery.ets'), 'utf8')
ok(/archiverLink:\s*string/.test(modelSrc), 'EhGallery carries archiverLink')
ok(/visible:\s*string/.test(modelSrc), 'EhGallery carries visible')
ok(/parentTitle:\s*string/.test(modelSrc), 'EhGallery carries parentTitle')
ok(/export class EhGalleryVersion/.test(modelSrc) && /newerVersions:\s*EhGalleryVersion\[\]/.test(modelSrc),
  'EhGallery carries parsed newer-version links')
const parserSrc = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhGalleryDetailParser.ets'), 'utf8')
ok(/RE_ARCHIVER_URL/.test(parserSrc) && /archiver\\.php/.test(parserSrc) && /RE_ARCHIVER_OR/.test(parserSrc),
  'detail parser supports modern archiver URL plus older or-token fallback')
ok(/RE_VISIBLE/.test(parserSrc) && /\.visible\s*=/.test(parserSrc), 'detail parser fills visible')
ok(/parentTitle/.test(parserSrc), 'detail parser fills parent display text')
ok(/parseNewerVersions/.test(parserSrc) && /RE_NEWER_BLOCK/.test(parserSrc),
  'detail parser fills newer-version links')
ok(/RE_RATING_POS/.test(parserSrc) && /\.ratingFallBack\s*=/.test(parserSrc), 'detail parser fills ratingFallBack from rating sprite')
const imageParserSrc = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhGalleryImageParser.ets'), 'utf8')
ok(/RE_SMALL_PREVIEW/.test(imageParserSrc), 'image parser has gdtm small-thumb branch')
ok(/parseSmallThumbs/.test(imageParserSrc), 'image parser parses gdtm sprite thumbnails')
ok(/hasImage/.test(imageParserSrc), 'image parser dedupes overlapping preview layouts')
ok(/RE_LARGE_PREVIEW/.test(imageParserSrc), 'image parser has gdtl large-thumb branch')
ok(/parseLargeThumbDims/.test(imageParserSrc), 'image parser derives gdtl dimensions from thumb URL')
const spriteSrc = readFileSync(join(ROOT, 'shared/src/main/ets/components/EhSpriteThumbnail.ets'), 'utf8')
ok(/private wholeImageAspect\(\): number/.test(spriteSrc), 'whole-image fallback computes aspect from parsed thumb dimensions')
ok(/\.aspectRatio\(this\.wholeImageAspect\(\)\)/.test(spriteSrc), 'whole-image fallback uses parsed aspect, not hardcoded 0.7')

if (failures > 0) { console.error(`\n✗ gallery-detail parser contract: ${failures} failure(s)`); process.exit(1) }
console.log('\n✓ gallery-detail parser contract passed')
