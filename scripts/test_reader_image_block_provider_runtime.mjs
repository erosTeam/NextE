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
const core = { ...load('ReaderContent'), ...load('ReaderSession') }
let decisionBlocked = true
const calls = { decisions: [], whitelist: [], rules: [] }
const feedback = []
const shared = {
  AppStrings: { get(name) { return name } },
  DiagnosticLogger: { warn() {}, info() {} },
  ImageBlockDecision: class { blocked = false; sourceType = ''; feedId = '' },
  ImageBlockRuntimeService: {
    async decisionForFile(_context, filePath) {
      calls.decisions.push(filePath)
      return { blocked: decisionBlocked, sourceType: 'local', feedId: 'feed' }
    },
    async addWhitelistForFile(_context, filePath) { calls.whitelist.push(filePath) },
    async addLocalRuleForFile(_context, ...values) { calls.rules.push(values) },
  },
}
const exports = {}
const source = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderImageBlockProvider.ets'), 'utf8')
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText, {
  exports,
  require: name => {
    if (name === '@kit.AbilityKit') return {}
    if (name === '@reader-kit/core') return core
    if (name === 'shared') return shared
    throw new Error(`unexpected import ${name}`)
  },
})
const { NextEReaderImageBlockProvider } = exports
const unit = new core.ReaderUnitKey('eh', '12', '12')
const page = new core.ReaderPage(unit, '12:1', 0)
const backend = {
  cancellationMode: 'consumer-only', informationSupported: true,
  async load() { return new core.ReaderAsset('file:///cache/page.jpg') },
  async prepareOriginal(target) { return { page: target, variant: 'original', async load() {
    return new core.ReaderAsset('file:///cache/original.jpg')
  } } },
}
const provider = new NextEReaderImageBlockProvider({}, backend, message => feedback.push(message))
const cancellation = new core.ReaderCancellation()
const blocked = await provider.load(page, 'original', cancellation, false)
assert.equal(blocked.notice.id.includes('nexte-image-block:'), true)
assert.equal(blocked.notice.previewUri, 'file:///cache/page.jpg')
assert.equal(provider.canMark(page, true), false)
assert.equal(await blocked.resolveNotice(), true)
assert.deepEqual(calls.whitelist, ['/cache/page.jpg'])
assert.deepEqual(feedback, ['reader_image_block_allowed'])

decisionBlocked = false
const visible = await provider.load(page, 'original', new core.ReaderCancellation(), false)
assert.equal(visible.notice, null)
assert.equal(provider.canMark(page, true), true)
assert.equal(provider.canMark(page, false), false)
assert.equal(await provider.mark(page, true, 'https://e-hentai.org/g/12/token/'), 'added')
assert.deepEqual(calls.rules, [[
  '/cache/page.jpg', 'scanlator-ad', 8, 'https://e-hentai.org/g/12/token/', 1,
]])

decisionBlocked = true
const plan = await provider.prepareOriginal(page, new core.ReaderCancellation())
const original = await plan.load(new core.ReaderCancellation(), false)
assert.equal(original.notice.previewUri, 'file:///cache/original.jpg')
assert.equal(calls.decisions.at(-1), '/cache/original.jpg')

decisionBlocked = false
const forcedProvider = new NextEReaderImageBlockProvider({}, backend, () => {}, 0)
const forced = await forcedProvider.load(page, 'original', new core.ReaderCancellation(), false)
assert.equal(forced.notice.id.includes('nexte-image-block:'), true)
assert.equal(forced.notice.previewUri, 'file:///cache/page.jpg')
assert.equal(calls.decisions.at(-1), '/cache/original.jpg')

console.log('reader image block provider runtime: ok')
