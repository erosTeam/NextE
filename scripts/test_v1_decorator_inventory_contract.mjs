#!/usr/bin/env node
/**
 * Hard gate (ported from V2Next): State Management V1 is retired in NextE.
 * Scans repository module roots (excluding DevEco-generated intermediates) for LIVE V1 component/state decorators
 * and fails (exit 1) if any are found. Must report `0 file(s)` before merge/push for any
 * ArkTS/UI/state change.
 *
 * Run: node scripts/test_v1_decorator_inventory_contract.mjs
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SCAN_DIRS = ['entry', 'shared', 'feature']

// V1 decorators that are forbidden. Each must NOT be immediately followed by `V2` (so
// @ComponentV2 / @ObservedV2 are allowed) and must be a decorator use (`@Name`).
const V1 = [
  'Component', 'State', 'Prop', 'Link', 'Watch', 'StorageLink', 'StorageProp',
  'Provide', 'Consume', 'ObjectLink', 'Observed', 'Track',
  'LocalStorageLink', 'LocalStorageProp',
]
const V1_RE = new RegExp('@(' + V1.join('|') + ')\\b(?!V2)', 'g')

function walk(dir, out) {
  let entries
  try {
    entries = readdirSync(dir)
  } catch {
    return out
  }
  for (const name of entries) {
    const p = join(dir, name)
    const s = statSync(p)
    if (s.isDirectory()) {
      // DevEco writes its ohosTest compatibility page under `<module>/.test/`.
      // It is a generated toolchain intermediate, not project source; do not mistake its
      // legacy decorators for a V1 regression in the tracked ArkTS code.
      if (name === 'build' || name === '.test' || name === 'oh_modules' || name === 'node_modules') continue
      walk(p, out)
    } else if (name.endsWith('.ets')) {
      out.push(p)
    }
  }
  return out
}

const files = []
for (const d of SCAN_DIRS) walk(join(ROOT, d), files)

const offenders = []
for (const f of files) {
  const text = readFileSync(f, 'utf8')
  const lines = text.split('\n')
  lines.forEach((line, i) => {
    // ignore comment lines
    const trimmed = line.trim()
    if (trimmed.startsWith('//') || trimmed.startsWith('*')) return
    V1_RE.lastIndex = 0
    let m
    while ((m = V1_RE.exec(line)) !== null) {
      offenders.push(`${relative(ROOT, f)}:${i + 1}  @${m[1]}`)
    }
  })
}

if (offenders.length > 0) {
  console.error('✗ V1 decorator inventory: ' + offenders.length + ' occurrence(s) in ' +
    new Set(offenders.map((o) => o.split(':')[0])).size + ' file(s)')
  for (const o of offenders) console.error('  ' + o)
  process.exit(1)
}
console.log('✓ V1 decorator inventory: 0 file(s) with live V1 decorators (scanned ' + files.length + ' .ets)')
