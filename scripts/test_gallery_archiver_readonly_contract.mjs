#!/usr/bin/env node
/**
 * Contract: gallery archiver exposes protected submit actions.
 *
 * It fetches/parses /archiver.php, shows GP/Credits plus Download/H@H options,
 * and every account-spending submit must go through a native confirmation.
 * Local archive POST returns a generated URL that is added to the real archiver download queue;
 * H@H POST returns the EH status message.
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

const grounding = [
  'eros_fe: lib/pages/gallery/view/archiver_dialog.dart, controller/archiver_controller.dart, common/parser/archiver_parser.dart, network/request.dart',
  'primary information: GP/Credits balance plus local archive and H@H choices with resolution/type, size, and cost',
  'primary action: choose an archive option; secondary actions: retry/back and local archiver queue download',
  'scope: protected submit plumbing, real archiver queue enqueue, local archive download, and completed archive Reader entry',
  'Harmony expression: HDS detail page action rows plus native confirmation before POST, toast result, and Downloads Archiver task handoff to Reader',
]

ok(grounding.length === 5, 'grounding has five lines')
ok(grounding[0].includes('archiver_dialog.dart') && grounding[0].includes('request.dart'),
  'grounding names concrete eros_fe archiver files')
ok(grounding[3].includes('real archiver queue'), 'scope includes real archiver queue implementation')

ok(/export class EhGalleryArchiverItem/.test(model), 'archiver item model exists')
ok(/export class EhGalleryArchiverQuote/.test(model), 'archiver quote model exists')
ok(/export class EhGalleryArchiverSubmitResult/.test(model), 'archiver submit result model exists')
ok(/localDownloadUrl: string/.test(model) && /message: string/.test(model),
  'submit result separates local URL and message')
ok(/downloadItems: EhGalleryArchiverItem\[\]/.test(model) && /hathItems: EhGalleryArchiverItem\[\]/.test(model),
  'quote separates Download and H@H options')

ok(/export class EhGalleryArchiverParser/.test(parser), 'archiver parser exists')
ok(/RE_FUNDS[\s\S]*GP[\s\S]*Credits/.test(parser), 'parser extracts GP/Credits balance')
ok(/parseDownloadItems/.test(parser) && /name=\["'\]dltype/.test(parser), 'parser extracts local download dltype options')
ok(/parseHathItems/.test(parser) && /RE_HATH_ROW/.test(parser), 'parser extracts H@H table options')
ok(/parseLocalSubmit/.test(parser) && /RE_LOCAL_REDIRECT/.test(parser) && /start=1/.test(parser),
  'parser extracts local archive redirect URL and starts download')
ok(/parseHathSubmit/.test(parser) && /RE_DB_P/.test(parser),
  'parser extracts H@H submit status message from #db paragraph')
ok(/HtmlSelectorUtils\.htmlUnescape/.test(parser), 'parser unescapes archiver text')

ok(/export class GalleryArchiverParams/.test(route), 'GalleryArchiverParams exists')
ok(/archiverLink: string/.test(route), 'GalleryArchiverParams carries EH or-token')
ok(/GalleryArchiverParams/.test(sharedIndex), 'shared barrel exports GalleryArchiverParams')
ok(/EhGalleryArchiverItem/.test(sharedIndex) && /EhGalleryArchiverQuote/.test(sharedIndex) &&
  /EhGalleryArchiverSubmitResult/.test(sharedIndex),
  'shared barrel exports archiver models')
ok(/EhGalleryArchiverParser/.test(sharedIndex), 'shared barrel exports archiver parser')

ok(/getGalleryArchiver\([\s\S]*archiverLink: string[\s\S]*Promise<EhGalleryArchiverQuote>/.test(api),
  'EhApiService exposes getGalleryArchiver')
ok(/private archiverUrl\([\s\S]*encodeURIComponent\(gid\)[\s\S]*encodeURIComponent\(token\)[\s\S]*encodeURIComponent\(archiverLink\)/.test(api),
  'API builds eros_fe archiver.php URL with encoded gid/token/or')
ok(/EhGalleryArchiverParser\.parse\(resp\.body\)/.test(api), 'API parses archiver response')
ok(/submitGalleryArchiverLocal\([\s\S]*Promise<EhGalleryArchiverSubmitResult>/.test(api) &&
  /formPair\('dltype', dltype\.trim\(\)\)/.test(api) &&
  /formPair\('dlcheck', dlcheck\.trim\(\)\)/.test(api) &&
  /EhGalleryArchiverParser\.parseLocalSubmit\([\s\S]*resp\.body/.test(api),
  'API submits local archive with dltype/dlcheck and parses local URL')
ok(/submitGalleryArchiverHath\([\s\S]*Promise<EhGalleryArchiverSubmitResult>/.test(api) &&
  /formPair\('hathdl_xres', resolution\.trim\(\)\)/.test(api) &&
  /EhGalleryArchiverParser\.parseHathSubmit\(resp\.body\)/.test(api),
  'API submits H@H archive with hathdl_xres and parses message')
ok(/postFormUrlEncoded\(url, body\)/.test(api) && /EhErrorClassifier\.classifyResponse\(url, isEx, resp, 'generic'\)/.test(api),
  'archiver POST uses protected form transport and EH error classification')

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
ok(/QuoteList\(\$r\('app\.string\.gallery_archiver_download'\), this\.quote\.downloadItems, false\)/.test(page),
  'page renders local Download options as local submit rows')
ok(/QuoteList\(\$r\('app\.string\.gallery_archiver_hath'\), this\.quote\.hathItems, true\)/.test(page),
  'page renders H@H options as H@H submit rows')
ok(/QuoteRow\(item: EhGalleryArchiverItem, isHath: boolean\)/.test(page) &&
  /this\.confirmArchiveSubmit\(item, isHath\)/.test(page),
  'quote rows are tappable action rows')
ok(/showAlertDialog\(\{[\s\S]*gallery_archiver_hath_confirm[\s\S]*gallery_archiver_download_confirm[\s\S]*common_cancel[\s\S]*common_ok[\s\S]*this\.submitArchive\(item, isHath\)/.test(page),
  'submits are gated by native confirmation')
ok(/submitGalleryArchiverLocal/.test(page) && /submitGalleryArchiverHath/.test(page),
  'page calls both protected archiver submit methods')
ok(/localDlcheck\(item\)[\s\S]*Original Archive[\s\S]*Resample Archive/.test(page),
  'local archive submit preserves eros_fe dlcheck labels')
ok(/DownloadQueueSettings\.enqueueArchiver/.test(page) && /DownloadQueueSettings\.downloadArchiver/.test(page) &&
  /localDownloadUrl/.test(page),
  'local archive result enqueues and starts the generated archive URL')
ok(/ARCHIVER_BALANCE_BADGE_SIZE/.test(theme) && /ThemeConstants\.ARCHIVER_BALANCE_BADGE_SIZE/.test(page),
  'balance badge size is tokenized')
ok(!/startAbility\(want\)|archiverTaskMap/.test(page),
  'archiver page does not external-open the archive URL or use a fake FE task map')
ok(!/ShareUtil|shareUrl/.test(page), 'archiver page does not repurpose share as a fake download action')

const strings = ['base', 'zh_CN', 'en_US', 'ja_JP'].map((locale) =>
  read(`entry/src/main/resources/${locale}/element/string.json`))
for (const key of [
  'gallery_archiver',
  'gallery_archiver_empty',
  'gallery_archiver_download',
  'gallery_archiver_hath',
  'gallery_archiver_download_confirm',
  'gallery_archiver_hath_confirm',
  'gallery_archiver_submit_notice',
  'gallery_archiver_submitted',
  'gallery_archiver_download_started',
  'download_archiver_already_queued',
]) {
  ok(strings.every((s) => s.includes(`"name": "${key}"`)), `i18n key present in all locales: ${key}`)
}

if (failures > 0) {
  console.error(`gallery archiver protected submit contract failed: ${failures} issue(s)`)
  process.exit(1)
}
console.log(`✓ gallery archiver protected submit contract: ${passed} assertions passed`)
