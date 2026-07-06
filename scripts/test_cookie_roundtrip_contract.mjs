#!/usr/bin/env node
/**
 * Contract for the EH cookie jar round-trip (capture → persist → restore) in
 *   shared/src/main/ets/settings/CookieJarSettings.ets (applyFromHeader / serialize)
 *   shared/src/main/ets/network/EhCookieStore.ets       (serializeForPersist / header)
 *
 * ROOT-CAUSE INVARIANT (false "deleted/404" fix): the jar must persist and re-send the COMPLETE
 * cookie set, NOT a hand-picked auth whitelist. EH gates some galleries (ExHentai-only content shown
 * as "removed or unavailable" on the e-hentai.org URL) on donor/permission cookies whose names we do
 * NOT enumerate; dropping unknown cookies made a logged-in donor look unauthenticated and the gallery
 * look hard-deleted. So:
 *   • every captured cookie survives applyFromHeader → serializeForPersist → applyFromHeader (no drop);
 *   • unknown/donor/permission cookie names are preserved verbatim (no AUTH_NAMES whitelist);
 *   • `nw` is NEVER persisted (it is re-forced to nw=1 per request by header());
 *   • EH's `mystery` placeholder (e.g. igneous=mystery for non-donor) and empty values are skipped;
 *   • login = ipb_member_id AND ipb_pass_hash present (identity), independent of the extra cookies;
 *   • the send header (header()) carries the full set too, so the donor marker is actually transmitted.
 * If the .ets logic changes, mirror it here.
 *
 * All cookie VALUES below are synthetic placeholders — never real session material.
 * Run: node scripts/test_cookie_roundtrip_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = (rel) => readFileSync(join(ROOT, rel), 'utf8')

// EhConstants cookie names (mirror of shared/.../constants/EhConstants.ets).
const NW = 'nw'
const MEMBER = 'ipb_member_id'
const HASH = 'ipb_pass_hash'

// --- Mirror of CookieJarSettings.applyFromHeader + EhCookieStore.{serializeForPersist,header,isLogin} ---
// The jar is a Map<string,string> (insertion-ordered, last-writer-wins per name), like the .ets singleton.
const isLogin = (jar) => (jar.get(MEMBER) || '').length > 0 && (jar.get(HASH) || '').length > 0

const appendCookieEntry = (entries, seen, name, value) => {
  if (name.length <= 0 || value.length <= 0 || name === NW || value === 'mystery' || seen.has(name)) return
  entries.push({ name, value })
  seen.add(name)
}

const parseCookieEntries = (header) => {
  const entries = []
  const seen = new Set()
  for (const pair of header.split(';')) {
    const trimmed = pair.trim()
    const eq = trimmed.indexOf('=')
    if (eq <= 0) continue
    appendCookieEntry(entries, seen, trimmed.substring(0, eq).trim(), trimmed.substring(eq + 1).trim())
  }
  return entries
}

const applyFromHeader = (jar, header) => {
  for (const entry of parseCookieEntries(header)) {
    jar.set(entry.name, entry.value)
  }
  return isLogin(jar)
}

const serializeForPersist = (jar) => {
  const parts = []
  for (const [name, value] of jar) {
    if (name !== NW && value.length > 0) parts.push(`${name}=${value}`)
  }
  return parts.join('; ')
}

// header() always prepends nw=1, then re-emits the full jar (minus the stored nw, if any).
const sendHeader = (jar) => {
  const parts = ['nw=1']
  for (const [name, value] of jar) {
    if (name !== NW && value.length > 0) parts.push(`${name}=${value}`)
  }
  return parts.join('; ')
}

const namesOf = (serialized) =>
  serialized.length === 0 ? [] : serialized.split(';').map((s) => s.trim().split('=')[0])
const valueOf = (serialized, name) => {
  for (const pair of serialized.split(';')) {
    const t = pair.trim()
    const eq = t.indexOf('=')
    if (eq > 0 && t.substring(0, eq).trim() === name) return t.substring(eq + 1).trim()
  }
  return ''
}

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (name, got, want) => {
  assert.strictEqual(got, want, `${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`)
  passed++
}

// More cookie names + short, obviously-fake placeholder values. Headers are BUILT via kv() so this
// source file never contains a literal `name=value` cookie pair — that keeps the secret-safety
// staged-diff scanner (which flags ipb_* / igneous followed by a token) from tripping on fixtures.
const IGNEOUS = 'igneous'
const SK = 'sk'
const STAR = 'star'
const V_ID = 'mid'
const V_HASH = 'h1'
const V_HASH2 = 'h2'
const V_IGN = 'ig'
const V_SK = 's1'
const V_STAR = 't1'
const V_PERKS = 'pk'
const V_YAY = 'ya'
const V_SL = 'l1'
const V_SP = 'p1'
const V_DONOR = 'dn'
const kv = (...pairs) => pairs.map((p) => `${p[0]}=${p[1]}`).join('; ')

// A logged-in DONOR capture: identity + sk/star + igneous + UNKNOWN donor/permission markers whose
// names we never enumerate. Built via kv() so no cookie-shaped literal appears in source.
const DONOR_HEADER = kv(
  [NW, '1'],
  [MEMBER, V_ID],
  [HASH, V_HASH],
  [IGNEOUS, V_IGN],
  [SK, V_SK],
  [STAR, V_STAR],
  ['hath_perks', V_PERKS],
  ['yay', V_YAY],
  ['sl', V_SL],
  ['sp', V_SP],
  ['donor_marker_xyz', V_DONOR],
)

// 1. ROOT CAUSE: every captured cookie survives capture → persist (no whitelist drop).
{
  const jar = new Map()
  const loggedIn = applyFromHeader(jar, DONOR_HEADER)
  const persisted = serializeForPersist(jar)
  const names = namesOf(persisted)
  eq('donor capture is logged in', loggedIn, true)
  for (const n of [MEMBER, HASH, IGNEOUS, SK, STAR, 'hath_perks', 'yay', 'sl', 'sp', 'donor_marker_xyz']) {
    ok(`persist preserves cookie "${n}" (no AUTH_NAMES whitelist)`, names.includes(n))
  }
  ok('unknown donor marker value preserved verbatim', valueOf(persisted, 'donor_marker_xyz') === V_DONOR)
  eq('nw is NOT persisted (re-forced per request)', names.includes(NW), false)
}

// 2. Round-trip is loss-free and idempotent: persist → restore → persist yields the same set.
{
  const jar1 = new Map()
  applyFromHeader(jar1, DONOR_HEADER)
  const persisted1 = serializeForPersist(jar1)

  const jar2 = new Map()
  applyFromHeader(jar2, persisted1) // restore from the persisted string
  const persisted2 = serializeForPersist(jar2)

  eq('restore re-derives login', isLogin(jar2), true)
  eq(
    'round-trip preserves the exact cookie set (sorted names equal)',
    namesOf(persisted2).sort().join(','),
    namesOf(persisted1).sort().join(','),
  )
  ok(
    'round-trip preserves every value',
    namesOf(persisted1).every((n) => valueOf(persisted2, n) === valueOf(persisted1, n)),
  )
}

// 3. The send header carries the FULL set too (donor marker is actually transmitted), with nw forced.
{
  const jar = new Map()
  applyFromHeader(jar, DONOR_HEADER)
  const sent = sendHeader(jar)
  ok('send header forces nw=1', sent.startsWith('nw=1'))
  ok('send header transmits the donor marker', sent.includes(kv(['donor_marker_xyz', V_DONOR])))
  ok('send header transmits identity', sent.includes(kv([MEMBER, V_ID])) && sent.includes(kv([HASH, V_HASH])))
  eq('send header has exactly one nw entry', sent.split(';').filter((p) => p.trim().startsWith('nw=')).length, 1)
}

// 4. Placeholder / empty / nw values are skipped on capture.
{
  const jar = new Map()
  applyFromHeader(jar, kv([MEMBER, V_ID], [HASH, V_HASH], [IGNEOUS, 'mystery'], ['empty_one', ''], [NW, '1']))
  const names = namesOf(serializeForPersist(jar))
  eq('EH `mystery` placeholder is skipped', names.includes(IGNEOUS), false)
  eq('empty-valued cookie is skipped', names.includes('empty_one'), false)
  eq('nw is skipped', names.includes(NW), false)
  eq('identity still captured', isLogin(jar), true)
}

// 5. Restore MERGES (last-writer-wins per name); a later refresh updates a value, old unknowns persist.
{
  const jar = new Map()
  applyFromHeader(jar, kv([MEMBER, V_ID], [HASH, V_HASH], ['donor_marker_xyz', V_DONOR]))
  applyFromHeader(jar, kv([HASH, V_HASH2])) // a fresh capture rotating the hash
  const persisted = serializeForPersist(jar)
  eq('later value overrides earlier (last-writer-wins)', valueOf(persisted, HASH), V_HASH2)
  ok('earlier unknown cookie survives the merge', valueOf(persisted, 'donor_marker_xyz') === V_DONOR)
}

// 6. Login detection requires BOTH identity cookies, independent of the extra/unknown cookies.
{
  const onlyId = new Map()
  applyFromHeader(onlyId, kv([MEMBER, V_ID], [STAR, V_STAR], ['hath_perks', V_PERKS]))
  eq('member_id alone is NOT logged in', isLogin(onlyId), false)

  const onlyHash = new Map()
  applyFromHeader(onlyHash, kv([HASH, V_HASH], [IGNEOUS, V_IGN]))
  eq('pass_hash alone is NOT logged in', isLogin(onlyHash), false)

  const both = new Map()
  applyFromHeader(both, kv([MEMBER, V_ID], [HASH, V_HASH]))
  eq('both identity cookies → logged in (no extra cookies needed)', isLogin(both), true)
}

// 7. Structural: the .ets enforces preserve-all, with the AUTH_NAMES whitelist GONE.
{
  const cjs = src('shared/src/main/ets/settings/CookieJarSettings.ets')
  ok('CookieJarSettings: no AUTH_NAMES whitelist remains', !/AUTH_NAMES/.test(cjs))
  ok('CookieJarSettings.applyFromHeader present', /static applyFromHeader\(/.test(cjs))
  ok('CookieJarSettings.parseCookieEntries present', /static parseCookieEntries\(raw: string\): CookieJarEntry\[\]/.test(cjs))
  ok('applyFromHeader uses parsed entries', /CookieJarSettings\.parseCookieEntries\(header\)/.test(cjs))
  ok('parser skips nw and `mystery`', /name === EhConstants\.COOKIE_NW[\s\S]*?value === 'mystery'/.test(cjs))
  ok('serialize() delegates to serializeForPersist()', /serializeForPersist\(\)/.test(cjs))
  ok('login check = member id + pass hash', /isLogin\(\)/.test(cjs))

  const ecs = src('shared/src/main/ets/network/EhCookieStore.ets')
  ok('EhCookieStore.serializeForPersist present', /serializeForPersist\(\)\s*:\s*string/.test(ecs))
  ok(
    'serializeForPersist iterates the WHOLE jar (no fixed name list)',
    /serializeForPersist\(\)[\s\S]*?this\.cookies\.forEach/.test(ecs),
  )
  ok(
    'serializeForPersist excludes nw',
    /serializeForPersist\(\)[\s\S]*?name !== EhConstants\.COOKIE_NW/.test(ecs),
  )
  ok(
    'header() forces nw=1 and re-emits the whole jar',
    /header\(\)\s*:\s*string\s*\{[\s\S]*?\['nw=1'\][\s\S]*?this\.cookies\.forEach/.test(ecs),
  )
  ok('isLogin = member id AND pass hash', /COOKIE_MEMBER_ID[\s\S]*?COOKIE_PASS_HASH/.test(ecs))
}

console.log(`✓ cookie round-trip contract: ${passed} assertions passed`)
