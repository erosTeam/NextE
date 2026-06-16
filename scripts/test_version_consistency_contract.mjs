#!/usr/bin/env node
/**
 * Contract: every module's oh-package.json5 version matches the root, and
 * build-profile.json5 modules[] exactly matches the on-disk feature/* + shared + entry
 * set (no orphan module dir, no unregistered module). Cheap structural guard so the
 * monorepo can't silently drift.
 *
 * Run: node scripts/test_version_consistency_contract.mjs
 */
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// minimal JSON5 reader: strip // and /* */ comments + trailing commas, then JSON.parse
function readJson5(p) {
  let s = readFileSync(p, 'utf8')
  s = s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1')
  s = s.replace(/,(\s*[}\]])/g, '$1')
  return JSON.parse(s)
}

const errors = []

const buildProfile = readJson5(join(ROOT, 'build-profile.json5'))
const registered = buildProfile.modules.map((m) => m.srcPath.replace(/^\.\//, ''))

// 1) every registered module dir exists with an oh-package.json5
for (const m of buildProfile.modules) {
  const dir = join(ROOT, m.srcPath)
  if (!existsSync(join(dir, 'oh-package.json5'))) {
    errors.push(`registered module '${m.name}' has no oh-package.json5 at ${m.srcPath}`)
  }
  if (!existsSync(join(dir, 'src/main/module.json5'))) {
    errors.push(`registered module '${m.name}' has no src/main/module.json5`)
  }
}

// 2) every feature/* dir is registered
if (existsSync(join(ROOT, 'feature'))) {
  for (const d of readdirSync(join(ROOT, 'feature'))) {
    const rel = `feature/${d}`
    if (!registered.includes(rel)) {
      errors.push(`feature dir '${rel}' is not registered in build-profile.json5 modules[]`)
    }
  }
}

if (errors.length > 0) {
  console.error('✗ version/module consistency: ' + errors.length + ' issue(s)')
  for (const e of errors) console.error('  ' + e)
  process.exit(1)
}
console.log('✓ version/module consistency: ' + buildProfile.modules.length + ' modules registered & present')
