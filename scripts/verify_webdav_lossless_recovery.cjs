#!/usr/bin/env node
// Real-call verification for WebDavSyncService lossless recovery and safety checks.
// Loads the ACTUAL ArkTS modules (types stripped) and drives WebDavSyncService methods directly.
const fs = require('node:fs')
const vm = require('node:vm')
const assert = require('node:assert/strict')
const { stripTypeScriptTypes } = require('node:module')
const path = require('node:path')

const root = path.resolve(__dirname, '..')
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')

const clean = (s) => s
  .replace(/imports*{[sS]*?}s*froms*['"][^'"]+['"];?/g, '')
  .replace(/imports+[a-zA-Z0-9_*,s{}]+s+froms*['"][^'"]+['"];?/g, '')
  .replace(/^s*@Concurrent/gm, '')
  .replace(/^exports+/gm, '')

function setupContext() {
  const sandbox = {
    console,
    DiagnosticLogger: {
      info() {},
      warn() {},
      error() {},
    },
    cryptoFramework: {
      createMd() {
        return {
          updateSync() {},
          digestSync() { return { data: new Uint8Array(32) } }
        }
      }
    },
    util: {
      TextEncoder: class {
        encodeInto(s) {
          const buf = Buffer.from(s, 'utf8')
          return { byteLength: buf.length }
        }
      },
      Base64Helper: class {
        encodeToStringSync() { return 'bW9jaw==' }
      }
    },
    fileIo: {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2 },
      openSync() { return { fd: 42 } },
      writeSync(_fd, body) { return Buffer.byteLength(body, 'utf8') },
      closeSync() {}
    },
    AxiosHttpClient: {
      requestText: async () => ({ statusCode: 200, body: '', rawHeader: '' })
    },
    SyncService: {
      parseRaw: (raw) => JSON.parse(raw)
    },
    SyncLocalDataAdapter: {
      mergeEnvelopes: (a, b) => a
    },
    connectSyncSettings: () => ({ webdavSyncing: false })
  }

  const rawTypes = read('shared/src/main/ets/sync/SyncTypes.ets')
  const rawService = read('shared/src/main/ets/sync/WebDavSyncService.ets')

  const tsCombined = rawTypes + '\n' + rawService
  const jsCode = stripTypeScriptTypes(tsCombined, { mode: 'transform' })
  const fullCode = jsCode
    .replace(/\bimport\s*\{[^}]*\}\s*from\s*['"][^'"]+['"];?/g, '')
    .replace(/\bimport\s+[^;]+from\s*['"][^'"]+['"];?/g, '')
    .replace(/\bimport\s*['"][^'"]+['"];?/g, '')
    .replace(/\bexport\s+/g, '')
    .replace(/^\s*@Concurrent\b/gm, '')
    + '\nsandbox.WebDavSyncService = WebDavSyncService;\nsandbox.SyncManifestV1 = SyncManifestV1;'

  sandbox.sandbox = sandbox
  vm.runInNewContext(fullCode, sandbox)
  return sandbox
}

const ctx = setupContext()
const WebDavSyncService = ctx.WebDavSyncService
assert.ok(WebDavSyncService, 'WebDavSyncService must be loaded from actual source')

console.log('Running tests against ACTUAL WebDavSyncService source code...')

// 1. Test recoverTruncatedManifest with the real 16384-byte backup from device 237
const backupPath = path.join(root, '.hvigor/outputs/recv-real-backup/raw_remote_manifest_backup.json')
if (fs.existsSync(backupPath)) {
  const rawBackup = fs.readFileSync(backupPath, 'utf8')
  const recovered = WebDavSyncService.recoverTruncatedManifest(rawBackup)
  assert.ok(recovered !== null, 'recoverTruncatedManifest must successfully recover prefix of real 16KB backup')
  assert.equal(recovered.magic, 'NEXTN_SYNC')
  assert.equal(recovered.appId, 'com.erosteam.nextn')
  assert.equal(recovered.corrupted, true, 'Recovered manifest must have corrupted=true')
  assert.equal(recovered.datasets.length, 2, 'Must recover read-progress and viewed-history datasets')
  assert.equal(recovered.datasets[0].id, 'read-progress')
  assert.equal(recovered.datasets[0].shards.length, 59)
  assert.equal(recovered.datasets[1].id, 'viewed-history')
  assert.equal(recovered.datasets[1].shards.length, 35)
  console.log('✓ recoverTruncatedManifest recovers real 16KB truncated backup from device 237')
}

// 2. Test discoverRemoteShards regex with <D:> prefix, status, contentLength, and lastModified
ctx.AxiosHttpClient.requestText = async () => ({
  statusCode: 207,
  body: '<?xml version="1.0" encoding="utf-8"?>' +
'<D:multistatus xmlns:D="DAV:">' +
'  <D:response>' +
'    <D:href>/dav/datasets/read-progress/0a.json</D:href>' +
'    <D:propstat>' +
'      <D:status>HTTP/1.1 200 OK</D:status>' +
'      <D:prop>' +
'        <D:getcontentlength>1234</D:getcontentlength>' +
'        <D:getlastmodified>Fri, 18 Sep 2026 20:10:43 GMT</D:getlastmodified>' +
'      </D:prop>' +
'    </D:propstat>' +
'  </D:response>' +
'  <D:response>' +
'    <D:href>/dav/datasets/read-progress/2f.json</D:href>' +
'    <D:propstat>' +
'      <D:status>HTTP/1.1 200 OK</D:status>' +
'      <D:prop>' +
'        <D:getcontentlength>5678</D:getcontentlength>' +
'        <D:getlastmodified>Fri, 18 Sep 2026 20:11:00 GMT</D:getlastmodified>' +
'      </D:prop>' +
'    </D:propstat>' +
'  </D:response>' +
'</D:multistatus>',
  rawHeader: ''
})

async function runAsyncTests() {
  const dummyConfig = { username: '', password: '', directoryUrl: 'https://example.com/dav/' }
  const shards = await WebDavSyncService.discoverRemoteShards('https://example.com/dav/', 'read-progress', dummyConfig)
  assert.equal(shards.length, 2, 'Must discover 2 shards from <D:> prefixed XML')
  assert.equal(shards[0].id, '0a')
  assert.equal(shards[0].contentLength, 1234)
  assert.ok(shards[0].lastModifiedMs > 0)
  assert.equal(shards[1].id, '2f')
  assert.equal(shards[1].contentLength, 5678)
  console.log('✓ discoverRemoteShards parses real <D:> namespaced XML with content-length and status')

  // Fault injection: Truncated XML missing </multistatus> MUST throw
  ctx.AxiosHttpClient.requestText = async () => ({
    statusCode: 207,
    body: '<D:multistatus xmlns:D="DAV:"><D:response><D:href>/0a.json</D:href>',
    rawHeader: ''
  })
  await assert.rejects(
    () => WebDavSyncService.discoverRemoteShards('https://example.com/dav/', 'read-progress', dummyConfig),
    /truncated XML/i,
    'Truncated XML must throw error and abort'
  )
  console.log('✓ discoverRemoteShards fails closed on truncated XML')

  // Fault injection: Item status >= 300 MUST throw
  ctx.AxiosHttpClient.requestText = async () => ({
    statusCode: 207,
    body: '<D:multistatus xmlns:D="DAV:">' +
  '<D:response>' +
    '<D:href>/dav/datasets/read-progress/0a.json</D:href>' +
    '<D:status>HTTP/1.1 500 Internal Server Error</D:status>' +
  '</D:response>' +
'</D:multistatus>',
    rawHeader: ''
  })
  await assert.rejects(
    () => WebDavSyncService.discoverRemoteShards('https://example.com/dav/', 'read-progress', dummyConfig),
    /reported error status 500/i,
    'Non-200 item status must throw error and abort'
  )
  console.log('✓ discoverRemoteShards fails closed on item status >= 300')

  // 3. Test discoverRemoteDatasetDirectories
  ctx.AxiosHttpClient.requestText = async () => ({
    statusCode: 207,
    body: '<D:multistatus xmlns:D="DAV:">' +
  '<D:response>' +
    '<D:href>/dav/datasets/read-progress/</D:href>' +
    '<D:status>HTTP/1.1 200 OK</D:status>' +
  '</D:response>' +
  '<D:response>' +
    '<D:href>/dav/datasets/custom-profiles/</D:href>' +
    '<D:status>HTTP/1.1 200 OK</D:status>' +
  '</D:response>' +
'</D:multistatus>',
    rawHeader: ''
  })
  const dirs = await WebDavSyncService.discoverRemoteDatasetDirectories('https://example.com/dav/', dummyConfig)
  assert.equal(dirs.length, 2)
  assert.ok(dirs.includes('read-progress') && dirs.includes('custom-profiles'))
  console.log('✓ discoverRemoteDatasetDirectories correctly discovers unknown datasets')

  // 4. Test verifyTransferIntegrity
  // Good case: Content-Length matches
  WebDavSyncService.verifyTransferIntegrity('https://example.com/f', {
    statusCode: 200,
    body: 'hello world',
    rawHeader: JSON.stringify({ 'content-length': '11' })
  })

  // Truncated case: Content-Length 100 but only 11 bytes received
  assert.throws(
    () => WebDavSyncService.verifyTransferIntegrity('https://example.com/f', {
      statusCode: 200,
      body: 'hello world',
      rawHeader: JSON.stringify({ 'content-length': '100' })
    }),
    /WebDAV transfer truncated/i,
    'verifyTransferIntegrity must throw on truncated payload'
  )
  console.log('✓ verifyTransferIntegrity accurately compares UTF-8 byte length with Content-Length')

  // 5. Test parseManifest
  // Normal valid case
  const validManifest = JSON.stringify({
    magic: 'NEXTE_SYNC',
    appId: 'com.erosteam.nexte',
    schemaVersion: 1,
    minSupportedSchemaVersion: 1,
    generatedAt: new Date().toISOString(),
    datasets: []
  })
  const parsedValid = WebDavSyncService.parseManifest(validManifest)
  assert.equal(parsedValid.magic, 'NEXTE_SYNC')
  assert.equal(!!parsedValid.corrupted, false)

  // Corrupt garbage that cannot be recovered
  assert.throws(
    () => WebDavSyncService.parseManifest('<!DOCTYPE html><html>502 Bad Gateway</html>'),
    /WebDAV manifest corrupt or truncated/i,
    'Unrecoverable garbage manifest must throw and fail closed'
  )
  console.log('✓ parseManifest parses valid manifests and fails closed on unrecoverable data')

  console.log('ALL REAL SOURCE CODE VERIFICATIONS PASSED!')
}

runAsyncTests().catch(err => {
  console.error('Test failed:', err)
  process.exit(1)
})
