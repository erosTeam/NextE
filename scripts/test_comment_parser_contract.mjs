#!/usr/bin/env node
// Contract test for EhCommentParser. Mirrors the ArkTS regex EXACTLY. Synthetic + real fixture.
// Run: node scripts/test_comment_parser_contract.mjs   (must report 0 failure(s))
import fs from 'fs'

const RE_BLOCK = '<div class="c1">[\\s\\S]*?<div class="c6" id="comment_(\\d+)">([\\s\\S]*?)</div>([\\s\\S]*?)(?=<a name="c\\d+"></a><div class="c1">|$)'
const RE_DATE = /Posted on ([^<]+?) by:/
const RE_AUTHOR = /by:\s*(?:&nbsp;\s*)*<a[^>]*>([^<]+)<\/a>/
const RE_MEMBER_ID = /index\.php\?showuser=(\d+)/
const RE_SCORE = /<div class="c5 nosel"[^>]*>[\s\S]*?([+-]\d+)/
const RE_C4 = /<div class="c4 nosel"[^>]*>([\s\S]*?)<\/div>/
const RE_C7 = /<div class="c7"[^>]*>([\s\S]*?)<\/div>/
const RE_SPAN = /<span[^>]*>([\s\S]*?)<\/span>/g
const RE_POSTED_PARTS = /(\d{1,2})\s+([A-Za-z]+)\s+(\d{4}),\s+(\d{1,2}):(\d{2})/
const g1 = (t, re) => { const m = t.match(re); return m && m[1] !== undefined ? m[1] : '' }
function stripHtml(h) {
  return h.replace(/<br\s*\/?>/g, '\n').replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#039;/g, "'").replace(/&amp;/g, '&').trim()
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
    const c4 = g1(m[0], RE_C4)
    out.push({
      commentId: m[1], contentText: stripHtml(m[2]),
      postedTime: localPostedTime(g1(m[0], RE_DATE).trim()), author: g1(m[0], RE_AUTHOR).trim(),
      memberId: g1(m[0], RE_MEMBER_ID).trim(),
      score: g1(m[0], RE_SCORE).trim(), vote: parseVote(c4),
      canEdit: c4.includes('edit_'), canVote: c4.includes('vote_'),
      scoreDetails: parseScoreDetails(m[3] || ''),
      isUploader: m[0].includes('Uploader Comment'),
    })
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
for (const field of ['memberId', 'vote', 'canEdit', 'canVote', 'scoreDetails']) {
  if (!new RegExp(`${field}:`).test(modelSrc)) fail(`model missing ${field}`)
}
if (!/RE_MEMBER_ID/.test(parserSrc) || !/parseVote/.test(parserSrc) || !/parseScoreDetails/.test(parserSrc) || !/localPostedTime/.test(parserSrc)) {
  fail('parser missing comment metadata helpers')
}

if (failures === 0) { console.log('✓ comment parser contract: all cases pass'); process.exit(0) }
else { console.error(`✗ comment parser contract: ${failures} failure(s)`); process.exit(1) }
