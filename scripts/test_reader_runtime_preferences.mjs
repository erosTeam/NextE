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

for (const doublePageEnabled of [true, false]) {
  reset({ mode: 'ltr', doublePageEnabled, spreadLayoutMode: 'split' })
  const retained = { ...state }
  for (const [choice, expectedMode] of [
    [{ layout: 'single', direction: 'rtl' }, 'rtl'],
    [{ layout: 'single', pagingAxis: 'vertical' }, 'topToBottom'],
    [{ layout: 'continuous' }, 'vertical'],
    [{ layout: 'single', direction: 'ltr' }, 'ltr'],
  ]) {
    events = []
    await Runtime.applyReadingMode({}, policy(choice))
    assert.deepEqual(state, { ...retained, mode: expectedMode })
    assert.deepEqual(events, [`mode:${expectedMode}`])
    events = []
    await Runtime.applyReadingMode({}, policy(choice))
    assert.deepEqual(events, [])
  }
}

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
assert.match(page, /observation: new ReaderObservationSink\(null,[\s\S]*position: ReaderObservedPosition/)
assert.match(page, /request\.preferencesReadWrite/)
assert.match(page, /preferenceSink: new ReaderPreferenceSink\([\s\S]*policy: ReaderDisplayPolicy,[\s\S]*intent: ReaderRuntimePolicyIntent/)
assert.match(page, /enabled: boolean, policy: ReaderDisplayPolicy[\s\S]*this\.persistCrop\(enabled, policy\)/)
assert.match(page, /pageTurnAnimation: this\.labRequest\?\.pageTurnAnimationOverride \?\? this\.readMode\.pageTurnAnimation/)
assert.match(page, /hostSettings: this\.request\.preferencesReadWrite[\s\S]*new ReaderHostSettings/)
assert.match(page, /this\.openHostSettings\(\)/)
assert.match(page, /active: this\.routeActive && this\.labVisibility\.foreground && !this\.readerSettingsSheetShown/)
assert.match(page, /\.bindSheet\([\s\S]*\$\$this\.readerSettingsSheetShown[\s\S]*this\.settingsSheetContent/)

const index = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8')
assert.equal((index.match(/settingsSheetContent: \(dismiss: \(\) => void\) =>/g) ?? []).length >= 3, true)

console.log('PASS NextE shared reader progress, preference, animation, and settings host bridges')

// Run the real host observation and lifecycle methods; no scroll or UI-shape assertion stands in for a trace.
const hostAst = ts.createSourceFile('host.ts', page.replace(/\bstruct /g, 'class '), ts.ScriptTarget.Latest, true)
const hostOwner = hostAst.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'NextEReaderLabPage')
const hostMethod = name => hostOwner.members.find(node => node.name?.text === name).getText(hostAst)
const { ReaderUnitKey } = require(path.join(root, 'third_party/reader-kit/tests/load-core.cjs'))('ReaderSession')
function observationHost() {
  const writes = [], ready = [], geometry = [], flushed = []
  class Empty { close() {} }
  const exported = {}
  vm.runInNewContext(ts.transpileModule(`export class Host { ${[
    'resetObservedSessionTracking', 'observeReaderPosition', 'persistObserved', 'aboutToAppear', 'aboutToDisappear',
  ].map(hostMethod).join('\n')} }`, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, {
    exports: exported, ReaderUnitKey,
    ReaderKeepScreenOn: Empty, NextEReaderLabAdapter: Empty, ReaderSystemImageSaveHost: Empty,
    ReaderMediaActions: Empty, NextEReaderImageBlockProvider: Empty, NextEReaderSuperResolutionProvider: Empty,
    NextEReaderTranslationProvider: Empty, NextEReaderSourcePreloadHost: Empty, ReaderPagedSession: Empty,
    connectNextEReaderTranslationProbe: () => ({ bindAction() {} }),
    readerSuperResolutionSetInteractionPaused() {}, clearTimeout() {},
    ReaderThumbnailTransitionCoordinator: { notifyReaderImageReady: (_context, work, page) => ready.push([work, page]) },
    GalleryReadProgressSettings: {
      setIndex: (_context, work, index) => writes.push([work, index]),
      flush: () => flushed.push(true),
    },
    console,
  })
  const host = new exported.Host()
  Object.assign(host, {
    request: { work: '123', unit: '123', productionSources: true, readingChrome: true, progressReadWrite: true },
    labRequest: null, entrySite: 'eh', unitKey: new ReaderUnitKey('eh', '123', '123'),
    rootOwnedEntryTarget: false, entryTransition: null, rootEntryHandoff: { reset() {} },
    routeActive: true, labVisibility: { foreground: true }, closeRequested: false, hostClosing: false,
    currentSourceIndex: -1, translationAutoEnabled: false, translationPreferenceRevision: 0,
    normalEntryGeometryLogged: false, persistedObservedUnit: null, persistedObservedSourceIndex: -1,
    managesTrialWindow: false, enhancementInteractionTimer: -1, volumeKeys: { close() {} },
    getUIContext: () => ({ getHostContext: () => ({ applicationInfo: { debug: false } }) }),
    logNormalEntryGeometry: stage => geometry.push(stage), initializeSession() {}, clearSystemEntryWindowPresentation() {},
  })
  const position = (index, work = '123', y = 0) => ({ anchor: {
    unit: new ReaderUnitKey('eh', work, work), sourceIndexHint: index, y,
  } })
  return { host, writes, ready, geometry, flushed, position }
}
{
  const f = observationHost()
  f.host.aboutToAppear()
  for (const y of [0, 0.1, 0.2, 0.8]) f.host.observeReaderPosition(f.position(2, '123', y))
  assert.deepEqual(f.geometry, ['content-ready'])
  assert.deepEqual(f.writes, [['123', 2]], 'first accepted page persists; fractional movement does not rewrite it')
  assert.equal(f.ready.length, 4, 'the real image-ready handoff still receives every observation')
  f.host.observeReaderPosition(f.position(3))
  f.host.observeReaderPosition(f.position(2))
  assert.deepEqual(f.writes, [['123', 2], ['123', 3], ['123', 2]], 'a real return to a prior page persists immediately')
  f.host.aboutToDisappear()
  assert.equal(f.flushed.length, 1, 'exit still drains the durable writer')
  f.host.aboutToAppear()
  f.host.observeReaderPosition(f.position(2))
  assert.equal(f.geometry.length, 2, 'a later entry captures its own first geometry')
  assert.equal(f.writes.length, 4, 're-entry persists its first observation even at the same page')
}
{
  const f = observationHost()
  f.host.labVisibility.foreground = false
  f.host.persistObserved(f.position(0))
  f.host.labVisibility.foreground = true
  f.host.persistObserved(f.position(0))
  assert.deepEqual(f.writes, [['123', 0]], 'a rejected publication does not consume first-observation persistence')
  f.host.persistObserved(f.position(0, 'other'))
  assert.equal(f.writes.length, 1, 'a foreign work cannot persist into the current work')
  f.host.request.work = 'other'; f.host.unitKey = new ReaderUnitKey('eh', 'other', 'other')
  f.host.persistObserved(f.position(0, 'other'))
  assert.deepEqual(f.writes, [['123', 0], ['other', 0]], 'session unit identity participates in deduplication')
}
console.log('PASS NextE real observation cadence, entry geometry, page persistence, exit flush and re-entry reset')
