#!/usr/bin/env node
/**
 * Contract for the shared EH WebView cookie handoff:
 *   entry/src/main/ets/pages/GalleryWebPage.ets
 *
 * Opening a gallery in the in-app WebView can prove the WebView has fresher cookies than the native
 * request jar. After EH/EX/forums pages load, GalleryWebPage must merge WebCookieManager back into the
 * app jar so native gallery detail requests stop seeing a logged-out 200 page.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const webPage = read('entry/src/main/ets/pages/GalleryWebPage.ets')
const settings = read('shared/src/main/ets/settings/CookieJarSettings.ets')

ok(
  'GalleryWebPage recognizes EH, EX, and forums as cookie-syncable hosts',
  /private shouldSyncWebCookies\(url: string\): boolean \{[\s\S]*EhConstants\.EH_BASE_URL[\s\S]*EhConstants\.EX_BASE_URL[\s\S]*this\.isForumsUrl\(url\)/.test(webPage),
)
ok(
  'GalleryWebPage merges WebCookieManager cookies after syncable pages finish',
  /private syncLoadedCookies\(\): void \{[\s\S]*if \(!this\.shouldSyncWebCookies\(this\.loadedUrl\)\)[\s\S]*CookieJarSettings\.mergeFromWebCookieManager\(this\.ctx\(\)\)/.test(webPage),
)
ok(
  'GalleryWebPage keeps profile DOM capture limited to forums profile pages',
  /CookieJarSettings\.mergeFromWebCookieManager\(this\.ctx\(\)\)[\s\S]*if \(!this\.isForumsUrl\(this\.loadedUrl\)\)[\s\S]*return[\s\S]*this\.captureForumProfileHtml\(\)/.test(webPage),
)
ok(
  'CookieJarSettings merge reads table-site cookies',
  /fetchCookie\(EhConstants\.EH_BASE_URL\)/.test(settings),
)
ok(
  'CookieJarSettings merge reads ExHentai cookies',
  /fetchCookie\(EhConstants\.EX_BASE_URL\)/.test(settings),
)
ok(
  'CookieJarSettings merge reads forums cookies',
  /fetchCookie\(\s*EhConstants\.FORUMS_BASE_URL,\s*\)/.test(settings),
)
ok(
  'CookieJarSettings merge persists through the central jar save path',
  /static async mergeFromWebCookieManager[\s\S]*await CookieJarSettings\.save\(context\)/.test(settings),
)

console.log(`✓ gallery-web cookie sync contract: ${passed} assertions passed`)
