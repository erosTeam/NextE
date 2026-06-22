#!/usr/bin/env node
/**
 * Contract: each concrete My Tags tagset page can open the EH /mytags web editor in the shared WebView.
 *
 * Run: node scripts/test_mytags_webview_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const page = readFileSync(join(ROOT, 'feature/user/src/main/ets/pages/MyTagsPage.ets'), 'utf8')
const webPage = readFileSync(join(ROOT, 'entry/src/main/ets/pages/GalleryWebPage.ets'), 'utf8')
const resources = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
].map((rel) => readFileSync(join(ROOT, rel), 'utf8'))

let failures = 0

function ok(condition, message) {
  if (!condition) {
    failures++
    console.error(`✗ ${message}`)
  }
}

ok(
  /GalleryWebParams/.test(page) &&
    /private openMyTagsWeb\(\): void[\s\S]*pushPathByName\('GalleryWeb', new GalleryWebParams\(this\.myTagsWebUrl\(\), title\)\)/.test(page),
  'MyTagsPage must route the web action through the shared GalleryWeb destination',
)
ok(
  /private myTagsWebUrl\(\): string[\s\S]*\/mytags[\s\S]*\/mytags\?tagset=\$\{encodeURIComponent\(tagset\)\}/.test(page),
  'MyTagsPage must open /mytags or /mytags?tagset=<current>',
)
ok(
  /'label': \$r\('app\.string\.mytags_open_web'\)[\s\S]*'icon': \$r\('sys\.symbol\.worldclock'\)[\s\S]*'isEnabled': !this\.loading && !this\.showingTagsetList/.test(page),
  'MyTags title menu must show a worldclock Web action only on concrete tagset pages',
)
ok(
  /if \(this\.showingTagsetList\)[\s\S]*items\.push\(\{ 'content': createInner \}\)[\s\S]*\} else \{[\s\S]*items\.push\(\{ 'content': webInner \}\)/.test(page),
  'tagset-list landing page must keep only the create action; concrete tagsets get the Web action',
)
ok(
  /private async injectAppCookies\(url: string\): Promise<void>[\s\S]*EhCookieStore\.getInstance\(\)\.header\(\)[\s\S]*WebCookieManager\.configCookieSync/.test(webPage),
  'shared GalleryWebPage must inject app cookies before loading EH pages',
)

for (const src of resources) {
  ok(src.includes('"name": "mytags_open_web"'), 'missing mytags_open_web i18n key')
}

if (failures > 0) {
  console.error(`\n✗ mytags webview contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags webview contract passed')
