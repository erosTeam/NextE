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
ok('Web login does not wipe Cloudflare challenge cookies', !/clearAllCookiesSync/.test(page) && /expireWebLoginIdentityCookies\(\)/.test(page))
ok('Web login only expires EH identity cookies before loading forums', /COOKIE_MEMBER_ID[\s\S]*COOKIE_PASS_HASH[\s\S]*configCookieSync\([\s\S]*Max-Age=0/.test(page) && /expireWebLoginIdentityCookies\(\)[\s\S]*loadUrl\(EhConstants\.FORUMS_LOGIN_FORM_URL\)/.test(page))
ok('Web login preserves visible forum failure or verification messages', /function loginNotice\(\)[\s\S]*nx-notice[\s\S]*white-space:pre-wrap/.test(page))
ok('Web login searches the full document for late captcha widgets', /function captchaNode\(n\)/.test(page) && /captchaNode\(document\)/.test(page) && /new MutationObserver\(function\(\)\{ updateCaptcha\(\); \}\)/.test(page))
ok('Web login recognizes Cloudflare Turnstile captcha widgets', /cf-turnstile/.test(page) && /challenges\.cloudflare\.com/.test(page) && /cf-turnstile-response/.test(page))
ok('Web login only moves real captcha widgets, not captcha advisory text', /var capSel='\.g-recaptcha,\.cf-turnstile,\[data-sitekey\],iframe/.test(page) && !/\[class\*=captcha\].*\[id\*=captcha\]/.test(page))
ok('Web login hides the captcha slot when no visible widget is available', /function visibleCaptcha\(n\)/.test(page) && /function collapseCaptcha\(\)/.test(page) && /max-height:96px/.test(page) && /#nx-box \.nx-cap:empty,#nx-box \.nx-cap\.nx-cap-empty\{display:none!important;margin:0!important;\}/.test(page))
ok('Web login resets the forum submit button layout', /submit\.removeAttribute\('style'\)/.test(page) && /submit\.className='nx-submit'/.test(page) && /position:static!important/.test(page) && /margin:4px 0 0!important/.test(page))

const logCalls = page.match(/DiagnosticLogger\.(info|warn|error)\([\s\S]*?\)/g) || []
for (const call of logCalls) {
  const leaksRaw =
    /\$\{\s*(header|ehCookie|exCookie|forumCookie)\s*\}/.test(call) ||
    /\+\s*(header|ehCookie|exCookie|forumCookie)\b/.test(call) ||
    /\b(header|ehCookie|exCookie|forumCookie)\s*\+/.test(call)
  ok(`Web login diagnostic does not log raw cookie values: ${call.slice(0, 48)}...`, !leaksRaw)
}

console.log(`✓ web-login cookie capture contract: ${passed} assertions passed`)
