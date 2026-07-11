#!/usr/bin/env node
import { createServer } from 'node:http'
import assert from 'node:assert/strict'

const ROOT = '/dav/nexte-sync-v1/'
const MANIFEST = `${ROOT}manifest.json`
const LEGACY_FILE = '/dav/nexte-sync-v1.json'
const SEARCH_SHARD = `${ROOT}datasets/search-history/0a.json`
const VIEWED_SHARD = `${ROOT}datasets/viewed-history/2f.json`
const USER = '用户'
const PASS = 'päss'
const AUTH = `Basic ${Buffer.from(`${USER}:${PASS}`, 'utf8').toString('base64')}`

const files = new Map()
const versions = new Map()
const collections = new Set()
const requests = []
let nextVersion = 0

const readBody = (req) => new Promise((resolve, reject) => {
  let body = ''
  req.setEncoding('utf8')
  req.on('data', (chunk) => {
    body += chunk
  })
  req.on('end', () => resolve(body))
  req.on('error', reject)
})

const write = (res, status, body = '', headers = {}) => {
  const out = { ...headers }
  if (body.length > 0) {
    out['Content-Type'] = 'application/json; charset=utf-8'
  }
  res.writeHead(status, Object.keys(out).length > 0 ? out : undefined)
  res.end(body)
}

const etagFor = (path) => `"${versions.get(path) ?? 0}"`

const server = createServer(async (req, res) => {
  requests.push({ method: req.method, url: req.url })
  if (req.headers.authorization !== AUTH) {
    write(res, 401, 'unauthorized')
    return
  }
  if (req.url === LEGACY_FILE && req.method === 'PUT') {
    write(res, 500, 'legacy file must not be written')
    return
  }
  if (req.method === 'MKCOL') {
    collections.add(req.url)
    write(res, 201)
    return
  }
  if (req.method === 'GET') {
    if (!files.has(req.url)) {
      write(res, 404, 'missing')
      return
    }
    write(res, 200, files.get(req.url), { ETag: etagFor(req.url) })
    return
  }
  if (req.method === 'PUT') {
    const exists = files.has(req.url)
    const ifMatch = typeof req.headers['if-match'] === 'string' ? req.headers['if-match'] : ''
    const ifNoneMatch = typeof req.headers['if-none-match'] === 'string' ? req.headers['if-none-match'] : ''
    if ((ifMatch.length > 0 && (!exists || ifMatch !== etagFor(req.url))) ||
      (ifNoneMatch === '*' && exists)) {
      write(res, 412, 'precondition failed')
      return
    }
    files.set(req.url, await readBody(req))
    nextVersion += 1
    versions.set(req.url, nextVersion)
    write(res, 201, '', { ETag: etagFor(req.url) })
    return
  }
  write(res, 405, 'method not allowed')
})

await new Promise((resolve) => {
  server.listen(0, '127.0.0.1', resolve)
})

try {
  const { port } = server.address()
  const base = `http://127.0.0.1:${port}`
  const headers = { Authorization: AUTH }
  const mkcol = async (path) => {
    const resp = await fetch(`${base}${path}`, { method: 'MKCOL', headers })
    assert.equal(resp.status, 201, `MKCOL ${path}`)
  }
  const putJson = async (path, payload) => {
    const resp = await fetch(`${base}${path}`, {
      method: 'PUT',
      headers: { ...headers, 'Content-Type': 'application/json; charset=utf-8' },
      body: payload,
    })
    assert.equal(resp.status, 201, `PUT ${path}`)
  }
  const getText = async (path, expectedStatus) => {
    const resp = await fetch(`${base}${path}`, { method: 'GET', headers })
    assert.equal(resp.status, expectedStatus, `GET ${path}`)
    return await resp.text()
  }
  const getEtag = async (path) => {
    const resp = await fetch(`${base}${path}`, { method: 'GET', headers })
    assert.equal(resp.status, 200, `GET ${path} ETag`)
    await resp.text()
    return resp.headers.get('etag') ?? ''
  }

  await mkcol(ROOT)
  await mkcol(`${ROOT}datasets/`)
  await mkcol(`${ROOT}datasets/search-history/`)
  await mkcol(`${ROOT}datasets/viewed-history/`)

  assert.equal(await getText(MANIFEST, 404), 'missing', 'empty manifest returns 404')

  const searchShard = JSON.stringify({
    magic: 'NEXTE_SYNC',
    appId: 'com.erosteam.nexte',
    schemaVersion: 1,
    minSupportedSchemaVersion: 1,
    datasetId: 'search-history',
    shardId: '0a',
    datasets: { searchHistory: [{ scopeKey: 'default', queryText: 'artist:test', updatedAt: 1 }] },
  })
  const viewedShard = JSON.stringify({
    magic: 'NEXTE_SYNC',
    appId: 'com.erosteam.nexte',
    schemaVersion: 1,
    minSupportedSchemaVersion: 1,
    datasetId: 'viewed-history',
    shardId: '2f',
    datasets: { viewedHistory: [{ scopeKey: 'default', gid: '1', token: 'tok', viewedAt: 2 }] },
  })
  const manifest = JSON.stringify({
    magic: 'NEXTE_SYNC',
    appId: 'com.erosteam.nexte',
    schemaVersion: 1,
    minSupportedSchemaVersion: 1,
    generatedAt: '2026-06-28T00:00:00.000Z',
    datasets: [
      {
        id: 'search-history',
        shards: [{ id: '0a', path: 'datasets/search-history/0a.json', sha256: 'search-sha', recordCount: 1, updatedAt: 1 }],
      },
      {
        id: 'viewed-history',
        shards: [{ id: '2f', path: 'datasets/viewed-history/2f.json', sha256: 'viewed-sha', recordCount: 1, updatedAt: 2 }],
      },
    ],
  })

  await putJson(SEARCH_SHARD, searchShard)
  await putJson(VIEWED_SHARD, viewedShard)
  await putJson(MANIFEST, manifest)

  assert.equal(await getText(SEARCH_SHARD, 200), searchShard, 'search-history shard round-trips')
  assert.equal(await getText(VIEWED_SHARD, 200), viewedShard, 'viewed-history shard round-trips')
  assert.equal(await getText(MANIFEST, 200), manifest, 'manifest round-trips')

  const manifestEtag = await getEtag(MANIFEST)
  assert.notEqual(manifestEtag, '', 'manifest returns an ETag')
  const updatedManifest = `${manifest}\n`
  const conditionalUpdate = await fetch(`${base}${MANIFEST}`, {
    method: 'PUT',
    headers: {
      ...headers,
      'Content-Type': 'application/json; charset=utf-8',
      'If-Match': manifestEtag,
    },
    body: updatedManifest,
  })
  assert.equal(conditionalUpdate.status, 201, 'versioned manifest PUT succeeds')
  const staleManifestUpdate = await fetch(`${base}${MANIFEST}`, {
    method: 'PUT',
    headers: {
      ...headers,
      'Content-Type': 'application/json; charset=utf-8',
      'If-Match': manifestEtag,
    },
    body: manifest,
  })
  assert.equal(staleManifestUpdate.status, 412, 'stale manifest PUT is rejected')
  assert.equal(await getText(MANIFEST, 200), updatedManifest, 'stale manifest PUT preserves current manifest')

  const INITIAL_MANIFEST = `${ROOT}conditional-create.json`
  const conditionalCreate = await fetch(`${base}${INITIAL_MANIFEST}`, {
    method: 'PUT',
    headers: {
      ...headers,
      'Content-Type': 'application/json; charset=utf-8',
      'If-None-Match': '*',
    },
    body: manifest,
  })
  assert.equal(conditionalCreate.status, 201, 'missing manifest conditional create succeeds')
  const duplicateCreate = await fetch(`${base}${INITIAL_MANIFEST}`, {
    method: 'PUT',
    headers: {
      ...headers,
      'Content-Type': 'application/json; charset=utf-8',
      'If-None-Match': '*',
    },
    body: manifest,
  })
  assert.equal(duplicateCreate.status, 412, 'duplicate manifest conditional create is rejected')

  const denied = await fetch(`${base}${MANIFEST}`, { method: 'GET' })
  assert.equal(denied.status, 401, 'server enforces Basic auth')

  assert.equal(files.has(LEGACY_FILE), false, 'legacy single-file path is not written')
  assert.equal(collections.has(ROOT), true, 'root collection was created')
  assert.equal(collections.has(`${ROOT}datasets/search-history/`), true, 'dataset collection was created')
  assert.equal(
    requests.some((item) => item.method === 'PUT' && item.url === LEGACY_FILE),
    false,
    'request log has no legacy single-file PUT',
  )
  assert.equal(
    requests.some((item) => item.method === 'PUT' && item.url === SEARCH_SHARD),
    true,
    'request log has shard PUT',
  )

  console.log('✓ local WebDAV sharded server contract passed')
} finally {
  await new Promise((resolve) => server.close(resolve))
}
