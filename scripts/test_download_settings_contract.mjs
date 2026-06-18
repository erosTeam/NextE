#!/usr/bin/env node
/**
 * Contract: download preferences are real persisted V2 state, not static copy in the Download tab.
 *
 * The Downloads tab is a queue workbench. This contract keeps the preferences implementation alive
 * for the later settings lane, but prevents those controls from drifting back into queue content.
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
ok(/@Trace originalMode: string = DownloadOriginalMode\.ASK/.test(state),
  'download original mode defaults to ask')
ok(/AppStorageV2\.connect\(\s*DownloadSettingsState/.test(state),
  'download settings holder connects through AppStorageV2')

const settings = read('shared/src/main/ets/settings/DownloadSettings.ets')
ok(/StorageKeys\.DOWNLOAD_CONCURRENCY/.test(settings), 'settings persist concurrency key')
ok(/StorageKeys\.DOWNLOAD_ORIGINAL/.test(settings), 'settings persist original-mode key')
ok(/clampConcurrency/.test(settings) && /MIN_CONCURRENCY: number = 1/.test(settings) &&
  /MAX_CONCURRENCY: number = 8/.test(settings), 'settings clamp concurrency to a bounded range')
ok(/normalizeOriginalMode/.test(settings) && /DownloadOriginalMode\.OFF/.test(settings) &&
  /DownloadOriginalMode\.ALWAYS/.test(settings), 'settings normalize original mode enum values')
ok(/static async restore/.test(settings) && /connectDownloadSettings\(\)/.test(settings),
  'settings restore preferences into the V2 holder')
ok(/static async setConcurrency/.test(settings) && /store\.putSync\(StorageKeys\.DOWNLOAD_CONCURRENCY/.test(settings),
  'settings write concurrency to preferences')
ok(/static async setOriginalMode/.test(settings) && /store\.putSync\(StorageKeys\.DOWNLOAD_ORIGINAL/.test(settings),
  'settings write original mode to preferences')

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok(/import \{ DownloadSettings \}/.test(bootstrap) && /await DownloadSettings\.restore\(context\)/.test(bootstrap),
  'bootstrap restores download settings')

const barrel = read('shared/src/main/ets/Index.ets')
ok(/DownloadSettingsState/.test(barrel) && /connectDownloadSettings/.test(barrel) &&
  /DownloadSettings/.test(barrel), 'shared barrel exports download settings API')

const settingsRoot = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
ok(/settings_download/.test(settingsRoot) && /pushPathByName\('DownloadSettings'/.test(settingsRoot),
  'settings root exposes a Download settings entry')

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
ok(/download_original_images/.test(downloadPage) && /trailingDropdown: true/.test(downloadPage) &&
  /DownloadSettings\.setOriginalMode/.test(downloadPage),
  'download settings page exposes original-image policy as a native dropdown')
ok(/DownloadOriginalMode\.OFF/.test(downloadPage) && /DownloadOriginalMode\.ASK/.test(downloadPage) &&
  /DownloadOriginalMode\.ALWAYS/.test(downloadPage),
  'download original-image menu covers off, ask, and always')
ok(!/restore_tasks_data|rebuild_tasks_data|download_location|allow_media_scan/.test(downloadPage),
  'this lane does not add unimplemented download path/task-maintenance placeholders')

const page = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
ok(!/connectDownloadSettings|DownloadSettingsState|DownloadSettings\.setConcurrency|DownloadSettings\.setOriginalMode/.test(page),
  'download queue page does not own persisted settings controls')
ok(!/hasCounter: true|cycleOriginalMode|download_concurrency|download_original_images|download_not_configured/.test(page),
  'download queue page does not mix settings rows into queue content')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "settings_download"'), `${locale}: settings_download exists`)
  ok(strings.includes('"name": "download_concurrency_hint"'), `${locale}: download_concurrency_hint exists`)
  ok(strings.includes('"name": "download_original_hint"'), `${locale}: download_original_hint exists`)
  ok(strings.includes('"name": "download_original_ask"'), `${locale}: download_original_ask exists`)
  ok(strings.includes('"name": "download_original_always"'), `${locale}: download_original_always exists`)
}

if (failures > 0) {
  console.error(`\n✗ download settings contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ download settings contract: persisted concurrency + original mode locked')
