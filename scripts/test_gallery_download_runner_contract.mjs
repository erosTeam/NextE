#!/usr/bin/env node
/**
 * Contract: Gallery downloads advance through a bounded foreground serial runner after seed
 * preparation. This is still not the full background download service.
 *
 * Run: node scripts/test_gallery_download_runner_contract.mjs
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

const grounding = [
  'eros_fe: lib/common/controller/download_controller.dart _startGalleryDownload() / _startImageTask(); lib/common/controller/download/image_download_processor.dart downloadImageFlow() / checkAndGetImageList()',
  'primary information: Downloads task row shows real file progress continuing beyond the first file',
  'primary action: detail Read remains primary; Download is secondary; queue row foregrounds download progress while Remove is secondary',
  'scope: after seed preparation, run a bounded foreground serial batch, skip already downloaded seeds, and stop on visible error; no background daemon, pause/resume, concurrent slot manager, external directory picker, archiver, or original-image policy expansion',
  'Harmony expression: keep the HDS grouped queue row and V2 state holder; implement the runner in DownloadQueueSettings single-writer with NetworkKit plus CoreFileKit writes',
]

ok(grounding.length === 5, 'download runner lane has five-line grounding')
ok(grounding[0].includes('download_controller.dart') &&
  grounding[0].includes('_startImageTask') &&
  grounding[0].includes('image_download_processor.dart') &&
  grounding[0].includes('downloadImageFlow'), 'grounding names concrete eros_fe files and methods')
ok(grounding[3].includes('bounded foreground serial batch') &&
  grounding[3].includes('no background daemon'), 'grounding states bounded runner scope and non-scope')

const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const queue = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')
const client = read('shared/src/main/ets/network/EhHttpClient.ets')

ok(/INITIAL_GALLERY_DOWNLOAD_BATCH_LIMIT: number = 3/.test(settings),
  'runner starts with a small bounded batch limit')
ok(/static async runGalleryDownloadBatch/.test(settings) &&
  /while \(downloaded < maxImages\)/.test(settings), 'runner loops serially up to maxImages')
ok(/activeGalleryRuns: string\[\] = \[\]/.test(settings) &&
  /activeGalleryRuns\.indexOf\(runKey\) >= 0/.test(settings) &&
  /removeActiveRun\(runKey\)/.test(settings), 'runner guards duplicate same-gallery runs')
ok(/await DownloadQueueSettings\.runGalleryDownloadBatch\(\s*context,\s*gid,\s*token,\s*INITIAL_GALLERY_DOWNLOAD_BATCH_LIMIT,\s*\)/.test(settings),
  'seed preparation chains into the bounded runner')
ok(/downloadFirstGalleryImage[\s\S]*runGalleryDownloadBatch\(context, gid, token, 1\)/.test(settings),
  'first-file compatibility entry remains a one-image batch')
ok(/firstPendingSeed/.test(settings) &&
  /seed\.filePath\.length === 0/.test(settings), 'runner skips already downloaded seeds')
ok(/downloadSeedToFile/.test(settings) &&
  /ImageResolveService\.getInstance\(\)\.resolve/.test(settings) &&
  /EhHttpClient\.getInstance\(\)\.downloadBinaryToFile/.test(settings),
  'runner resolves each image page immediately before writing the file')
ok(/updateSeedDownloadError/.test(settings) &&
  /DownloadGalleryTaskStatus\.ERROR/.test(settings), 'runner persists a visible failure and stops on error')
ok(/DownloadGalleryTaskStatus\.COMPLETE/.test(settings) &&
  /firstPendingSeed\(refreshed\) === null/.test(settings), 'runner marks complete when no seeds remain')

ok(/COMPLETE: string = 'complete'/.test(model) &&
  /isComplete\(\)/.test(model), 'download task can represent completion')
ok(/selectedFinishedCount/.test(queue) &&
  /download_status_complete/.test(queue) &&
  /task\.isComplete\(\)/.test(queue), 'downloads page reflects completed task count and status')
ok(/HttpDataType\.ARRAY_BUFFER/.test(client) &&
  /fs\.write/.test(client), 'runner still writes files through NetworkKit/CoreFileKit')

ok(!/DownloadAgentService|PauseTask|ResumeTask|Executor|requestInStream|postArchiver|downloadRemote/.test(
  `${settings}\n${queue}`,
), 'runner slice does not introduce background agents, pause/resume, concurrent executor, stream queue, or archive submit')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  ok(strings.includes('"name": "download_status_complete"'), `${locale}: complete status string exists`)
}

if (failures > 0) {
  console.error(`\n✗ gallery download runner contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download runner contract: bounded foreground serial batch locked')
