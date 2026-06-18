#!/usr/bin/env node
/**
 * Contract: the Downloads tab is a real queue workbench surface, not the old two-line placeholder.
 *
 * eros_fe's first-level Downloads tab is split into Gallery and Archiver queues. NextE's first
 * download lane should expose that structure without pretending the later background download service
 * or destructive archive submit flow already exists.
 *
 * Run: node scripts/test_download_workbench_contract.mjs
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

const page = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')

ok(/DOWNLOAD_VIEW_GALLERY/.test(page) && /DOWNLOAD_VIEW_ARCHIVER/.test(page),
  'download page defines Gallery and Archiver queue views')
ok(/@Local viewType: string = DOWNLOAD_VIEW_GALLERY/.test(page),
  'download page owns a reactive selected queue view')
ok(/private QueueSwitcher\(\)/.test(page) && /SwitchButton\(\$r\('app\.string\.tab_gallery'\), DOWNLOAD_VIEW_GALLERY\)/.test(page),
  'download page renders a Gallery switcher item')
ok(/SwitchButton\(\$r\('app\.string\.download_archiver'\), DOWNLOAD_VIEW_ARCHIVER\)/.test(page),
  'download page renders an Archiver switcher item')
ok(/SecondaryListScaffold/.test(page) && /GroupedListSection/.test(page),
  'download page uses the existing grouped-list scaffold, not a centered placeholder')
ok(/SummarySection/.test(page) && /download_active_tasks/.test(page) && /download_finished_tasks/.test(page),
  'download page shows queue summary rows')
ok(/EmptyQueueSection/.test(page) && /selectedEmptyText/.test(page) && /selectedNextStep/.test(page),
  'download page shows per-queue empty-state guidance')
ok(/SettingsPreviewSection/.test(page) && /download_concurrency/.test(page) && /download_original_images/.test(page),
  'download page reserves visible settings summary rows')
ok(!/queue · resume · archiver · offline read \(M4\)/.test(page) && !/Text\('Downloads'\)/.test(page),
  'old literal placeholder copy is gone')
ok(!/postArchiver|downloadRemote|downloadLoacal|downloadLocal|DownloadAgentService/.test(page),
  'this lane does not submit archive requests or start background downloads')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'download_archiver',
    'download_gallery_queue',
    'download_archiver_queue',
    'download_active_tasks',
    'download_finished_tasks',
    'download_status_empty',
    'download_gallery_empty',
    'download_archiver_empty',
    'download_gallery_next_step',
    'download_archiver_next_step',
    'download_concurrency',
    'download_original_images',
    'download_not_configured',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ download workbench contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ download workbench contract: Gallery/Archiver queue surface and i18n locked')
