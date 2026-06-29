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
const archiveBot = read('shared/src/main/ets/services/ArchiveBotService.ets')
const downloadSettings = read('shared/src/main/ets/settings/DownloadSettings.ets')
const downloadQueue = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const page = read('feature/gallery/src/main/ets/pages/GalleryArchiverPage.ets')
const downloadPage = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const galleryIndex = read('feature/gallery/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const theme = read('shared/src/main/ets/theme/ThemeConstants.ets')
const relationsStart = detail.indexOf('relationsRow() {')
const relationsEnd = detail.indexOf('@Builder', relationsStart + 1)
const detailRelations = relationsStart >= 0
  ? detail.substring(relationsStart, relationsEnd > relationsStart ? relationsEnd : detail.length)
  : ''

function cleanText(raw) {
  return raw
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function labelValue(html, label) {
  const text = cleanText(html)
  const needle = `${label}:`
  const pos = text.indexOf(needle)
  if (pos < 0) return ''
  return labelValueFromText(text, needle, pos)
}

function labelValueLast(html, label) {
  const text = cleanText(html)
  const needle = `${label}:`
  const pos = text.lastIndexOf(needle)
  if (pos < 0) return ''
  return labelValueFromText(text, needle, pos)
}

function labelValueFromText(text, needle, pos) {
  const labels = [
    'Download Cost:',
    'Estimated Size:',
    'Cost:',
    'Size:',
    'Download:',
    'Original Archive',
    'Resample Archive',
    'H@H Downloader',
    'H@H',
  ]
  let end = text.length
  for (const candidate of labels) {
    const idx = text.indexOf(candidate, pos + needle.length)
    if (idx >= 0 && idx < end) end = idx
  }
  const value = text.substring(pos + needle.length, end).replace(/!$/, '').trim()
  if (needle.includes('Size:')) {
    const size = value.match(/^([0-9][0-9.,]*\s*(?:KiB|MiB|GiB|KB|MB|GB|B))/i)
    if (size && size[1] !== undefined) return size[1].trim()
  }
  return value
}

function inputValue(html, name) {
  const a = html.match(new RegExp(`name=["']${name}["'][^>]*value=["']([^"']*)["']`, 'i'))
  if (a && a[1] !== undefined) return a[1].replace(/&amp;/g, '&').trim()
  const b = html.match(new RegExp(`value=["']([^"']*)["'][^>]*name=["']${name}["']`, 'i'))
  return b && b[1] !== undefined ? b[1].replace(/&amp;/g, '&').trim() : ''
}

function localResolution(dltype, dlcheck) {
  if (dlcheck) return dlcheck.startsWith('Download ') ? dlcheck.slice('Download '.length).trim() : dlcheck
  return dltype === 'org' ? 'Original Archive' : 'Resample Archive'
}

function paragraphTexts(html) {
  return [...html.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)].map((m) => cleanText(m[1] || ''))
}

function parseQuote(html) {
  const out = { gp: '', credits: '', downloadItems: [], hathItems: [] }
  const funds = html.match(/([0-9,]+)\s+GP[\s\S]*?([0-9,]+)\s+Credits/i)
  if (funds) {
    out.gp = funds[1].replace(/,/g, '')
    out.credits = funds[2].replace(/,/g, '')
  }
  const formRe = /<form\b[\s\S]*?<\/form>/gi
  let dl = formRe.exec(html)
  while (dl) {
    const form = dl[0]
    const dltype = inputValue(form, 'dltype')
    if (dltype && !out.downloadItems.some((item) => item.dltype === dltype)) {
      const window = html.substring(Math.max(0, dl.index - 360), Math.min(html.length, dl.index + dl[0].length + 360))
      const beforeForm = html.substring(Math.max(0, dl.index - 360), dl.index)
      const afterForm = html.substring(dl.index + dl[0].length, Math.min(html.length, dl.index + dl[0].length + 360))
      const dlcheck = inputValue(form, 'dlcheck')
      let priceText = labelValueLast(beforeForm, 'Download Cost')
      if (!priceText) priceText = labelValueLast(beforeForm, 'Cost')
      if (!priceText) priceText = labelValue(window, 'Download Cost')
      let sizeText = labelValue(afterForm, 'Estimated Size')
      if (!sizeText) sizeText = labelValue(afterForm, 'Size')
      if (!sizeText) sizeText = labelValue(window, 'Estimated Size')
      out.downloadItems.push({
        dltype,
        dlcheck,
        resolution: localResolution(dltype, dlcheck),
        priceText,
        sizeText,
      })
    }
    dl = formRe.exec(html)
  }
  const hathRe = /<td\b[^>]*>([\s\S]*?)<\/td>/gi
  let row = hathRe.exec(html)
  while (row) {
    const cell = row[1] !== undefined ? row[1] : ''
    const action = cell.match(/\('([^']+)'\)/)
    const dltype = action && action[1] !== undefined ? action[1] : ''
    const lines = paragraphTexts(cell)
    const resolution = lines[0] || cleanText(cell)
    const size = lines[1] || ''
    const price = lines[2] || ''
    if (dltype && size.toUpperCase() !== 'N/A') {
      out.hathItems.push({ dltype, resolution, sizeText: size, priceText: price })
    }
    row = hathRe.exec(html)
  }
  return out
}

function parseLocalSubmit(html) {
  const match = html.match(/document\.location\s*=\s*["']([^"']+)["']/)
  if (!match || match[1] === undefined) return { localDownloadUrl: '', message: cleanText(html) }
  let url = match[1].replace(/&amp;/g, '&').trim()
  if (url && !url.includes('start=1')) url = url.includes('?') ? `${url}&start=1` : `${url}?start=1`
  return { localDownloadUrl: url, message: url }
}

function parseHathSubmit(html) {
  const match = html.match(/<div\b[^>]*id=["']db["'][^>]*>[\s\S]*?<p\b[^>]*>([\s\S]*?)<\/p>/i)
  return { message: match && match[1] !== undefined ? cleanText(match[1]) : cleanText(html) }
}

const grounding = [
  'eros_fe: lib/pages/gallery/view/archiver_dialog.dart, controller/archiver_controller.dart, common/parser/archiver_parser.dart, network/request.dart',
  'primary information: GP/Credits balance plus local archive and H@H choices with resolution/type, size, and cost',
  'primary action: choose an archive option; secondary actions: retry/back and local archiver queue download',
  'scope: protected submit plumbing, real archiver queue enqueue, local archive download, and completed archive Reader entry',
  'Harmony expression: detail action opens an AppModalScaffold half-modal; native confirmation gates POST, toast result, and Downloads Archiver task handoff to Reader',
  'JHenTai archive bot: docs/wiki Archive-Bot-Usage.md plus lib/src/network/archive_bot_request.dart define bot as a URL resolver source, not a replacement downloader',
]

ok(grounding.length === 6, 'grounding has six lines')
ok(grounding[0].includes('archiver_dialog.dart') && grounding[0].includes('request.dart'),
  'grounding names concrete eros_fe archiver files')
ok(grounding[3].includes('real archiver queue'), 'scope includes real archiver queue implementation')
ok(grounding[5].includes('JHenTai archive bot') && grounding[5].includes('URL resolver source'),
  'grounding records the JHenTai archive bot boundary')

ok(/export class EhGalleryArchiverItem/.test(model), 'archiver item model exists')
ok(/dlcheck:\s*string/.test(model), 'archiver item preserves local submit dlcheck label')
ok(/export class EhGalleryArchiverQuote/.test(model), 'archiver quote model exists')
ok(/export class EhGalleryArchiverSubmitResult/.test(model), 'archiver submit result model exists')
ok(/localDownloadUrl: string/.test(model) && /message: string/.test(model),
  'submit result separates local URL and message')
ok(/downloadItems: EhGalleryArchiverItem\[\]/.test(model) && /hathItems: EhGalleryArchiverItem\[\]/.test(model),
  'quote separates Download and H@H options')

ok(/export class EhGalleryArchiverParser/.test(parser), 'archiver parser exists')
ok(/RE_FUNDS[\s\S]*GP[\s\S]*Credits/.test(parser), 'parser extracts GP/Credits balance')
ok(/parseDownloadItems/.test(parser) && /RE_FORM/.test(parser) && /inputValue\(form, 'dltype'\)/.test(parser),
  'parser extracts local download form dltype options')
ok(/parseHathItems/.test(parser) && /RE_HATH_CELL/.test(parser) && /paragraphTexts\(cell\)/.test(parser),
  'parser extracts H@H options from each table cell')
ok(/parseLocalSubmit/.test(parser) && /RE_LOCAL_REDIRECT/.test(parser) && /start=1/.test(parser),
  'parser extracts local archive redirect URL and starts download')
ok(/parseHathSubmit/.test(parser) && /RE_DB_P/.test(parser),
  'parser extracts H@H submit status message from #db paragraph')
ok(/HtmlSelectorUtils\.htmlUnescape/.test(parser), 'parser unescapes archiver text')

const quote = parseQuote(`
<div>12,345 GP</div><div>6,789 Credits</div>
<div>Download Cost: <strong>500 GP</strong></div>
<form><input name="dltype" value="org"><input name="dlcheck" value="Download Original Archive"></form>
<p>Estimated Size: <strong>42.5 MB</strong></p>
<div>Download Cost: <strong>250 GP</strong></div>
<form><input value="res" name="dltype"><input name="dlcheck" value="Download Resample Archive"></form>
<p>Estimated Size: <strong>20.0 MB</strong></p>
<table>
<tr><td><p><a onclick="return do_hathdl('780')">780x</a></p><p>18.0 MB</p><p>100 GP</p></td>
<td><p><a onclick="return do_hathdl('org')">Original</a></p><p>N/A</p><p>0 GP</p></td></tr>
</table>`)
ok(quote.gp === '12345' && quote.credits === '6789', 'parser contract extracts archiver balances')
ok(quote.downloadItems.length === 2 &&
  quote.downloadItems[0].dltype === 'org' &&
  quote.downloadItems[0].resolution === 'Original Archive' &&
  quote.downloadItems[0].dlcheck === 'Download Original Archive' &&
  quote.downloadItems[0].priceText === '500 GP' &&
  quote.downloadItems[0].sizeText === '42.5 MB' &&
  quote.downloadItems[1].dltype === 'res' &&
  quote.downloadItems[1].sizeText === '20.0 MB' &&
  quote.downloadItems[1].priceText === '250 GP',
  'parser contract extracts local archive options with cost/size')
ok(quote.hathItems.length === 1 &&
  quote.hathItems[0].dltype === '780' &&
  quote.hathItems[0].resolution === '780x' &&
  quote.hathItems[0].sizeText === '18.0 MB' &&
  quote.hathItems[0].priceText === '100 GP',
  'parser contract extracts H@H options and skips N/A rows')
const localSubmit = parseLocalSubmit('<script>document.location = "archiver.php?gid=1&amp;token=t&amp;or=o";</script>')
ok(localSubmit.localDownloadUrl === 'archiver.php?gid=1&token=t&or=o&start=1' &&
  localSubmit.message === localSubmit.localDownloadUrl,
  'parser contract extracts local submit redirect and appends start=1')
ok(parseHathSubmit('<div id="db"><p>H@H request queued.</p></div>').message === 'H@H request queued.',
  'parser contract extracts H@H submit message')

ok(/export class GalleryArchiverParams/.test(route), 'GalleryArchiverParams exists')
ok(/archiverLink: string/.test(route) && /full archiver\.php URL/.test(route), 'GalleryArchiverParams carries modern archiver URL or legacy token')
ok(/GalleryArchiverParams/.test(sharedIndex), 'shared barrel exports GalleryArchiverParams')
ok(/EhGalleryArchiverItem/.test(sharedIndex) && /EhGalleryArchiverQuote/.test(sharedIndex) &&
  /EhGalleryArchiverSubmitResult/.test(sharedIndex),
  'shared barrel exports archiver models')
ok(/EhGalleryArchiverParser/.test(sharedIndex), 'shared barrel exports archiver parser')
ok(/ArchiveBotService/.test(sharedIndex) && /ArchiveBotType/.test(sharedIndex) &&
  /DownloadArchiverParseSource/.test(sharedIndex),
  'shared barrel exports archive bot service, type, and parse source')

ok(/getGalleryArchiver\([\s\S]*archiverLink: string[\s\S]*Promise<EhGalleryArchiverQuote>/.test(api),
  'EhApiService exposes getGalleryArchiver')
ok(/private archiverUrl\([\s\S]*normalizeArchiverUrl\(link, isEx\)[\s\S]*encodeURIComponent\(gid\)[\s\S]*encodeURIComponent\(token\)[\s\S]*encodeURIComponent\(link\)/.test(api),
  'API uses modern archiver.php URL when present and keeps older gid/token/or fallback')
ok(/private normalizeArchiverUrl/.test(api) && /\/archiver\.php/.test(api),
  'API normalizes archiver URL to the active EH/EX domain')
ok(/EhGalleryArchiverParser\.parse\(resp\.body\)/.test(api), 'API parses archiver response')
ok(/submitGalleryArchiverLocal\([\s\S]*Promise<EhGalleryArchiverSubmitResult>/.test(api) &&
  /formPair\('dltype', dltype\.trim\(\)\)/.test(api) &&
  /formPair\('dlcheck', dlcheck\.trim\(\)\)/.test(api) &&
  /EhGalleryArchiverParser\.parseLocalSubmit\([\s\S]*resp\.body/.test(api),
  'API submits local archive with dltype/dlcheck and parses local URL')
ok(/ARCHIVER_PREPARE_RETRY_MS: number = 1000/.test(api) &&
  /if \(result\.localDownloadUrl\.length === 0\) \{[\s\S]*EhApiService\.delay\(ARCHIVER_PREPARE_RETRY_MS\)[\s\S]*postArchiverForm\(url, body, isEx\)[\s\S]*parseLocalSubmit\(resp\.body\)/.test(api),
  'local archive submit retries once after EH prepares the archive, matching EhViewer behavior')
ok(/submitGalleryArchiverHath\([\s\S]*Promise<EhGalleryArchiverSubmitResult>/.test(api) &&
  /formPair\('hathdl_xres', resolution\.trim\(\)\)/.test(api) &&
  /EhGalleryArchiverParser\.parseHathSubmit\(resp\.body\)/.test(api),
  'API submits H@H archive with hathdl_xres and parses message')
ok(/postFormUrlEncoded\(url, body\)/.test(api) && /EhErrorClassifier\.classifyResponse\(url, isEx, resp, 'generic'\)/.test(api),
  'archiver POST uses protected form transport and EH error classification')

ok(/export \{ GalleryArchiverPage \}/.test(galleryIndex), 'gallery barrel exports GalleryArchiverPage')
ok(/GalleryArchiverPage/.test(entry) && /name === 'GalleryArchiver'[\s\S]*GalleryArchiverPage\(\)/.test(entry),
  'entry registers GalleryArchiver route')
ok(/private openArchiver\(\): void/.test(detail), 'detail page can open archiver sheet')
ok(/const DETAIL_SHEET_ARCHIVER: string = 'archiver'/.test(detail) &&
  /@Local\s+archiverSheetParams:\s+GalleryArchiverParams/.test(detail) &&
  /new GalleryArchiverParams\([\s\S]*this\.vm\.gallery\.archiverLink/.test(detail),
  'detail prepares gid/token/archiver-link/site/title for the archiver sheet')
ok(/this\.openDetailSheet\(DETAIL_SHEET_ARCHIVER\)/.test(detail) &&
  !/private openArchiver\(\): void[\s\S]*pushPathByName\(\s*'GalleryArchiver'/.test(detail),
  'detail opens archiver through the half-modal sheet, not the main route stack')
ok(!/archiverLink\.length > 0[\s\S]*app\.string\.download_archiver/.test(detailRelations) &&
  /app\.string\.download_archiver[\s\S]*this\.openArchiver\(\)/.test(detailRelations),
  'detail keeps the FE-style archiver entry visible and lets the archiver sheet load or report errors')

ok(/export struct GalleryArchiverContent/.test(page) &&
  /AppModalScaffold\(\{[\s\S]*gallery_archiver[\s\S]*showConfirmAction: false/.test(page),
  'archiver content can render as an AppModalScaffold half-modal')
ok(/GalleryArchiverContent\(\{[\s\S]*params: this\.params/.test(page),
  'GalleryArchiverPage remains a compatibility wrapper around shared content')
ok(/getGalleryArchiver/.test(page), 'archiver content loads through EhApiService')
ok(!/archiver_missing_or_token/.test(page),
  'archiver content no longer blocks modern gid/token-only archiver requests as missing archiver params')
ok(/BalanceBadge\('G'/.test(page) && /BalanceBadge\('C'/.test(page), 'page renders GP/Credits balance badges')
ok(/QuoteList\(\$r\('app\.string\.gallery_archiver_download'\), this\.quote\.downloadItems, false\)/.test(page),
  'page renders local Download options as local submit rows')
ok(/QuoteList\(\$r\('app\.string\.gallery_archiver_hath'\), this\.quote\.hathItems, true\)/.test(page),
  'page renders H@H options as H@H submit rows')
ok(/DownloadSettings\.archiveBotReady\(this\.downloadSettings\)/.test(page) &&
  /BotQuoteList\(\)/.test(page),
  'page only renders archive bot options when bot settings are ready')
ok(/gallery_archiver_bot_original/.test(page) && /gallery_archiver_bot_free/.test(page) &&
  /task\.dltype = 'org'/.test(page) &&
  /task\.tag = `\$\{task\.gid\}:org`/.test(page) &&
  !/bot:org/.test(page) &&
  /task\.parseSource = DownloadArchiverParseSource\.BOT/.test(page) &&
  /task\.url = ''/.test(page),
  'archive bot option reuses the original archive task with bot parse source and no official URL')
ok(/QuoteRow\(item: EhGalleryArchiverItem, isHath: boolean\)/.test(page) &&
  /this\.confirmArchiveSubmit\(item, isHath\)/.test(page),
  'quote rows are tappable action rows')
ok(/Grid\(\)[\s\S]*GridItem\(\)[\s\S]*this\.QuoteRow\(item, isHath\)[\s\S]*\.columnsTemplate\('1fr 1fr'\)/.test(page),
  'archiver options render as a two-column grid in the half-modal')
ok(!/chevron_right/.test(page), 'archiver option grid does not show tiny trailing arrows')
ok(/showAlertDialog\(\{[\s\S]*gallery_archiver_hath_confirm[\s\S]*gallery_archiver_download_confirm[\s\S]*common_cancel[\s\S]*common_ok[\s\S]*this\.submitArchive\(item, isHath\)/.test(page),
  'submits are gated by native confirmation')
ok(/submitGalleryArchiverLocal/.test(page) && /submitGalleryArchiverHath/.test(page),
  'page calls both protected archiver submit methods')
ok(/localDlcheck\(item\)[\s\S]*item\.dlcheck\.length > 0[\s\S]*Download Original Archive[\s\S]*Download Resample Archive/.test(page),
  'local archive submit preserves parsed dlcheck labels with JHenTai-compatible fallback labels')
ok(/DownloadQueueSettings\.enqueueArchiver/.test(page) &&
  /localDownloadUrl/.test(page) &&
  /DownloadQueueSettings\.downloadArchiver\(this\.ctx\(\), task\.tag\)\.catch\(\(error: Error\) => \{[\s\S]*archiver_background_start_failed/.test(page),
  'local and bot archive results enqueue the task then start the package download in the background with failure diagnostics')
ok(/ARCHIVER_BALANCE_BADGE_SIZE/.test(theme) && /ThemeConstants\.ARCHIVER_BALANCE_BADGE_SIZE/.test(page),
  'balance badge size is tokenized')
ok(!/startAbility\(want\)|archiverTaskMap/.test(page),
  'archiver page does not external-open the archive URL or use a fake FE task map')
ok(!/ShareUtil|shareUrl/.test(page), 'archiver page does not repurpose share as a fake download action')

ok(/https:\/\/eh-arc-api\.mhdy\.icu/.test(downloadSettings) &&
  /https:\/\/api\.archive-at-home\.org\/jhentai/.test(downloadSettings) &&
  /archiveBotReady/.test(downloadSettings),
  'download settings carries JHenTai archive bot defaults and readiness check')
ok(/requestBalance/.test(archiveBot) && /requestCheckIn/.test(archiveBot) && /requestResolve/.test(archiveBot),
  'archive bot service exposes balance, check-in, and resolve operations')
ok(/ARCHIVE_AT_HOME_CLIENT: string = 'app\/jhentai'/.test(archiveBot) &&
  /headers\.Authorization = `Bearer \$\{settings\.archiveBotApiKey\}`/.test(archiveBot) &&
  /headers\['X-Client'\] = ARCHIVE_AT_HOME_CLIENT/.test(archiveBot),
  'Archive-at-Home requests include JHenTai-compatible auth and client headers')
ok(/api\/v1\/me\/balance/.test(archiveBot) && /api\/v1\/me\/checkin/.test(archiveBot) &&
  /api\/v1\/parse/.test(archiveBot) &&
  /gallery_id: gid/.test(archiveBot) &&
  /gallery_key: token/.test(archiveBot) &&
  /force: reParse/.test(archiveBot),
  'Archive-at-Home endpoints and resolve body match JHenTai protocol')
ok(/return `\$\{base\}\/\$\{action === 'resolve' \? 'resolve' : action\}`/.test(archiveBot) &&
  /apikey: settings\.archiveBotApiKey/.test(archiveBot) &&
  /force_resolve: reParse/.test(archiveBot),
  'EH-ArBot endpoints and resolve body match JHenTai protocol')
ok(/rec\.data !== undefined \? rec\.data : \(rec as ArchiveBotDataJson\)/.test(archiveBot),
  'archive bot response parser accepts wrapped data and direct business objects')
ok(/if \(code >= 400\) \{[\s\S]*parseResponse\(text\)[\s\S]*ArchiveBotService\.message\(errResp\)/.test(archiveBot) &&
  /out\.error = typeof rec\.error === 'string' \? rec\.error : ''/.test(archiveBot) &&
  /typeof resp\.error === 'string' && resp\.error\.length > 0/.test(archiveBot),
  'archive bot HTTP errors preserve service error body instead of collapsing to a status code')
ok(/private static safeNumber\(value\?: Object\): number/.test(archiveBot) &&
  /typeof value === 'string'[\s\S]*Number\.parseFloat\(value\)/.test(archiveBot),
  'archive bot parser accepts numeric values and numeric strings from bot services')
ok(/resolveArchiverBotUrl/.test(downloadQueue) &&
  /ArchiveBotService\.requestResolve/.test(downloadQueue) &&
  /normalizeArchiverDownloadUrl\(result\.url\)/.test(downloadQueue) &&
  /archive_bot_resolve_start/.test(downloadQueue) &&
  /archive_bot_resolve_done/.test(downloadQueue),
  'download queue resolves bot archive URLs before package download and logs the path')
ok(/autostart/.test(downloadQueue) && /start=1/.test(downloadQueue),
  'bot archive URL normalization removes autostart and starts the archive download')
ok(/if \(task\.url\.length === 0 && task\.parseSource !== DownloadArchiverParseSource\.BOT\) \{[\s\S]*return false/.test(downloadQueue) &&
  /if \(task\.url\.length === 0 && task\.parseSource === DownloadArchiverParseSource\.BOT\) \{[\s\S]*resolveArchiverBotUrl\(context, tag, task\)/.test(downloadQueue),
  'bot-source archive tasks skip official unlock/download-page URL requirements and resolve through the bot')
ok(/private static canResumeArchiverTask\(task: DownloadArchiverTask\): boolean \{[\s\S]*DownloadGalleryTaskStatus\.QUEUED[\s\S]*DownloadGalleryTaskStatus\.PREPARING[\s\S]*DownloadGalleryTaskStatus\.PAUSED[\s\S]*DownloadGalleryTaskStatus\.ERROR/.test(downloadQueue),
  'bot-source archive tasks left in resolving/preparing state can be resumed')
ok(/for \(let i: number = 0; i < archiverTasks\.length; i\+\+\) \{[\s\S]*shouldAutoResumeArchiverTask\(archiverTasks\[i\]\)[\s\S]*downloadArchiver\(context, archiverTasks\[i\]\.tag\)/.test(downloadQueue) &&
  /shouldAutoResumeArchiverTask\(task: DownloadArchiverTask\): boolean \{[\s\S]*DownloadGalleryTaskStatus\.QUEUED[\s\S]*DownloadGalleryTaskStatus\.PREPARING[\s\S]*connectDownloadSettings\(\)\.autoRetryFailed && task\.status === DownloadGalleryTaskStatus\.ERROR/.test(downloadQueue),
  'startup pending-resume restarts queued or interrupted preparing archive tasks and setting-enabled failed archive tasks')
ok(/DownloadSettings\.archiveBotReady\(\)/.test(downloadPage) &&
  /task\.parseSource === DownloadArchiverParseSource\.BOT/.test(downloadPage) &&
  /download_archiver_use_bot/.test(downloadPage),
  'download list exposes JHenTai-style switch-to-bot action only for ready, non-bot archive tasks')
ok(/private canResumeArchiverTask\(task: DownloadArchiverTask\): boolean \{[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*DownloadGalleryTaskStatus\.PREPARING[\s\S]*DownloadGalleryTaskStatus\.PAUSED[\s\S]*DownloadGalleryTaskStatus\.QUEUED/.test(downloadPage),
  'download list can resume archive bot tasks left in resolving/preparing state')
ok(/struct DownloadArchiverTaskCardView[\s\S]*private canResumeArchiverTask\(\): boolean \{[\s\S]*DownloadGalleryTaskStatus\.ERROR[\s\S]*DownloadGalleryTaskStatus\.PREPARING[\s\S]*DownloadGalleryTaskStatus\.PAUSED[\s\S]*DownloadGalleryTaskStatus\.QUEUED/.test(downloadPage),
  'archiver task card uses the same preparing-resumable rule as the queue page')

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
  'gallery_archiver_bot',
  'gallery_archiver_bot_original',
  'gallery_archiver_bot_free',
  'gallery_archiver_bot_not_ready',
  'download_archiver_already_queued',
  'download_archiver_use_bot',
]) {
  ok(strings.every((s) => s.includes(`"name": "${key}"`)), `i18n key present in all locales: ${key}`)
}

if (failures > 0) {
  console.error(`gallery archiver protected submit contract failed: ${failures} issue(s)`)
  process.exit(1)
}
console.log(`✓ gallery archiver protected submit contract: ${passed} assertions passed`)
