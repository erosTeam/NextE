import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import vm from 'node:vm'
import crypto from 'node:crypto'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const modelSource = fs.readFileSync(new URL('../shared/src/main/ets/services/ComicTranslationModelService.ets', import.meta.url), 'utf8')
const clientSource = fs.readFileSync(new URL('../shared/src/main/ets/network/EhHttpClient.ets', import.meta.url), 'utf8')
const logger = { warn() {} }
const constants = { USER_AGENT: 'fixture-agent', ACCEPT_LANGUAGE: 'en' }
const payload = Buffer.from('verified model fixture')
const sha = crypto.createHash('sha256').update(payload).digest('hex')

function load(source, modules, globals = {}) {
  const context = { exports: {}, require: name => {
    assert.ok(name in modules, `unexpected module ${name}`)
    return modules[name]
  }, Date, setTimeout, clearTimeout, ...globals }
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  return context.exports
}

function files() {
  return { OpenMode: { READ_ONLY: 0, READ_WRITE: 2, CREATE: 4, TRUNC: 8 },
    statSync: fs.statSync, accessSync: fs.existsSync,
    unlinkSync: fs.unlinkSync, renameSync: fs.renameSync,
    openSync: (file, flags) => ({ fd: fs.openSync(file, flags === 0 ? 'r' : 'w+') }),
    closeSync: file => fs.closeSync(file.fd),
    readSync: (fd, buffer, options) => fs.readSync(fd, Buffer.from(buffer), 0, options.length, null),
    writeSync: (fd, buffer, options) => fs.writeSync(fd, Buffer.from(buffer), 0, buffer.byteLength, options.offset),
  }
}

function modelFixture(download) {
  return load(modelSource, {
    '@kit.CoreFileKit': { fileIo: files() },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd() {
      const hash = crypto.createHash('sha256')
      return { updateSync: value => hash.update(value.data), digestSync: () => ({ data: hash.digest() }) }
    } } },
    '../diagnostics/DiagnosticLogger': { DiagnosticLogger: logger },
    '../network/EhHttpClient': { EhHttpClient: { getInstance: () => ({ downloadBinaryToFileInStream: download }) } },
  }).ComicTranslationModelService
}

test('corrupt HTTP 200 body is rejected and the next verified source is installed', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-model-test-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const attempts = []
  const service = modelFixture(async (...args) => {
    const [url, file] = args
    attempts.push(url)
    assert.equal(args[8], false, 'model requests explicitly disable EH credentials')
    const body = attempts.length === 1 ? Buffer.alloc(payload.length, 120) : payload
    fs.writeFileSync(file, body)
    return body.length
  })
  const destination = path.join(dir, 'model.bin')
  await service.installAssetIfMissing('model.bin', destination, payload.length, sha)
  assert.equal(attempts.length, 2)
  assert.match(attempts[0], /^https:\/\/github.com\//)
  assert.match(attempts[1], /^https:\/\/ghproxy.net\//)
  assert.equal(service.preferredSource, 1)
  assert.deepEqual(fs.readFileSync(destination), payload)
  assert.equal(fs.existsSync(destination + '.part'), false)
  await service.installAssetIfMissing('model.bin', destination, payload.length, sha)
  assert.equal(attempts.length, 2, 'verified installed files do not download again')
})

test('all failures remove partial bytes without replacing the installed file or selecting a bad source', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-model-test-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const attempts = []
  const service = modelFixture(async (url, file) => {
    attempts.push(url)
    fs.writeFileSync(file, 'short')
    if (attempts.length % 2) throw new Error('fixture transport failed')
    return 5
  })
  const destination = path.join(dir, 'model.bin')
  fs.writeFileSync(destination, 'old version')
  service.preferredSource = 2
  await assert.rejects(service.installAssetIfMissing('model.bin', destination, payload.length, sha), /unavailable on all 4 sources/)
  assert.equal(attempts.length, 4)
  assert.equal(new Set(attempts).size, 4)
  assert.equal(service.preferredSource, 2)
  assert.equal(fs.readFileSync(destination, 'utf8'), 'old version')
  assert.equal(fs.existsSync(destination + '.part'), false)
})

function clientFixture(mode) {
  const requests = [], timers = new Map()
  let timerId = 0, armed = 0, credentialReads = 0
  const shim = files()
  const client = load(clientSource, {
    '@ohos/axios': { default: { request: async config => {
      requests.push({ channel: 'axios', headers: config.headers })
      return await config.adapter(config)
    } } },
    '@kit.CoreFileKit': { fileIo: shim },
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, createHttp() {
      const events = new Map()
      let rejectStream
      return { on: (name, handler) => events.set(name, handler),
        destroy() { if (rejectStream) rejectStream(new Error('fixture destroyed')) },
        async requestInStream(url, options) {
          requests.push({ channel: 'native', url, headers: options.header })
          const data = payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength)
          if (mode === 'stall') {
            return await new Promise((_resolve, reject) => {
              rejectStream = reject
              events.get('dataReceive')(data)
              events.get('dataReceiveProgress')({ receiveSize: payload.length, totalSize: payload.length + 5 })
              assert.equal(armed, 2, 'duplicate progress does not postpone the deadline')
              assert.equal(timers.size, 1, 'stall guard remains active after the first chunk')
              ;[...timers.values()][0]()
            })
          }
          events.get('dataReceive')(data)
          return 200
        },
      }
    } } },
    '../constants/EhConstants': { EhConstants: constants },
    './EhCookieStore': { EhCookieStore: { getInstance() {
      credentialReads++
      return { header: () => 'synthetic-account-marker' }
    } } },
    '../diagnostics/DiagnosticLogger': { DiagnosticLogger: logger },
  }, { setTimeout: (callback, delay) => {
      if (delay !== 50) { queueMicrotask(callback); return -1 }
      armed++; timers.set(++timerId, callback); return timerId
    },
    clearTimeout: id => timers.delete(id) })
  return { client: client.EhHttpClient.getInstance(), requests, timers, reads: () => credentialReads }
}

test('public streaming has no Cookie in the envelope or native request, while EH defaults retain auth', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-http-test-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const f = clientFixture('success')
  await f.client.downloadBinaryToFileInStream('https://fixture.invalid/public', path.join(dir, 'public'), () => {}, 100, 50, '*/*', 1, 1000, false)
  assert.equal(f.reads(), 0)
  assert.ok(f.requests.every(request => !Object.hasOwn(request.headers, 'Cookie')))
  assert.deepEqual(fs.readFileSync(path.join(dir, 'public')), payload)
  await f.client.downloadBinaryToFileInStream('https://fixture.invalid/eh', path.join(dir, 'eh'), () => {}, 100, 50, '*/*', 1, 1000)
  assert.ok(f.requests.slice(2).every(request => request.headers.Cookie === 'synthetic-account-marker'))
  assert.equal(f.timers.size, 0)
})

test('a stream stalled after its first chunk times out and cleans partial output', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-http-test-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const f = clientFixture('stall')
  const file = path.join(dir, 'partial')
  await assert.rejects(f.client.downloadBinaryToFileInStream('https://fixture.invalid/public', file, () => {}, 100, 50, '*/*', 1, 1000, false), /no progress timeout/)
  assert.equal(fs.existsSync(file), false)
  assert.equal(f.timers.size, 0)
})
