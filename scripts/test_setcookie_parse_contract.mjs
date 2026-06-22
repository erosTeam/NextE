#!/usr/bin/env node
// Contract test for CookieJarSettings.applyFromSetCookie's extraction logic.
//
// The runtime captures auth cookies from HttpResponse.cookies (a comma/newline-joined blob of the server's
// Set-Cookie headers) by regex-extracting each known cookie name. This mirrors that exact regex so a
// refactor that breaks igneous capture (the ExHentai unlock) fails here instead of silently on device.
//
// Keep in lockstep with shared/src/main/ets/settings/CookieJarSettings.ets#applyFromSetCookie.

const AUTH_NAMES = ['ipb_member_id', 'ipb_pass_hash', 'igneous', 'sk', 'star']

// Mirror of the ArkTS extraction: per name, /name=([^;,\s]+)/, skip 'mystery'.
function extract(setCookie) {
  const out = {}
  for (const name of AUTH_NAMES) {
    const m = new RegExp(`${name}=([^;,\\s]+)`).exec(setCookie)
    if (m !== null && m[1].length > 0 && m[1] !== 'mystery') {
      out[name] = m[1]
    }
  }
  return out
}

let failures = 0
function check(label, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    console.error(`✗ ${label}\n   expected ${e}\n   actual   ${a}`)
    failures++
  } else {
    console.log(`✓ ${label}`)
  }
}

// 1. A real exhentai.org/uconfig.php response: igneous with attributes + path, joined with a comma.
check(
  'real igneous from uconfig.php blob',
  extract('igneous=1a2b3c4d5e6f7a8b; expires=Tue, 01-Jan-2030 00:00:00 GMT; path=/; domain=.exhentai.org'),
  { igneous: '1a2b3c4d5e6f7a8b' },
)

// 2. The non-donor placeholder MUST be skipped (this is the whole reason hasIgneous can be false).
check('igneous=mystery is skipped', extract('igneous=mystery; path=/; domain=.exhentai.org'), {})

// 3. A forums password-login response: identity cookies extracted from a multi-Set-Cookie blob.
check(
  'identity cookies from a login blob',
  extract(
    'ipb_member_id=2007706; path=/, ipb_pass_hash=0123456789abcdef0123456789abcdef; path=/, sk=zzz999; path=/',
  ),
  { ipb_member_id: '2007706', ipb_pass_hash: '0123456789abcdef0123456789abcdef', sk: 'zzz999' },
)

// 4. Empty / absent → nothing.
check('empty blob → nothing', extract(''), {})
check('no auth cookies → nothing', extract('foo=bar; baz=qux; path=/'), {})

// 5. The value must stop at the first delimiter, not swallow attributes.
check('value stops at ;', extract('igneous=deadbeef; HttpOnly'), { igneous: 'deadbeef' })

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`)
  process.exit(1)
}
console.log('\n✓ set-cookie parse contract: all checks passed')
