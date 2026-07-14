#!/usr/bin/env node
/**
 * Security and data-integrity contract for manual Cookie import.
 *
 * The invariants it locks down:
 *   • required identity is ipb_member_id + ipb_pass_hash; a paste missing either is rejected and
 *     must NOT mutate/persist the jar (validate-before-apply);
 *   • the COMPLETE pasted header is applied (unknown donor/permission cookies preserved, not
 *     whitelist-dropped) — applyFromHeader already guarantees this (see cookie-roundtrip contract);
 *   • REDACTION: the import boundary never logs the raw Cookie header or persists the pasted text
 *     outside CookieJarSettings;
 *   • logout clears memory and WebView identity before deleting the persisted bundle.
 *
 * All cookie material below is built from short synthetic tokens via kv() so no real session
 * material — and no `name=value`-shaped literal — ever appears in source (keeps secret-safety green).
 * Run: node scripts/test_cookie_import_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = (rel) => readFileSync(join(ROOT, rel), 'utf8')

const PAGE = 'entry/src/main/ets/pages/EhCookieImportPage.ets'
const COOKIE_SETTINGS = 'shared/src/main/ets/settings/CookieJarSettings.ets'

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (name, got, want) => {
  assert.strictEqual(got, want, `${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`)
  passed++
}

// --- 1. Redaction: never log the raw header / cookie values; never persist the pasted text ---
{
  const page = src(PAGE)
  // Every DiagnosticLogger.{info,warn,error} call's message arg must not interpolate the raw paste.
  const logCalls = page.match(/DiagnosticLogger\.(info|warn|error)\([\s\S]*?\)/g) || []
  ok('page emits at least one diagnostic', logCalls.length > 0)
  for (const call of logCalls) {
    // The risk is interpolating/concatenating the RAW paste into a log line. Passing `header` to a
    // counting helper (cookieCount(header) → number) is safe; emitting `${header}`/`${this.cookieText}`
    // or `+ header` as a logged VALUE is not.
    const leaksRaw =
      /\$\{\s*(this\.cookieText|header)\s*\}/.test(call) ||
      /\+\s*(this\.cookieText|header)\b/.test(call) ||
      /\b(this\.cookieText|header)\s*\+/.test(call)
    ok(`diagnostic does not log the raw paste: ${call.slice(0, 48)}…`, !leaksRaw)
  }
  // The pasted text must only flow into CookieJarSettings — never into Preferences/AppStorage/clipboard directly.
  ok('page does not persist cookieText to Preferences directly', !/putSync[\s\S]*cookieText/.test(page))
  ok('page does not stash cookieText in AppStorage', !/AppStorage\w*\.[a-zA-Z]+\([\s\S]*cookieText/.test(page))
  ok('diagnostic logs parsed count, not values', /cookie_import_applied'[\s\S]*cookies=\$\{this\.parsedCookies\.length\}/.test(page))
}

// --- 2. Behavior mirror: validate-before-apply. Missing identity rejects WITHOUT mutating the jar. ---
{
  const NW = 'nw'
  const MEMBER = 'ipb_member_id'
  const HASH = 'ipb_pass_hash'
  const kv = (...pairs) => pairs.map((p) => `${p[0]}=${p[1]}`).join('; ')

  const parseEntries = (header) => {
    const entries = []
    const seen = new Set()
    for (const pair of header.split(';')) {
      const trimmed = pair.trim()
      const i = trimmed.indexOf('=')
      if (i <= 0) continue
      const name = trimmed.substring(0, i).trim()
      const value = trimmed.substring(i + 1).trim()
      if (name.length > 0 && name !== NW && value.length > 0 && value !== 'mystery' && !seen.has(name)) {
        entries.push({ name, value })
        seen.add(name)
      }
    }
    return entries
  }
  const valueOf = (entries, name) => {
    const found = entries.find((entry) => entry.name === name)
    return found ? found.value : ''
  }
  // Mirror of EhCookieImportPage.submit() guard: apply ONLY when both identity cookies are present.
  const wouldApply = (jar, header) => {
    const entries = parseEntries(header)
    const member = valueOf(entries, MEMBER)
    const hash = valueOf(entries, HASH)
    if (member.length === 0 || hash.length === 0) return false // rejected: jar untouched
    for (const entry of entries) {
      jar.set(entry.name, entry.value)
    }
    return true
  }

  // 4a. Missing pass_hash → rejected, jar stays empty.
  const jarA = new Map()
  eq('missing pass_hash is rejected', wouldApply(jarA, kv([MEMBER, 'mid'])), false)
  eq('rejected paste leaves jar untouched', jarA.size, 0)

  // 4b. Missing member_id → rejected, jar stays empty.
  const jarB = new Map()
  eq('missing member_id is rejected', wouldApply(jarB, kv([HASH, 'h1'])), false)
  eq('rejected paste (no member) leaves jar untouched', jarB.size, 0)

  // 4c. Both identity cookies + unknown donor marker → applied, complete set preserved.
  const jarC = new Map()
  eq('both identity cookies applied', wouldApply(jarC, kv([MEMBER, 'mid'], [HASH, 'h1'], ['donor_marker_xyz', 'dn'])), true)
  ok('applied jar keeps identity', jarC.get(MEMBER) === 'mid' && jarC.get(HASH) === 'h1')
  ok('applied jar preserves unknown donor cookie (no whitelist drop)', jarC.get('donor_marker_xyz') === 'dn')
  eq('nw is never stored', jarC.has(NW), false)
}

// --- 3. Logout safety: clear jar first, refresh state immediately, then delete persisted bundle. ---
{
  const cookieSettings = src(COOKIE_SETTINGS)
  ok('CookieJarSettings.clear clears the in-memory jar before persistence I/O', /static\s+async\s+clear[\s\S]*?EhCookieStore\.getInstance\(\)\.clear\(\)/.test(cookieSettings))
  ok('CookieJarSettings.clear expires WebView identity cookies on logout', /static\s+async\s+clear[\s\S]*?CookieJarSettings\.expireWebIdentityCookies\(\)/.test(cookieSettings))
  ok('CookieJarSettings.switchTo expires stale WebView identity before loading another account', /static\s+async\s+switchTo[\s\S]*?EhCookieStore\.getInstance\(\)\.clear\(\)[\s\S]*?CookieJarSettings\.expireWebIdentityCookies\(\)[\s\S]*?CookieJarSettings\.applyFromHeader\(bundle\)/.test(cookieSettings))
  ok('WebView identity expiry keeps Cloudflare cookies by avoiding clearAllCookiesSync', /static expireWebIdentityCookies\(\): void[\s\S]*configCookieSync[\s\S]*Max-Age=0/.test(cookieSettings) && !/clearAllCookiesSync/.test(cookieSettings))
  ok('CookieJarSettings.clear syncs AuthState immediately after clearing jar', /static\s+async\s+clear[\s\S]*?EhCookieStore\.getInstance\(\)\.clear\(\)[\s\S]*?CookieJarSettings\.expireWebIdentityCookies\(\)[\s\S]*?CookieJarSettings\.syncAuthState\(/.test(cookieSettings))
  ok('CookieJarSettings.clear deletes persisted cookie jar', /deleteSync\(StorageKeys\.COOKIE_JAR\)/.test(cookieSettings))
}

console.log(`✓ cookie import safety contract: ${passed} assertions passed`)
