import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { test } from 'node:test'
import vm from 'node:vm'
const drainClose = () => new Promise(resolve => setImmediate(resolve))
function chromeHost() {
  const v = setup({ deferRestore: true })
  v.launch()
  return v
}
test('chrome preparation waits for window then live layout readiness', async () => {
  const v = chromeHost(); let completed = false
  const ready = v.host.prepareReaderTrialChrome(() => true).then(value => { completed = true; return value })
  assert.equal(v.host.testPreparations.length, 1); assert.equal(v.layouts.length, 0)
  v.host.testPreparations[0].resolve(true); await drainClose()
  assert.equal(completed, false); assert.equal(v.layouts.length, 1)
  assert.equal(v.layouts[0].measure(), '')
  v.host.layoutSafeArea.topAvoidHeight = 24
  assert.equal(v.layouts[0].measure(), '24:0')
  assert.equal(v.layouts[0].current(), true)
  v.layouts[0].resolve(true); assert.equal(await ready, true)
})
test('window preparation false does not schedule layout or report readiness', async () => {
  const v = chromeHost()
  const ready = v.host.prepareReaderTrialChrome(() => true)
  v.host.testPreparations[0].resolve(false)
  assert.equal(await ready, false); assert.equal(v.layouts.length, 0)
})
test('stale lease, request, epoch or caller cancels before layout scheduling', async () => {
  for (const changed of ['lease', 'request', 'epoch', 'caller']) {
    const v = chromeHost(); let current = true
    const ready = v.host.prepareReaderTrialChrome(() => current)
    if (changed === 'lease') v.host.readerTrialWindow = {}
    if (changed === 'request') v.host.readerTrialRequest = {}
    if (changed === 'epoch') v.host.readerTrialEpoch++
    if (changed === 'caller') current = false
    v.host.testPreparations[0].resolve(true)
    assert.equal(await ready, false, changed); assert.equal(v.layouts.length, 0)
  }
})
test('closing synchronously cancels chrome preparation before Surface Param propagation', async () => {
  const v = chromeHost(); const lease = v.host.readerTrialWindow
  assert.equal(v.host.readerTrialCloseRequested, false)
  const ready = v.host.prepareReaderTrialChrome(() => true)
  const close = v.host.closeReaderTrial()
  assert.equal(v.host.readerTrialCloseRequested, true)
  v.host.testPreparations[0].resolve(true)
  assert.equal(await ready, false); assert.equal(v.layouts.length, 0)
  lease.restore(); await close
  v.launch()
  assert.equal(v.host.readerTrialCloseRequested, false)
})
test('layout scheduler sees lease/request/epoch/close invalidation while pending', async () => {
  for (const changed of ['lease', 'request', 'epoch', 'close']) {
    const v = chromeHost()
    const ready = v.host.prepareReaderTrialChrome(() => true)
    v.host.testPreparations[0].resolve(true); await drainClose()
    if (changed === 'lease') v.host.readerTrialWindow = {}
    if (changed === 'request') v.host.readerTrialRequest = {}
    if (changed === 'epoch') v.host.readerTrialEpoch++
    if (changed === 'close') v.host.readerTrialCloseRequested = true
    assert.equal(v.layouts[0].current(), false, changed)
    v.layouts[0].resolve(false); assert.equal(await ready, false)
  }
})

test('ready close waits for actual host layout promise and duplicate close shares it', async () => {
  const v = setup({ readiness: 'ready', deferRestore: true })
  v.launch()
  const request = v.host.readerTrialRequest, clears = v.host.readerTrialStack.clears
  const lease = v.host.readerTrialWindow
  const close = v.host.closeReaderTrial()
  assert.equal(v.host.closeReaderTrial(), close)
  await drainClose()
  assert.notEqual(lease.colorsStarted, true)
  assert.equal(v.layouts.length, 1)
  assert.equal(v.layouts[0].current(), true)
  assert.equal(v.host.readerTrialRequest, request)
  assert.equal(v.host.readerTrialStack.clears, clears)
  assert.equal(v.host.closeReaderTrial(), close)
  v.layouts[0].resolve(true); await drainClose()
  assert.equal(lease.callbackResult, true)
  assert.equal(lease.colorsStarted, true); assert.notEqual(lease.colorsCompleted, true)
  assert.equal(v.host.readerTrialRequest, request)
  assert.equal(v.host.readerTrialStack.clears, clears)
  v.windows[0].restore(); await close
  assert.equal(lease.colorsCompleted, true)
  assert.equal(v.host.readerTrialRequest, null)
  assert.equal(v.host.readerTrialStack.clears, clears + 1)
  assert.ok(v.logs.includes('[ReaderTrialHost] close_layout_ready=true'))
})

test('destroy or replace while layout is pending rejects late clear', async () => {
  for (const action of ['destroy', 'replace']) {
    const v = setup({ readiness: 'ready', deferRestore: true })
    v.launch()
    const lease = v.host.readerTrialWindow
    const close = v.host.closeReaderTrial()
    await drainClose()
    const clears = v.host.readerTrialStack.clears
    if (action === 'destroy') v.host.aboutToDisappear()
    else { v.host.readerTrialRequest = { work: 'replacement' }; v.host.readerTrialEpoch++ }
    const retained = v.host.readerTrialRequest
    assert.equal(v.layouts[0].current(), false)
    v.layouts[0].resolve(false); await drainClose()
    assert.equal(lease.callbackResult, false)
    assert.equal(lease.colorsStarted, true); assert.notEqual(lease.colorsCompleted, true)
    assert.equal(v.host.readerTrialRequest, retained)
    v.windows[0].restore(); await close
    assert.equal(lease.colorsCompleted, true)
    assert.equal(v.host.readerTrialRequest, retained)
    assert.equal(v.host.readerTrialStack.clears, clears)
    assert.equal(v.logs.includes('[ReaderTrialHost] close_layout_ready=true'), false)
  }
})

test('failed and not-required restoration never report layout readiness', async () => {
  for (const readiness of ['failed', 'not-required', 'already-visible']) {
    const v = setup({ readiness, deferRestore: true })
    v.launch()
    const close = v.host.closeReaderTrial()
    v.windows[0].restore(); await close
    assert.equal(v.layouts.length, 0)
    assert.equal(v.logs.some(message => message.includes('close_layout_ready=')), false)
    assert.equal(v.host.readerTrialRequest, null)
  }
})

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js')
const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8')
function section(start, end) {
  const first = source.indexOf(start)
  const last = source.indexOf(end, first + start.length)
  assert.ok(first >= 0 && last > first)
  return source.slice(first, last)
}
function method(name) {
  const start = source.indexOf(`  ${name}(): void {`)
  let depth = 0
  const body = source.indexOf('{', start)
  for (let i = body; i < source.length; i++) {
    if (source[i] === '{') depth++
    if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1)
  }
  throw new Error(name)
}
const realHost = section('struct Index {', '\n  @Builder')
  .replace('struct Index {', 'export class Index {') +
  section("  @Monitor('readerLabLaunch.version')", '\n  @Local navStackHolder:') +
  method('aboutToDisappear') + '\n}'
const compiled = ts.transpileModule(realHost.replace(/@Local\s+/g, '')
  .replace(/@Monitor\([\s\S]*?\)\s*/g, ''), {
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  })
assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0)

function setup({ readiness = 'not-required' } = {}) {
  const layouts = [], logs = [], preparations = []
  const visibility = { foreground: true }
  const site = { isEx: false }
  let restricted = false
  let next = null
  const windows = []
  const installs = []
  const releases = []
  class NavPathStack {
    clears = 0
    routes = []
    clear() { this.clears++ }
    pushPathByName(name, params) { this.routes.push({ name, params }) }
  }
  class ReaderTrialWindow {
    prepareStatusBarVisible() {
      return new Promise(resolve => preparations.push({ lease: this, resolve }))
    }
    getCloseSystemAvoidAreaResult() { return readiness }
    constructor() { windows.push(this); this.opens = 0; this.closes = 0 }
    open() { this.opens++ }
    close(beforeRestoreColors = null) {
      this.closes++
      if (!this.closing) {
        const colors = new Promise(resolve => { this.restore = resolve })
        // Schedule the host callback after area readiness, before deferred colors.
        this.closing = Promise.resolve().then(async () => {
          if ((readiness === 'ready' || readiness === 'already-visible') && beforeRestoreColors !== null) {
            this.callbackResult = await beforeRestoreColors()
          }
          this.colorsStarted = true
          await colors
          this.colorsCompleted = true
        })
      }
      return this.closing
    }
  }
  const relay = {
    clear() {}, releasePending(token) { releases.push(token) },
    install(site, work, callback) { installs.push({ site, work, callback }); return installs.length },
  }
  const exports = {}
  vm.runInNewContext(compiled.outputText, {
    exports, NavPathStack, ReaderTrialWindow,
    console: { info: message => logs.push(message) },
    ReaderTrialLayoutCommit: { wait(context, measure, current) {
      return new Promise(resolve => layouts.push({ measure, current, resolve }))
    } },
    ReaderTrialEntryRelay: relay,
    ReaderTrialEntryProbe: { close() {}, phase() {}, hostRemoved() {}, windowEvent() {} },
    connectReaderLabLaunch: () => ({ consume() { const value = next; next = null; return value } }),
    connectReaderLabVisibility: () => visibility,
    connectSiteMode: () => site,
    GalleryDetailParams: class { constructor(work, unit) { this.work = work; this.unit = unit } },
    setDownloadQueuePageActive() {},
  })
  const host = new exports.Index()
  host.layoutSafeArea = { topAvoidHeight: 0, bottomAvoidHeight: 0 }
  host.testPreparations = preparations
  host.safeMode = { restricted: () => restricted }
  host.readerOverlay = { visible: false }
  host.securitySettings = { locked: false }
  host.navStackHolder = { navigationRevision: 0 }
  host.stack = new NavPathStack()
  host.ctx = () => ({ applicationInfo: { debug: true } })
  host.getUIContext = () => ({})
  host.clearHomeTabAnimationGuardTimer = () => {}
  function launch(overrides = {}) {
    const request = { readingChrome: true, thumbnailEntry: false, work: 'work', unit: 'unit', ...overrides }
    next = request
    host.handleReaderLabLaunch()
    // The real NavDestination reports onShown after the launch request has mounted. Mirror that
    // lifecycle edge so window-open and close/restore assertions exercise a visible trial.
    if (request.readingChrome && !request.thumbnailEntry && host.readerTrialRequest === request) {
      host.readerTrialDestinationShown = true
      host.syncReaderTrialWindow()
    }
    return request
  }
  return { host, visibility, site, windows, installs, releases, launch, layouts, logs,
    restrict: () => { restricted = true } }
}

test('visible close retains the exact reader until restore, duplicates reuse and cannot reopen', async () => {
  const v = setup(); const request = v.launch()
  let cancelled = 0; let released = 0
  const entry = { phase: 'moving', cancel() { cancelled++ } }
  const preview = { release() { released++ } }
  v.host.readerEntryTransition = entry; v.host.readerEntryPreview = preview
  const entryEpoch = v.host.readerEntryEpoch
  const claim = { epoch: entryEpoch, source: { snapshotComponentId: 'source' } }
  v.host.readerEntryClaim = claim; v.host.readerTrialEntryGuardToken = 17
  const clears = v.host.readerTrialStack.clears
  const close = v.host.closeReaderTrial()
  assert.equal(v.host.closeReaderTrial(), close)
  assert.equal(v.host.readerTrialRequest, request)
  assert.equal(v.host.readerEntryTransition, entry)
  assert.equal(v.host.readerEntryPreview, preview)
  assert.equal(v.host.readerTrialStack.clears, clears)
  assert.equal(cancelled, 0); assert.equal(released, 0)
  assert.equal(v.host.readerTrialWindow, null)
  assert.equal(v.host.readerEntryEpoch, entryEpoch + 1)
  assert.equal(v.host.readerEntryClaim, null)
  assert.equal(v.host.readerTrialEntryGuardToken, 0)
  assert.ok(v.releases.includes(17))
  assert.equal(v.host.authorizeReaderEntryDeparture(claim, entryEpoch), false)
  v.host.syncReaderTrialWindow()
  assert.equal(v.windows[0].opens, 1); assert.equal(v.windows[0].closes, 1)
  v.windows[0].restore(); await close
  assert.equal(v.host.readerTrialRequest, null)
  assert.equal(cancelled, 1); assert.equal(released, 1)
  assert.equal(v.host.readerTrialClosing, null)
})

test('hidden layout clears request synchronously before cancel and never opens colors', () => {
  const v = setup(); v.visibility.foreground = false
  v.launch()
  let cancelled = 0
  v.host.readerEntryTransition = { phase: 'layout', cancel() {
    assert.equal(v.host.readerTrialRequest, null); cancelled++
  } }
  assert.equal(v.host.closeReaderTrial(), null)
  assert.equal(cancelled, 1); assert.equal(v.windows[0].opens, 0)
  assert.equal(v.host.readerEntryTransition, null)
  v.windows[0].restore()
})

test('new Wants wait for restore and only the newest request is presented', async () => {
  const v = setup(); const original = v.launch()
  v.launch({ work: 'superseded' })
  const close = v.host.readerTrialClosing
  const latest = v.launch({ work: 'latest' })
  assert.equal(v.host.readerTrialRequest, original); assert.equal(v.windows.length, 1)
  v.windows[0].restore(); await close
  assert.equal(v.host.readerTrialRequest, latest); assert.equal(v.windows.length, 2)
  v.host.readerTrialDestinationShown = true; v.host.syncReaderTrialWindow()
  assert.equal(v.windows[1].opens, 1)
})

test('queued launches reject changed foreground, site, safe mode, lock or production overlay', async () => {
  for (const invalid of ['background', 'site', 'safe', 'locked', 'overlay']) {
    const v = setup(); v.launch(); v.launch({ work: 'next' })
    const close = v.host.readerTrialClosing
    if (invalid === 'background') v.visibility.foreground = false
    if (invalid === 'site') v.site.isEx = true
    if (invalid === 'safe') v.restrict()
    if (invalid === 'locked') v.host.securitySettings.locked = true
    if (invalid === 'overlay') v.host.readerOverlay.visible = true
    v.windows[0].restore(); await close
    assert.equal(v.host.readerTrialRequest, null, invalid)
    assert.equal(v.windows.length, 1, invalid)
  }
})

test('initial foreground=false Want is retained and opens only after foreground arrives', () => {
  const v = setup(); v.visibility.foreground = false
  const request = v.launch()
  assert.equal(v.host.readerTrialRequest, request)
  assert.equal(v.windows[0].opens, 0)
  v.visibility.foreground = true; v.host.syncReaderTrialWindow()
  assert.equal(v.windows[0].opens, 1)
  const thumb = setup(); thumb.visibility.foreground = false
  thumb.launch({ thumbnailEntry: true })
  assert.equal(thumb.installs.length, 1)
  assert.equal(thumb.host.stack.routes[0].name, 'GalleryDetail')
})

test('destruction invalidates late clear and queued launch without mutating the retired tree', async () => {
  const v = setup(); const original = v.launch(); v.launch({ work: 'next' })
  const close = v.host.readerTrialClosing
  const clears = v.host.readerTrialStack.clears
  v.host.aboutToDisappear()
  assert.equal(v.host.readerTrialHostAlive, false)
  v.windows[0].restore(); await close
  assert.equal(v.host.readerTrialRequest, original)
  assert.equal(v.host.readerTrialStack.clears, clears)
  assert.equal(v.windows.length, 1)
})

test('settled old request cannot clear replacement identity', async () => {
  const v = setup(); v.launch(); const close = v.host.closeReaderTrial()
  const replacement = { work: 'replacement' }
  v.host.readerTrialRequest = replacement; v.host.readerTrialEpoch++
  v.windows[0].restore(); await close
  assert.equal(v.host.readerTrialRequest, replacement)
})

test('thumbnail relay is armed only after restore and its captured launch/site fences stay live', async () => {
  const v = setup(); v.launch(); v.launch({ thumbnailEntry: true })
  const close = v.host.readerTrialClosing
  assert.equal(v.installs.length, 0)
  v.windows[0].restore(); await close
  assert.equal(v.installs.length, 1)
  const callback = v.installs[0].callback
  v.site.isEx = true
  assert.equal(callback({}), false)
  v.site.isEx = false; v.visibility.foreground = false
  assert.equal(callback({}), false)
  v.visibility.foreground = true; v.host.readerTrialLaunchEpoch++
  assert.equal(callback({}), false)
})

test('E still closes a visible trial on background through the existing environment method', async () => {
  const v = setup(); const request = v.launch()
  v.visibility.foreground = false; v.host.onReaderEntryEnvironment()
  const close = v.host.readerTrialClosing
  assert.ok(close); assert.equal(v.host.readerTrialRequest, request)
  v.windows[0].restore(); await close
  assert.equal(v.host.readerTrialRequest, null)
})
