import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function compile(source, dependencies = {}, globals = {}) {
  const exports = {}
  const output = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020,
    experimentalDecorators: true,
  } }).outputText
  vm.runInNewContext(output, {
    exports,
    require(name) {
      assert.ok(name in dependencies, name)
      return dependencies[name]
    },
    ...globals,
  })
  return exports
}

// Execute the actual route owner. Native Navigation is the host boundary;
// these checks prove cancellation state only, not animation or device acceptance.
let selected = 'shared'
const routes = compile(fs.readFileSync(path.join(root,
  'shared/src/main/ets/state/ReaderOverlayNavigationState.ets'), 'utf8'), {
  '@kit.ArkUI': { AppStorageV2: { connect: (_type, _key, create) => create() } },
  '../model/RouteParams': {},
  './NextEReaderBackendSelectionState': {
    NextEReaderBackend: { SHARED: 'shared', LEGACY: 'legacy' },
    resolveNextEReaderBackendSelection: () => selected,
  },
  './ReaderThumbnailTransitionState': { connectReaderThumbnailTransition: () => ({ reset() {} }) },
}, { ObservedV2: value => value, Trace() {}, NavPathStack: class {
  paths = []
  clear() { this.paths = [] }
  pushPathByName(name, value) { this.paths.push([name, value]) }
  getAllPathName() { return this.paths.map(value => value[0]) }
  pop() { this.paths.pop() }
} }).ReaderOverlayNavigationState

for (const backend of ['shared', 'legacy']) {
  selected = backend
  const navigation = new routes()
  navigation.open({ gid: 'safe', index: 2 }, false)
  assert.equal(navigation.cancelPendingReader(), true)
  assert.equal(navigation.visible, false)
  navigation.presentPendingReader() // Delayed onAppear of the retired root.
  assert.equal(navigation.stack.paths.length, 0)
  navigation.open({ gid: 'safe', index: 2 }, false)
  navigation.presentPendingReader()
  assert.equal(navigation.stack.paths[1][0], backend === 'shared' ? 'ReaderShared' : 'Reader')
  assert.equal(navigation.cancelPendingReader(), false)
  assert.equal(navigation.visible, true)
  navigation.close(false)
  navigation.finishClose()
  assert.equal(navigation.visible, false)
}
console.log('PASS pending Reader cancellation and active route preservation')
