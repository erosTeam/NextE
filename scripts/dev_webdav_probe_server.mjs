#!/usr/bin/env node
import { createServer } from 'node:http'
import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const port = Number(process.argv[2] || '18765')
const outDir = process.argv[3] || '.hvigor/outputs/webdav-sync-probe'
const user = process.env.NEXTE_WEBDAV_USER || 'nexte'
const pass = process.env.NEXTE_WEBDAV_PASS || 'nexte'
const auth = `Basic ${Buffer.from(`${user}:${pass}`, 'utf8').toString('base64')}`
const files = new Map()
const collections = new Set()
const requests = []

mkdirSync(outDir, { recursive: true })

if (process.env.NEXTE_WEBDAV_SEED_SEARCH === '1') {
  files.set('/dav/nexte-sync-v1/datasets/search-history/0a.json', JSON.stringify({
    magic: 'NEXTE_SYNC',
    appId: 'com.erosteam.nexte',
    schemaVersion: 1,
    minSupportedSchemaVersion: 1,
    generatedAt: '1970-01-01T00:00:01.000Z',
    datasetId: 'search-history',
    shardId: '0a',
    datasets: {
      readProgress: [],
      viewedHistory: [],
      localFavorites: [],
      searchHistory: [
        {
          scopeKey: 'default',
          queryText: 'webdav-probe-seed',
          positionIndex: 0,
          updatedAt: 1000,
          deletedAt: 0,
        },
      ],
      localBlockSettings: [],
      localBlockRules: [],
      customProfiles: [],
      customProfileSelection: [],
    },
  }))
  files.set('/dav/nexte-sync-v1/manifest.json', JSON.stringify({
    magic: 'NEXTE_SYNC',
    appId: 'com.erosteam.nexte',
    schemaVersion: 1,
    minSupportedSchemaVersion: 1,
    generatedAt: '2026-06-28T00:00:00.000Z',
    datasets: [
      {
        id: 'search-history',
        shards: [
          {
            id: '0a',
            path: 'datasets/search-history/0a.json',
            sha256: 'stale-seed-sha',
            recordCount: 1,
            updatedAt: 1000,
          },
        ],
      },
    ],
  }))
}

const readBody = (req) => new Promise((resolve, reject) => {
  let body = ''
  req.setEncoding('utf8')
  req.on('data', (chunk) => {
    body += chunk
  })
  req.on('end', () => resolve(body))
  req.on('error', reject)
})

const writeSummary = () => {
  const fileList = []
  for (const key of files.keys()) {
    fileList.push(key)
  }
  const summary = {
    port,
    user,
    root: '/dav/nexte-sync-v1/',
    requestCount: requests.length,
    requests,
    collections: Array.from(collections.values()),
    files: fileList,
    wroteLegacyFile: requests.some((item) => item.method === 'PUT' && item.url === '/dav/nexte-sync-v1.json'),
    wroteManifest: requests.some((item) => item.method === 'PUT' && item.url === '/dav/nexte-sync-v1/manifest.json'),
    wroteShard: requests.some((item) => item.method === 'PUT' && /\/dav\/nexte-sync-v1\/datasets\/[^/]+\/[0-3][0-9a-f]\.json/.test(item.url)),
  }
  writeFileSync(join(outDir, 'summary.json'), `${JSON.stringify(summary, null, 2)}\n`)
}

const respond = (res, status, body = '') => {
  res.writeHead(status, body.length > 0 ? { 'Content-Type': 'application/json; charset=utf-8' } : undefined)
  res.end(body)
}

const server = createServer(async (req, res) => {
  const item = { method: req.method || '', url: req.url || '', bytes: 0, status: 0 }
  requests.push(item)
  try {
    if (req.headers.authorization !== auth) {
      item.status = 401
      respond(res, 401, 'unauthorized')
      return
    }
    if (req.url === '/dav/nexte-sync-v1.json' && req.method === 'PUT') {
      item.status = 500
      respond(res, 500, 'legacy file must not be written')
      return
    }
    if (req.method === 'MKCOL') {
      collections.add(req.url || '')
      item.status = 201
      respond(res, 201)
      return
    }
    if (req.method === 'GET') {
      if (!files.has(req.url)) {
        item.status = 404
        respond(res, 404, 'missing')
        return
      }
      item.status = 200
      respond(res, 200, files.get(req.url))
      return
    }
    if (req.method === 'PUT') {
      const body = await readBody(req)
      item.bytes = body.length
      files.set(req.url, body)
      item.status = 201
      respond(res, 201)
      return
    }
    item.status = 405
    respond(res, 405, 'method not allowed')
  } finally {
    writeSummary()
  }
})

server.listen(port, '127.0.0.1', () => {
  writeSummary()
  console.log(`NextE WebDAV probe listening on http://127.0.0.1:${port}/dav/ user=${user}`)
})

process.on('SIGINT', () => {
  writeSummary()
  server.close(() => process.exit(0))
})
process.on('SIGTERM', () => {
  writeSummary()
  server.close(() => process.exit(0))
})
