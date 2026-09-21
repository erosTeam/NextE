
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require(process.env.READER_KIT_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = p => fs.readFileSync(path.join(root, p), 'utf8')

function loadVisibility() {
  const out = {}
  const state = { foreground: false }
  const sandbox = {
    exports: out,
    module: { exports: out },
    require: n => ({ '@kit.ArkUI': { AppStorageV2: { connect: () => state } } })[n],
  }
  vm.runInNewContext(ts.transpileModule(
    read('third_party/reader-kit/reader-ui/src/main/ets/ReaderLabVisibility.ets').replace(
      /^\s*@(?:ObservedV2|Trace)\b.*$/gm, ''), { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    } }).outputText, sandbox)
  return { mod: out, state }
}

test('foreground signal updates unconditionally in release builds (debugBuild=false)', () => {
  const { mod, state } = loadVisibility()
  assert.equal(state.foreground, false, 'starts closed')
  mod.updateReaderLabForeground(true, false)
  assert.equal(state.foreground, true, 'release onForeground must open the reader active gate')
  mod.updateReaderLabForeground(false, false)
  assert.equal(state.foreground, false, 'release onBackground must close the gate again')
})

test('foreground signal still updates in debug builds (debugBuild=true)', () => {
  const { mod, state } = loadVisibility()
  mod.updateReaderLabForeground(true, true)
  assert.equal(state.foreground, true)
})

test('source no longer gates the update behind debugBuild', () => {
  const source = read('third_party/reader-kit/reader-ui/src/main/ets/ReaderLabVisibility.ets')
  assert.ok(!/if\s*\(\s*debugBuild\s*\)/.test(source), 'debugBuild gate must stay removed')
  assert.match(source, /updateReaderLabForeground\(foreground: boolean, _debugBuild: boolean\)/)
})
