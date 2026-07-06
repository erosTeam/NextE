#!/usr/bin/env node
// Contract test for the EH cookie-jar parsing (CookieJarSettings.parseCookieEntries /
// parseCookieValue / applyFromHeader). Mirrors the ArkTS logic so parser drift fails here.
// Run: node scripts/test_cookiejar_contract.mjs  (must report 0 failure(s))

const NW = 'nw'
const MEMBER = 'ipb_member_id'
const HASH = 'ipb_pass_hash'

function isCookieAttribute(fragment) {
  const eq = fragment.indexOf('=')
  const name = (eq >= 0 ? fragment.substring(0, eq) : fragment).trim().toLowerCase()
  return ['path', 'domain', 'expires', 'max-age', 'secure', 'httponly', 'samesite'].includes(name)
}

function appendCookieEntry(entries, seen, name, value) {
  if (name.length <= 0 || value.length <= 0 || name === NW || value === 'mystery' || seen.has(name)) return
  entries.push({ name, value })
  seen.add(name)
}

function parseJsonCookieEntries(text) {
  if (!text.startsWith('[') && !text.startsWith('{')) return []
  try {
    const root = JSON.parse(text)
    const source = Array.isArray(root) ? root : Array.isArray(root.cookies) ? root.cookies : []
    const entries = []
    const seen = new Set()
    for (const item of source) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) continue
      if (item.name === undefined || item.value === undefined) continue
      appendCookieEntry(entries, seen, `${item.name}`, `${item.value}`)
    }
    return entries
  } catch (_error) {
    return []
  }
}

function parseCookieFragments(fragments, entries, seen, setCookieLine) {
  for (const raw of fragments) {
    const fragment = raw.trim()
    if (fragment.length === 0) continue
    if (!setCookieLine && isCookieAttribute(fragment)) continue
    const eq = fragment.indexOf('=')
    if (eq <= 0) continue
    appendCookieEntry(entries, seen, fragment.substring(0, eq).trim(), fragment.substring(eq + 1).trim())
  }
}

function parseCookieLine(rawLine, entries, seen) {
  let line = rawLine.trim()
  if (line.length === 0) return
  const lower = line.toLowerCase()
  if (lower.startsWith('cookie:')) {
    line = line.substring('cookie:'.length).trim()
    parseCookieFragments(line.split(';'), entries, seen, false)
    return
  }
  if (lower.startsWith('set-cookie:')) {
    line = line.substring('set-cookie:'.length).trim()
    const parts = line.split(';')
    parseCookieFragments([parts.length > 0 ? parts[0] : line], entries, seen, true)
    return
  }
  if (line.includes(';')) {
    parseCookieFragments(line.split(';'), entries, seen, false)
    return
  }
  parseCookieFragments([line], entries, seen, false)
}

function parseCookieEntries(raw) {
  const text = raw.trim()
  if (text.length === 0) return []
  const jsonEntries = parseJsonCookieEntries(text)
  if (jsonEntries.length > 0) return jsonEntries
  const entries = []
  const seen = new Set()
  for (const line of text.replace(/\r/g, '\n').split('\n')) parseCookieLine(line, entries, seen)
  return entries
}

function parseCookieValue(header, name) {
  for (const entry of parseCookieEntries(header)) {
    if (entry.name === name) return entry.value
  }
  return ''
}

// --- mirror of applyFromHeader + EhCookieStore.isLogin ---
function applyFromHeader(header) {
  const store = {}
  for (const entry of parseCookieEntries(header)) {
    store[entry.name] = entry.value
  }
  const isLogin = (store[MEMBER] || '').length > 0 && (store[HASH] || '').length > 0
  return { store, isLogin }
}

let failures = 0
function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    console.error(`✗ ${name}: expected ${e}, got ${a}`)
    failures++
  }
}

// 1. Full EH table-site login header (note nw is forced separately, ignored here).
const full = 'ipb_member_id=1234567; ipb_pass_hash=0a1b2c3d4e5f60718293a4b5c6d7e8f9; igneous=deadbeefcafe; sk=abc; nw=1'
check('member_id', parseCookieValue(full, 'ipb_member_id'), '1234567')
check('pass_hash', parseCookieValue(full, 'ipb_pass_hash'), '0a1b2c3d4e5f60718293a4b5c6d7e8f9')
check('igneous', parseCookieValue(full, 'igneous'), 'deadbeefcafe')
check('absent_returns_empty', parseCookieValue(full, 'star'), '')
check('full_isLogin', applyFromHeader(full).isLogin, true)

// 2. ExHentai "no perks" sentinel: igneous=mystery must be treated as unset.
const mystery = 'ipb_member_id=42; ipb_pass_hash=hash; igneous=mystery'
check('mystery_dropped', applyFromHeader(mystery).store['igneous'], undefined)
check('mystery_still_login', applyFromHeader(mystery).isLogin, true)

// 3. Anonymous (only nw): not logged in.
check('anon_not_login', applyFromHeader('nw=1').isLogin, false)

// 4. Missing pass_hash: not logged in even with member id.
check('half_not_login', applyFromHeader('ipb_member_id=99').isLogin, false)

// 5. Combined headers (e-hentai.org + forums merge): first occurrence wins, whitespace tolerant.
const combined = 'ipb_member_id=111; ipb_pass_hash=aaa ; nw=1; ipb_member_id=222; ipb_pass_hash=bbb'
check('combined_first_wins_member', parseCookieValue(combined, 'ipb_member_id'), '111')
check('combined_trims_value', parseCookieValue(combined, 'ipb_pass_hash'), 'aaa')

// 6. Newline / Cookie: / Set-Cookie: formats are accepted; attributes are ignored.
const multiline = 'Cookie: ipb_member_id=321; path=/; ipb_pass_hash=hhh\nSet-Cookie: igneous=ig1; Path=/; Domain=.exhentai.org'
check('multiline_entries', parseCookieEntries(multiline), [
  { name: 'ipb_member_id', value: '321' },
  { name: 'ipb_pass_hash', value: 'hhh' },
  { name: 'igneous', value: 'ig1' },
])

// 7. Browser JSON export arrays are accepted.
const json = JSON.stringify([{ name: MEMBER, value: 'json-mid' }, { name: HASH, value: 'json-hash' }])
check('json_member', parseCookieValue(json, MEMBER), 'json-mid')
check('json_is_login', applyFromHeader(json).isLogin, true)

// 8. Empty / malformed are safe.
check('empty_header', parseCookieValue('', 'ipb_member_id'), '')
check('malformed_no_eq', parseCookieValue('garbage; =novalue; ipb_member_id=ok', 'ipb_member_id'), 'ok')

if (failures === 0) {
  console.log('✓ cookie-jar contract: all cookie-header parse cases pass')
  process.exit(0)
} else {
  console.error(`✗ cookie-jar contract: ${failures} failure(s)`)
  process.exit(1)
}
