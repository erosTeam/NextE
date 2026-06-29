#!/usr/bin/env node
/**
 * Contract for gallery detail title-menu utility actions.
 *
 * The detail title bar should stay compact: favorite/share remain highest-priority inline actions, and
 * HDS maxCount=3 turns the third slot into overflow containing refresh plus utility actions. Tag voting
 * is a protected child surface; the detail menu itself must not submit EH write endpoints.
 *
 * Run: node scripts/test_gallery_detail_menu_actions_contract.mjs
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

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const routeParams = read('shared/src/main/ets/model/RouteParams.ets')
const galleryIndex = read('feature/gallery/src/main/ets/Index.ets')
const webPage = read('entry/src/main/ets/pages/GalleryWebPage.ets')
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
const editTagsPage = read('feature/gallery/src/main/ets/pages/GalleryEditTagsPage.ets')

ok('detail menu uses HDS overflow behavior with maxCount 3',
  /return \{ 'value': items, 'maxCount': 3 \}/.test(detail))
ok('favorite and share remain the first two menu actions',
  /const items: Record<string, Object>\[\] = \[\s*\{ 'content': favoriteInner \},\s*\{ 'content': shareInner \},/.test(detail))
ok('comments remain third inline and refresh stays in overflow actions',
  /\{ 'content': commentsInner \},\s*\{ 'content': refreshInner \},\s*\{ 'content': editTagsInner \},/.test(detail))
ok('menu includes edit tags, copy link, copy title, external browser, and internal web actions',
  /detail_edit_tags/.test(detail) &&
  /detail_copy_link/.test(detail) &&
  /detail_copy_title/.test(detail) &&
  /detail_open_browser/.test(detail) &&
  /detail_open_internal_web/.test(detail))
ok('gallery URL helper builds the current-site /g/gid/token URL',
  /private galleryUrl\(\): string \{[\s\S]*EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)[\s\S]*\/g\/\$\{this\.params\.gid\}\/\$\{this\.params\.token\}\//.test(detail))
ok('copy actions use the system pasteboard and toast feedback',
  /import \{ pasteboard \} from '@kit\.BasicServicesKit'/.test(detail) &&
  /pasteboard\.createData\(pasteboard\.MIMETYPE_TEXT_PLAIN, content\)/.test(detail) &&
  /pasteboard\.getSystemPasteboard\(\)\.setDataSync\(data\)/.test(detail) &&
  /detail_link_copied/.test(detail) &&
  /detail_title_copied/.test(detail))
ok('external browser action uses system view-data Want',
  /import \{ common, Want \} from '@kit\.AbilityKit'/.test(detail) &&
  /const want: Want = \{ action: 'ohos\.want\.action\.viewData', uri: this\.galleryUrl\(\) \}/.test(detail) &&
  /this\.ctx\(\)[\s\S]*\.startAbility\(want\)/.test(detail))
ok('internal WebView route is typed and registered',
  /export class GalleryWebParams/.test(routeParams) &&
  /GalleryWebParams/.test(read('shared/src/main/ets/Index.ets')) &&
  /name === 'GalleryWeb'[\s\S]*GalleryWebPage\(\)/.test(entry) &&
  /new GalleryWebParams\(this\.galleryUrl\(\), this\.navTitle\(\)\)/.test(detail))
ok('GalleryWebPage reuses EhWebView with app UA',
  /EhWebView\(\{/.test(webPage) &&
  /this\.controller\.setCustomUserAgent\(/.test(webPage) &&
  /this\.isForumsUrl\(this\.params\.url\)[\s\S]*this\.forumsUserAgent\(\)[\s\S]*EhConstants\.USER_AGENT/.test(webPage) &&
  /this\.safeLoadUrl\(url\)/.test(webPage))
ok('GalleryWebPage consumes route params before loading a non-empty URL',
  /\.onReady\(\(context: NavDestinationContext\) => \{[\s\S]*const p = context\.pathInfo\.param as GalleryWebParams[\s\S]*this\.params = p[\s\S]*this\.loadIfReady\(\)/.test(webPage) &&
  /private loadIfReady\(\): void \{[\s\S]*this\.params\.url\.length === 0[\s\S]*return[\s\S]*this\.loadWithCookies\(this\.params\.url\)/.test(webPage))
ok('GalleryWebPage injects app cookies before safe loading',
  /EhCookieStore\.getInstance\(\)\.header\(\)/.test(webPage) &&
  /const parts: string\[\] = header\.split\(';'\)/.test(webPage) &&
  /webview\.WebCookieManager\.configCookieSync\(baseUrl, `\$\{pair\}; Path=\/`, false, true\)/.test(webPage) &&
  /webview\.WebCookieManager\.saveCookieSync\(\)/.test(webPage) &&
  /webview\.WebCookieManager\.saveCookieAsync\(\)/.test(webPage) &&
  /private safeLoadUrl\(url: string\): void \{[\s\S]*this\.controller\.loadUrl\(url\)/.test(webPage))
ok('EntryAbility initializes ArkWeb engine before WebView routes run',
  /import \{ webview \} from '@kit\.ArkWeb'/.test(entryAbility) &&
  /webview\.WebviewController\.initializeWebEngine\(\)/.test(entryAbility))
ok('edit-tags route opens a protected child surface',
  /export class GalleryEditTagsParams/.test(routeParams) &&
  /gid:\s*string/.test(routeParams) &&
  /token:\s*string/.test(routeParams) &&
  /isEx:\s*boolean/.test(routeParams) &&
  /GalleryEditTagsParams/.test(read('shared/src/main/ets/Index.ets')) &&
  /export \{ GalleryEditTagsPage \}/.test(galleryIndex) &&
  /name === 'GalleryEditTags'[\s\S]*GalleryEditTagsPage\(\)/.test(entry) &&
  /new GalleryEditTagsParams\([\s\S]*this\.params\.gid,[\s\S]*this\.params\.token,[\s\S]*connectSiteMode\(\)\.isEx,[\s\S]*this\.navTitle\(\)/.test(detail))
ok('edit-tags page loads current tags and protects tag vote submits behind confirmation',
  /EhApiService\.getInstance\(\)\.getGalleryDetail/.test(editTagsPage) &&
  /this\.tagGroupsData = result\.gallery\.tagGroups/.test(editTagsPage) &&
  /\.onReady\(\(context: NavDestinationContext\) => \{[\s\S]*this\.params = p[\s\S]*this\.loadTags\(\)/.test(editTagsPage) &&
  /private confirmTagVote\(vote: number\): void[\s\S]*showAlertDialog\([\s\S]*submitTagVote\(tagKey, vote, this\.selectedTagVote\)/.test(editTagsPage) &&
  /private async submitTagVote\(tagKey: string, vote: number, previousVote: number\): Promise<void>/.test(editTagsPage) &&
  /EhApiPhpService\.tagGallery\(/.test(editTagsPage))
ok('detail menu implementation does not call EH destructive tag write endpoints',
  !/taggallery|setusertag/.test(detail))

const locales = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]
const keys = [
  'detail_edit_tags',
  'detail_copy_link',
  'detail_copy_title',
  'detail_link_copied',
  'detail_title_copied',
  'detail_open_browser',
  'detail_open_internal_web',
  'detail_edit_tags_readonly_title',
  'detail_edit_tags_readonly_desc',
]
for (const locale of locales) {
  const text = read(locale)
  for (const key of keys) {
    ok(`${locale} defines ${key}`, text.includes(`"name": "${key}"`))
  }
}

console.log(`✓ gallery detail menu actions contract: ${passed} assertions passed`)
