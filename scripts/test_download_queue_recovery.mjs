// Execute the production queue and recovery methods with temporary files and an in-memory store.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import vm from 'node:vm'
import { stripTypeScriptTypes } from 'node:module'

const source = fs.readFileSync(new URL('../shared/src/main/ets/settings/DownloadQueueSettings.ets', import.meta.url), 'utf8')
const names = ['restore', 'importTasksFromDownloadDirectory', 'enqueueGallery', 'enqueueArchiver',
  'loadGalleryMetadataTasks', 'loadArchiverMetadataTasks', 'mergeRestoredGalleryTasks', 'mergeRestoredArchiverTasks',
  'countNewGalleryTasks', 'countNewArchiverTasks', 'parse', 'parseArchiver', 'sameGalleryTask']
const methods = names.map(name => {
  const match = source.match(new RegExp(`^  (?:private )?static (?:async )?${name}\\(`, 'm'))
  assert(match, name)
  const end = source.indexOf('\n  }', match.index)
  return source.slice(match.index, end + 4)
}).join('\n')
class GalleryTask {
  constructor(gid = '') { Object.assign(this, { gid, token: `t${gid}`, title: '', titleJp: '', thumbUrl: '', imgWidth: 0, imgHeight: 0, pageCount: 0, category: '', uploader: '', upgradeFromGid: '', preferOriginal: false, imageSeeds: [], status: 'complete', firstPageCount: 0, previewPageCount: 0, preparedAt: 0, prepareError: '' }) }
  copy() { return Object.assign(new GalleryTask(), this, { imageSeeds: [...this.imageSeeds] }) }
  syncProgressCounts() {}
}
class ArchiverTask {
  constructor(tag = '') { Object.assign(this, { tag, gid: tag, token: '', title: '', thumbUrl: '', imgWidth: 0, imgHeight: 0, url: 'https://example.test', parseSource: 'official', status: 'complete', bytesWritten: 1, filePath: '/existing', resolution: '', queuedAt: 0, downloadedAt: 0 }) }
  copy() { return Object.assign(new ArchiverTask(), this) }
}
const state = { galleryTasks: [], archiverTasks: [] }
const stored = { gallery: [], archiver: [] }
const warnings = []
const context = vm.createContext({
  fs: { accessSync: p => fs.existsSync(p), listFileSync: fs.readdirSync, statSync: fs.statSync,
    readTextSync: p => fs.readFileSync(p, 'utf8') },
  DownloadGalleryTask: GalleryTask, DownloadArchiverTask: ArchiverTask,
  DownloadDirectoryImportResult: class {
    constructor() { this.galleryTasks = 0; this.archiverTasks = 0; this.scannedGalleryTasks = 0; this.scannedArchiverTasks = 0 }
  },
  DownloadGalleryTaskStatus: { QUEUED: 'queued', COMPLETE: 'complete', DOWNLOADING: 'downloading' },
  DownloadArchiverParseSource: { BOT: 'bot', OFFICIAL: 'official' },
  DiagnosticLogger: { info() {}, warn: (...args) => warnings.push(args), ownerHash: () => 'redacted' },
  DownloadQueueRepository: { load: async () => stored.gallery, loadArchiver: async () => stored.archiver },
  DownloadQueueRestoreReconciler: {
    galleryNeedsRdbReconcile: (old, next) => old.length !== next.length,
    archiverNeedsRdbReconcile: (old, next) => old.length !== next.length,
  },
  connectDownloadQueue: () => state,
  DOWNLOAD_METADATA_FILE: 'metadata.json', ARCHIVER_METADATA_SUFFIX: '.metadata.json',
})
vm.runInContext(stripTypeScriptTypes(`class DownloadQueueSettings {\n${methods}\n}\nthis.subject = DownloadQueueSettings`), context)
const subject = context.subject
subject.galleryDownloads = new Map()
subject.archiverDownloads = new Map()
subject.cancelledGalleryDownloads = new Set()
subject.cancelledArchiverDownloads = new Set()
subject.taskKey = (gid, token, original) => `${gid}:${token}:${original}`
subject.setGalleryTasks = (s, tasks) => { s.galleryTasks = tasks }
subject.setArchiverTasks = (s, tasks) => { s.archiverTasks = tasks }
subject.fillArchiverTaskFromGalleryTask = () => {}
subject.findGalleryTaskIn = () => undefined
subject.galleryQuality = () => 'resampled'
subject.persistGalleryTask = async (...args) => { assert.equal(args.length, 2) }
subject.persistArchiverTask = async (...args) => { assert.equal(args.length, 2) }
subject.parseSeeds = () => []
subject.normalizeStatus = value => value
subject.normalizeArchiverParseSource = value => value
subject.joinPath = path.join
subject.migrateLegacyPreferences = async () => {}
subject.normalizeRestoredGalleryTasks = tasks => tasks
subject.normalizeRestoredArchiverTasks = tasks => tasks
subject.hydrateArchiverTasksFromGalleryTasks = tasks => tasks
subject.persist = async (_, tasks) => { stored.gallery = tasks.map(task => task.copy()) }
subject.persistArchiver = async (_, tasks) => { stored.archiver = tasks.map(task => task.copy()) }
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-queue-recovery-'))
try {
  state.galleryTasks = Array.from({ length: 201 }, (_, i) => new GalleryTask(`g${i}`))
  state.archiverTasks = Array.from({ length: 101 }, (_, i) => new ArchiverTask(`a${i}`))
  await subject.enqueueGallery({}, new GalleryTask('new'))
  await subject.enqueueArchiver({}, new ArchiverTask('new'))
  assert.equal(state.galleryTasks.length, 202)
  assert.equal(state.archiverTasks.length, 102)
  assert(state.galleryTasks.some(task => task.gid === 'g200'))
  assert(state.archiverTasks.some(task => task.tag === 'a100'))
  console.log('PASS enqueue preserves every prior task beyond both old limits')

  const galleryRoot = path.join(fixture, 'gallery')
  const archiverRoot = path.join(fixture, 'archiver')
  fs.mkdirSync(galleryRoot); fs.mkdirSync(archiverRoot)
  for (let i = 0; i < 205; i++) {
    const dir = path.join(galleryRoot, `gallery-${i}`)
    fs.mkdirSync(dir)
    fs.writeFileSync(path.join(dir, 'metadata.json'), JSON.stringify([new GalleryTask(`g${i}`)]))
  }
  for (let i = 0; i < 105; i++) {
    fs.writeFileSync(path.join(archiverRoot, `archive-${i}.metadata.json`), JSON.stringify([new ArchiverTask(`a${i}`)]))
  }
  fs.mkdirSync(path.join(archiverRoot, 'bad.metadata.json')) // A single unreadable entry must not stop scanning.
  subject.galleryRootDirs = () => [galleryRoot]
  subject.archiverRootDirs = () => [archiverRoot]
  const gallery = subject.loadGalleryMetadataTasks()
  const archiver = subject.loadArchiverMetadataTasks()
  assert.equal(gallery.length, 205)
  assert.equal(archiver.length, 105)
  assert(warnings.some(args => args[1] === 'archiver_metadata_entry_restore_failed'))
  assert.equal(subject.parse(JSON.stringify(Array.from({ length: 205 }, (_, i) => new GalleryTask(`x${i}`)))).length, 205)
  assert.equal(subject.parseArchiver(JSON.stringify(Array.from({ length: 105 }, (_, i) => new ArchiverTask(`x${i}`)))).length, 105)
  console.log('PASS metadata scanning and parsing recover beyond old limits, despite a bad entry')

  const mergedGallery = subject.mergeRestoredGalleryTasks([new GalleryTask('g0')], gallery)
  const mergedArchiver = subject.mergeRestoredArchiverTasks([new ArchiverTask('a0')], archiver)
  assert.equal(mergedGallery.length, 205)
  assert.equal(mergedArchiver.length, 105)
  assert.equal(mergedGallery.filter(task => task.gid === 'g0').length, 1)
  assert.equal(mergedArchiver.filter(task => task.tag === 'a0').length, 1)
  console.log('PASS recovery merges all sidecars without replacing or duplicating current records')

  stored.gallery = [new GalleryTask('g0')]
  stored.archiver = [new ArchiverTask('a0')]
  await subject.restore({})
  assert.equal(state.galleryTasks.length, 205)
  assert.equal(state.archiverTasks.length, 105)
  assert.equal(stored.gallery.length, 205)
  assert.equal(stored.archiver.length, 105)
  await subject.restore({})
  assert.equal(state.galleryTasks.length, 205)
  assert.equal(state.archiverTasks.length, 105)
  console.log('PASS startup merges sidecars when their roots are already available')

  state.galleryTasks = gallery.map(task => task.copy())
  state.archiverTasks = Array.from({ length: 100 }, (_, i) => new ArchiverTask(`a${i}`))
  subject.ensureDownloadStorageReady = async () => true
  const imported = await subject.importTasksFromDownloadDirectory({})
  assert.equal(imported.archiverTasks, 5)
  assert.equal(state.archiverTasks.length, 105)
  assert.equal(stored.archiver.length, 105)
  const repeated = await subject.importTasksFromDownloadDirectory({})
  assert.equal(repeated.archiverTasks, 0)
  assert.equal(state.archiverTasks.length, 105)
  console.log('PASS explicit directory recovery finds five displaced archive tasks and does not duplicate them')
} finally {
  fs.rmSync(fixture, { recursive: true, force: true })
}
