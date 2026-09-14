import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const text = fs.readFileSync(new URL('../feature/reader/src/main/ets/lab/NextEReaderLabAdapter.ets', import.meta.url), 'utf8')
const start = text.indexOf('class NextEOriginalAssetPlan ')
const end = text.indexOf('export class NextEReaderLabAdapter', start)
const source = text.slice(start, end).replace('class NextEOriginalAssetPlan', 'export class NextEOriginalAssetPlan')
const copyable = values => ({ ...values, copy() { return copyable(this) } })
const token = () => ({ cancelled: false, check() { if (this.cancelled) throw new Error('cancelled') } })
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r }); return { promise, resolve } }
function fixture(resolveOriginal) {
  const downloads = []
  const context = { exports: {},
    ImageResolveService: { getInstance: () => ({ resolveOriginal }) },
    ImagePipelineService: { async loadReaderFile(_context, url, key, _priority, _unused, force) {
      downloads.push({ url, key, force }); return { displayUri: url, filePath: 'local-file', bytes: 42 }
    } },
    ReaderImageInformation: class {}, ReaderFileInformation: class { constructor(path, facts) { this.facts = facts } },
    NextEReaderCropSource: class { constructor(path) { this.path = path } },
    ReaderAsset: class { constructor(uri, release, information) { Object.assign(this, { uri, release, information }) } },
  }
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  const plan = new context.exports.NextEOriginalAssetPlan(copyable({ key: 'page' }), {},
    copyable({ originImageUrl: 'old', reloadKey: 'old-key' }), 'old', 'original-cache')
  return { plan, downloads }
}
test('successful retry retains refreshed original URL for later normal loads', async () => {
  const f = fixture(async (source, force) => {
    assert.equal(force, true); source.originImageUrl = 'fresh'; source.reloadKey = 'fresh-key'; return 'fresh'
  })
  const result = await f.plan.load(token(), true)
  await f.plan.load(token(), false)
  assert.deepEqual(f.downloads, [
    { url: 'fresh', key: 'original-cache', force: true },
    { url: 'fresh', key: 'original-cache', force: false },
  ])
  assert.equal(result.information.facts.variant, 'original')
})
test('cancelled old resolver cannot overwrite a newer successful plan source or URL', async () => {
  const old = deferred(); let calls = 0
  const f = fixture(async source => {
    if (++calls === 1) {
      await old.promise; source.originImageUrl = 'stale'; source.reloadKey = 'stale-key'; return 'stale'
    }
    source.originImageUrl = 'fresh'; source.reloadKey = 'fresh-key'; return 'fresh'
  })
  const cancelled = token(), first = f.plan.load(cancelled, true)
  cancelled.cancelled = true
  await f.plan.load(token(), true)
  old.resolve(); await assert.rejects(first, /cancelled/)
  assert.equal(f.plan.source.reloadKey, 'fresh-key')
  await f.plan.load(token(), false)
  assert.deepEqual(f.downloads.map(value => value.url), ['fresh', 'fresh'])
})
test('original resolver failure never downloads or falls back to the default variant', async () => {
  const f = fixture(async () => { throw new Error('quota') })
  await assert.rejects(f.plan.load(token(), true), /quota/)
  assert.equal(f.downloads.length, 0)
})

test('default asset manual reload re-sources before replacing cached bytes', async () => {
  const resolutions = [], downloads = []
  const ReaderAsset = class {
    constructor(uri, release, information) { Object.assign(this, { uri, release, information }) }
  }
  const context = { exports: {}, require: name => {
    if (name === 'shared') return {
      ImageResolveService: { getInstance: () => ({ resolve: async (source, changeSource) => {
        resolutions.push({ changeSource, reloadKey: source.reloadKey })
        source.imageUrl = changeSource ? 'https://fixture.invalid/fresh.webp' : 'https://fixture.invalid/old.webp'
        source.reloadKey = changeSource ? 'fresh-key' : source.reloadKey
        return source.imageUrl
      } }) },
      ImagePipelineService: {
        readerFileCacheKey: () => 'resampled-cache',
        loadReaderFile: async (_context, url, key, _priority, _unused, force) => {
          downloads.push({ url, key, force })
          return { displayUri: url, filePath: 'local-file', bytes: 42 }
        },
      },
      ReaderPageCropService: {},
    }
    if (name === '@reader-kit/core') return {
      ReaderAsset,
      ReaderImageInformation: class {},
    }
    if (name === '@reader-kit/ui') return {
      ReaderFileInformation: class { constructor(path, facts) { Object.assign(this, { path, facts }) } },
    }
    if (name === '../viewmodel/ReaderViewModel') return { ReaderViewModel: class {} }
    if (name === '@kit.ArkData') return { uniformTypeDescriptor: {} }
    if (name === '@kit.ShareKit') return { systemShare: {} }
    return {}
  } }
  vm.runInNewContext(ts.transpileModule(text, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  const adapter = new context.exports.NextEReaderLabAdapter({}, 'token', false)
  adapter.pages.set('page', copyable({ page: 1, reloadKey: 'old-key', originImageUrl: '' }))
  const page = { key: 'page', unit: { work: 'gallery' }, sourceIndex: 0 }

  await adapter.load(page, 'original', token(), false)
  await adapter.load(page, 'original', token(), true)
  await adapter.load(page, 'original', token(), true)

  assert.deepEqual(resolutions, [
    { changeSource: false, reloadKey: 'old-key' },
    { changeSource: true, reloadKey: 'old-key' },
    { changeSource: true, reloadKey: 'fresh-key' },
  ])
  assert.deepEqual(downloads, [
    { url: 'https://fixture.invalid/old.webp', key: 'resampled-cache', force: false },
    { url: 'https://fixture.invalid/fresh.webp', key: 'resampled-cache', force: true },
    { url: 'https://fixture.invalid/fresh.webp', key: 'resampled-cache', force: true },
  ])
})

test('shared preload resolves and warms the default cache without creating a Reader asset', async () => {
  const resolutions = [], downloads = []
  const context = { exports: {}, require: name => {
    if (name === 'shared') return {
      ImageResolveService: { getInstance: () => ({ resolve: async (source, force) => {
        resolutions.push({ page: source.page, force })
        source.imageUrl = 'https://fixture.invalid/preloaded.webp'
        return source.imageUrl
      } }) },
      ImagePipelineService: {
        readerFileCacheKey: (_work, _token, page, original) => `${page}:${original}`,
        loadReaderFile: async (_context, url, key, priority) => {
          downloads.push({ url, key, priority })
          return { displayUri: url, filePath: 'preloaded-file', bytes: 42 }
        },
      },
      ReaderPageCropService: {},
    }
    if (name === '@reader-kit/core') return {}
    if (name === '@reader-kit/ui') return {}
    if (name === '../viewmodel/ReaderViewModel') return { ReaderViewModel: class {} }
    if (name === '@kit.ArkData') return { uniformTypeDescriptor: {} }
    if (name === '@kit.ShareKit') return { systemShare: {} }
    return {}
  } }
  vm.runInNewContext(ts.transpileModule(text, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  const adapter = new context.exports.NextEReaderLabAdapter({}, 'token', false)
  adapter.pages.set('page', copyable({ page: 7, imageUrl: '' }))
  await adapter.preload({ key: 'page', unit: { work: 'gallery' }, sourceIndex: 6 }, token())
  assert.deepEqual(resolutions, [{ page: 7, force: undefined }])
  assert.deepEqual(downloads, [{
    url: 'https://fixture.invalid/preloaded.webp', key: '7:false', priority: 100,
  }])
})

test('actual share adapter builds its hyperlink from the selected variant and rejects cancelled resolution', async () => {
  const calls = [], records = [], c = token()
  const context = { exports: {}, require: name => {
    if (name === 'shared') return { ImageResolveService: { getInstance: () => ({
      resolve: async () => { calls.push('default'); return 'https://fixture.invalid/resampled.webp' },
      resolveOriginal: async () => { calls.push('original'); return 'https://fixture.invalid/original.jpg' },
    }) } }
    if (name === '@kit.ArkData') return { uniformTypeDescriptor: { UniformDataType: { HYPERLINK: 'link' } } }
    if (name === '@kit.ShareKit') return { systemShare: {
      SharedData: class { constructor(record) { records.push(record) } },
      SelectionMode: { SINGLE: 1 }, SharePreviewMode: { DETAIL: 1 },
    } }
    if (name === '@reader-kit/ui') return { ReaderSystemSharePresentation: class {} }
    return {}
  } }
  vm.runInNewContext(ts.transpileModule(text, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  const adapter = new context.exports.NextEReaderLabAdapter({}, 'token', false)
  adapter.page = async () => ({ key: 'p2' })
  adapter.pages.set('p2', copyable({ page: 1 }))
  const target = { unit: { title: 'Fixture', key: { unit: 'gallery' } }, sourceIndex: 1, variant: 'original' }
  await adapter.prepare(target, c)
  target.variant = 'default'; await adapter.prepare(target, c)
  assert.deepEqual(calls, ['original', 'default'])
  assert.deepEqual(records.map(r => r.content), ['https://fixture.invalid/original.jpg', 'https://fixture.invalid/resampled.webp'])
  assert.deepEqual(records.map(r => r.title), ['Fixture 2', 'Fixture 2'])
  c.cancelled = true
  await assert.rejects(adapter.prepare(target, c), /cancelled/)
  assert.equal(records.length, 2)
})

test('optional adapter selects a complete local source before network and keeps local assets local', async () => {
  const records = [], network = [], downloads = []
  class ReaderParams {
    constructor(gid, token, index) {
      Object.assign(this, { gid, token, index, fileCount: 0, title: '', seedImages: [], sourceLanguage: 'auto',
        source: { isLocal: () => false } })
    }
  }
  const localImage = copyable({ page: 1, imageUrl: 'file:///fixture/page-1.jpg', thumbUrl: 'https://invalid/thumb.jpg',
    thumbWidth: 0, thumbHeight: 0, spriteWidth: 0, spriteHeight: 0, thumbOffsetX: 0 })
  const localParams = { gid: 'gallery', token: 'token', index: 0, fileCount: 1, title: 'Downloaded fixture',
    seedImages: [localImage], sourceLanguage: 'english',
    source: { kind: 'galleryDownload', variant: 'original', isLocal: () => true } }
  const ReaderAsset = class {
    constructor(uri, release, information) { Object.assign(this, { uri, release, information }) }
  }
  const context = { exports: {}, require: name => {
    if (name === 'shared') return {
      ReaderParams,
      ReaderLocalSourceService: { preferLocal: async () => localParams },
      EhApiService: { getInstance: () => ({ getGalleryDetail: async () => { network.push('detail'); throw new Error('network') } }) },
      ImageResolveService: { getInstance: () => ({ resolve: async () => { network.push('resolve'); return '' },
        resolveOriginal: async () => { network.push('original'); return '' } }) },
      ImagePipelineService: { loadReaderFile: async () => { downloads.push('download'); return {} } },
      ReaderPageCropService: {},
    }
    if (name === '@reader-kit/core') return {
      ReaderUnit: class { constructor(key, title, pageCount) { Object.assign(this, { key, title, pageCount }) } },
      ReaderPage: class { constructor(unit, key, sourceIndex) {
        Object.assign(this, { unit, key, sourceIndex, thumbnail: {} })
      } },
      ReaderAsset,
      ReaderImageInformation: class {},
    }
    if (name === '@reader-kit/ui') return {
      ReaderFileInformation: class { constructor(path, facts) { Object.assign(this, { path, facts }) } },
      ReaderSystemSharePresentation: class { constructor(_context, data) { this.data = data } },
    }
    if (name === '@kit.ArkData') return { uniformTypeDescriptor: { UniformDataType: { IMAGE: 'image', HYPERLINK: 'link' } } }
    if (name === '@kit.ShareKit') return { systemShare: {
      SharedData: class { constructor(record) { this.record = record; records.push(record) } },
      SelectionMode: { SINGLE: 1 }, SharePreviewMode: { DETAIL: 1 },
    } }
    if (name === '../viewmodel/ReaderViewModel') return { ReaderViewModel: class {} }
    return {}
  } }
  vm.runInNewContext(ts.transpileModule(text, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  const adapter = new context.exports.NextEReaderLabAdapter({}, 'token', false)
  const cancellation = token()
  const unit = await adapter.open({ scope: 'eh', work: 'gallery', unit: 'gallery' }, cancellation)
  assert.equal(unit.title, 'Downloaded fixture')
  assert.equal(unit.pageCount, 1)
  assert.deepEqual(network, [])
  const page = await adapter.page(unit, 0, cancellation)
  assert.equal(page.thumbnail.kind, 'image')
  const asset = await adapter.load(page, 'original', cancellation, false)
  assert.equal(asset.uri, 'file:///fixture/page-1.jpg')
  assert.equal(asset.information.path, '/fixture/page-1.jpg')
  assert.equal(asset.information.facts.variant, 'original')
  await adapter.preload(page, cancellation)
  assert.deepEqual(downloads, [])
  await adapter.prepare({ unit, sourceIndex: 0, variant: 'default' }, cancellation)
  assert.equal(records.length, 1)
  assert.equal(records[0].uri, 'file:///fixture/page-1.jpg')
  assert.equal(records[0].utd, 'image')
  await assert.rejects(adapter.prepareOriginal(page, cancellation), /local_original_already_selected/)
})

const pageSource = fs.readFileSync(new URL('../feature/reader/src/main/ets/lab/NextEReaderLabPage.ets', import.meta.url), 'utf8')
test('optional host passes its cache warmer and persisted depth into reader-kit', () => {
  assert.match(text, /implements ReaderCatalog, ReaderAssetProvider, ReaderPreloadHost/)
  assert.match(pageSource, /new ReaderPagedSession\(adapter,[\s\S]*?\), adapter\)/)
  assert.match(pageSource, /preloadDepth: this\.readMode\.preloadPages/)
})
