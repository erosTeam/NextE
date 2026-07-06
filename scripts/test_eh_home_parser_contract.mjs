#!/usr/bin/env node
/**
 * Contract for EhHomeParser (GET /home.php image limits). Mirrors the ArkTS parser over compact
 * fixtures so the FE-derived strong-value mapping cannot silently drift.
 * Run: node scripts/test_eh_home_parser_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const src = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhHomeParser.ets'), 'utf8')
let failures = 0
function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    console.error(`✗ ${name}: expected ${e}, got ${a}`)
    failures += 1
  }
}
function ok(name, cond) {
  if (!cond) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

function strongNumbers(html) {
  const out = []
  const re = /<strong[^>]*>([\s\S]*?)<\/strong>/g
  let m
  while ((m = re.exec(html)) !== null) {
    const raw = m[1].replace(/<[^>]*>/g, '').trim()
    const value = Number.parseInt(raw.replace(/,/g, ''), 10)
    if (!Number.isNaN(value)) out.push(value)
  }
  return out
}
function homebox(html) {
  return (html.match(/<div[^>]*class="[^"]*\bhomebox\b[^"]*"[^>]*>([\s\S]*?)<\/div>/) || ['', ''])[1]
}
function attr(tag, name) {
  return (tag.match(new RegExp(`${name}=["']([^"']*)["']`, 'i')) || ['', ''])[1]
}
function resolveUrl(raw) {
  if (raw.startsWith('https://') || raw.startsWith('http://')) return raw
  if (raw.startsWith('/')) return `https://e-hentai.org${raw}`
  if (raw.length > 0) return `https://e-hentai.org/${raw}`
  return ''
}
function formBody(form) {
  const parts = []
  const re = /<input\b[^>]*>/g
  let m
  while ((m = re.exec(form)) !== null) {
    const name = attr(m[0], 'name')
    if (name.length > 0) parts.push(`${encodeURIComponent(name)}=${encodeURIComponent(attr(m[0], 'value'))}`)
  }
  return parts.join('&')
}
function resetAction(html) {
  const formRe = /<form\b[\s\S]*?<\/form>/g
  let formMatch
  while ((formMatch = formRe.exec(html)) !== null) {
    const form = formMatch[0]
    const text = form.replace(/<[^>]*>/g, ' ')
    const action = attr(form, 'action')
    if (text.includes('Reset') || text.includes('reset') || form.includes('Reset') || form.includes('reset') || action.includes('reset')) {
      return {
        resetActionUrl: resolveUrl(action) || 'https://e-hentai.org/home.php',
        resetActionMethod: attr(form, 'method').toUpperCase() === 'POST' ? 'POST' : 'GET',
        resetActionBody: formBody(form),
      }
    }
  }
  const href = (html.match(/<a\b[^>]*href="([^"]*(?:reset|limit)[^"]*)"[^>]*>[\s\S]*?(?:Reset|reset)[\s\S]*?<\/a>/) || ['', ''])[1]
  if (href.length > 0) {
    return { resetActionUrl: resolveUrl(href), resetActionMethod: 'GET', resetActionBody: '' }
  }
  return { resetActionUrl: '', resetActionMethod: '', resetActionBody: '' }
}
function parseHome(html) {
  const box = homebox(html)
  const scoped = box.length > 0 ? box : html
  const text = scoped.replace(/<[^>]*>/g, ' ')
  const values = strongNumbers(scoped)
  const highResolutionLimited = text.includes('high-resolution images can be limited')
  const action = resetAction(scoped)
  if (values.length < 3) {
    return {
      currentLimit: 0,
      totLimit: 0,
      resetCost: 0,
      ...action,
      highResolutionLimited,
      unlockCost: values.length > 0 ? values[0] : 0,
    }
  }
  return {
    currentLimit: values[0],
    totLimit: values[1],
    resetCost: values[2],
    ...action,
    highResolutionLimited,
    unlockCost: 0,
  }
}

const normal = `
<body>
  <div class="stuffbox">
    <div class="homebox">
      <p>You are currently at <strong>4,321</strong> out of <strong>10,000</strong> image views.</p>
      <p>Reset cost: <strong>125</strong> GP</p>
      <form method="post" action="/home.php">
        <input type="hidden" name="reset" value="1">
        <input type="hidden" name="sk" value="abc">
        <input type="submit" value="Reset">
      </form>
    </div>
  </div>
</body>`
check('normal image limits', parseHome(normal), {
  currentLimit: 4321,
  totLimit: 10000,
  resetCost: 125,
  resetActionUrl: 'https://e-hentai.org/home.php',
  resetActionMethod: 'POST',
  resetActionBody: 'reset=1&sk=abc',
  highResolutionLimited: false,
  unlockCost: 0,
})

const limited = `
<body>
  <div class="stuffbox">
    <div class="homebox">
      <p>Your high-resolution images can be limited.</p>
      <p>Unlock cost: <strong>2,500</strong> GP</p>
    </div>
  </div>
</body>`
check('high-resolution unlock cost', parseHome(limited), {
  currentLimit: 0,
  totLimit: 0,
  resetCost: 0,
  resetActionUrl: '',
  resetActionMethod: '',
  resetActionBody: '',
  highResolutionLimited: true,
  unlockCost: 2500,
})

const ipBasedHighResolutionQuota = `
<body>
  <div class="stuffbox">
    <div class="homebox">
      <p>Due to widespread usage of bulk downloaders, high-resolution images can be limited.</p>
      <p>You are currently using IP-based limits. No restrictions are currently in effect.</p>
      <p>You can get a Bronze Star or the More Pages hathperk to tie image limits to your account.</p>
      <p>Alternatively, you can unlock a high-resolution quota for 24 hours by spending <strong>20,000</strong> GP.</p>
      <p>Note that for the latter, clearing your cookies will revert you to IP-based limits.</p>
    </div>
  </div>
</body>`
check('ip-based high-resolution quota unlock copy', parseHome(ipBasedHighResolutionQuota), {
  currentLimit: 0,
  totLimit: 0,
  resetCost: 0,
  resetActionUrl: '',
  resetActionMethod: '',
  resetActionBody: '',
  highResolutionLimited: true,
  unlockCost: 20000,
})

const resetLink = `
<body>
  <div class="stuffbox">
    <div class="homebox">
      <p><strong>1</strong> / <strong>2</strong> Reset cost: <strong>3</strong></p>
      <a href="/home.php?reset=1&sk=abc">Reset Limit</a>
    </div>
  </div>
</body>`
check('image limit reset link action', parseHome(resetLink), {
  currentLimit: 1,
  totLimit: 2,
  resetCost: 3,
  resetActionUrl: 'https://e-hentai.org/home.php?reset=1&sk=abc',
  resetActionMethod: 'GET',
  resetActionBody: '',
  highResolutionLimited: false,
  unlockCost: 0,
})

ok('parser scopes to homebox and reads strong values', src.includes('homebox(html)') && src.includes('strongNumbers'))
ok('parser maps >=3 values to current/total/reset', /values\.length < 3[\s\S]*new EhHome\(values\[0\], values\[1\], values\[2\]/.test(src))
ok('parser maps <3 values to unlockCost', /values\.length > 0 \? values\[0\] : 0/.test(src))
ok('parser detects high-resolution limitation text', src.includes('high-resolution images can be limited'))
ok('parser extracts reset form/link action', src.includes('resetAction(homebox.length > 0 ? homebox : html)') && src.includes('formBody(form)'))

if (failures === 0) {
  console.log('✓ eh home parser contract passed')
  process.exit(0)
}
console.error(`✗ eh home parser contract: ${failures} failure(s)`)
process.exit(1)
