#!/usr/bin/env node
// Contract test for EhCommentParser. Mirrors the ArkTS regex EXACTLY. Synthetic + real fixture.
// Run: node scripts/test_comment_parser_contract.mjs   (must report 0 failure(s))
import fs from 'fs'

const RE_BLOCK = '<div class="c1">[\\s\\S]*?(?=<a name="c\\d+"></a><div class="c1">|$)'
const RE_BODY_OPEN = /<div class="c6" id="comment_(\d+)">/
const RE_DATE = /Posted on ([^<]+?) by:/
const RE_AUTHOR = /by:\s*(?:&nbsp;\s*)*<a[^>]*>([^<]+)<\/a>/
const RE_MEMBER_ID = /index\.php\?showuser=(\d+)/
const RE_SCORE = /<div class="c5 nosel"[^>]*>[\s\S]*?([+-]\d+)/
const RE_C4 = /<div class="c4 nosel"[^>]*>([\s\S]*?)<\/div>/
const RE_C7 = /<div class="c7"[^>]*>([\s\S]*?)<\/div>/
const RE_SPAN = /<span[^>]*>([\s\S]*?)<\/span>/g
const RE_POSTED_PARTS = /(\d{1,2})\s+([A-Za-z]+)\s+(\d{4}),\s+(\d{1,2}):(\d{2})/
const g1 = (t, re) => { const m = t.match(re); return m && m[1] !== undefined ? m[1] : '' }
const namedEntities = new Map([
  ['amp', '&'], ['lt', '<'], ['gt', '>'], ['quot', '"'], ['apos', "'"], ['nbsp', ' '],
])
function htmlUnescape(s) {
  if (!s || !s.includes('&')) return s
  return s.replace(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);/g, (match, ent) => {
    if (ent[0] === '#') {
      const code = ent[1] === 'x' || ent[1] === 'X'
        ? Number.parseInt(ent.slice(2), 16)
        : Number.parseInt(ent.slice(1), 10)
      return Number.isNaN(code) || code <= 0 || code > 0x10ffff ? match : String.fromCodePoint(code)
    }
    return namedEntities.get(ent) ?? match
  })
}
function stripHtmlFragment(h) {
  return htmlUnescape(h.replace(/<br\s*\/?>/g, '\n').replace(/<[^>]+>/g, '')).replace(/\u00A0/g, ' ')
}
function stripHtmlNoLinks(h) {
  return stripHtmlFragment(h).trim()
}
function trimBodyResult(text, links, spans, images) {
  const startTrim = text.length - text.trimStart().length
  const endTrim = text.length - text.trimEnd().length
  const end = text.length - endTrim
  const trimmedText = startTrim < end ? text.substring(startTrim, end) : ''
  return {
    text: trimmedText,
    links: links
      .filter(l => l.end > startTrim && l.start < end)
      .map(l => ({ start: l.start - startTrim, end: l.end - startTrim, url: l.url })),
    spans: spans
      .filter(s => s.end > startTrim && s.start < end)
      .map(s => ({
        start: s.start - startTrim,
        end: s.end - startTrim,
        url: s.url || '',
        bold: !!s.bold,
        italic: !!s.italic,
        underline: !!s.underline,
        strike: !!s.strike,
        color: s.color || '',
      })),
    images: images.map(image => ({
      position: Math.max(0, Math.min(trimmedText.length, image.position - startTrim)),
      src: image.src,
      href: image.href,
      alt: image.alt,
    })),
  }
}
function parseBody(h) {
  const result = { text: '', links: [], spans: [], images: [] }
  parseInlineHtml(h, {}, result)
  return trimBodyResult(result.text, result.links, result.spans, result.images)
}
function appendStyledText(result, raw, style) {
  if (!raw) return
  const text = htmlUnescape(raw).replace(/\u00A0/g, ' ')
  if (!text) return
  const start = result.text.length
  result.text += text
  const end = result.text.length
  if (style.url) result.links.push({ start, end, url: style.url })
  if (style.url || style.bold || style.italic || style.underline || style.strike || style.color) {
    result.spans.push({
      start, end,
      url: style.url || '',
      bold: !!style.bold,
      italic: !!style.italic,
      underline: !!style.underline,
      strike: !!style.strike,
      color: style.color || '',
    })
  }
}
function appendInlineImage(result, tag, style) {
  const src = attrValue(tag, 'src')
  if (!src) return
  result.images.push({
    position: result.text.length,
    src,
    href: style.url || '',
    alt: attrValue(tag, 'alt'),
  })
}
function tagName(tag) {
  const m = tag.match(/^<\s*\/?\s*([A-Za-z0-9]+)/)
  return m && m[1] ? m[1].toLowerCase() : ''
}
function supportedInlineTag(name) {
  return ['a', 'strong', 'b', 'em', 'i', 'u', 'del', 's', 'strike', 'span'].includes(name)
}
function findClosingTag(html, from, name) {
  const re = new RegExp(`<\\s*\\/?\\s*${name}\\b[^>]*>`, 'gi')
  re.lastIndex = from
  let depth = 1
  let m
  while ((m = re.exec(html)) !== null) {
    const token = m[0] || ''
    if (token.startsWith('</')) {
      depth--
      if (depth === 0) return m.index ?? -1
    } else if (!token.endsWith('/>')) {
      depth++
    }
  }
  return -1
}
function attrValue(tag, name) {
  const re = new RegExp(`${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i')
  const m = tag.match(re)
  const value = m ? (m[1] ?? m[2] ?? m[3] ?? '') : ''
  return htmlUnescape(value).replace(/\u00A0/g, ' ').trim()
}
function applyCssStyle(style, raw) {
  const css = raw.toLowerCase()
  if (css.includes('font-weight') && (css.includes('bold') || css.includes('700'))) style.bold = true
  if (css.includes('font-style') && css.includes('italic')) style.italic = true
  if (css.includes('text-decoration')) {
    if (css.includes('underline')) style.underline = true
    if (css.includes('line-through')) style.strike = true
  }
  const color = raw.match(/(?:^|;)\s*color\s*:\s*(#[0-9a-fA-F]{3,8})/)
  if (color && color[1]) style.color = color[1]
}
function styleForTag(name, tag, parent) {
  const style = { ...parent }
  if (name === 'a') style.url = attrValue(tag, 'href')
  else if (name === 'strong' || name === 'b') style.bold = true
  else if (name === 'em' || name === 'i') style.italic = true
  else if (name === 'u') style.underline = true
  else if (name === 'del' || name === 's' || name === 'strike') style.strike = true
  else if (name === 'span') applyCssStyle(style, attrValue(tag, 'style'))
  return style
}
function parseInlineHtml(html, style, result) {
  const links = []
  let cursor = 0
  while (cursor < html.length) {
    const tagStart = html.indexOf('<', cursor)
    if (tagStart < 0) {
      appendStyledText(result, html.substring(cursor), style)
      return
    }
    if (tagStart > cursor) appendStyledText(result, html.substring(cursor, tagStart), style)
    const tagEnd = html.indexOf('>', tagStart + 1)
    if (tagEnd < 0) {
      appendStyledText(result, html.substring(tagStart), style)
      return
    }
    const tag = html.substring(tagStart, tagEnd + 1)
    const name = tagName(tag)
    if (tag.startsWith('</')) {
      cursor = tagEnd + 1
      continue
    }
    if (name === 'br') {
      appendStyledText(result, '\n', style)
      cursor = tagEnd + 1
      continue
    }
    if (name === 'img') {
      appendInlineImage(result, tag, style)
      cursor = tagEnd + 1
      continue
    }
    if (name === 'div' && attrValue(tag, 'id') === 'spa') {
      const spaCloseStart = findClosingTag(html, tagEnd + 1, name)
      const spaCloseEnd = spaCloseStart < 0 ? -1 : html.indexOf('>', spaCloseStart + 1)
      cursor = spaCloseEnd < 0 ? html.length : spaCloseEnd + 1
      continue
    }
    const closeStart = findClosingTag(html, tagEnd + 1, name)
    if (closeStart < 0 || !supportedInlineTag(name)) {
      cursor = tagEnd + 1
      continue
    }
    const nextStyle = styleForTag(name, tag, style)
    const before = result.text.length
    const beforeImageCount = result.images.length
    parseInlineHtml(html.substring(tagEnd + 1, closeStart), nextStyle, result)
    if (name === 'a' && result.text.length === before && result.images.length === beforeImageCount && nextStyle.url) {
      appendStyledText(result, nextStyle.url, nextStyle)
    }
    const closeEnd = html.indexOf('>', closeStart + 1)
    cursor = closeEnd < 0 ? html.length : closeEnd + 1
  }
}
function stripHtml(h) {
  return stripHtmlNoLinks(h)
}
const monthIndex = (m) => [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
].indexOf(m)
const pad2 = (n) => n < 10 ? `0${n}` : `${n}`
function localPostedTime(raw) {
  const m = raw.match(RE_POSTED_PARTS)
  if (!m) return raw
  const month = monthIndex(m[2])
  if (month < 0) return raw
  const dt = new Date(Date.UTC(+m[3], month, +m[1], +m[4], +m[5], 0))
  return `${dt.getFullYear()}-${pad2(dt.getMonth() + 1)}-${pad2(dt.getDate())} ${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`
}
function nthAnchorStyle(html, n) {
  const re = /<a[^>]*>/g
  let index = 0
  let m
  while ((m = re.exec(html)) !== null) {
    index += 1
    if (index === n) {
      const style = (m[0] || '').match(/style="([^"]*)"/)
      return style && style[1] ? style[1].trim() : ''
    }
  }
  return ''
}
function parseVote(c4) {
  if (!c4) return 0
  if (nthAnchorStyle(c4, 1).length > 0) return 1
  if (nthAnchorStyle(c4, 2).length > 0) return -1
  return 0
}
function parseScoreDetails(trailingHtml) {
  const c7 = g1(trailingHtml, RE_C7)
  if (!c7) return []
  const out = []
  const firstTag = c7.match(/<[^>]+>/)
  const leadHtml = firstTag && firstTag.index !== undefined ? c7.substring(0, firstTag.index) : c7
  const lead = stripHtml(leadHtml).replace(/,\s*$/, '').trim()
  if (lead.length > 0) out.push(lead)
  let m
  while ((m = RE_SPAN.exec(c7)) !== null) {
    const text = stripHtml(m[1] || '')
    if (text.length > 0) out.push(text)
  }
  RE_SPAN.lastIndex = 0
  return out
}
function parse(html) {
  const out = []
  const re = new RegExp(RE_BLOCK, 'g')
  let m
  while ((m = re.exec(html)) !== null) {
    const block = m[0] || ''
    const bodyOpen = block.match(RE_BODY_OPEN)
    if (!bodyOpen || bodyOpen.index === undefined || !bodyOpen[1]) continue
    const bodyTagEnd = block.indexOf('>', bodyOpen.index)
    const bodyCloseStart = bodyTagEnd < 0 ? -1 : findClosingTag(block, bodyTagEnd + 1, 'div')
    const bodyCloseEnd = bodyCloseStart < 0 ? -1 : block.indexOf('>', bodyCloseStart + 1)
    if (bodyTagEnd < 0 || bodyCloseStart < 0 || bodyCloseEnd < 0) continue
    const c4 = g1(block, RE_C4)
    const body = parseBody(block.substring(bodyTagEnd + 1, bodyCloseStart))
    const comment = {
      commentId: bodyOpen[1], contentText: body.text, contentLinks: body.links, contentSpans: body.spans, contentImages: body.images,
      postedTime: localPostedTime(g1(block, RE_DATE).trim()), author: g1(block, RE_AUTHOR).trim(),
      memberId: g1(block, RE_MEMBER_ID).trim(),
      score: g1(block, RE_SCORE).trim(), vote: parseVote(c4),
      canEdit: c4.includes('edit_'), canVote: c4.includes('vote_'),
      scoreDetails: parseScoreDetails(block.substring(bodyCloseEnd + 1)),
      isUploader: block.includes('Uploader Comment') || g1(block, RE_SCORE).trim().length === 0,
    }
    if (comment.contentText.length > 0 || comment.contentImages.length > 0) out.push(comment)
  }
  return out
}

let failures = 0
const fail = (m) => { console.error('✗ ' + m); failures++ }

// 1. Synthetic.
const synthetic = `
<a name="c1"></a><div class="c1"><div class="c2"><div class="c3">Posted on 22 May 2026, 13:49 by: &nbsp; <a href="https://forums.e-hentai.org/index.php?showuser=101">alice</a>&nbsp;</div><div class="c4 nosel"><a name="ulcomment"></a>Uploader Comment</div></div><div class="c6" id="comment_0">hello&nbsp;world<br />line2</div><div class="c7" id="cvotes_0"></div></div>
<a name="c2"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=202">bob</a></div><div class="c4 nosel"><a onclick="return vote_comment(202,8337138,1)" style="color:#0a0">+</a><a onclick="return vote_comment(202,8337138,-1)">-</a><a onclick="return edit_comment(8337138)">Edit</a></div><div class="c5 nosel" onclick="x">Score +12</div></div><div class="c6" id="comment_8337138">nice &amp; cool</div><div class="c7" id="cvotes_8337138">Base +10, <span>+2 helpful</span><span>-0 abuse</span></div></div>`
const syn = parse(synthetic)
if (syn.length !== 2) fail(`synthetic: expected 2 comments, got ${syn.length}`)
if (syn[0] && (syn[0].author !== 'alice' || syn[0].postedTime !== localPostedTime('22 May 2026, 13:49') || syn[0].contentText !== 'hello world\nline2')) fail(`syn c0 wrong: ${JSON.stringify(syn[0])}`)
if (syn[0] && (!syn[0].isUploader || syn[0].score !== '')) fail(`syn c0 uploader/score wrong: ${JSON.stringify(syn[0])}`)
if (syn[0] && (syn[0].memberId !== '101' || syn[0].vote !== 0 || syn[0].canVote || syn[0].canEdit || syn[0].scoreDetails.length !== 0)) fail(`syn c0 metadata wrong: ${JSON.stringify(syn[0])}`)
if (syn[1] && (syn[1].author !== 'bob' || syn[1].commentId !== '8337138' || syn[1].contentText !== 'nice & cool')) fail(`syn c1 wrong: ${JSON.stringify(syn[1])}`)
if (syn[1] && (syn[1].isUploader || syn[1].score !== '+12')) fail(`syn c1 uploader/score wrong: ${JSON.stringify(syn[1])}`)
if (syn[1] && (syn[1].memberId !== '202' || syn[1].vote !== 1 || !syn[1].canVote || !syn[1].canEdit)) fail(`syn c1 metadata wrong: ${JSON.stringify(syn[1])}`)
if (syn[1] && JSON.stringify(syn[1].scoreDetails) !== JSON.stringify(['Base +10', '+2 helpful', '-0 abuse'])) fail(`syn c1 scoreDetails wrong: ${JSON.stringify(syn[1])}`)

const downVote = parse(`<a name="c3"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=303">c</a></div><div class="c4 nosel"><a onclick="return vote_1()">+</a><a onclick="return vote_2()" style="color:#c00">-</a></div></div><div class="c6" id="comment_9">x</div></div>`)
if (downVote[0] && downVote[0].vote !== -1) fail(`downvote style should parse as -1: ${JSON.stringify(downVote[0])}`)

const uploaderWithoutMarker = parse(`<a name="c4"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=404">real-uploader</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_0">uploader text</div></div>`)
if (uploaderWithoutMarker[0] && !uploaderWithoutMarker[0].isUploader) fail(`score-less uploader should parse as uploader: ${JSON.stringify(uploaderWithoutMarker[0])}`)

const numericEntities = parse(`<a name="c5"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=505">d</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_10">&#37;realporn&#37; &amp; &#x25;literal&#x25;</div></div>`)
if (numericEntities[0] && numericEntities[0].contentText !== '%realporn% & %literal%') fail(`numeric entities should decode for literal matching: ${JSON.stringify(numericEntities[0])}`)

const linkedLabel = parse(`<a name="c6"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=606">e</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_11">see <a href="https://e-hentai.org/g/4029582/a90c43f079/">this gallery</a> ok</div></div>`)
if (linkedLabel[0] && linkedLabel[0].contentText !== 'see this gallery ok') fail(`linked label should stay readable without exposing href: ${JSON.stringify(linkedLabel[0])}`)
if (linkedLabel[0] && linkedLabel[0].contentText.includes('4029582')) fail(`linked label must not append raw URL into visible text: ${JSON.stringify(linkedLabel[0])}`)
if (linkedLabel[0] && JSON.stringify(linkedLabel[0].contentLinks) !== JSON.stringify([{ start: 4, end: 16, url: 'https://e-hentai.org/g/4029582/a90c43f079/' }])) fail(`linked label href metadata wrong: ${JSON.stringify(linkedLabel[0])}`)
if (linkedLabel[0] && JSON.stringify(linkedLabel[0].contentSpans) !== JSON.stringify([{ start: 4, end: 16, url: 'https://e-hentai.org/g/4029582/a90c43f079/', bold: false, italic: false, underline: false, strike: false, color: '' }])) fail(`linked label render span wrong: ${JSON.stringify(linkedLabel[0])}`)

const richHtml = parse(`<a name="c7"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=707">f</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_12"><strong>bold</strong> <em>italic</em> <u>under</u> <del>gone</del> <span style="color:#ff00aa;font-weight:bold;font-style:italic;text-decoration:underline">style</span></div></div>`)
if (richHtml[0] && richHtml[0].contentText !== 'bold italic under gone style') fail(`rich html text wrong: ${JSON.stringify(richHtml[0])}`)
if (richHtml[0]) {
  const spans = richHtml[0].contentSpans
  const hasBold = spans.some(s => s.start === 0 && s.end === 4 && s.bold)
  const hasItalic = spans.some(s => richHtml[0].contentText.substring(s.start, s.end) === 'italic' && s.italic)
  const hasUnderline = spans.some(s => richHtml[0].contentText.substring(s.start, s.end) === 'under' && s.underline)
  const hasStrike = spans.some(s => richHtml[0].contentText.substring(s.start, s.end) === 'gone' && s.strike)
  const hasStyle = spans.some(s => richHtml[0].contentText.substring(s.start, s.end) === 'style' && s.bold && s.italic && s.underline && s.color === '#ff00aa')
  if (!hasBold || !hasItalic || !hasUnderline || !hasStrike || !hasStyle) fail(`rich html spans wrong: ${JSON.stringify(spans)}`)
}

const inlineImages = parse(`<a name="c8"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=808">g</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_13">before<a href="https://example.com/post"><img src="https://images.example/a.png" alt="A"/><img src='https://images.example/b.png' alt='B'></a>after</div></div>`)
if (inlineImages[0] && inlineImages[0].contentText !== 'beforeafter') fail(`inline image text should remain readable: ${JSON.stringify(inlineImages[0])}`)
if (inlineImages[0] && JSON.stringify(inlineImages[0].contentImages) !== JSON.stringify([
  { position: 6, src: 'https://images.example/a.png', href: 'https://example.com/post', alt: 'A' },
  { position: 6, src: 'https://images.example/b.png', href: 'https://example.com/post', alt: 'B' },
])) fail(`adjacent inline images should retain their shared position and link: ${JSON.stringify(inlineImages[0])}`)

const imageOnly = parse(`<a name="c9"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=909">h</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_14">\n  <img src="https://images.example/only.png" alt="only"/>\n</div></div>`)
if (imageOnly.length !== 1 || imageOnly[0].contentImages.length !== 1 || imageOnly[0].contentImages[0].position !== 0) fail(`image-only comment must survive body trimming: ${JSON.stringify(imageOnly)}`)

const spaPlaceholder = parse(`<a name="c10"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="https://forums.e-hentai.org/index.php?showuser=1001">i</a></div><div class="c4 nosel"></div></div><div class="c6" id="comment_15">before<div id="spa">hidden<img src="https://images.example/hidden.png"/></div>after</div></div>`)
if (spaPlaceholder[0] && (spaPlaceholder[0].contentText !== 'beforeafter' || spaPlaceholder[0].contentImages.length !== 0)) fail(`spa placeholder must not leak content: ${JSON.stringify(spaPlaceholder[0])}`)

// 2. Real fixture.
const realPath = new URL('./fixtures/gdetail_real.html', import.meta.url)
if (fs.existsSync(realPath)) {
  const real = parse(fs.readFileSync(realPath, 'utf8'))
  if (real.length < 3) fail(`real: too few comments (${real.length})`)
  const withAuthor = real.filter(c => c.author.length > 0).length
  const withDate = real.filter(c => /\d{4}/.test(c.postedTime)).length
  const withBody = real.filter(c => c.contentText.length > 0).length
  const withScore = real.filter(c => /^[+-]\d+$/.test(c.score)).length
  const withMember = real.filter(c => /^\d+$/.test(c.memberId)).length
  const uploaderCount = real.filter(c => c.isUploader).length
  if (withAuthor < real.length * 0.8) fail(`real: only ${withAuthor}/${real.length} have an author`)
  if (withDate < real.length * 0.8) fail(`real: only ${withDate}/${real.length} have a date`)
  if (withMember < real.length * 0.8) fail(`real: only ${withMember}/${real.length} have memberId`)
  if (withScore < 1) fail(`real: no comment scores parsed`)
  if (uploaderCount !== 1) fail(`real: expected exactly 1 uploader comment, got ${uploaderCount}`)
  console.log(`  real fixture: ${real.length} comments (${withAuthor} authors, ${withDate} dates, ${withBody} bodies, ${withScore} scored, ${withMember} member ids, ${uploaderCount} uploader)`)
} else {
  console.log('  (real detail fixture not present — synthetic only)')
}

const modelSrc = fs.readFileSync(new URL('../shared/src/main/ets/model/EhGalleryComment.ets', import.meta.url), 'utf8')
const parserSrc = fs.readFileSync(new URL('../shared/src/main/ets/parser/EhCommentParser.ets', import.meta.url), 'utf8')
for (const field of ['memberId', 'vote', 'canEdit', 'canVote', 'scoreDetails', 'contentLinks', 'contentImages']) {
  if (!new RegExp(`${field}:`).test(modelSrc)) fail(`model missing ${field}`)
}
if (!/RE_MEMBER_ID/.test(parserSrc) || !/parseVote/.test(parserSrc) || !/parseScoreDetails/.test(parserSrc) || !/localPostedTime/.test(parserSrc) || !/parseBody/.test(parserSrc)) {
  fail('parser missing comment metadata helpers')
}
if (!/appendInlineImage/.test(parserSrc) || !/name === 'img'/.test(parserSrc)) {
  fail('parser must retain inline image references')
}
if (!/attrValue\(tag, 'id'\) === 'spa'/.test(parserSrc)) {
  fail('parser must omit spa placeholder subtrees')
}

if (failures === 0) { console.log('✓ comment parser contract: all cases pass'); process.exit(0) }
else { console.error(`✗ comment parser contract: ${failures} failure(s)`); process.exit(1) }
