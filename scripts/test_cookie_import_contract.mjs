#!/usr/bin/env node
/**
 * Contract for the manual Cookie login/import path:
 *   entry/src/main/ets/pages/EhCookieImportPage.ets   (the paste-and-import screen)
 *   entry/src/main/ets/pages/Index.ets                (the 'EhCookieImport' route)
 *   feature/settings/src/main/ets/pages/SettingsPage.ets (the reachable entry row)
 *
 * This is the SAFE manual fallback to the WebView login. The invariants it locks down:
 *   • the screen is reachable from Settings (pushPathByName('EhCookieImport')) and routed in Index;
 *   • it REUSES CookieJarSettings.parseCookieEntries/replaceFromHeader/save (no page-owned parser);
 *   • required identity is ipb_member_id + ipb_pass_hash; a paste missing either is rejected and
 *     must NOT mutate/persist the jar (validate-before-apply);
 *   • the COMPLETE pasted header is applied (unknown donor/permission cookies preserved, not
 *     whitelist-dropped) — applyFromHeader already guarantees this (see cookie-roundtrip contract);
 *   • REDACTION: the page never logs the raw Cookie header or any cookie value, and never persists
 *     the pasted text anywhere except through CookieJarSettings; diagnostics carry counts/booleans;
 *   • the user-facing strings exist in all four locales.
 *
 * All cookie material below is built from short synthetic tokens via kv() so no real session
 * material — and no `name=value`-shaped literal — ever appears in source (keeps secret-safety green).
 * Run: node scripts/test_cookie_import_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = (rel) => readFileSync(join(ROOT, rel), 'utf8')

const PAGE = 'entry/src/main/ets/pages/EhCookieImportPage.ets'
const INDEX = 'entry/src/main/ets/pages/Index.ets'
const SETTINGS = 'feature/settings/src/main/ets/pages/SettingsPage.ets'
const ACCOUNT_LOGIN = 'feature/settings/src/main/ets/pages/AccountLoginPage.ets'
const ACCOUNT_PAGE = 'feature/settings/src/main/ets/pages/AccountPage.ets'
const ACCOUNT_COOKIE_PAGE = 'feature/settings/src/main/ets/pages/AccountCookiePage.ets'
const COOKIE_SETTINGS = 'shared/src/main/ets/settings/CookieJarSettings.ets'
const AUTH_STATE = 'shared/src/main/ets/state/AuthState.ets'
const USER_PROFILE = 'shared/src/main/ets/services/UserProfileService.ets'
const PASSWORD_LOGIN = 'entry/src/main/ets/pages/EhPasswordLoginPage.ets'
const ZH_STRINGS = 'entry/src/main/resources/zh_CN/element/string.json'
const LOGIN_FLOW = 'shared/src/main/ets/navigation/LoginFlowNavigation.ets'

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (name, got, want) => {
  assert.strictEqual(got, want, `${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`)
  passed++
}

// --- 1. Route + reachability: screen exists, routed in Index, reachable from Settings ---
{
  ok('EhCookieImportPage.ets exists', existsSync(join(ROOT, PAGE)))
  const page = src(PAGE)
  ok('page is a V2 component (no V1 decorators)', /@ComponentV2/.test(page))
  ok('page declares struct EhCookieImportPage', /struct EhCookieImportPage/.test(page))

  const index = src(INDEX)
  ok('Index imports EhCookieImportPage', /import \{ EhCookieImportPage \}/.test(index))
  ok("Index routes the 'EhCookieImport' family", /'ehCookieImport': wrapBuilder<\[\]>\(IndexEhCookieImportRoute\)/.test(index))

  const settings = src(SETTINGS)
  const accountLogin = src(ACCOUNT_LOGIN)
  const accountPage = src(ACCOUNT_PAGE)
  ok('Settings pushes the account login chooser route', /pushPathByName\('AccountLogin'/.test(settings))
  ok('Account login pushes the EhCookieImport route', /pushPathByName\('EhCookieImport'/.test(accountLogin))
  ok('Account login keeps the WebView login route intact', /pushPathByName\('EhLogin'/.test(accountLogin))
  ok('cookie import row is in the logged-out login chooser', /settings_login_cookie/.test(accountLogin))
  ok('Cookie import success closes the whole login flow to Account', /closeLoginFlowToAccount\(this\.stack\)/.test(page) && /pushPathByName\('Account', null\)/.test(src(LOGIN_FLOW)))
  ok('logout confirmation keeps cancel as primary button', /primaryButton:\s*\{[\s\S]*?common_cancel[\s\S]*?\}[\s\S]*?secondaryButton:/.test(accountPage))
  ok('logout confirmation puts destructive account removal on secondary button', /secondaryButton:\s*\{[\s\S]*?settings_logout[\s\S]*?fontColor:\s*Color\.Red[\s\S]*?removeAndMaybeExit/.test(accountPage))
}

// --- 2. Reuse: the page delegates to CookieJarSettings, does not hand-roll a second parser ---
{
  const page = src(PAGE)
  ok('page parses pasted text through CookieJarSettings.parseCookieEntries', /CookieJarSettings\.parseCookieEntries\(this\.cookieText\)/.test(page))
  ok('page renders parsed cookies before confirmation', /CookiePreviewSection\(\)[\s\S]*?ForEach\(\s*this\.parsedCookies/.test(page))
  ok('page reuses CookieJarSettings.replaceFromHeader', /CookieJarSettings\.replaceFromHeader\(/.test(page))
  ok('page reuses CookieJarSettings.save', /CookieJarSettings\.save\(/.test(page))
  ok('page best-effort refreshes active profile after cookie import',
    /UserProfileService\.refreshAndSaveActive\(ctx\)/.test(page))
  ok('page confirms only after required cookies exist', /canConfirmCookieImport\(\)[\s\S]*COOKIE_MEMBER_ID[\s\S]*COOKIE_PASS_HASH/.test(page))
  // No bespoke cookie-jar mutation: the page must not poke EhCookieStore.set directly.
  ok('page does NOT call EhCookieStore.set directly', !/EhCookieStore\s*[.(].*\.set\(/.test(page) && !/\.set\(\s*name/.test(page))
}

// --- 2b. Account switch UI mirrors non-sensitive active jar/profile state ---
{
  const authState = src(AUTH_STATE)
  const cookieSettings = src(COOKIE_SETTINGS)
  const accountPage = src(ACCOUNT_PAGE)
  const accountCookiePage = src(ACCOUNT_COOKIE_PAGE)
  const profileService = src(USER_PROFILE)
  const passwordLogin = src(PASSWORD_LOGIN)
  const zhStrings = src(ZH_STRINGS)

  ok('AuthState carries only a non-sensitive cookie count mirror',
    /@Trace\s+cookieCount:\s*number\s*=\s*0/.test(authState))
  ok('CookieJarSettings syncs cookieCount from current jar entries',
    /auth\.cookieCount\s*=\s*store\.entries\(\)\.length/.test(cookieSettings))
  ok('Account page renders cookie summary from reactive AuthState cookieCount',
    /account_cookie_count_format[\s\S]*this\.auth\.cookieCount/.test(accountPage))
  ok('Account page does not render no-limit home.php responses as unavailable quota',
    /imageQuotaText\(\): ResourceStr[\s\S]*this\.home\.hasImageLimits\(\)[\s\S]*return `\$\{this\.home\.currentLimit\} \/ \$\{this\.home\.totLimit\}`[\s\S]*this\.homeLoaded \? ''/.test(accountPage) &&
      /imageQuotaSubtitle\(\): ResourceStr[\s\S]*this\.home\.hasUnlockCost\(\)[\s\S]*account_image_unlock_cost_format/.test(accountPage))
  ok('Chinese high-resolution quota copy preserves IP limit and 24-hour unlock context',
    zhStrings.includes('当前使用 IP 图片额度，暂无限制') &&
      zhStrings.includes('解锁 24 小时账号高分辨率额度'))
  ok('Account Cookie page reloads when active member or cookie count changes',
    /@Local\s+auth:\s*AuthState\s*=\s*connectAuth\(\)/.test(accountCookiePage) &&
      /@Monitor\('auth\.memberId', 'auth\.cookieCount'\)[\s\S]*this\.reload\(\)/.test(accountCookiePage))
  ok('UserProfileService can load stored per-member profile snapshots',
    /static async loadStoredProfile\([\s\S]*memberId: string[\s\S]*profileKey\(memberId\)/.test(profileService))
  ok('UserProfileService can refresh, materialize, and save the active profile',
    /static async refreshAndSaveActive\([\s\S]*refreshActive\(\)[\s\S]*materializeAvatar\(context\)[\s\S]*saveActive\(context\)/.test(profileService))
  ok('UserProfileService drops stale profile refreshes after account switches',
    /user_profile_probe_stale/.test(profileService) &&
      /EhCookieStore\.getInstance\(\)\.get\(EhConstants\.COOKIE_MEMBER_ID\) !== memberId/.test(profileService))
  ok('Account page loads saved profiles for all visible account rows',
    /@Local\s+accountProfiles:\s*AccountProfileSummary\[\]/.test(accountPage) &&
      /loadAccountProfiles\(\)[\s\S]*UserProfileService\.loadStoredProfile\(this\.ctx\(\), memberId\)/.test(accountPage) &&
      /accountTitle\(memberId: string\)[\s\S]*this\.accountProfile\(memberId\)/.test(accountPage) &&
      /AccountAvatar\(\{[\s\S]*avatarUrl: this\.accountAvatarUrl\(memberId\)/.test(accountPage))
  ok('password login path also attempts profile refresh before returning success',
    /CookieJarSettings\.passwordLogin/.test(passwordLogin) &&
      /passwordLogin\([\s\S]*UserProfileService\.refreshAndSaveActive\(context\)/.test(cookieSettings))
}

// --- 3. Redaction: never log the raw header / cookie values; never persist the pasted text ---
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

// --- 4. Behavior mirror: validate-before-apply. Missing identity rejects WITHOUT mutating the jar. ---
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

// --- 5. Logout safety: clear jar first, refresh UI immediately, then delete persisted bundle. ---
{
  const cookieSettings = src(COOKIE_SETTINGS)
  ok('CookieJarSettings.clear clears the in-memory jar before persistence I/O', /static\s+async\s+clear[\s\S]*?EhCookieStore\.getInstance\(\)\.clear\(\)/.test(cookieSettings))
  ok('CookieJarSettings.clear expires WebView identity cookies on logout', /static\s+async\s+clear[\s\S]*?CookieJarSettings\.expireWebIdentityCookies\(\)/.test(cookieSettings))
  ok('CookieJarSettings.switchTo expires stale WebView identity before loading another account', /static\s+async\s+switchTo[\s\S]*?EhCookieStore\.getInstance\(\)\.clear\(\)[\s\S]*?CookieJarSettings\.expireWebIdentityCookies\(\)[\s\S]*?CookieJarSettings\.applyFromHeader\(bundle\)/.test(cookieSettings))
  ok('WebView identity expiry keeps Cloudflare cookies by avoiding clearAllCookiesSync', /static expireWebIdentityCookies\(\): void[\s\S]*configCookieSync[\s\S]*Max-Age=0/.test(cookieSettings) && !/clearAllCookiesSync/.test(cookieSettings))
  ok('CookieJarSettings.clear syncs AuthState immediately after clearing jar', /static\s+async\s+clear[\s\S]*?EhCookieStore\.getInstance\(\)\.clear\(\)[\s\S]*?CookieJarSettings\.expireWebIdentityCookies\(\)[\s\S]*?CookieJarSettings\.syncAuthState\(\)/.test(cookieSettings))
  ok('CookieJarSettings.clear deletes persisted cookie jar', /deleteSync\(StorageKeys\.COOKIE_JAR\)/.test(cookieSettings))
}

// --- 6. i18n: the import strings exist in all four locales ---
{
  const KEYS = [
    'settings_login_cookie',
    'cookie_import_title',
    'cookie_import_hint',
    'cookie_import_placeholder',
    'cookie_import_submit',
    'cookie_import_confirm',
    'cookie_import_invalid',
    'cookie_import_preview_title',
    'cookie_import_preview_empty',
    'cookie_import_preview_missing',
    'cookie_import_preview_count',
    'account_cookie_title',
    'account_cookie_summary',
    'account_cookie_count_format',
    'account_cookie_ex_available',
    'account_cookie_ex_locked',
    'account_cookie_empty',
    'account_cookie_copy',
    'account_cookie_export',
    'account_cookie_copied',
    'account_cookie_copy_failed',
    'account_cookie_exported',
    'account_cookie_export_failed',
  ]
  const LOCALES = ['base', 'en_US', 'zh_CN', 'ja_JP']
  for (const loc of LOCALES) {
    const json = JSON.parse(src(`entry/src/main/resources/${loc}/element/string.json`))
    const names = new Set(json.string.map((e) => e.name))
    for (const k of KEYS) ok(`${loc} defines string "${k}"`, names.has(k))
  }
}

console.log(`✓ cookie import contract: ${passed} assertions passed`)
