#!/usr/bin/env node
/**
 * Contract for the WebView login cookie handoff:
 *   entry/src/main/ets/pages/EhLoginWebPage.ets
 *
 * Web login must not only capture the forums identity cookies. The native EH request stack needs the
 * complete jar across the table site, ExHentai, and forums domains, then should refresh igneous through
 * the existing safe uconfig path. Cookie values are never logged.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const page = src('entry/src/main/ets/pages/EhLoginWebPage.ets')
const settings = src('shared/src/main/ets/settings/CookieJarSettings.ets')
const accountLogin = src('feature/settings/src/main/ets/pages/AccountLoginPage.ets')
const styleSettings = src('shared/src/main/ets/settings/WebLoginStyleSettings.ets')
const styleState = src('shared/src/main/ets/state/WebLoginStyleState.ets')
const bootstrap = src('shared/src/main/ets/settings/SettingsBootstrap.ets')
const storageKeys = src('shared/src/main/ets/constants/StorageKeys.ets')

ok('Web login is a V2 component', /@ComponentV2[\s\S]*struct EhLoginWebPage/.test(page))
ok('Web login fetches table-site WebView cookies', /fetchWebCookie\(EhConstants\.EH_BASE_URL,\s*'eh'\)/.test(page))
ok('Web login fetches ExHentai WebView cookies', /fetchWebCookie\(EhConstants\.EX_BASE_URL,\s*'ex'\)/.test(page))
ok('Web login fetches forums WebView cookies', /fetchWebCookie\(EhConstants\.FORUMS_BASE_URL,\s*'forums'\)/.test(page))
ok(
  'Web login combines all three captured cookie domains before validation',
  /const header: string = `\$\{ehCookie\}; \$\{exCookie\}; \$\{forumCookie\}`/.test(page),
)
ok(
  'Web login validates identity cookies before mutating the app jar',
  /parseCookieValue\(header, EhConstants\.COOKIE_MEMBER_ID\)[\s\S]*parseCookieValue\(header, EhConstants\.COOKIE_PASS_HASH\)[\s\S]*if \(member\.length === 0 \|\| pass\.length === 0\)[\s\S]*return[\s\S]*CookieJarSettings\.replaceFromHeader\(header\)/.test(page),
)
ok('Web login saves through CookieJarSettings.save', /await CookieJarSettings\.save\(ctx\)/.test(page))
ok('Web login refreshes igneous after the identity jar is saved', /await CookieJarSettings\.save\(ctx\)[\s\S]*refreshIgneousAfterLogin\(ctx\)/.test(page))
ok('Web login igneous refresh reuses CookieJarSettings.refreshIgneous', /CookieJarSettings\.refreshIgneous\(ctx\)/.test(page))
ok('CookieJarSettings.refreshIgneous fetches ExHentai uconfig', /EX_BASE_URL\}\/uconfig\.php/.test(settings))
ok('Web login does not wipe Cloudflare challenge cookies', !/clearAllCookiesSync/.test(page) && /CookieJarSettings\.expireWebIdentityCookies\(\)/.test(page))
ok(
  'Web login only expires EH identity cookies before loading forums',
  /private static authCookieNames\(\): string\[\][\s\S]*COOKIE_MEMBER_ID[\s\S]*COOKIE_PASS_HASH[\s\S]*ipb_session_id/.test(settings) &&
    /static expireWebIdentityCookies\(\): void[\s\S]*configCookieSync\([\s\S]*Max-Age=0/.test(settings) &&
    /CookieJarSettings\.expireWebIdentityCookies\(\)[\s\S]*Web\(\{ src: EhConstants\.FORUMS_LOGIN_FORM_URL/.test(page),
)
ok('Web login restyle keeps the forum DOM instead of moving captcha controls', !/MutationObserver/.test(page) && !/appendChild\(.*cap/.test(page) && /Keep the real forum DOM in place/.test(page))
ok('Web login restyle is guarded against ArkWeb runJavaScript pileups', /private restyleInFlight: boolean = false/.test(page) && /if \(this\.restyleInFlight\)/.test(page) && /setTimeout\(\(\): void => \{[\s\S]*this\.restyleInFlight = false[\s\S]*\}, 1500\)/.test(page))
ok('Web login avoids ArkWeb-fragile :has selectors', !/:has\(/.test(page))
ok('Web login tags the real forum form and chrome instead of moving captcha controls', /form\.classList\.add\('nxe-login-form'\)/.test(page) && /nxe-login-chrome/.test(page) && /nxe-login-shell/.test(page))
ok('Web login applies mobile CSS around the real password form', /document\.querySelector\('input\[type=password\]'\)/.test(page) && /form\.nxe-login-form input\[type=text\]/.test(page) && /form\.nxe-login-form input\[type=submit\]/.test(page))
ok('Web login marks captcha controls and keeps their media visible', /querySelectorAll\('iframe,canvas,img,\.cf-turnstile,\[data-sitekey\],\[name="cf-turnstile-response"\]'\)/.test(page) && /nxe-login-captcha-row/.test(page) && /visibility:visible!important/.test(page))
ok('Web login resets the forum submit button layout', /submit\.removeAttribute\('style'\)/.test(page) && /submit\.className='nx-submit'/.test(page) && /position:static!important/.test(page) && /margin:8px 0 0!important/.test(page))
ok('Web login exposes a persistent beautify setting in the login chooser', /connectWebLoginStyle/.test(accountLogin) && /web_login_beautify_setting/.test(accountLogin) && /WebLoginStyleSettings\.save/.test(accountLogin))
ok('Web login style setting is restored during bootstrap', /WEB_LOGIN_BEAUTIFY_ENABLED/.test(storageKeys) && /@ObservedV2[\s\S]*class WebLoginStyleState[\s\S]*@Trace beautifyEnabled: boolean = true/.test(styleState) && /WebLoginStyleSettings\.restore\(context\)/.test(bootstrap))
ok('Web login can be switched to raw mode from the title bar', /runtimeBeautifyEnabled/.test(page) && /web_login_use_original/.test(page) && /web_login_use_beautified/.test(page) && /toggleRuntimeLoginStyle\(\)/.test(page))
ok('Raw Web login mode skips CSS restyling', /if \(this\.runtimeBeautifyEnabled\) \{[\s\S]*this\.restyleLoginForm\(\)/.test(page) && /this\.controller\.loadUrl\(EhConstants\.FORUMS_LOGIN_FORM_URL\)/.test(page))
ok('Web login style setting persists with the settings store', /StorageKeys\.WEB_LOGIN_BEAUTIFY_ENABLED/.test(styleSettings) && /store\.putSync\(StorageKeys\.WEB_LOGIN_BEAUTIFY_ENABLED, value\)/.test(styleSettings))

const logCalls = page.match(/DiagnosticLogger\.(info|warn|error)\([\s\S]*?\)/g) || []
for (const call of logCalls) {
  const leaksRaw =
    /\$\{\s*(header|ehCookie|exCookie|forumCookie)\s*\}/.test(call) ||
    /\+\s*(header|ehCookie|exCookie|forumCookie)\b/.test(call) ||
    /\b(header|ehCookie|exCookie|forumCookie)\s*\+/.test(call)
  ok(`Web login diagnostic does not log raw cookie values: ${call.slice(0, 48)}...`, !leaksRaw)
}

console.log(`✓ web-login cookie capture contract: ${passed} assertions passed`)
