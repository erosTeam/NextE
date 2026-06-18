#!/usr/bin/env node
/**
 * Contract: download preferences are real persisted V2 state, not static copy in the Download tab.
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

const page = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
ok(/@Local downloadSettings: DownloadSettingsState = connectDownloadSettings\(\)/.test(page),
  'download page reads the reactive download settings holder')
ok(/hasCounter: true/.test(page) && /counterValue: `\$\{this\.downloadSettings\.concurrency\}`/.test(page),
  'download page exposes concurrency as a counter')
ok(/DownloadSettings\.setConcurrency\(this\.ctx\(\), this\.downloadSettings\.concurrency \+ delta\)/.test(page),
  'download page counter writes through DownloadSettings')
ok(/private cycleOriginalMode\(\): void/.test(page) && /DownloadSettings\.setOriginalMode\(this\.ctx\(\), next\)/.test(page),
  'download page cycles original image policy through DownloadSettings')
ok(!/download_not_configured/.test(page), 'download page no longer renders Not configured for real settings')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "download_original_ask"'), `${locale}: download_original_ask exists`)
  ok(strings.includes('"name": "download_original_always"'), `${locale}: download_original_always exists`)
}

if (failures > 0) {
  console.error(`\n✗ download settings contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ download settings contract: persisted concurrency + original mode locked')
