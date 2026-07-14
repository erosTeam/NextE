#!/usr/bin/env node
/**
 * Contract: explicit AppStorageV2 aliases use only the characters accepted by ArkUI.
 *
 * These aliases are process-local UI state identities, not persisted preference keys. Invalid
 * aliases make AceStateMgmt emit a warning for every connect(), which becomes a main-thread log
 * storm when a long list constructs a page of reusable cards.
 */
import assert from 'node:assert'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SOURCE_ROOTS = ['entry', 'feature', 'shared']
const SKIPPED_DIRECTORIES = new Set(['.git', '.hvigor', 'build', 'oh_modules'])
const VALID_KEY = /^[A-Za-z0-9_]{1,255}$/
const STRING_CONSTANT = /(?:export\s+)?const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*string\s*=\s*(['"])([^'"\r\n]*)\2/g
const CONNECT_CALL = /AppStorageV2\.connect\s*\(/g
const CONNECT_KEY_ARGUMENT = /AppStorageV2\.connect\s*\(\s*[^,]+,\s*(?:(['"])([^'"\r\n]+)\1|([A-Za-z_$][A-Za-z0-9_$]*))/g

const etsFiles = []
const visit = (path) => {
  const stat = statSync(path)
  if (stat.isDirectory()) {
    for (const name of readdirSync(path)) {
      if (SKIPPED_DIRECTORIES.has(name)) {
        continue
      }
      visit(join(path, name))
    }
    return
  }
  if (path.endsWith('.ets')) {
    etsFiles.push(path)
  }
}

for (const sourceRoot of SOURCE_ROOTS) {
  visit(join(ROOT, sourceRoot))
}

let checked = 0
const seenKeys = new Map()
for (const path of etsFiles) {
  const source = readFileSync(path, 'utf8')
  const relativePath = path.slice(ROOT.length + 1)
  const constants = new Map()
  for (const match of source.matchAll(STRING_CONSTANT)) {
    constants.set(match[1], match[3])
  }

  const connectCount = Array.from(source.matchAll(CONNECT_CALL)).length
  const connectKeys = Array.from(source.matchAll(CONNECT_KEY_ARGUMENT))
  assert.equal(
    connectKeys.length,
    connectCount,
    `${relativePath} must expose every AppStorageV2.connect key as a string constant or literal`,
  )

  for (const match of connectKeys) {
    const key = match[2] ?? constants.get(match[3])
    assert.ok(key, `${relativePath} cannot resolve AppStorageV2 key ${match[3] ?? '<literal>'}`)
    assert.match(
      key,
      VALID_KEY,
      `${relativePath} contains invalid AppStorageV2 key ${JSON.stringify(key)}`,
    )
    assert.ok(
      !seenKeys.has(key),
      `${relativePath} reuses AppStorageV2 key ${JSON.stringify(key)} from ${seenKeys.get(key)}`,
    )
    seenKeys.set(key, relativePath)
    checked++
  }
}

assert.ok(checked > 0, 'expected to inspect explicit V2 storage aliases')
console.log(`✓ AppStorageV2 key contract passed (${checked} explicit aliases)`)
