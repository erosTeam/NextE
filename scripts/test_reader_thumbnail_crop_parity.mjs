import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const pageSource = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabPage.ets'), 'utf8')
const tree = ts.createSourceFile('NextEReaderLabPage.ets',
  pageSource.replace('export struct NextEReaderLabPage', 'export class NextEReaderLabPage'),
  ts.ScriptTarget.Latest, true)
const cls = tree.statements.find(value => ts.isClassDeclaration(value) && value.name?.text === 'NextEReaderLabPage')
assert.ok(cls)
const cropMethod = cls.members.find(value => value.name?.getText(tree) === 'initialCropBorders')
assert.ok(cropMethod)

const output = ts.transpileModule(`export class Host { ${cropMethod.getText(tree)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText
const exports = {}
vm.runInNewContext(output, { exports, require, ReadMode: { VERTICAL: 'vertical' } })

for (const [request, labRequest, readMode, expected] of [
  [{ preferencesReadWrite: true }, { cropBorders: true },
    { mode: 'vertical', cropBordersContinuous: true, cropBordersPaged: true }, true],
  [{ preferencesReadWrite: true }, { cropBorders: false },
    { mode: 'paged_rtl', cropBordersContinuous: false, cropBordersPaged: true }, true],
  [{ preferencesReadWrite: false }, { cropBorders: false },
    { mode: 'paged_rtl', cropBordersContinuous: false, cropBordersPaged: true }, false],
]) {
  const host = new exports.Host()
  Object.assign(host, { request, labRequest, readMode })
  assert.equal(host.initialCropBorders(), expected)
}

assert.match(pageSource,
  /new ReaderCropPolicy\([\s\S]*?this\.request\.preferencesReadWrite \|\| this\.labRequest\?\.cropBorders === true/,
  'thumbnail entry must not disable the host crop control')

console.log('NextE shared-reader thumbnail crop parity passed')
