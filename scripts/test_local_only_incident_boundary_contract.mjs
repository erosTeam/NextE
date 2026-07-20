#!/usr/bin/env node
/**
 * Contract: local incident notes must not become repository content or tracked-document dependencies.
 *
 * Run: node scripts/test_local_only_incident_boundary_contract.mjs
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const GIT_ROOT = ROOT.endsWith('/') ? ROOT.slice(0, -1) : ROOT
const INCIDENT_DIR = 'docs/agent-guides/incidents/'
const SELF = 'scripts/test_local_only_incident_boundary_contract.mjs'
const TRACKED_TEXT = /\.(md|txt|json|json5|ya?ml)$/i
const INCIDENT_FILE_REFERENCE = /(?:docs\/agent-guides\/)?incidents\/[^\s)"'<>]+\.md/gi

const tracked = execFileSync('git', [
  '-c', `safe.directory=${GIT_ROOT}`,
  '-C', GIT_ROOT,
  'ls-files',
  '-z',
], {
  cwd: GIT_ROOT,
  encoding: 'utf8',
}).split('\0').filter(Boolean)
const errors = []

for (const path of tracked) {
  if (path.startsWith(INCIDENT_DIR)) {
    errors.push(`tracked local incident file: ${path}`)
  }
  if (path === SELF || !TRACKED_TEXT.test(path)) {
    continue
  }
  const full = join(ROOT, path)
  if (!existsSync(full)) {
    continue
  }
  const text = readFileSync(full, 'utf8')
  const references = text.match(INCIDENT_FILE_REFERENCE) ?? []
  for (const reference of references) {
    errors.push(`tracked file ${path} references local incident: ${reference}`)
  }
}

if (errors.length > 0) {
  console.error(`✗ local-only incident boundary: ${errors.length} issue(s)`)
  for (const error of errors) {
    console.error(`  ${error}`)
  }
  process.exit(1)
}

console.log('✓ local-only incident boundary: no tracked incident files or file references')
