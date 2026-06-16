#!/usr/bin/env node
// Contract test for EhCommentParser. Mirrors the ArkTS regex EXACTLY. Synthetic + real fixture.
// Run: node scripts/test_comment_parser_contract.mjs   (must report 0 failure(s))
import fs from 'fs'

const RE_BLOCK = '<div class="c1">[\\s\\S]*?<div class="c6" id="comment_(\\d+)">([\\s\\S]*?)</div>'
const RE_DATE = /Posted on ([^<]+?) by:/
const RE_AUTHOR = /by:\s*(?:&nbsp;\s*)*<a[^>]*>([^<]+)<\/a>/
const RE_SCORE = /<div class="c5 nosel"[^>]*>[\s\S]*?([+-]\d+)/
const g1 = (t, re) => { const m = t.match(re); return m && m[1] !== undefined ? m[1] : '' }
function stripHtml(h) {
  return h.replace(/<br\s*\/?>/g, '\n').replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#039;/g, "'").replace(/&amp;/g, '&').trim()
}
function parse(html) {
  const out = []
  const re = new RegExp(RE_BLOCK, 'g')
  let m
  while ((m = re.exec(html)) !== null) {
    out.push({
      commentId: m[1], contentText: stripHtml(m[2]),
      postedTime: g1(m[0], RE_DATE).trim(), author: g1(m[0], RE_AUTHOR).trim(),
      score: g1(m[0], RE_SCORE).trim(), isUploader: m[0].includes('Uploader Comment'),
    })
  }
  return out
}

let failures = 0
const fail = (m) => { console.error('✗ ' + m); failures++ }

// 1. Synthetic.
const synthetic = `
<a name="c1"></a><div class="c1"><div class="c2"><div class="c3">Posted on 22 May 2026, 13:49 by: &nbsp; <a href="/uploader/alice">alice</a>&nbsp;</div><div class="c4 nosel"><a name="ulcomment"></a>Uploader Comment</div></div><div class="c6" id="comment_0">hello&nbsp;world<br />line2</div><div class="c7" id="cvotes_0"></div></div>
<a name="c2"></a><div class="c1"><div class="c2"><div class="c3">Posted on 23 May 2026, 09:00 by: <a href="/uploader/bob">bob</a></div><div class="c5 nosel" onclick="x">Score +12</div></div><div class="c6" id="comment_8337138">nice &amp; cool</div></div>`
const syn = parse(synthetic)
if (syn.length !== 2) fail(`synthetic: expected 2 comments, got ${syn.length}`)
if (syn[0] && (syn[0].author !== 'alice' || syn[0].postedTime !== '22 May 2026, 13:49' || syn[0].contentText !== 'hello world\nline2')) fail(`syn c0 wrong: ${JSON.stringify(syn[0])}`)
if (syn[0] && (!syn[0].isUploader || syn[0].score !== '')) fail(`syn c0 uploader/score wrong: ${JSON.stringify(syn[0])}`)
if (syn[1] && (syn[1].author !== 'bob' || syn[1].commentId !== '8337138' || syn[1].contentText !== 'nice & cool')) fail(`syn c1 wrong: ${JSON.stringify(syn[1])}`)
if (syn[1] && (syn[1].isUploader || syn[1].score !== '+12')) fail(`syn c1 uploader/score wrong: ${JSON.stringify(syn[1])}`)

// 2. Real fixture.
const realPath = new URL('./fixtures/gdetail_real.html', import.meta.url)
if (fs.existsSync(realPath)) {
  const real = parse(fs.readFileSync(realPath, 'utf8'))
  if (real.length < 3) fail(`real: too few comments (${real.length})`)
  const withAuthor = real.filter(c => c.author.length > 0).length
  const withDate = real.filter(c => /\d{4}/.test(c.postedTime)).length
  const withBody = real.filter(c => c.contentText.length > 0).length
  const withScore = real.filter(c => /^[+-]\d+$/.test(c.score)).length
  const uploaderCount = real.filter(c => c.isUploader).length
  if (withAuthor < real.length * 0.8) fail(`real: only ${withAuthor}/${real.length} have an author`)
  if (withDate < real.length * 0.8) fail(`real: only ${withDate}/${real.length} have a date`)
  if (withScore < 1) fail(`real: no comment scores parsed`)
  if (uploaderCount !== 1) fail(`real: expected exactly 1 uploader comment, got ${uploaderCount}`)
  console.log(`  real fixture: ${real.length} comments (${withAuthor} authors, ${withDate} dates, ${withBody} bodies, ${withScore} scored, ${uploaderCount} uploader)`)
} else {
  console.log('  (real detail fixture not present — synthetic only)')
}

if (failures === 0) { console.log('✓ comment parser contract: all cases pass'); process.exit(0) }
else { console.error(`✗ comment parser contract: ${failures} failure(s)`); process.exit(1) }
