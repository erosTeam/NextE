#!/usr/bin/env node
/**
 * Contract: download policy preferences stay in the dedicated settings page while the gallery image
 * executor consumes the parts it can currently honor.
 *
 * The Downloads tab is still a queue workbench; settings controls must not be mixed into its queue
 * body. The root entry opens the dedicated Download settings page.
 *
 * Run: node scripts/test_download_settings_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const state = read('shared/src/main/ets/state/DownloadSettingsState.ets')
ok(/@ObservedV2\s+export class DownloadSettingsState/.test(state), 'download settings holder is V2')
ok(/@Trace concurrency: number = 2/.test(state), 'download concurrency defaults to 2')
ok(/@Trace requestIntervalSeconds: number = 0/.test(state), 'download request interval defaults to off')
ok(/@Trace retryCount: number = 2/.test(state), 'download retry count defaults to 2')
ok(/@Trace autoRetryFailed: boolean = true/.test(state), 'download failed-task auto retry defaults to on')
ok(/@Trace speedLimitKbps: number = 0/.test(state), 'download speed limit defaults to off')
ok(/@Trace originalMode: string = DownloadOriginalMode\.ASK/.test(state),
  'download original mode defaults to ask')
ok(/AppStorageV2\.connect\(\s*DownloadSettingsState/.test(state),
  'download settings holder connects through AppStorageV2')

const settings = read('shared/src/main/ets/settings/DownloadSettings.ets')
const queueSettings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
ok(/StorageKeys\.DOWNLOAD_CONCURRENCY/.test(settings), 'settings persist concurrency key')
ok(/StorageKeys\.DOWNLOAD_REQUEST_INTERVAL_SECONDS/.test(settings), 'settings persist request interval key')
ok(/StorageKeys\.DOWNLOAD_RETRY_COUNT/.test(settings), 'settings persist retry count key')
ok(/StorageKeys\.DOWNLOAD_AUTO_RETRY_FAILED/.test(settings), 'settings persist failed-task auto retry key')
ok(/StorageKeys\.DOWNLOAD_SPEED_LIMIT_KBPS/.test(settings), 'settings persist speed limit key')
ok(/StorageKeys\.DOWNLOAD_ORIGINAL/.test(settings), 'settings persist original-mode key')
ok(/clampConcurrency/.test(settings) && /MIN_CONCURRENCY: number = 1/.test(settings) &&
  /MAX_CONCURRENCY: number = 8/.test(settings), 'settings clamp concurrency to a bounded range')
ok(/clampRequestIntervalSeconds/.test(settings) && /MIN_REQUEST_INTERVAL_SECONDS: number = 0/.test(settings) &&
  /MAX_REQUEST_INTERVAL_SECONDS: number = 10/.test(settings), 'settings clamp request interval to a bounded range')
ok(/clampRetryCount/.test(settings) && /MIN_RETRY_COUNT: number = 0/.test(settings) &&
  /MAX_RETRY_COUNT: number = 5/.test(settings), 'settings clamp retry count to a bounded range')
ok(/clampSpeedLimitKbps/.test(settings) && /MIN_SPEED_LIMIT_KBPS: number = 0/.test(settings) &&
  /MAX_SPEED_LIMIT_KBPS: number = 8192/.test(settings) &&
  /SPEED_LIMIT_STEP_KBPS: number = 256/.test(settings), 'settings clamp speed limit to bounded KB/s steps')
ok(/normalizeOriginalMode/.test(settings) && /DownloadOriginalMode\.OFF/.test(settings) &&
  /DownloadOriginalMode\.ALWAYS/.test(settings), 'settings normalize original mode enum values')
ok(/static async restore/.test(settings) && /connectDownloadSettings\(\)/.test(settings),
  'settings restore preferences into the V2 holder')
ok(/static async setConcurrency/.test(settings) && /store\.putSync\(StorageKeys\.DOWNLOAD_CONCURRENCY/.test(settings),
  'settings write concurrency to preferences')
ok(/static async setRequestIntervalSeconds/.test(settings) &&
  /store\.putSync\(StorageKeys\.DOWNLOAD_REQUEST_INTERVAL_SECONDS/.test(settings),
  'settings write request interval to preferences')
ok(/static async setRetryCount/.test(settings) && /store\.putSync\(StorageKeys\.DOWNLOAD_RETRY_COUNT/.test(settings),
  'settings write retry count to preferences')
ok(/static async setAutoRetryFailed/.test(settings) &&
  /store\.putSync\(StorageKeys\.DOWNLOAD_AUTO_RETRY_FAILED/.test(settings),
  'settings write failed-task auto retry to preferences')
ok(/static async setSpeedLimitKbps/.test(settings) &&
  /store\.putSync\(StorageKeys\.DOWNLOAD_SPEED_LIMIT_KBPS/.test(settings),
  'settings write speed limit to preferences')
ok(/static async setOriginalMode/.test(settings) && /store\.putSync\(StorageKeys\.DOWNLOAD_ORIGINAL/.test(settings),
  'settings write original mode to preferences')
ok(/connectDownloadSettings\(\)\.concurrency/.test(queueSettings) &&
  /connectDownloadSettings\(\)\.requestIntervalSeconds/.test(queueSettings) &&
  /connectDownloadSettings\(\)\.retryCount/.test(queueSettings) &&
  /connectDownloadSettings\(\)\.autoRetryFailed/.test(queueSettings) &&
  /connectDownloadSettings\(\)\.speedLimitKbps/.test(queueSettings) &&
  /connectDownloadSettings\(\)\.originalMode/.test(queueSettings),
  'gallery image executor consumes persisted download policy')
ok(/batchIndex > 0/.test(queueSettings) &&
  /DownloadQueueSettings\.delay\(connectDownloadSettings\(\)\.requestIntervalSeconds \* 1000\)/.test(queueSettings),
  'gallery image executor throttles later image batches by the persisted request interval')
ok(/downloadSeedToFile\(context, gid, token, seed, useOriginal, retryCount\)/.test(queueSettings) &&
  /Math\.round\(retryCount\) \+ 1/.test(queueSettings),
  'gallery image executor retries each failed image according to the persisted retry count')
ok(/const attempts: number = Math\.max\(1, Math\.round\(connectDownloadSettings\(\)\.retryCount\) \+ 1\)/.test(queueSettings) &&
  /downloadBinaryToFileInStream\([\s\S]*ARCHIVER_ACCEPT,[\s\S]*attempts/.test(queueSettings),
  'archiver executor retries according to the persisted retry count')
ok(/const batchStartedAt: number = Date\.now\(\)/.test(queueSettings) &&
  /delayForSpeedLimit\(batchStartedAt, results\)/.test(queueSettings) &&
  /const kbps: number = connectDownloadSettings\(\)\.speedLimitKbps/.test(queueSettings) &&
  /Math\.ceil\(bytes \* 1000 \/ \(kbps \* 1024\)\)/.test(queueSettings),
  'gallery image executor applies the persisted average speed limit after successful batches')
const archiverDownloadBody = queueSettings.match(/private static async runArchiverDownload\([\s\S]*?\n  \}/)?.[0] ?? ''
ok(/downloadBinaryToFileInStream\([\s\S]*ARCHIVER_ACCEPT,[\s\S]*attempts/.test(archiverDownloadBody) &&
  !/delayBytesForSpeedLimit/.test(archiverDownloadBody),
  'archiver executor does not apply gallery image speed throttling to single package downloads')

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok(/import \{ DownloadSettings \}/.test(bootstrap) && /await DownloadSettings\.restore\(context\)/.test(bootstrap),
  'bootstrap restores download settings')

const barrel = read('shared/src/main/ets/Index.ets')
ok(/DownloadSettingsState/.test(barrel) && /connectDownloadSettings/.test(barrel) &&
  /DownloadSettings/.test(barrel), 'shared barrel exports download settings API')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
ok(/settings_download/.test(settingsRoot) && /pushPathByName\('DownloadSettings', null\)/.test(settingsRoot),
  'settings root exposes the dedicated Download settings page')
ok(/settings_reader[\s\S]*settings_download[\s\S]*settings_search/.test(settingsRoot),
  'settings root places Download settings between Reader and Search')

const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
ok(/DownloadSettingsPage/.test(settingsIndex), 'settings barrel exports DownloadSettingsPage')

const entryIndex = read('entry/src/main/ets/pages/Index.ets')
ok(/DownloadSettingsPage/.test(entryIndex) && /name === 'DownloadSettings'/.test(entryIndex),
  'entry router registers the DownloadSettings route')

const downloadPage = read('feature/settings/src/main/ets/pages/DownloadSettingsPage.ets')
ok(/eros_fe DownloadSettingPage/.test(downloadPage), 'download settings page records eros_fe grounding')
ok(/@ComponentV2\s+export struct DownloadSettingsPage/.test(downloadPage),
  'download settings page is V2-only')
ok(/@Local downloadSettings: DownloadSettingsState = connectDownloadSettings\(\)/.test(downloadPage),
  'download settings page reads the persisted download settings holder')
ok(/download_concurrency/.test(downloadPage) && /hasCounter: true/.test(downloadPage) &&
  /DownloadSettings\.setConcurrency/.test(downloadPage),
  'download settings page exposes persisted image concurrency as a counter')
ok(/download_request_interval/.test(downloadPage) && /hasCounter: true/.test(downloadPage) &&
  /DownloadSettings\.setRequestIntervalSeconds/.test(downloadPage),
  'download settings page exposes persisted request interval as a counter')
ok(/download_retry_count/.test(downloadPage) && /hasCounter: true/.test(downloadPage) &&
  /DownloadSettings\.setRetryCount/.test(downloadPage),
  'download settings page exposes persisted retry count as a counter')
ok(/download_auto_retry_failed/.test(downloadPage) && /hasSwitch: true/.test(downloadPage) &&
  /checked: this\.downloadSettings\.autoRetryFailed/.test(downloadPage) &&
  /DownloadSettings\.setAutoRetryFailed/.test(downloadPage),
  'download settings page exposes failed-task auto retry as a persisted switch')
ok(/download_speed_limit/.test(downloadPage) && /hasCounter: true/.test(downloadPage) &&
  /DownloadSettings\.setSpeedLimitKbps/.test(downloadPage) &&
  /speedLimitLabel/.test(downloadPage),
  'download settings page exposes persisted average speed limit as a counter')
ok(/download_original_images/.test(downloadPage) && /trailingDropdown: true/.test(downloadPage) &&
  /DownloadSettings\.setOriginalMode/.test(downloadPage),
  'download settings page exposes original-image policy as a native dropdown')
ok(/DownloadOriginalMode\.OFF/.test(downloadPage) && /DownloadOriginalMode\.ASK/.test(downloadPage) &&
  /DownloadOriginalMode\.ALWAYS/.test(downloadPage),
  'download original-image menu covers off, ask, and always')
ok(/archiveBotBalanceBusy/.test(downloadPage) && /archiveBotCheckInBusy/.test(downloadPage) &&
  /archiveBotBalanceStatus/.test(downloadPage) && /archiveBotCheckInStatus/.test(downloadPage) &&
  !/@Local archiveBotBusy/.test(downloadPage) && !/@Local archiveBotStatus/.test(downloadPage),
  'archive bot balance and check-in rows keep independent loading states')
ok(/setArchiveBotBalance\(this\.ctx\(\), result\.gp\)/.test(downloadPage) &&
  /DOWNLOAD_ARCHIVE_BOT_BALANCE_GP/.test(settings) &&
  /archiveBotBalanceGp/.test(state),
  'archive bot balance is cached in persisted download settings')
ok(/refreshArchiveBotBalanceSilently\(\)/.test(downloadPage) &&
  /aboutToAppear\(\)[\s\S]*this\.refreshArchiveBotBalanceSilently\(\)/.test(downloadPage) &&
  /archive_bot_balance_auto_refresh_start/.test(downloadPage) &&
  /archive_bot_balance_auto_refresh_failed/.test(downloadPage),
  'download settings page silently refreshes archive bot balance on entry')
ok(/if \(result\.hasBalance\) \{[\s\S]*setArchiveBotBalance\(this\.ctx\(\), result\.gp\)/.test(downloadPage),
  'archive bot balance cache is updated only when the response carries a balance field')
ok(/result\.message\.length > 0 && result\.reward <= 0/.test(downloadPage) &&
  /result\.hasBalance && \(result\.gp > 0 \|\| result\.reward > 0\)/.test(downloadPage),
  'archive bot check-in shows server messages and does not let already-checked zero balances overwrite cache')
ok(/canCheckArchiveBotBalance/.test(downloadPage) && /canCheckInArchiveBot/.test(downloadPage) &&
  /download_archive_bot_balance[\s\S]*archiveBotBalanceBusy[\s\S]*BusySuffix/.test(downloadPage) &&
  /download_archive_bot_checkin[\s\S]*archiveBotCheckInBusy[\s\S]*BusySuffix/.test(downloadPage),
  'archive bot balance and check-in actions show row-local loading feedback')
ok(/archive_bot_balance_check_start/.test(downloadPage) && /archive_bot_balance_check_done/.test(downloadPage) &&
  /archive_bot_balance_check_failed/.test(downloadPage) && /archive_bot_checkin_start/.test(downloadPage) &&
  /archive_bot_checkin_done/.test(downloadPage) && /archive_bot_checkin_failed/.test(downloadPage),
  'archive bot settings validation emits action-level diagnostics')
ok(!/restore_tasks_data|rebuild_tasks_data|download_location|allow_media_scan/.test(downloadPage),
  'this lane does not add unimplemented download path/task-maintenance placeholders')

const archiveBotService = read('shared/src/main/ets/services/ArchiveBotService.ets')
ok(/archive_bot_request_start/.test(archiveBotService) && /archive_bot_request_done/.test(archiveBotService) &&
  /archive_bot_request_failed/.test(archiveBotService) && /DiagnosticLogger\.ownerHash\(gid\)/.test(archiveBotService),
  'archive bot service emits redacted request start/done/failure diagnostics')
ok(/body\.length > 0[\s\S]*extraData: body/.test(archiveBotService) &&
  /headers\(settings, false\)/.test(archiveBotService) &&
  /if \(hasBody\) \{[\s\S]*Content-Type/.test(archiveBotService),
  'archive-at-home no-body actions are sent without JSON body headers')

const page = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
ok(!/connectDownloadSettings|DownloadSettingsState|DownloadSettings\.setConcurrency|DownloadSettings\.setOriginalMode/.test(page),
  'download queue page does not own persisted settings controls')
ok(!/hasCounter: true|cycleOriginalMode|download_concurrency|download_original_images|download_not_configured/.test(page),
  'download queue page does not mix settings rows into queue content')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "settings_download"'), `${locale}: settings_download exists`)
  ok(strings.includes('"name": "download_concurrency_hint"'), `${locale}: download_concurrency_hint exists`)
  ok(strings.includes('"name": "download_request_interval"'), `${locale}: download_request_interval exists`)
  ok(strings.includes('"name": "download_request_interval_hint"'), `${locale}: download_request_interval_hint exists`)
  ok(strings.includes('"name": "download_retry_count"'), `${locale}: download_retry_count exists`)
  ok(strings.includes('"name": "download_retry_count_hint"'), `${locale}: download_retry_count_hint exists`)
  ok(strings.includes('"name": "download_auto_retry_failed"'), `${locale}: download_auto_retry_failed exists`)
  ok(strings.includes('"name": "download_auto_retry_failed_hint"'), `${locale}: download_auto_retry_failed_hint exists`)
  ok(strings.includes('"name": "download_speed_limit"'), `${locale}: download_speed_limit exists`)
  ok(strings.includes('"name": "download_speed_limit_hint"'), `${locale}: download_speed_limit_hint exists`)
  ok(strings.includes('"name": "download_original_hint"'), `${locale}: download_original_hint exists`)
  ok(strings.includes('"name": "download_original_ask"'), `${locale}: download_original_ask exists`)
  ok(strings.includes('"name": "download_original_always"'), `${locale}: download_original_always exists`)
  ok(strings.includes('"name": "download_original_prompt"'), `${locale}: download_original_prompt exists`)
  ok(strings.includes('"name": "download_use_regular_image"'), `${locale}: download_use_regular_image exists`)
  ok(strings.includes('"name": "download_use_original_image"'), `${locale}: download_use_original_image exists`)
  ok(strings.includes('"name": "download_archiver_use_bot"'), `${locale}: download_archiver_use_bot exists`)
  ok(!/普通图|压缩图/.test(strings), `${locale}: legacy compressed/regular image wording is not used`)
  if (locale === 'zh_CN') {
    ok(strings.includes('"value": "重采样图片"'), 'zh_CN: regular image option is named 重采样图片')
    ok(strings.includes('"value": "重采样图片或原始文件"'), 'zh_CN: original image subtitle uses 重采样图片 without trailing punctuation')
  }
}

if (failures > 0) {
  console.error(`\n✗ download settings contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ download settings contract: exposed settings page feeds the gallery executor')
