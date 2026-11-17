// Execute the archive service against temporary files; platform decompression is represented by unzip.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import vm from 'node:vm'
import { execFileSync } from 'node:child_process'
import { stripTypeScriptTypes } from 'node:module'

const source = fs.readFileSync(new URL('../shared/src/main/ets/services/ArchiveImageService.ets', import.meta.url), 'utf8')
const body = source.slice(source.indexOf('export class ArchiveImageService'))
  .replace('export class ArchiveImageService', 'class ArchiveImageService')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-archive-test-'))
let calls = 0
let fail = false
let failMarker = false
let release = null
const io = {
  accessSync: fs.existsSync,
  mkdirSync: (p, recursive) => fs.mkdirSync(p, { recursive }),
  listFileSync: fs.readdirSync,
  statSync: fs.statSync,
  readTextSync: p => fs.readFileSync(p, 'utf8'),
  openSync: p => ({ fd: fs.openSync(p, 'w') }),
  writeSync: (fd, value) => failMarker ? 0 : fs.writeSync(fd, value),
  closeSync: file => fs.closeSync(file.fd),
  unlinkSync: fs.unlinkSync,
  rmdirSync: p => fs.rmSync(p, { recursive: true }),
  OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
}
const zlib = {
  ParallelStrategy: { PARALLEL_STRATEGY_PARALLEL_DECOMPRESSION: 1 },
  PathSeparatorStrategy: { PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH: 1 },
  async decompressFile(input, output) {
    calls++
    if (release !== null) await new Promise(resolve => { release(resolve) })
    if (fail) { fs.writeFileSync(path.join(output, 'partial.jpg'), 'partial'); throw Error('extract failed') }
    execFileSync('/usr/bin/unzip', ['-qq', input, '-d', output])
  },
}
class Image { constructor(page) { this.page = page } }
const scope = vm.createContext({ fileIo: io, zlib, EhGalleryImage: Image,
  ImagePipelineService: { displayUri: p => `file://${p}` }, DiagnosticLogger: { info() {}, warn() {} },
  ARCHIVE_IMAGE_CACHE_DIR: 'download-archiver-read', ARCHIVE_COMPLETE_MARKER_PREFIX: 'complete:' })
vm.runInContext(stripTypeScriptTypes(`${body}\nthis.service = ArchiveImageService`), scope)
const service = scope.service
try {
  const archive = path.join(root, 'sample.cbz')
  execFileSync('python3', ['-c', `import sys, zipfile\nwith zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as z:\n for i in range(1,156): z.writestr(('nested/' if i > 100 else '') + str(i) + '.jpg', b'image')\n z.writestr('notes.txt', b'ignore')`, archive])
  const context = { cacheDir: root }
  const task = { tag: 'comic', filePath: archive, downloadedAt: 1, bytesWritten: 1 }
  const legacy = path.join(root, 'download-archiver-read', 'comic-1')
  const output = `${legacy}-verified-v1`
  fs.mkdirSync(legacy, { recursive: true })
  for (let i = 1; i <= 100; i++) fs.writeFileSync(path.join(legacy, `${i}.jpg`), 'image')
  fs.mkdirSync(output, { recursive: true })
  for (let i = 1; i <= 100; i++) fs.writeFileSync(path.join(output, `${i}.jpg`), 'partial')
  const first = await service.imagesForTask(context, task)
  assert.equal(first.length, 155)
  assert(first[100].imageUrl.endsWith('/nested/101.jpg'))
  assert.equal(first[154].page, 155)
  assert.equal(fs.readdirSync(legacy).length, 100)
  assert.equal(calls, 1)
  console.log('PASS unverified 100-page cache is rebuilt from a 155-page CBZ; legacy cache stays untouched')

  assert.equal((await service.imagesForTask(context, task)).length, 155)
  assert.equal(calls, 1)
  fs.unlinkSync(path.join(output, '1.jpg'))
  assert.equal((await service.imagesForTask(context, task)).length, 155)
  assert.equal(calls, 2)
  console.log('PASS completed caches are reused, and missing extracted images trigger reconstruction')

  const broken = { ...task, tag: 'failed' }
  fail = true
  await assert.rejects(service.imagesForTask(context, broken), /extract failed/)
  const brokenOutput = path.join(root, 'download-archiver-read', 'failed-1-verified-v1')
  assert.equal(fs.existsSync(brokenOutput), false)
  assert.equal(fs.existsSync(`${brokenOutput}.complete`), false)
  fail = false
  assert.equal((await service.imagesForTask(context, broken)).length, 155)
  console.log('PASS failed extraction removes its incomplete cache and can be retried')

  const failedMarker = { ...task, tag: 'marker-failed' }
  failMarker = true
  await assert.rejects(service.imagesForTask(context, failedMarker), /marker write incomplete/)
  const failedMarkerOutput = path.join(root, 'download-archiver-read', 'marker-failed-1-verified-v1')
  assert.equal(fs.existsSync(failedMarkerOutput), false)
  assert.equal(fs.existsSync(`${failedMarkerOutput}.complete`), false)
  failMarker = false
  assert.equal((await service.imagesForTask(context, failedMarker)).length, 155)
  console.log('PASS a failed completion-marker write is not treated as a valid cache')

  const concurrent = { ...task, tag: 'concurrent' }
  let continueExtraction
  release = resolve => { continueExtraction = resolve }
  const before = calls
  const a = service.imagesForTask(context, concurrent)
  const b = service.imagesForTask(context, concurrent)
  assert.equal(calls, before + 1)
  release = null
  continueExtraction()
  assert.equal((await a).length, 155)
  assert.equal((await b).length, 155)
  assert.equal(calls, before + 1)
  console.log('PASS concurrent archive requests share one extraction')
} finally {
  fs.rmSync(root, { recursive: true, force: true })
}
