#!/usr/bin/env node

import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { spawnSync } from 'node:child_process'

const root = process.cwd()
const flagPath = 'shared/src/main/ets/services/ClipboardLinkBuildFlag.ets'
const modulePath = 'entry/src/main/module.json5'
const workflowPath = '.github/workflows/build.yml'
const scriptPath = 'scripts/prepare_public_clipboard_build.py'

function ok(condition, message) {
  if (!condition) {
    throw new Error(message)
  }
}

const sourceFlag = readFileSync(join(root, flagPath), 'utf8')
const sourceModule = readFileSync(join(root, modulePath), 'utf8')
const workflow = readFileSync(join(root, workflowPath), 'utf8')
ok(sourceFlag.includes('CLIPBOARD_LINK_BUILD_ENABLED: boolean = true'), 'full source build must enable clipboard detection')
ok(sourceModule.includes('ohos.permission.READ_PASTEBOARD'), 'full source build must declare READ_PASTEBOARD')
ok(workflow.includes('python3 scripts/prepare_public_clipboard_build.py'), 'public CI must run clipboard preparation')

const fixture = mkdtempSync(join(tmpdir(), 'nexte-public-clipboard-'))
try {
  for (const relative of [flagPath, modulePath]) {
    const target = join(fixture, relative)
    mkdirSync(dirname(target), { recursive: true })
    cpSync(join(root, relative), target)
  }
  const result = spawnSync('python3', [join(root, scriptPath), '--root', fixture], { encoding: 'utf8' })
  ok(result.status === 0, `public clipboard preparation failed: ${result.stderr || result.stdout}`)
  const publicFlag = readFileSync(join(fixture, flagPath), 'utf8')
  const publicModule = readFileSync(join(fixture, modulePath), 'utf8')
  ok(publicFlag.includes('CLIPBOARD_LINK_BUILD_ENABLED: boolean = false'), 'public build must disable clipboard detection')
  ok(!publicModule.includes('ohos.permission.READ_PASTEBOARD'), 'public build must remove READ_PASTEBOARD')
} finally {
  rmSync(fixture, { recursive: true, force: true })
}

console.log('✓ public clipboard build contract passed')
