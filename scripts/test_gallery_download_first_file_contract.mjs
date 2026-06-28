#!/usr/bin/env node
/**
 * Contract: the Gallery download queue advances from `/s/` seed preparation to a bounded
 * full-gallery image executor. The executor consumes persisted download settings, records per-page
 * file metadata, and completes the task when every prepared seed has a local file.
 *
 * Run: node scripts/test_gallery_download_first_file_contract.mjs
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
  'eros_fe: lib/common/controller/download_controller.dart downloadGallery() / _addGalleryTask() / _startImageTask(); lib/common/controller/download/image_download_processor.dart downloadImageFlow() / getImageDownloadInfo() / fetchImageInfo()',
  'primary information: Downloads task row shows real file download progress through completion, not only seed preparation',
  'primary action: detail Read remains primary; Download remains secondary; queue row foregrounds download status/progress while Remove is secondary',
  'scope: resolve prepared /s/ seeds to real image URLs, write files under the app sandbox, honor image concurrency, and record per-page metadata; archiver and offline-reader source resolver remain separate lanes',
  'Harmony expression: HDS grouped list task row with downloaded progress in the subtitle; NetworkKit request plus CoreFileKit sandbox write, no new heavy UI',
]

ok(grounding.length === 5, 'download executor lane has five-line grounding')
ok(grounding[0].includes('download_controller.dart') &&
  grounding[0].includes('image_download_processor.dart') &&
  grounding[0].includes('downloadImageFlow') &&
  grounding[0].includes('fetchImageInfo'), 'grounding names concrete eros_fe files and methods')
ok(grounding[3].includes('/s/ seeds') && grounding[3].includes('image concurrency') &&
  grounding[3].includes('per-page metadata'), 'grounding states full executor scope')

const model = read('shared/src/main/ets/model/DownloadGalleryTask.ets')
const settings = read('shared/src/main/ets/settings/DownloadQueueSettings.ets')
const repo = read('shared/src/main/ets/storage/DownloadQueueRepository.ets')
const client = read('shared/src/main/ets/network/EhHttpClient.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const queue = read('feature/download/src/main/ets/pages/DownloadQueuePage.ets')

ok(/filePath: string = ''/.test(model) && /bytesWritten: number = 0/.test(model) &&
  /downloadError: string = ''/.test(model), 'download seed records sandbox file path, bytes, and error')
ok(/downloadedAt: number = 0/.test(model) && /downloadedCount/.test(model) &&
  /downloadProgressText/.test(model) && /pendingDownloadCount/.test(model),
  'gallery task tracks image download progress and remaining work')
ok(/DOWNLOADING: string = 'downloading'/.test(model) &&
  /PARTIAL: string = 'partial'/.test(model) &&
  /COMPLETE: string = 'complete'/.test(model), 'gallery task has full executor statuses')
ok(/preferOriginal: boolean = false/.test(model) && /task\.preferOriginal = this\.preferOriginal/.test(model),
  'gallery task persists the per-task original-image preference')

ok(/downloadGalleryImages/.test(settings) &&
  /connectDownloadSettings\(\)\.concurrency/.test(settings) &&
  /pendingSeeds/.test(settings), 'queue executor consumes persisted concurrency to pick pending work')
ok(/Promise\.all\(jobs\)/.test(settings) && /applyDownloadResults/.test(settings),
  'queue executor parallelizes downloads but merges state in one batch write')
ok(/ImageResolveService\.getInstance\(\)\.resolve/.test(settings) &&
  /ImageResolveService\.getInstance\(\)\.resolveOriginal/.test(settings),
  'queue executor resolves normal images and honors the always-original policy')
ok(/task\.preferOriginal\s*\|\|/.test(settings) &&
  /connectDownloadSettings\(\)\.originalMode === DownloadOriginalMode\.ALWAYS/.test(settings),
  'queue executor honors per-task original preference before the global always policy')
ok(/EhGalleryImage/.test(settings) && /image\.sUrl = seed\.imagePageUrl/.test(settings),
  'executor turns DownloadImageSeed back into an image-page resolve seed')
ok(/EhHttpClient\.getInstance\(\)\.downloadBinaryToFile/.test(settings),
  'executor downloads the resolved URL to a file')
ok(/context\.filesDir/.test(settings) && /download-gallery/.test(settings),
  'executor writes under the app sandbox download-gallery directory')
ok(/prepareGallerySeeds\(/.test(detail), 'detail download still starts through seed preparation')
ok(/enqueueGalleryDownloadWithPolicy/.test(detail) &&
  /DownloadOriginalMode\.ASK/.test(detail) &&
  /showAlertDialog/.test(detail) &&
  /task\.preferOriginal = preferOriginal/.test(detail),
  'detail download implements ask-mode choice before enqueueing a task')
ok(/await DownloadQueueSettings\.downloadGalleryImages\(context, gid, token\)/.test(settings),
  'seed preparation chains into the gallery image executor after preview seeds are ready')
ok(/parseSeeds/.test(settings) && /raw\.filePath/.test(settings) && /raw\.bytesWritten/.test(settings),
  'persisted queue restores downloaded file metadata')
ok(/mergePreparedSeeds/.test(settings) && /previous\.filePath\.length > 0/.test(settings) &&
  /out\.bytesWritten = previous\.bytesWritten/.test(settings),
  'seed refresh preserves existing downloaded file metadata for incremental updates')
ok(/private static sameSeed/.test(settings) &&
  /a\.page > 0 && b\.page > 0[\s\S]*return a\.page === b\.page/.test(settings),
  'incremental seed identity follows page number first so refreshed /s/ URLs do not redownload complete pages')
ok(/DownloadGalleryTaskStatus\.COMPLETE/.test(repo) && /DownloadGalleryTaskStatus\.COMPLETE/.test(settings),
  'repository and legacy parser preserve complete status instead of falling back to queued')
ok(/prefer_original/.test(repo), 'repository persists per-task original preference')

ok(/downloadBinaryToFile/.test(client) && /HttpDataType\.ARRAY_BUFFER/.test(client) &&
  /fs\.write/.test(client) && /maxLimit/.test(client), 'HTTP client can write binary response to a sandbox file')

ok(/download_file_progress/.test(queue) && /task\.downloadProgressText\(\)/.test(queue) &&
  /download_status_complete/.test(queue), 'downloads page shows file progress and complete status')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'download_status_downloading',
    'download_status_partial',
    'download_status_complete',
    'download_file_progress',
    'download_original_prompt',
    'download_use_regular_image',
    'download_use_original_image',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery download executor contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ gallery download executor contract: bounded full-gallery image executor locked')
