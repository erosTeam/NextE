#!/usr/bin/env node
/**
 * Contract: Mac harness/build signing uses the official DevEco/Hvigor path.
 *
 * NextE's old Linux workflow used dev.sh. On the migrated macOS host, harness
 * build verification must not call dev.sh, and harness hooks must not fall back
 * to stale /home/gamer plugin paths from the old desktop.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let passed = 0
const ok = (cond, msg) => {
  assert.ok(cond, msg)
  passed++
}
const eq = (got, want, msg) => {
  assert.strictEqual(got, want, msg)
  passed++
}

const config = JSON.parse(read('.harness/config.json'))
eq(config.buildCmd, 'bash scripts/build_hvigor_signed.sh', 'harness buildCmd uses official signed Hvigor wrapper')
ok(!config.buildCmd.includes('dev.sh'), 'harness buildCmd does not call dev.sh')
ok(
  config.gates.some(
    (gate) =>
      gate.name === 'mac-harness-signing' &&
      gate.command === 'node scripts/test_mac_harness_signing_contract.mjs' &&
      gate.blocking === true,
  ),
  'harness registers mac-harness-signing gate',
)

const hook = read('.harness/hooks/pre-commit')
ok(hook.includes('command -v harness-verify'), 'harness hook probes harness-verify from PATH')
ok(!hook.includes('/home/gamer'), 'harness hook does not contain stale /home/gamer fallback')
ok(!hook.includes('plugins/cache/harness-kit'), 'harness hook does not contain baked plugin cache fallback')
ok(hook.includes('exit 127'), 'harness hook fails loudly when harness-verify is unavailable')

const build = read('scripts/build_hvigor_signed.sh')
ok(build.includes('DevEco-Studio.app'), 'signed build wrapper knows the macOS DevEco app path')
ok(build.includes('hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon'), 'signed build wrapper runs the official Hvigor command')
ok(!build.includes('dev.sh'), 'signed build wrapper does not call dev.sh')
ok(build.includes('signingConfigs'), 'signed build wrapper checks that local signing config is installed')
ok(build.includes('scripts/setup-local-build-profile.sh'), 'signed build wrapper tells operators how to install local build-profile signing')

for (const rel of ['README.md', 'CLAUDE.md', 'docs/loop.md']) {
  const doc = read(rel)
  ok(doc.includes('scripts/build_hvigor_signed.sh'), `${rel} documents the macOS Hvigor wrapper`)
  ok(doc.includes('setup-local-build-profile.sh'), `${rel} documents local build-profile setup`)
}
ok(/Do \*\*not\*\* use `dev\.sh` on macOS/.test(read('CLAUDE.md')), 'CLAUDE.md explicitly forbids dev.sh on macOS')
ok(/`dev\.sh` 是 Linux legacy helper,不要在 macOS 上使用/.test(read('README.md')), 'README.md explicitly labels dev.sh as Linux legacy for macOS users')

console.log(`✓ mac harness signing contract: ${passed} assertions passed`)
