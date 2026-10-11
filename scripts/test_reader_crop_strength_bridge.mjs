import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createHash } from 'node:crypto'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const sourcePath = path.join(root, 'feature/reader/src/main/ets/lab/NextEReaderCropSource.ets')
const source = fs.readFileSync(sourcePath, 'utf8')
const calls = []
const context = { exports: {}, require: name => {
  if (name === 'shared') return {
    DiagnosticLogger: { info() {} },
    ReaderPageCropService: { async detectFile(filePath, strength) {
    calls.push({ filePath, strength })
    return { left: .1, top: .2, right: .3, bottom: .4 }
  } } }
  if (name === '@reader-kit/core') return { ReaderImageCropBounds: class {
    constructor(left, top, right, bottom) { Object.assign(this, { left, top, right, bottom }) }
  } }
  return {}
} }
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
} }).outputText, context)

let strength = 'strong'
const crop = new context.exports.NextEReaderCropSource('/cache/page.webp', 'reader-test', () => strength)
assert.deepEqual({ ...(await crop.read()) }, { left: .1, top: .2, right: .3, bottom: .4 })
strength = 'conservative'
await crop.read()
assert.equal(calls.length, 2)
assert.equal(calls[0].strength, 'strong')
assert.equal(calls[1].strength, 'conservative')
assert.equal(calls[0].filePath, '/cache/page.webp')

const page = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabPage.ets'), 'utf8')
assert.match(page, /private cropStrength\(\): string[\s\S]*?ReadMode\.VERTICAL[\s\S]*?cropStrengthContinuous[\s\S]*?cropStrengthPaged/)
assert.match(page, /new ReaderCropPolicy\([\s\S]*?this\.cropSourceRevision\(\)\)/)
assert.match(page, /new NextEReaderLabAdapter\([\s\S]*?\(\): string => this\.cropStrength\(\)\)/)
assert.match(page, /new NextEReaderSuperResolutionProvider\([\s\S]*?\(\): string => this\.cropStrength\(\)(?:\)|,)/)
assert.match(page, /new NextEReaderTranslationProvider\([\s\S]*?\(\): string => this\.cropStrength\(\)(?:\)|,)/)

for (const file of [
  'NextEReaderLabAdapter.ets',
  'NextEReaderSuperResolutionProvider.ets',
  'NextEReaderTranslationProvider.ets',
]) {
  const text = fs.readFileSync(path.join(root, 'feature/reader/src/main/ets/lab', file), 'utf8')
  assert.match(text, /new NextEReaderCropSource\(/)
  assert.doesNotMatch(text, /ReaderPageCropService\.detect\(/)
}

console.log('NextE shared-reader crop strength bridge passed')

// Warm and displayed asset instances reuse crop work by content, while a reused
// file path with different bytes and a new strength each require a fresh result.
let bytes = Buffer.from('first image bytes')
let handles = 0
let cropExecutions = 0
const offsets = new Map()
class Bounds {
  constructor(left = 0, top = 0, right = 0, bottom = 0) { Object.assign(this, { left, top, right, bottom }) }
  static none() { return new Bounds() }
  static parse(text) { const v = JSON.parse(text); return new Bounds(v.left, v.top, v.right, v.bottom) }
}
const cropService = {}
const serviceContext = { exports: cropService, require: name => {
  if (name === '@kit.ArkTS') return { taskpool: { async execute(fn, ...args) {
    if (fn.name === 'hashReaderPageCropFile') return fn(...args)
    cropExecutions++
    return JSON.stringify({ left: .1, top: .2, right: .3, bottom: .4 })
  } } }
  if (name === '@kit.ImageKit') return {}
  if (name === '@kit.CoreFileKit') return { fileIo: {
    OpenMode: { READ_ONLY: 0 },
    openSync() { const fd = ++handles; offsets.set(fd, 0); return { fd } },
    readSync(fd, buffer) {
      const offset = offsets.get(fd); const part = bytes.subarray(offset, offset + buffer.byteLength)
      new Uint8Array(buffer).set(part); offsets.set(fd, offset + part.length); return part.length
    },
    closeSync(file) { offsets.delete(file.fd) },
  } }
  if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd() {
    const digest = createHash('sha256')
    return { updateSync(value) { digest.update(value.data) }, digestSync() { return { data: digest.digest() } } }
  } } }
  if (name === '../model/ReaderPageCropBounds') return { ReaderPageCropBounds: Bounds,
    ReaderPageCropDetector: { normalizeStrength: value => value }, ReaderPageCropStrength: { STANDARD: 'standard' } }
  throw new Error(`unexpected import ${name}`)
} }
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,
  'shared/src/main/ets/services/ReaderPageCropService.ets'), 'utf8').replace(/^@Concurrent\r?\n/gm, ''), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText, serviceContext)
await cropService.ReaderPageCropService.detectFile('/same-path.webp', 'standard')
await cropService.ReaderPageCropService.detectFile('/same-path.webp', 'standard')
assert.equal(cropExecutions, 1, 'a displayed asset reuses the warmed bounds')
bytes = Buffer.from('other image bytes')
await cropService.ReaderPageCropService.detectFile('/same-path.webp', 'standard')
assert.equal(cropExecutions, 2, 'changed bytes cannot reuse stale geometry')
await cropService.ReaderPageCropService.detectFile('/same-path.webp', 'strong')
assert.equal(cropExecutions, 3)
assert.equal(offsets.size, 0, 'all identity readers close their file handles')
console.log('NextE content-addressed crop preprocessing runtime passed')
