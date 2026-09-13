import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import vm from 'node:vm'
import { test } from 'node:test'

const require = createRequire(import.meta.url)
const ts = require(process.env.NEXTE_TYPESCRIPT_PATH ??
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
function load(path, modules = {}) {
  const exports = {}
  const code = ts.transpileModule(readFileSync(new URL(`../shared/src/main/ets/${path}.ets`, import.meta.url), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText
  vm.runInNewContext(code, { exports, require: name => {
    assert.ok(name in modules, `undeclared dependency: ${name}`)
    return modules[name]
  }, console })
  return exports
}
function deferred() {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}
function setup() {
  const pending = []
  const model = load('model/EhGalleryImage')
  const parser = load('parser/EhImagePageParser', {
    '../model/EhGallery': { EhGallery: { parseFileCount: text => Number(text) } },
  })
  const service = load('services/ImageResolveService', {
    '../model/EhGalleryImage': model,
    '../parser/EhImagePageParser': parser,
    '../utils/EhUrlRouter': { EhUrlRouter: { parseImagePage: () => null } },
    '../diagnostics/DiagnosticLogger': { DiagnosticLogger: { info() {}, warn() {} } },
    '../network/EhApiPhpService': { EhApiPhpService: {} },
    '../network/EhHttpClient': { EhHttpClient: { getInstance: () => ({ getText(url) {
      const request = deferred(); pending.push({ ...request, url }); return request.promise
    } }) } },
  })
  const page = () => { const image = new model.EhGalleryImage(2); image.sUrl = 'https://example.org/s/key/1-2'; return image }
  return { service: new service.ImageResolveService(), pending, page }
}
function response(name, original = true) {
  return { statusCode: 200, body: `<img id="img" src="https://example.org/${name}.webp">` +
    `showkey="show-${name}"<a onclick="return nl('${name}')">` +
    (original ? `<a href="https://example.org/fullimg/${name}">Original</a>` : '') }
}
function facts(image) { return [image.imageUrl, image.originImageUrl, image.showKey, image.reloadKey] }

test('coalesced readers receive the same complete metadata from one actual resolver run', async () => {
  const { service, pending, page } = setup()
  const owner = page(), joined = page()
  const first = service.resolve(owner), second = service.resolve(joined)
  assert.equal(pending.length, 1)
  pending[0].resolve(response('first'))
  assert.deepEqual(await Promise.all([first, second]), ['https://example.org/first.webp', 'https://example.org/first.webp'])
  assert.deepEqual(facts(joined), facts(owner))
  assert.equal(joined.originImageUrl, 'https://example.org/fullimg/first')
  owner.originImageUrl = 'caller-mutation'
  assert.equal(joined.originImageUrl, 'https://example.org/fullimg/first')
  const cached = page(); await service.resolve(cached)
  assert.deepEqual(facts(cached), facts(joined))
  assert.equal(pending.length, 1)
})

test('a parsed response without original availability stays absent for both consumers', async () => {
  const { service, pending, page } = setup()
  const owner = page(), joined = page()
  const first = service.resolve(owner), second = service.resolve(joined)
  pending[0].resolve(response('no-original', false))
  await Promise.all([first, second])
  assert.equal(joined.imageUrl, owner.imageUrl)
  assert.equal(joined.originImageUrl, '')
})

test('shared failure retires the flight and a new request can recover', async () => {
  const { service, pending, page } = setup()
  const first = service.resolve(page()), second = service.resolve(page())
  const failures = Promise.allSettled([first, second])
  pending[0].reject(new Error('controlled transport failure'))
  assert.deepEqual((await failures).map(result => result.status), ['rejected', 'rejected'])
  const retry = page(), result = service.resolve(retry)
  assert.equal(pending.length, 2)
  pending[1].resolve(response('retry')); await result
  assert.equal(retry.originImageUrl, 'https://example.org/fullimg/retry')
})

test('late old-flight consumers retain their own facts without replacing newer source cache', async () => {
  const { service, pending, page } = setup()
  const old = page(), joined = page(), replacement = page()
  const first = service.resolve(old), second = service.resolve(joined)
  const fresh = service.resolve(replacement, true)
  assert.equal(pending.length, 2)
  pending[1].resolve(response('new')); await fresh
  pending[0].resolve(response('old')); await Promise.all([first, second])
  assert.deepEqual(facts(joined), facts(old))
  assert.equal(joined.originImageUrl, 'https://example.org/fullimg/old')
  const cached = page(); await service.resolve(cached)
  assert.deepEqual(facts(cached), facts(replacement))
  assert.equal(cached.originImageUrl, 'https://example.org/fullimg/new')
  assert.equal(pending.length, 2)
})

test('overlapping resolves on one mutable image cannot mix a flight URL with another source metadata', async () => {
  const { service, pending, page } = setup()
  const owner = page(), joined = page()
  const first = service.resolve(owner), second = service.resolve(joined)
  const fresh = service.resolve(owner, true)
  pending[0].resolve(response('old'))
  pending[1].resolve(response('new'))
  await Promise.all([first, second, fresh])
  assert.deepEqual(facts(joined), ['https://example.org/old.webp', 'https://example.org/fullimg/old', 'show-old', 'old'])
  const cached = page(); await service.resolve(cached)
  assert.equal(cached.imageUrl, 'https://example.org/new.webp')
  assert.equal(cached.originImageUrl, 'https://example.org/fullimg/new')
})
