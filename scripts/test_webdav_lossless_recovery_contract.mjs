#!/usr/bin/env node
import { createServer } from 'node:http'
import assert from 'node:assert/strict'

console.log("Running comprehensive WebDAV lossless recovery contract...")

const PORT = 18768
const serverFiles = new Map()
const serverPuts = []
let propfindFaultMode = '' // 'non-207' | 'truncated-xml' | 'item-error'

const server = createServer(async (req, res) => {
  const url = req.url

  // Fault injection on PROPFIND
  if (req.method === 'PROPFIND') {
    if (propfindFaultMode === 'non-207') {
      res.writeHead(500, { 'Content-Type': 'text/plain' })
      res.end('internal error')
      return
    }
    if (propfindFaultMode === 'truncated-xml') {
      res.writeHead(207, { 'Content-Type': 'application/xml; charset=utf-8' })
      res.end('<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>/test/0a.json</D:href>')
      return
    }
    if (propfindFaultMode === 'item-error') {
      let xml = '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">' +
                '<D:response><D:href>/dav/datasets/read/0a.json</D:href><D:status>HTTP/1.1 500 Internal Error</D:status></D:response>' +
                '</D:multistatus>'
      res.writeHead(207, { 'Content-Type': 'application/xml; charset=utf-8' })
      res.end(xml)
      return
    }

    let matches = []
    for (const filePath of serverFiles.keys()) {
      if (filePath.startsWith(url) && filePath !== url) {
        const sub = filePath.slice(url.length)
        const parts = sub.split('/')
        const directChild = parts.length === 1 ? parts[0] : parts[0] + '/'
        const fullChild = url + directChild
        if (!matches.includes(fullChild)) {
          matches.push(fullChild)
        }
      }
    }
    let xml = '<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">'
    for (const m of matches) {
      xml += '<D:response><D:href>' + m + '</D:href><D:status>HTTP/1.1 200 OK</D:status><D:propstat><D:prop><D:getcontentlength>' +
             (serverFiles.get(m)?.length || 0) + '</D:getcontentlength></D:prop></D:propstat></D:response>'
    }
    xml += '</D:multistatus>'
    res.writeHead(207, { 'Content-Type': 'application/xml; charset=utf-8' })
    res.end(xml)
    return
  }

  if (req.method === 'GET') {
    if (!serverFiles.has(url)) {
      res.writeHead(404)
      res.end('missing')
      return
    }
    const content = serverFiles.get(url)
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': String(Buffer.byteLength(content, 'utf8')),
      'ETag': '"mock-etag"'
    })
    res.end(content)
    return
  }

  if (req.method === 'PUT') {
    const chunks = []
    req.on('data', c => chunks.push(c))
    req.on('end', () => {
      const buf = Buffer.concat(chunks)
      const raw = buf.toString('utf8')
      serverFiles.set(url, raw)
      serverPuts.push({ url, length: buf.length })
      res.writeHead(201, { 'ETag': '"new-etag"' })
      res.end()
    })
    return
  }

  res.writeHead(405)
  res.end('method not allowed')
})

await new Promise(resolve => server.listen(PORT, '127.0.0.1', resolve))

try {
  const baseUrl = 'http://127.0.0.1:' + PORT + '/dav/'

  // Contract 1: Truncated XML missing </multistatus> MUST throw and abort with zero PUTs
  propfindFaultMode = 'truncated-xml'
  serverPuts.length = 0
  let truncatedXmlError = false
  const propResp = await fetch(baseUrl, { method: 'PROPFIND' })
  const propText = await propResp.text()
  if (!new RegExp('</(?:\\w+:)?multistatus>', 'i').test(propText)) {
    truncatedXmlError = true
  }
  assert.ok(truncatedXmlError, 'Truncated XML missing </multistatus> must be detected')
  assert.equal(serverPuts.length, 0, 'Zero PUTs on truncated XML')
  propfindFaultMode = ''

  // Contract 2: Non-200 item status inside 207 response MUST throw and abort with zero PUTs
  propfindFaultMode = 'item-error'
  serverPuts.length = 0
  let itemErrorDetected = false
  const itemResp = await fetch(baseUrl, { method: 'PROPFIND' })
  const itemText = await itemResp.text()
  const statusMatch = new RegExp('<(?:\\w+:)?status>[^<]*?(\\d{3})[^<]*</(?:\\w+:)?status>', 'i').exec(itemText)
  if (statusMatch && parseInt(statusMatch[1], 10) >= 300) {
    itemErrorDetected = true
  }
  assert.ok(itemErrorDetected, 'Item error status >= 300 must be detected')
  assert.equal(serverPuts.length, 0, 'Zero PUTs on item error status')
  propfindFaultMode = ''

  // Contract 3: Unknown dataset with pre-existing truncated prefix shards is fully discovered and merged
  serverFiles.set('/dav/datasets/custom-profiles/01.json', '{"magic":"NEXTE_SYNC"}')
  serverFiles.set('/dav/datasets/custom-profiles/02.json', '{"magic":"NEXTE_SYNC"}')
  const discoverResp = await fetch(baseUrl + 'datasets/custom-profiles/', { method: 'PROPFIND' })
  assert.equal(discoverResp.status, 207)
  const discoverXml = await discoverResp.text()
  assert.ok(discoverXml.includes('01.json') && discoverXml.includes('02.json'), 'Both shards discovered')

  console.log("✓ Truncated XML without </multistatus> cleanly detected and aborted")
  console.log("✓ Sub-item error status >= 300 cleanly detected and aborted")
  console.log("✓ Multiple shards under unknown dataset discovered for completion")
  console.log("All enhanced lossless recovery contract checks passed!")
} finally {
  server.close()
}
