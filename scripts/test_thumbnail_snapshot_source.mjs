import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import vm from 'node:vm'
import { test } from 'node:test'

const require = createRequire(import.meta.url)
const ts = require(process.env.NEXTE_TYPESCRIPT_PATH ??
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
function load(path, modules = {}, component = '') {
  let source = readFileSync(new URL(`../shared/src/main/ets/${path}.ets`, import.meta.url), 'utf8')
  if (component) {
    // Execute the real component methods; only ArkUI declarative builders are excluded.
    const boundary = source.indexOf(component === 'EhSpriteThumbnail' ? '\n  @Builder' : '\n  build() {')
    source = source.slice(0, boundary).replace(`export struct ${component}`, `export class ${component}`) + '\n}\n'
  }
  const exports = {}
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true },
  }).outputText
  vm.runInNewContext(code, {
    exports, require: name => { assert.ok(name in modules, `undeclared dependency: ${name}`); return modules[name] },
    ComponentV2: value => value, Param() {}, Event() {}, Local() {}, Monitor: () => () => {},
    ImageFit: { Cover: 1 }, getContext: () => undefined, setTimeout, clearTimeout,
  })
  return exports
}
const handles = load('components/EhThumbnailSnapshotSource')
const pipeline = load('services/ImagePipelineTypes')
const native = { createNativeRoot() {}, updateNativeRoot() {}, clearNativeRoot() {}, destroyNativeRoot() {} }
const vendor = {
  ImageKnifeOptionV2: class {}, CacheStrategy: { MEMORY: 1, DEFAULT: 2, NONE: 3 },
  Priority: { HIGH: 1, LOW: 2, MEDIUM: 3 }, DownSamplingStrategy: {}, ContentTransitionType: { IDENTITY: 0 },
  ImageKnife: { getInstance: () => ({ reload() {} }) },
}
const { ImageKnifeProImageAdapter } = load('services/ImageKnifeProImageAdapter', {
  '@ohos.arkui.node': { NodeContent: class {} }, 'libimageknifepro.so': { default: native },
  '@ohos/imageknifepro': vendor,
  '../diagnostics/DiagnosticLogger': { DiagnosticLogger: { info() {}, warn() {}, ownerHash: () => 'redacted' } },
  './ImageKnifeProRuntime': { ImageKnifeProRuntime: { defaultHeaders: () => [] } },
  './ImagePipelineTypes': pipeline, '../components/EhThumbnailSnapshotSource': handles,
}, 'ImageKnifeProImageAdapter')
const { EhSpriteThumbnail } = load('components/EhSpriteThumbnail', {
  '../theme/ThemeConstants': { ThemeConstants: { THUMB_RADIUS: 4 } },
  '../constants/EhConstants': { EhConstants: { cdnThumb: url => url.replace('s.exhentai.org', 'ehgt.org') } },
  './EhImageKnifeImage': { EH_IMAGE_PRIORITY_LOW: 0 }, './EhThumbnailSnapshotSource': handles,
  '../services/ImagePipelineTypes': pipeline,
  '../model/ImageBlockRule': { ImageBlockDecision: class {} },
  '../services/ImageBlockRuntimeService': { ImageBlockRuntimeService: {} },
  '../state/ImageBlockRuntimeState': { connectImageBlockRuntime: () => ({ signal: 0 }) },
  '../state/GalleryDetailTransitionState': { connectGalleryDetailTransition: () => ({ eligible: false }) },
}, 'EhSpriteThumbnail')

const info = (requestId = 'native#1', width = 800, height = 400) => ({ requestId, imageWidth: width, imageHeight: height })
const event = (loadingStatus = 1) => ({ loadingStatus, width: 800, height: 400, contentWidth: 400, contentHeight: 200 })
function adapter() {
  const instance = new ImageKnifeProImageAdapter()
  instance.src = 'https://ehgt.org/sheet'; instance.getUniqueId = () => 7
  const ready = []; let complete = 0; let errors = 0
  instance.onContentReady = source => ready.push(source)
  instance.onComplete = () => { complete++ }; instance.onError = () => { errors++ }
  instance.aboutToAppear()
  const option = instance.option
  option.onLoadListener.onLoadStart(info())
  return { instance, option, ready, complete: () => complete, errors: () => errors }
}
function succeed(value) {
  value.option.onLoadListener.onLoadSuccess(info())
  value.option.onComplete(event())
  return value.ready.at(-1)
}
function sprite() {
  const instance = new EhSpriteThumbnail()
  instance.url = 'https://s.exhentai.org/sheet'; instance.imageKey = 'page-key'
  instance.thumbWidth = 100; instance.thumbHeight = 200; instance.offsetX = 100
  instance.spriteWidth = 800; instance.spriteHeight = 400
  const ready = []; instance.onSnapshotSourceChange = source => ready.push(source)
  instance.aboutToAppear()
  const value = adapter()
  value.instance.onImageInfo = (width, height) => instance.onThumbImageInfo(width, height)
  value.instance.onComplete = () => instance.onThumbComplete()
  value.instance.onContentReady = source => instance.onThumbContentReady(source)
  succeed(value)
  return { instance, ready, adapter: value, source: ready.at(-1) }
}

test('content readiness requires both current main success and positive native content, in either order', () => {
  for (const nativeFirst of [false, true]) {
    const value = adapter()
    if (nativeFirst) value.option.onComplete(event())
    else value.option.onLoadListener.onLoadSuccess(info())
    assert.equal(value.ready.length, 0)
    if (nativeFirst) value.option.onLoadListener.onLoadSuccess(info())
    else value.option.onComplete(event())
    assert.equal(value.ready.length, 1); assert.equal(value.ready[0].isCurrent(), true)
    assert.equal(value.ready[0].width, 800); assert.equal(value.complete(), 1)
    value.option.onComplete(event()); value.option.onLoadListener.onLoadSuccess(info())
    assert.equal(value.ready.length, 1)
  }
})

test('data-only status, missing/wrong request identity and non-finite sizes do not grant readiness', () => {
  for (const invalid of [undefined, event(0), { ...event(), width: NaN }, { ...event(), contentHeight: 0 }]) {
    const value = adapter(); value.option.onLoadListener.onLoadSuccess(info()); value.option.onComplete(invalid)
    assert.equal(value.ready.length, 0)
  }
  for (const invalid of [info('wrong#1'), info('native#1', Infinity), info('native#1', 0)]) {
    const value = adapter(); value.option.onLoadListener.onLoadSuccess(invalid); value.option.onComplete(event())
    assert.equal(value.ready.length, 0)
  }
  const missing = adapter(); missing.option.onLoadListener.onLoadStart(info(''))
  missing.option.onLoadListener.onLoadSuccess(info('')); missing.option.onComplete(event())
  assert.equal(missing.ready.length, 0)
})

test('live URL, signature and actual reload Param changes fence callbacks before their Monitor runs', () => {
  for (const [field, changed] of [['src', 'https://ehgt.org/other'], ['signature', 'new'], ['reloadToken', 1]]) {
    const value = adapter(); const source = succeed(value)
    value.instance[field] = changed
    assert.equal(source.isCurrent(), false)
    value.option.onLoadListener.onLoadSuccess(info()); value.option.onComplete(event())
    assert.equal(value.ready.length, 1)
  }
})

test('old option callbacks and recycled or disappeared native roots cannot authorize content', () => {
  for (const retire of ['aboutToRecycle', 'aboutToDisappear', 'onOptionInputChanged']) {
    const value = adapter(); const source = succeed(value)
    value.instance[retire]()
    assert.equal(source.isCurrent(), false)
    value.option.onLoadListener.onLoadSuccess(info()); value.option.onComplete(event())
    assert.equal(value.ready.length, 1)
  }
})

test('failure revokes a source and a new load must collect fresh success and native readiness', () => {
  const value = adapter(); const source = succeed(value)
  value.option.onLoadListener.onLoadFailed('failed', info())
  assert.equal(source.isCurrent(), false)
  value.option.onLoadListener.onLoadSuccess(info()); value.option.onComplete(event())
  assert.equal(value.ready.length, 1)
  value.option.onLoadListener.onLoadStart(info('native#2'))
  value.option.onLoadListener.onLoadSuccess(info('native#2'))
  assert.equal(value.ready.length, 1)
  // EventImage has no requestId; this proves current option/native content, not a per-retry decode timestamp.
  value.option.onComplete(event())
  assert.equal(value.ready.length, 2); assert.equal(value.ready[1].isCurrent(), true)
  assert.equal(value.complete(), 1)
  const failed = adapter(); failed.option.onLoadListener.onLoadFailed('failed', info())
  assert.equal(failed.errors(), 1); assert.equal(failed.ready.length, 0)
})

test('actual Sprite emits only a live cropped-content handle and no owned pixels', () => {
  const value = sprite()
  assert.equal(value.ready[0], null); assert.equal(value.source.isCurrent(), true)
  assert.equal(value.source.url, 'https://s.exhentai.org/sheet')
  assert.equal(value.source.imageKey, 'page-key'); assert.equal(value.source.offsetX, 100)
  assert.equal(value.source.thumbWidth, 100); assert.equal(value.source.thumbHeight, 200)
  value.instance.aboutToDisappear()
  assert.equal(value.source.isCurrent(), false); assert.equal(value.ready.at(-1), null)
})

test('Sprite live crop/key/layout/blocked/failed changes reject old handles without Monitor ordering', () => {
  for (const [field, changed] of [['offsetX', 200], ['imageKey', 'another'], ['displayWidth', 100],
    ['forceImageBlocked', true], ['imageBlocked', true], ['failed', true], ['activeReloadToken', 1]]) {
    const value = sprite(); value.instance[field] = changed
    assert.equal(value.source.isCurrent(), false, field)
  }
  const changed = sprite(); changed.instance.offsetX = 200; changed.instance.onSnapshotInputChanged()
  assert.equal(changed.source.isCurrent(), false)
  assert.equal(changed.ready.at(-1).offsetX, 200); assert.equal(changed.ready.at(-1).isCurrent(), true)
})

test('Sprite rejects out-of-sheet crops and old resource callbacks while allowing refresh of successful pixels', () => {
  const value = sprite()
  value.instance.reloadToken = 3; value.instance.onReloadRequested()
  assert.equal(value.instance.activeReloadToken, 0); assert.equal(value.source.isCurrent(), true)
  value.instance.offsetX = 750; value.instance.onSnapshotInputChanged()
  assert.equal(value.source.isCurrent(), false); assert.equal(value.ready.at(-1), null)
  const old = new handles.EhImageContentSource('https://ehgt.org/old', 0, 800, 400, () => true)
  const count = value.ready.length; value.instance.onThumbContentReady(old)
  assert.equal(value.ready.length, count)
  value.instance.aboutToDisappear(); value.instance.onThumbContentReady(value.instance.snapshotContent ?? old)
  assert.equal(value.ready.at(-1), null)
})

test('failed Sprite reload consumes only the actual retry token and rejects the retired content', () => {
  const value = sprite(); const retiredContent = value.instance.snapshotContent
  value.instance.onThumbError(); value.instance.onSnapshotInputChanged()
  assert.equal(value.source.isCurrent(), false); assert.equal(value.ready.at(-1), null)
  value.instance.reloadToken = 4; value.instance.onReloadRequested()
  assert.equal(value.instance.activeReloadToken, 4); assert.equal(value.instance.loaded, false)
  value.instance.onThumbContentReady(retiredContent)
  assert.equal(value.ready.at(-1), null)
  value.adapter.instance.reloadToken = 4; value.adapter.instance.onOptionInputChanged()
  value.adapter.option = value.adapter.instance.option
  value.adapter.option.onLoadListener.onLoadStart(info())
  succeed(value.adapter)
  assert.equal(value.ready.at(-1).isCurrent(), true)
  assert.equal(value.source.isCurrent(), false)
})
