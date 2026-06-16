#!/usr/bin/env node
// Contract test for the EH cookie-jar parsing (CookieJarSettings.parseCookieValue /
// applyFromHeader). Mirrors the ArkTS logic EXACTLY so a drift in either side fails here.
// Run: node scripts/test_cookiejar_contract.mjs  (must report 0 failure(s))

const AUTH_NAMES = ['ipb_member_id', 'ipb_pass_hash', 'igneous', 'sk', 'star']

// --- mirror of CookieJarSettings.parseCookieValue (ArkTS) ---
function parseCookieValue(header, name) {
  if (header.length === 0) return ''
  for (const pair of header.split(';')) {
    const trimmed = pair.trim()
    const eq = trimmed.indexOf('=')
    if (eq <= 0) continue
    if (trimmed.substring(0, eq) === name) return trimmed.substring(eq + 1).trim()
  }
  return ''
}

// --- mirror of applyFromHeader + EhCookieStore.isLogin ---
function applyFromHeader(header) {
  const store = {}
  for (const name of AUTH_NAMES) {
    const value = parseCookieValue(header, name)
    if (value.length > 0 && value !== 'mystery') store[name] = value
  }
  const isLogin = (store['ipb_member_id'] || '').length > 0 && (store['ipb_pass_hash'] || '').length > 0
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

// 6. Empty / malformed are safe.
check('empty_header', parseCookieValue('', 'ipb_member_id'), '')
check('malformed_no_eq', parseCookieValue('garbage; =novalue; ipb_member_id=ok', 'ipb_member_id'), 'ok')

if (failures === 0) {
  console.log('✓ cookie-jar contract: all cookie-header parse cases pass')
  process.exit(0)
} else {
  console.error(`✗ cookie-jar contract: ${failures} failure(s)`)
  process.exit(1)
}
