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
const released = []
const calls = []
let processResult = { filePath: '/cache/enhanced.jpg', displayUri: 'file:///cache/enhanced.jpg',
  applied: true, reason: '' }
let processPromise = null
const shared = {
  ReaderSuperResolutionTaskPriority: { CURRENT: 0, PREFETCH: 1 },
  ReaderPageCropService: { async detect() { return new core.ReaderImageCropBounds() } },
  async readerSuperResolutionProcess(...args) {
    calls.push(args); args[3]('processing'); return processPromise === null ? processResult : processPromise
  },
  readerSuperResolutionReleaseOwner(owner) { released.push(owner) },
}
const exports = {}
const source = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderSuperResolutionProvider.ets'), 'utf8')
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
    throw new Error(`unexpected import ${name}`)
  },
})
const { NextEReaderSuperResolutionConfiguration, NextEReaderSuperResolutionProvider } = exports
const unit = new core.ReaderUnitKey('eh', '12', '12')
const page = new core.ReaderPage(unit, '12:1', 0)
let configuration = new NextEReaderSuperResolutionConfiguration(true, 'waifu', 'vulkan', 2000)
const sourceAsset = new core.ReaderAsset('file:///cache/source.jpg')
sourceAsset.originalAvailable = true
const backend = { cancellationMode: 'consumer-only', informationSupported: true,
  async load() { return sourceAsset }, async prepareOriginal(p) {
    return { page: p, async load() { return sourceAsset } }
  } }
const provider = new NextEReaderSuperResolutionProvider({}, backend, () => configuration,
  () => '', (candidate) => candidate === page ? 'https://ehgt.org/original-page.jpg?token=fixture' : '')
const cancellation = new core.ReaderCancellation()
await provider.load(page, 'original', cancellation, false)
const identity = configuration.identity()
const plan = await provider.prepareVariant(page, 'enhanced', identity, cancellation)
assert.equal(calls.length, 1)
assert.equal(calls[0][1], '/cache/source.jpg')
assert.equal(calls[0][2], 'eh:12:12:12:1:0')
assert.match(calls[0][4], /^reader-shared:/)
assert.equal(plan.identity, identity)
assert.equal(provider.information(page, identity).applied, true)
assert.equal(provider.information(page, identity).reason, '')
const enhanced = await plan.load(new core.ReaderCancellation(), false)
assert.equal(enhanced.uri, 'file:///cache/enhanced.jpg')
assert.equal(enhanced.saveUri, 'https://ehgt.org/original-page.jpg?token=fixture')
assert.equal(enhanced.originalAvailable, true)
enhanced.release(); enhanced.release()
assert.equal(released.length, 1)

let resolveProcessing
processPromise = new Promise(resolve => { resolveProcessing = resolve })
const cancelled = new core.ReaderCancellation()
const pending = provider.prepareVariant(page, 'enhanced', identity, cancelled)
await Promise.resolve()
cancelled.cancel()
resolveProcessing(processResult)
await assert.rejects(pending, /reader_request_cancelled/)
assert.ok(released.length >= 2)

processPromise = null
configuration = new NextEReaderSuperResolutionConfiguration(true, 'waifu', 'cpu', 2000)
await assert.rejects(provider.prepareVariant(page, 'enhanced', identity, new core.ReaderCancellation()),
  /reader_variant_unavailable/)
processResult = { filePath: '', displayUri: 'file:///cache/source.jpg', applied: false,
  reason: 'model_not_installed' }
await assert.rejects(provider.prepareVariant(page, 'enhanced', configuration.identity(), new core.ReaderCancellation()),
  /reader_variant_not_applied:model_not_installed/)
assert.equal(provider.information(page, configuration.identity()).applied, false)
assert.equal(provider.information(page, configuration.identity()).reason, 'model_not_installed')

// A future page needs only a leased file, never an off-screen decoded frame.
processResult = { filePath: '/cache/enhanced.jpg', displayUri: 'file:///cache/enhanced.jpg', applied: true, reason: '' }
let sourceReleases = 0
let sourceBlocked = false
const preloader = new NextEReaderSuperResolutionProvider({}, backend, () => configuration,
  () => '', () => 'https://ehgt.org/original-page.jpg', async () => {
    const asset = new core.ReaderAsset('file:///cache/source.jpg', () => { sourceReleases++ })
    if (sourceBlocked) asset.notice = { kind: 'blocked' }
    return asset
  })
await preloader.preload(page, new core.ReaderCancellation())
assert.equal(calls.at(-1)[2], calls[0][2], 'prewarm and visible request share the processed cache identity')
assert.equal(calls.at(-1)[5], shared.ReaderSuperResolutionTaskPriority.PREFETCH)
assert.equal(sourceReleases, 1)
sourceBlocked = true
const beforeBlocked = calls.length
await preloader.preload(page, new core.ReaderCancellation())
assert.equal(calls.length, beforeBlocked, 'blocked source never enters enhancement')
assert.equal(sourceReleases, 2)
sourceBlocked = false
let finishWarm
processPromise = new Promise(resolve => { finishWarm = resolve })
const warmCancellation = new core.ReaderCancellation()
const warm = preloader.preload(page, warmCancellation)
await Promise.resolve(); await Promise.resolve()
warmCancellation.cancel()
finishWarm(processResult)
await assert.rejects(warm, /reader_request_cancelled/)
assert.equal(sourceReleases, 3, 'cancelled warm retains its source until the processor returns')
processPromise = null

// A replaced window can overlap an older cancelled warm while the native work drains.
let finishOverlapping
processPromise = new Promise(resolve => { finishOverlapping = resolve })
const olderCancellation = new core.ReaderCancellation()
const overlapCallStart = calls.length
const olderWarm = preloader.preload(page, olderCancellation)
for (let step = 0; step < 10 && calls.length < overlapCallStart + 1; step++) await Promise.resolve()
assert.equal(calls.length, overlapCallStart + 1)
const olderOwner = calls.at(-1)[4]
const newerWarm = preloader.preload(page, new core.ReaderCancellation())
for (let step = 0; step < 10 && calls.length < overlapCallStart + 2; step++) await Promise.resolve()
assert.equal(calls.length, overlapCallStart + 2)
const newerOwner = calls.at(-1)[4]
assert.notEqual(olderOwner, newerOwner, 'retiring an old window must not release the newer window owner')
const beforeOlderCancel = released.length
olderCancellation.cancel()
assert.equal(released[beforeOlderCancel], olderOwner)
assert.equal(released.slice(beforeOlderCancel).includes(newerOwner), false)
finishOverlapping(processResult)
await assert.rejects(olderWarm, /reader_request_cancelled/)
await newerWarm
assert.equal(released.includes(newerOwner), true)
processPromise = null

const preloadExports = {}
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderProcessingPreloadHost.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText, { exports: preloadExports, require: name => {
  if (name === '@reader-kit/core') return core
  if (name === './NextEReaderSuperResolutionProvider') return exports
  throw new Error(`unexpected import ${name}`)
}, console: { info() {}, warn() {} } })
const warmedPages = []
const demands = new preloadExports.NextEReaderProcessingPreloadHost({ async preload(_page, token) {
  token.check()
} }, { async preload(candidate, token) { token.check(); warmedPages.push(candidate.sourceIndex) } })
const window = new core.ReaderCancellation()
await demands.preload(page, window)
demands.setActive(false)
demands.refresh()
await Promise.resolve(); await Promise.resolve()
assert.equal(warmedPages.length, 1, 'inactive reader starts no processing')
demands.setActive(true)
await Promise.resolve(); await Promise.resolve(); await Promise.resolve()
assert.equal(warmedPages.length, 2, 'foreground restores retained demand')
window.cancel()
demands.refresh()
await Promise.resolve(); await Promise.resolve()
assert.equal(warmedPages.length, 2, 'retired window does not rewarm')
demands.close()

const nativeExports = {}
const nativeSource = fs.readFileSync(path.join(root,
  'shared/src/main/ets/services/ReaderNativeSuperResolution.ets'), 'utf8')
vm.runInNewContext(ts.transpileModule(nativeSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText, {
  exports: nativeExports,
  require: name => {
    if (name === 'libreader_enhancement.so') return { default: undefined }
    throw new Error(`unexpected import ${name}`)
  },
})
assert.doesNotThrow(() => nativeExports.ReaderNativeSuperResolution.setInteractionPaused(true))
const serviceSource = fs.readFileSync(path.join(root,
  'shared/src/main/ets/services/ReaderSuperResolutionService.ets'), 'utf8')
assert.match(serviceSource,
  /effectivePaused: boolean = connectReadMode\(\)\.superResolutionEnabled &&/)
const hostSource = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabPage.ets'), 'utf8')
assert.match(hostSource,
  /private superResolutionAvailable\(\): boolean \{[\s\S]*?superResolutionEnabled[\s\S]*?superResolutionModel !== ReaderSuperResolutionModel\.NONE/)
assert.match(hostSource,
  /variantPolicy: new ReaderVariantPolicy\(new ReaderVariantPreference\([\s\S]*?this\.superResolutionAvailable\(\) \? 'enhanced' : 'default'/)
assert.match(hostSource,
  /private superResolutionIdentity\(\): string \{[\s\S]*?return this\.superResolutionAvailable\(\) \? this\.superResolutionConfiguration\(\)\.identity\(\) : ''/)
assert.match(hostSource, /new ReaderMediaActions\([\s\S]*?this\.imageInformationSupplement\(frame, value\)/)
assert.match(hostSource, /reader_image_info_enhancement_applied/)
assert.match(hostSource, /reader_image_info_enhancement_processing/)
assert.match(hostSource, /reader_image_info_enhancement_queued/)
assert.match(hostSource, /reader_image_info_enhancement_not_applied/)

const adapterSource = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabAdapter.ets'), 'utf8')
assert.match(adapterSource, /imageInformationSource\(page: ReaderPage\): string/)
assert.match(adapterSource, /ReaderSourceKind\.GALLERY_DOWNLOAD/)
assert.match(adapterSource, /ReaderSourceKind\.ARCHIVE/)
assert.match(adapterSource, /reader_image_info_source/)

console.log('reader super-resolution provider runtime: ok')
