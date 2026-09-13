import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const core = require(path.join(root, 'third_party/reader-kit/tests/load-core.cjs'))('ReaderDisplayMap')
const enums = {
  ReadMode: { LTR: 'ltr', RTL: 'rtl', TOP_TO_BOTTOM: 'topToBottom', VERTICAL: 'vertical' },
  ReadColumnMode: { ODD_LEFT: 'oddLeft', EVEN_LEFT: 'evenLeft' },
  ReadSpreadLayout: { JOINED: 'joined', SPLIT: 'split' },
}

function compile(source, deps) {
  const out = {}
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, { exports: out, require: name => {
    assert.ok(name in deps, name)
    return deps[name]
  } })
  return out
}

let state, events
const settings = {
  setMode: async (_context, value) => { state.mode = value; events.push(`mode:${value}`) },
  setDoublePageEnabled: async (_context, value) => { state.doublePageEnabled = value; events.push(`double:${value}`) },
  setSpreadLayoutMode: async (_context, value) => { state.spreadLayoutMode = value; events.push(`spread:${value}`) },
  setCropBordersPaged: async (_context, value) => { state.cropBordersPaged = value; events.push(`crop-paged:${value}`) },
  setCropBordersContinuous: async (_context, value) => { state.cropBordersContinuous = value; events.push(`crop-continuous:${value}`) },
}
const progress = {
  setColumnMode: (_context, gid, value) => { assert.equal(gid, '123'); events.push(`column:${value}`) },
}
const source = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderRuntimePreferences.ets'), 'utf8')
const Runtime = compile(source, {
  '@kit.AbilityKit': {}, '@reader-kit/core': core,
  shared: { ...enums, connectReadMode: () => state, ReadModeSettings: settings,
    GalleryReadProgressSettings: progress },
}).NextEReaderRuntimePreferences

function reset(extra = {}) {
  state = { mode: 'rtl', doublePageEnabled: true, spreadLayoutMode: 'joined',
    cropBordersPaged: false, cropBordersContinuous: true, ...extra }
  events = []
}
function policy(extra = {}) { return Object.assign(new core.ReaderDisplayPolicy(), extra) }

reset()
await Runtime.applyLayout({}, policy({ layout: 'single', pagingAxis: 'vertical', direction: 'ltr' }))
assert.equal(state.mode, 'topToBottom')
assert.equal(state.doublePageEnabled, true)
assert.deepEqual(events, ['mode:topToBottom'])

reset()
await Runtime.applyLayout({}, policy({ layout: 'continuous', direction: 'ltr' }))
assert.equal(state.mode, 'vertical')
assert.equal(state.doublePageEnabled, true)
assert.deepEqual(events, ['mode:vertical'])

reset()
await Runtime.applyLayout({}, policy({ layout: 'single', pagingAxis: 'horizontal', direction: 'ltr' }))
assert.deepEqual([state.mode, state.doublePageEnabled], ['ltr', false])
assert.deepEqual(events, ['mode:ltr', 'double:false'])

reset({ mode: 'ltr', doublePageEnabled: false })
await Runtime.applyLayout({}, policy({ layout: 'spread', direction: 'rtl' }))
assert.deepEqual([state.mode, state.doublePageEnabled], ['rtl', true])
assert.deepEqual(events, ['mode:rtl', 'double:true'])

reset({ mode: 'ltr', doublePageEnabled: true })
await Runtime.applyDirection({}, policy({ layout: 'spread', direction: 'rtl' }))
assert.equal(state.mode, 'rtl')
assert.equal(state.doublePageEnabled, true)
assert.deepEqual(events, ['mode:rtl'])

reset({ mode: 'vertical' })
await Runtime.applyDirection({}, policy({ layout: 'continuous', direction: 'rtl' }))
assert.deepEqual(events, [])
assert.equal(state.mode, 'vertical')

reset({ mode: 'topToBottom' })
await Runtime.applyDirection({}, policy({ layout: 'single', pagingAxis: 'vertical', direction: 'rtl' }))
assert.deepEqual(events, [])
assert.equal(state.mode, 'topToBottom')

reset()
await Runtime.applySpreadLayout({}, policy({ spreadLayout: 'split' }))
assert.equal(state.spreadLayoutMode, 'split')
assert.deepEqual(events, ['spread:split'])

reset()
Runtime.applyFirstPageAlone({}, '123', policy({ firstPageAlone: true }))
assert.deepEqual(events, ['column:evenLeft'])

reset()
await Runtime.applyCrop({}, policy({ layout: 'single' }), true)
assert.equal(state.cropBordersPaged, true)
assert.deepEqual(events, ['crop-paged:true'])

reset()
await Runtime.applyCrop({}, policy({ layout: 'continuous' }), false)
assert.equal(state.cropBordersContinuous, false)
assert.deepEqual(events, ['crop-continuous:false'])

const page = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabPage.ets'), 'utf8')
assert.match(page, /request\.progressReadWrite && !this\.request\.pageIndexProvided/)
assert.match(page, /onObservedPosition: \(position: ReaderObservedPosition\)/)
assert.match(page, /request\.preferencesReadWrite/)
assert.match(page, /onPolicyChanged: \(policy: ReaderDisplayPolicy, intent: ReaderRuntimePolicyIntent\)/)
assert.match(page, /onCropChanged: \(enabled: boolean, policy: ReaderDisplayPolicy\)/)
assert.match(page, /pageTurnAnimation: this\.request\.pageTurnAnimationOverride \?\? this\.readMode\.pageTurnAnimation/)
assert.match(page, /hostSettingsAvailable: this\.request\.preferencesReadWrite/)
assert.match(page, /onHostSettings: \(\): void => \{ this\.openHostSettings\(\) \}/)
assert.match(page, /active: this\.routeActive && this\.labVisibility\.foreground && !this\.readerSettingsSheetShown/)
assert.match(page, /\.bindSheet\([\s\S]*\$\$this\.readerSettingsSheetShown[\s\S]*this\.settingsSheetContent/)

const index = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8')
assert.equal((index.match(/settingsSheetContent: \(dismiss: \(\) => void\) =>/g) ?? []).length >= 3, true)

console.log('PASS NextE shared reader progress, preference, animation, and settings host bridges')
