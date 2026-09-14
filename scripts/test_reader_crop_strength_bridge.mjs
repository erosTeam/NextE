import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
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
    ReaderPageCropService: { async detect(filePath, identity, strength) {
    calls.push({ filePath, identity, strength })
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
assert.match(calls[0].identity, /^reader-test:/)
assert.equal(calls[1].identity, calls[0].identity)

const page = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabPage.ets'), 'utf8')
assert.match(page, /private cropStrength\(\): string[\s\S]*?ReadMode\.VERTICAL[\s\S]*?cropStrengthContinuous[\s\S]*?cropStrengthPaged/)
assert.match(page, /new ReaderCropPolicy\([\s\S]*?this\.cropSourceRevision\(\)\)/)
assert.match(page, /new NextEReaderLabAdapter\([\s\S]*?\(\): string => this\.cropStrength\(\)\)/)
assert.match(page, /new NextEReaderSuperResolutionProvider\([\s\S]*?\(\): string => this\.cropStrength\(\)\)/)
assert.match(page, /new NextEReaderTranslationProvider\([\s\S]*?\(\): string => this\.cropStrength\(\)\)/)

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
