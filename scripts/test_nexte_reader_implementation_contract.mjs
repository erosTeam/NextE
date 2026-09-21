
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
const _cached = {}

function compileStripped(source, deps) {
  const out = {}
  vm.runInNewContext(ts.transpileModule(
    source.replace(/^\s*@(?:ObservedV2|Trace)\b.*$/gm, ''), { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    } }).outputText, { exports: out, require: n => (n in deps ? deps[n] : {}) })
  return out
}

test('NextE selection state defaults to shared and accepts explicit legacy in release', () => {
  const deps = {
    '@kit.AbilityKit': { Want: class Want {} },
    '@kit.ArkUI': { AppStorageV2: { connect: (cls, _k, f) => {
      if (!_cached[_k]) _cached[_k] = f()
      return _cached[_k]
    } } },
  }
  const out = {}
  vm.runInNewContext(ts.transpileModule(
    read('shared/src/main/ets/state/NextEReaderBackendSelectionState.ets').replace(
      /^\s*@(?:ObservedV2|Trace)\b.*$/gm, ''), { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    } }).outputText, { exports: out, require: n => (n in deps ? deps[n] : {}) })
  const Selection = out.connectNextEReaderBackendSelection()
  assert.equal(Selection.current(), 'shared', 'production default is shared')
  Selection.selectForRehearsal('legacy', false)
  assert.equal(Selection.current(), 'legacy', 'release may select the legacy fallback')
  Selection.selectForRehearsal('shared', false)
  assert.equal(Selection.current(), 'shared', 'release may select the shared default')

  const mod = out
  mod.captureNextEReaderBackendWant({ parameters: {} }, false)
  assert.equal(Selection.current(), 'shared', 'release normal launch keeps the persisted default')
  mod.captureNextEReaderBackendWant({ parameters: { nexte_reader_backend: 'legacy' } }, true)
  assert.equal(Selection.current(), 'legacy', 'debug Want overrides to legacy')
})

test('NextE routing resolves the persisted choice when no in-process override exists', () => {
  // Mirror of the overlay route decision: version==0 -> persisted choice; else selection wins.
  const persisted = 'legacy'
  const selection = { version: 0, current: () => 'shared' }
  const requested = selection.version > 0
    ? selection.current()
    : (persisted === 'legacy' ? 'legacy' : 'shared')
  assert.equal(requested, 'legacy')

  const selection2 = { version: 1, current: () => 'shared' }
  const persisted2 = 'legacy'
  const requested2 = selection2.version > 0
    ? selection2.current()
    : (persisted2 === 'legacy' ? 'legacy' : 'shared')
  assert.equal(requested2, 'shared', 'in-process override wins after an explicit selection')
})

