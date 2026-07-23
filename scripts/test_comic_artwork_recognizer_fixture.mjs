#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const rawRoot = join(root, 'entry', 'src', 'ohosTest', 'resources', 'rawfile')
const manifestPath = join(rawRoot, 'comic_artwork_recognizer_eval_v1.json')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))

function fail(message) {
  throw new Error(`comic artwork recognizer fixture: ${message}`)
}

function pngDimensions(bytes, label) {
  const signature = '89504e470d0a1a0a'
  if (bytes.length < 24 || bytes.subarray(0, 8).toString('hex') !== signature ||
    bytes.subarray(12, 16).toString('ascii') !== 'IHDR') {
    fail(`${label} is not a valid PNG with an IHDR header`)
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  }
}

if (manifest.schemaVersion !== 1 ||
  manifest.fixtureSetId !== 'nexte-original-artwork-recognizer-v1' ||
  typeof manifest.provenance !== 'string' || manifest.provenance.length < 40) {
  fail('invalid manifest identity or provenance')
}
if (!Array.isArray(manifest.sources) || manifest.sources.length !== 2 ||
  !Array.isArray(manifest.cases)) {
  fail('expected two sources and a case array')
}

const sources = new Map()
for (const source of manifest.sources) {
  if (typeof source.id !== 'string' || sources.has(source.id) ||
    typeof source.rawFile !== 'string' || !/^[A-Za-z0-9_.-]+$/.test(source.rawFile) ||
    !/^[a-f0-9]{64}$/.test(source.sha256) ||
    !Number.isInteger(source.width) || !Number.isInteger(source.height)) {
    fail('invalid or duplicate source metadata')
  }
  const path = join(rawRoot, source.rawFile)
  const bytes = readFileSync(path)
  const digest = createHash('sha256').update(bytes).digest('hex')
  const dimensions = pngDimensions(bytes, source.rawFile)
  if (digest !== source.sha256 || dimensions.width !== source.width ||
    dimensions.height !== source.height) {
    fail(`${source.rawFile} identity does not match the manifest`)
  }
  sources.set(source.id, source)
}

const roles = new Set(['prose-control', 'artwork-positive', 'artwork-negative'])
const ids = new Set()
const counts = new Map([...roles].map((role) => [role, 0]))
for (const testCase of manifest.cases) {
  const source = sources.get(testCase.sourceId)
  if (typeof testCase.id !== 'string' || ids.has(testCase.id) || !source ||
    !roles.has(testCase.role) || !Array.isArray(testCase.bounds) ||
    testCase.bounds.length !== 4 ||
    typeof testCase.rotateCounterClockwise !== 'boolean' ||
    !Array.isArray(testCase.expectedVariants)) {
    fail('invalid or duplicate case metadata')
  }
  ids.add(testCase.id)
  counts.set(testCase.role, counts.get(testCase.role) + 1)
  const [left, top, right, bottom] = testCase.bounds
  if (![left, top, right, bottom].every(Number.isInteger) || left < 0 || top < 0 ||
    right <= left || bottom <= top || right > source.width || bottom > source.height) {
    fail(`${testCase.id} has out-of-range bounds`)
  }
  const variants = new Set(testCase.expectedVariants)
  if (variants.size !== testCase.expectedVariants.length ||
    [...variants].some((value) => typeof value !== 'string' || value.trim().length === 0)) {
    fail(`${testCase.id} has invalid expected variants`)
  }
  if (testCase.role === 'artwork-negative' ? variants.size !== 0 : variants.size === 0) {
    fail(`${testCase.id} expected variants do not match its role`)
  }
}

if (counts.get('artwork-positive') < 2 || counts.get('artwork-negative') < 5 ||
  counts.get('prose-control') < 8) {
  fail(`insufficient role coverage: ${JSON.stringify(Object.fromEntries(counts))}`)
}

console.log(
  `✓ comic artwork recognizer fixture: ${manifest.cases.length} cases ` +
    `(${counts.get('prose-control')} prose, ${counts.get('artwork-positive')} artwork, ` +
    `${counts.get('artwork-negative')} negative)`,
)
