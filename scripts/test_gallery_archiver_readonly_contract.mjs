#!/usr/bin/env node
/**
 * Contract: gallery archiver is a read-only quote/options surface.
 *
 * It may fetch and parse /archiver.php, show GP/Credits plus Download/H@H options,
 * and navigate from gallery detail. It must not submit local/remote archive downloads
 * or enqueue download tasks in this lane.
 *
 * Run: node scripts/test_gallery_archiver_readonly_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
let passed = 0
function ok(cond, msg) {
  if (!cond) {
    failures += 1
    console.error(`✗ ${msg}`)
  } else {
    passed += 1
  }
}

const model = read('shared/src/main/ets/model/EhGalleryArchiver.ets')
const parser = read('shared/src/main/ets/parser/EhGalleryArchiverParser.ets')
const route = read('shared/src/main/ets/model/RouteParams.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const page = read('feature/gallery/src/main/ets/pages/GalleryArchiverPage.ets')
const galleryIndex = read('feature/gallery/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')

ok(/export class EhGalleryArchiverItem/.test(model), 'archiver item model exists')
ok(/export class EhGalleryArchiverQuote/.test(model), 'archiver quote model exists')
ok(/downloadItems: EhGalleryArchiverItem\[\]/.test(model) && /hathItems: EhGalleryArchiverItem\[\]/.test(model),
  'quote separates Download and H@H options')
ok(/export class EhGalleryArchiverParser/.test(parser), 'archiver parser exists')
ok(/RE_FUNDS[\s\S]*GP[\s\S]*Credits/.test(parser), 'parser extracts GP/Credits balance')
ok(/parseDownloadItems/.test(parser) && /name=\["'\]dltype/.test(parser), 'parser extracts local download dltype options')
ok(/parseHathItems/.test(parser) && /RE_HATH_ROW/.test(parser), 'parser extracts H@H table options')
ok(/HtmlSelectorUtils\.htmlUnescape/.test(parser), 'parser unescapes archiver text')

ok(/export class GalleryArchiverParams/.test(route), 'GalleryArchiverParams exists')
ok(/archiverLink: string/.test(route), 'GalleryArchiverParams carries EH or-token')
ok(/GalleryArchiverParams/.test(sharedIndex), 'shared barrel exports GalleryArchiverParams')
ok(/EhGalleryArchiverItem, EhGalleryArchiverQuote/.test(sharedIndex), 'shared barrel exports archiver models')
ok(/EhGalleryArchiverParser/.test(sharedIndex), 'shared barrel exports archiver parser')

ok(/getGalleryArchiver\([\s\S]*archiverLink: string[\s\S]*Promise<EhGalleryArchiverQuote>/.test(api),
  'EhApiService exposes read-only getGalleryArchiver')
ok(/\/archiver\.php\?gid=\$\{gid\}&token=\$\{token\}&or=\$\{encodeURIComponent\(archiverLink\)\}/.test(api),
  'API builds eros_fe archiver.php URL with gid/token/or')
ok(/EhGalleryArchiverParser\.parse\(resp\.body\)/.test(api), 'API parses archiver response')

ok(/export \{ GalleryArchiverPage \}/.test(galleryIndex), 'gallery barrel exports GalleryArchiverPage')
ok(/GalleryArchiverPage/.test(entry) && /name === 'GalleryArchiver'[\s\S]*GalleryArchiverPage\(\)/.test(entry),
  'entry registers GalleryArchiver route')
ok(/private openArchiver\(\): void/.test(detail), 'detail page can open archiver route')
ok(/new GalleryArchiverParams\([\s\S]*this\.vm\.gallery\.archiverLink/.test(detail),
  'detail passes gid/token/or-token/site/title to archiver page')
ok(/this\.vm\.gallery\.archiverLink\.length > 0[\s\S]*app\.string\.download_archiver[\s\S]*this\.openArchiver\(\)/.test(detail),
  'detail shows archiver entry only when or-token exists')

ok(/getGalleryArchiver/.test(page), 'archiver page loads through EhApiService')
ok(/BalanceBadge\('G'/.test(page) && /BalanceBadge\('C'/.test(page), 'page renders GP/Credits balance badges')
ok(/QuoteList\(\$r\('app\.string\.gallery_archiver_download'\), this\.quote\.downloadItems\)/.test(page),
  'page renders Download options')
ok(/QuoteList\(\$r\('app\.string\.gallery_archiver_hath'\), this\.quote\.hathItems\)/.test(page),
  'page renders H@H options')
ok(/ARCHIVER_BALANCE_BADGE_SIZE/.test(theme) && /ThemeConstants\.ARCHIVER_BALANCE_BADGE_SIZE/.test(page),
  'balance badge size is tokenized')

ok(!/postArchiver|downloadRemote|downloadLoacal|downloadLocal|DownloadQueueSettings|enqueueGalleryDownload/.test(page),
  'archiver page does not submit archive requests or write queues')
ok(!/postArchiver/.test(api), 'API lane has no archiver POST method')
ok(!/Button\([\s\S]*QuoteRow/.test(page), 'quote rows are display rows, not submit buttons')
ok(!/ShareUtil|shareUrl/.test(page), 'archiver page does not repurpose share as a fake download action')

const strings = ['base', 'zh_CN', 'en_US', 'ja_JP'].map((locale) =>
  read(`entry/src/main/resources/${locale}/element/string.json`))
for (const key of ['gallery_archiver', 'gallery_archiver_empty', 'gallery_archiver_download', 'gallery_archiver_hath']) {
  ok(strings.every((s) => s.includes(`"name": "${key}"`)), `i18n key present in all locales: ${key}`)
}

if (failures > 0) {
  console.error(`gallery archiver read-only contract failed: ${failures} issue(s)`)
  process.exit(1)
}
console.log(`✓ gallery archiver read-only contract: ${passed} assertions passed`)
