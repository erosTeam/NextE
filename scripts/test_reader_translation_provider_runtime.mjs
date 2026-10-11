import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const ts = require(process.env.READER_KIT_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const load = require(path.join(root, 'third_party/reader-kit/tests/load-core.cjs'))
const core = { ...load('ReaderContent'), ...load('ReaderSession'), ...load('ReaderImageCrop'),
  ...load('ReaderImageInformation') }
const calls = []
let pending = null
let runtimeBehavior = null
let runtimeResult = { renderedPage: { identity: { projectId: 'nexte-gallery:eh:12:zh-CN', pageIndex: 0,
  targetLanguage: 'zh-CN' }, localFilePath: '/cache/translated.png' } }
const shared = {
  ReaderPageCropService: { async detect() { return new core.ReaderImageCropBounds() } },
  ComicTranslationReaderPageInput: class {
    projectId = ''; pageIndex = -1; imageFilePath = ''; imageWidth = 0; imageHeight = 0
    sourceLanguage = 'auto'; targetLanguage = 'zh-CN'
  },
  ComicTranslationRuntimeService: {
    async runReaderPage(...args) {
      calls.push(args)
      if (runtimeBehavior !== null) return runtimeBehavior(...args)
      return pending === null ? runtimeResult : pending
    },
  },
  // Mirrors the real classifier contract for the failure-code recording path.
  ComicTranslationErrorClassifier: {
    classify(error) {
      const message = String(error && error.message).toLowerCase()
      if (message.includes('manga rendering service')) return 'rendering_service_configuration'
      if (message.includes('api key')) return 'provider_configuration'
      if (message.includes('harmony device ocr')) return 'local_visual_unavailable'
      if (message.includes('no translatable text')) return 'no_translatable_text'
      return 'provider_request_failed'
    },
  },
}
const exports = {}
const source = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderTranslationProvider.ets'), 'utf8')
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText, {
  exports,
  require: name => {
    if (name === '@kit.AbilityKit') return {}
    if (name === '@reader-kit/core') return core
    if (name === '@reader-kit/ui') return { ReaderFileInformation: class { constructor(filePath, facts) {
      this.path = filePath; this.facts = facts
    } } }
    if (name === 'shared') return shared
    if (name === './NextEReaderCropSource') return { NextEReaderCropSource: class {
      constructor(path, _identity, _strength) { this.path = path }
    } }
    // Debug seam: no local result is armed, so the probe stays inert in this logic test.
    if (name === './NextEReaderTranslationProbe') return { connectNextEReaderTranslationProbe: () => ({
      deliver() {}, result() { return '' }, unavailable() { return false },
      async pauseBeforeResult() {}, release() {}, cancel() {},
    }) }
    throw new Error(`unexpected import ${name}`)
  },
})
const { NextEReaderTranslationConfiguration, NextEReaderTranslationProvider } = exports
const unit = new core.ReaderUnitKey('eh', '12', '12')
const page = new core.ReaderPage(unit, '12:1', 0)
page.width = 900
page.height = 1400
let configuration = new NextEReaderTranslationConfiguration(true,
  'nexte-gallery:eh:12:zh-CN', 'zh-CN', 'japanese', 3)
const sourceAsset = new core.ReaderAsset('file:///cache/source.jpg')
sourceAsset.originalAvailable = true
let delegated = false
const backend = { cancellationMode: 'consumer-only', informationSupported: true,
  async load() { return sourceAsset },
  async prepareOriginal(p) { return { page: p, async load() { return sourceAsset } } },
  async prepareVariant(p, variant, identity) {
    delegated = true
    return { page: p, variant, identity, async load() { return sourceAsset } }
  } }
const saveUriForPage = (candidate) => candidate === page ? 'https://ehgt.org/original-page.jpg?token=fixture' : ''
const provider = new NextEReaderTranslationProvider({}, backend, () => configuration,
  () => '', saveUriForPage)
const cancellation = new core.ReaderCancellation()
await provider.load(page, 'original', cancellation, false)
const identity = configuration.identity()
const plan = await provider.prepareVariant(page, 'translated', identity, cancellation)
assert.equal(calls.length, 1)
assert.equal(calls[0][1].projectId, 'nexte-gallery:eh:12:zh-CN')
assert.equal(calls[0][1].imageFilePath, '/cache/source.jpg')
assert.equal(calls[0][1].imageWidth, 900)
assert.equal(calls[0][1].imageHeight, 1400)
assert.equal(calls[0][1].sourceLanguage, 'japanese')
const translated = await plan.load(new core.ReaderCancellation(), false)
assert.equal(translated.uri, 'file:///cache/translated.png')
assert.equal(translated.saveUri, 'https://ehgt.org/original-page.jpg?token=fixture')
assert.equal(translated.originalAvailable, true)

await provider.prepareVariant(page, 'enhanced', 'enhanced-id', new core.ReaderCancellation())
assert.equal(delegated, true)

configuration = new NextEReaderTranslationConfiguration(true,
  'nexte-gallery:eh:12:zh-CN', 'zh-CN', 'auto', 4)
await assert.rejects(provider.prepareVariant(page, 'translated', identity, new core.ReaderCancellation()),
  /reader_translation_configuration_unavailable/)

configuration = new NextEReaderTranslationConfiguration(true,
  'nexte-gallery:eh:12:zh-CN', 'zh-CN', 'japanese', 3)
let resolveRuntime
pending = new Promise(resolve => { resolveRuntime = resolve })
const cancelled = new core.ReaderCancellation()
const operation = provider.prepareVariant(page, 'translated', identity, cancelled)
await Promise.resolve()
cancelled.cancel()
resolveRuntime(runtimeResult)
await assert.rejects(operation, /reader_request_cancelled/)

pending = null
runtimeResult = { renderedPage: { identity: { projectId: 'other', pageIndex: 0,
  targetLanguage: 'zh-CN' }, localFilePath: '/cache/stale.png' } }
await assert.rejects(provider.prepareVariant(page, 'translated', identity, new core.ReaderCancellation()),
  /reader_translation_result_stale/)

// A translation failure records its classified code for the host to render, and an
// ordinary success clears any earlier code.
assert.equal(provider.lastFailureCode(page.sourceIndex), '')
const failingProvider = new NextEReaderTranslationProvider({}, backend, () => configuration,
  () => '', saveUriForPage)
await failingProvider.load(page, 'original', cancellation, false)
pending = Promise.reject(new Error('Configure the manga rendering service first'))
await assert.rejects(failingProvider.prepareVariant(page, 'translated', identity,
  new core.ReaderCancellation()), /manga rendering service/)
pending = null
assert.equal(failingProvider.lastFailureCode(page.sourceIndex), 'rendering_service_configuration')

runtimeResult = { renderedPage: { identity: { projectId: 'nexte-gallery:eh:12:zh-CN', pageIndex: 0,
  targetLanguage: 'zh-CN' }, localFilePath: '/cache/translated.png' } }
const okProvider = new NextEReaderTranslationProvider({}, backend, () => configuration,
  () => '', saveUriForPage)
await okProvider.load(page, 'original', cancellation, false)
assert.equal(okProvider.lastFailureCode(page.sourceIndex), '')

// Preprocessing waits for file readiness, rather than the two-second displayed-frame poll.
const future = new core.ReaderPage(unit, '12:2', 1)
let readySource
const sourceReady = new Promise(resolve => { readySource = resolve })
let warmSourceReleases = 0
let finishModel
let modelStarted = false
runtimeBehavior = async (_context, input) => {
  assert.equal(input.imageWidth, 800, 'undisplayed page uses retained source header width')
  assert.equal(input.imageHeight, 1200, 'undisplayed page uses retained source header height')
  modelStarted = true
  await new Promise(resolve => { finishModel = resolve })
  return { renderedPage: { identity: { projectId: input.projectId, pageIndex: input.pageIndex,
    targetLanguage: input.targetLanguage }, localFilePath: '/cache/warm-translated.png' } }
}
const warmProvider = new NextEReaderTranslationProvider({}, backend, () => configuration,
  () => '', () => 'https://ehgt.org/source.jpg', async () => {
    await sourceReady
    return new core.ReaderAsset('file:///cache/future.jpg', () => { warmSourceReleases++ }, {
      async read() {
        const facts = new core.ReaderImageInformation()
        facts.width = 800; facts.height = 1200
        return facts
      },
    })
  })
const warmToken = new core.ReaderCancellation()
const background = warmProvider.prepareVariant(future, 'translated', identity, warmToken)
const beforeReady = calls.length
await Promise.resolve(); await Promise.resolve()
assert.equal(calls.length, beforeReady, 'unready source starts no model call')
readySource()
for (let i = 0; i < 12; i++) await Promise.resolve()
assert.equal(calls.at(-1)[1].imageWidth, 800, 'production preflight gets a positive file-header width')
assert.equal(calls.at(-1)[1].imageHeight, 1200)
assert.equal(modelStarted, true, 'future page processing needs no decoded frame')
assert.equal(future.width, 0, 'catalog page remains undecoded and unmodified')
assert.equal(future.height, 0)
const beforeJoin = calls.length
// Entering the prewarmed page joins its existing task.
const displayed = warmProvider.prepareVariant(future, 'translated', identity, new core.ReaderCancellation())
warmToken.cancel()
finishModel()
await assert.rejects(background, /reader_request_cancelled/)
assert.equal((await displayed).variant, 'translated')
assert.equal(calls.length, beforeJoin, 'foreground joins the running next-page task without consuming quota again')
assert.equal(warmSourceReleases, 2, 'both consumers release their independently retained source')

// Distinct pages share one model lane. A retired queued page consumes no model quota.
let releaseFirst
let activeModels = 0
let peakModels = 0
const startedPages = []
runtimeBehavior = async (_context, input) => {
  activeModels++; peakModels = Math.max(peakModels, activeModels); startedPages.push(input.pageIndex)
  if (input.pageIndex === 0) await new Promise(resolve => { releaseFirst = resolve })
  activeModels--
  return { renderedPage: { identity: { projectId: input.projectId, pageIndex: input.pageIndex,
    targetLanguage: input.targetLanguage }, localFilePath: `/cache/page-${input.pageIndex}.png` } }
}
const serialProvider = new NextEReaderTranslationProvider({}, backend, () => configuration,
  () => '', () => 'https://ehgt.org/source.jpg')
const latest = new core.ReaderPage(unit, '12:3', 2)
for (const candidate of [page, future, latest]) {
  await serialProvider.load(candidate, 'original', new core.ReaderCancellation(), false)
}
const first = serialProvider.prepareVariant(page, 'translated', identity, new core.ReaderCancellation())
for (let i = 0; i < 10; i++) await Promise.resolve()
const retired = new core.ReaderCancellation()
const queued = serialProvider.prepareVariant(future, 'translated', identity, retired)
const queuedRejected = assert.rejects(queued, /reader_request_cancelled/)
retired.cancel()
const current = serialProvider.prepareVariant(latest, 'translated', identity, new core.ReaderCancellation())
assert.deepEqual(startedPages, [0])
releaseFirst()
await first; await queuedRejected; await current
assert.deepEqual(startedPages, [0, 2])
assert.equal(peakModels, 1)
runtimeBehavior = null
await okProvider.prepareVariant(page, 'translated', identity, new core.ReaderCancellation())
assert.equal(okProvider.lastFailureCode(page.sourceIndex), '')

console.log('reader translation provider runtime: ok')
