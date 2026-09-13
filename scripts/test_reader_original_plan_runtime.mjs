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
  const target = { unit: { title: 'Fixture' }, sourceIndex: 1, variant: 'original' }
  await adapter.prepare(target, c)
  target.variant = 'default'; await adapter.prepare(target, c)
  assert.deepEqual(calls, ['original', 'default'])
  assert.deepEqual(records.map(r => r.content), ['https://fixture.invalid/original.jpg', 'https://fixture.invalid/resampled.webp'])
  assert.deepEqual(records.map(r => r.title), ['Fixture 2', 'Fixture 2'])
  c.cancelled = true
  await assert.rejects(adapter.prepare(target, c), /cancelled/)
  assert.equal(records.length, 2)
})
