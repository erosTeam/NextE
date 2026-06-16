#!/usr/bin/env node
/**
 * Contract: the device-QA tooling must keep the target awake on every path that drives the device,
 * so a dimmed/asleep screen can't break aa start / hilog / screenshot / deep-link capture. This
 * regressed once (dev.sh --launch / --log ran `hdc shell` directly, bypassing keep-awake), so it is
 * locked structurally here.
 *
 * Coverage required:
 *   • dev.sh defines a keep_awake() wrapper that calls scripts/keep_awake.sh and honors HDC_TARGET;
 *   • dev.sh --launch and --log call keep_awake BEFORE the hdc shell command;
 *   • the default install path keeps-awake via scripts/sign.py (the `*)` case runs sign.py, and
 *     sign.py keeps-awake both before and after install);
 *   • scripts/keep_awake.sh issues the power-shell wakeup + timeout override.
 *
 * Run: node scripts/test_devsh_keepawake_contract.mjs   (exit 1 on any failure)
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    failures++
    console.error(`✗ ${msg}`)
  }
}

// Extract a shell `case` arm body: text between `<label>)` and the next `;;`.
function caseArm(src, label) {
  const re = new RegExp(`${label.replace(/[|]/g, '\\|')}\\)`)
  const m = re.exec(src)
  if (!m) return ''
  const start = m.index + m[0].length
  const end = src.indexOf(';;', start)
  return end >= 0 ? src.slice(start, end) : src.slice(start)
}

const devsh = read('dev.sh')
const signpy = read('scripts/sign.py')
const keepawake = read('scripts/keep_awake.sh')

// 1. dev.sh keep_awake() wrapper.
ok(/keep_awake\(\)\s*\{/.test(devsh), 'dev.sh defines a keep_awake() wrapper')
const wrapper = (() => {
  const m = /keep_awake\(\)\s*\{/.exec(devsh)
  if (!m) return ''
  const start = m.index
  const end = devsh.indexOf('\n}', start)
  return end >= 0 ? devsh.slice(start, end) : ''
})()
ok(/keep_awake\.sh/.test(wrapper), 'dev.sh keep_awake() invokes scripts/keep_awake.sh')
ok(/HDC_TARGET/.test(wrapper), 'dev.sh keep_awake() honors HDC_TARGET')

// 2. --launch and --log call keep_awake BEFORE the hdc shell command.
const launch = caseArm(devsh, '--launch')
ok(/keep_awake/.test(launch), 'dev.sh --launch calls keep_awake')
ok(/aa start/.test(launch), 'dev.sh --launch still runs aa start')
ok(
  launch.indexOf('keep_awake') >= 0 &&
    launch.indexOf('keep_awake') < launch.indexOf('aa start'),
  'dev.sh --launch calls keep_awake BEFORE aa start',
)

const log = caseArm(devsh, '--log')
ok(/keep_awake/.test(log), 'dev.sh --log calls keep_awake')
ok(/hilog/.test(log), 'dev.sh --log still runs hilog')
ok(
  log.indexOf('keep_awake') >= 0 && log.indexOf('keep_awake') < log.indexOf('hilog'),
  'dev.sh --log calls keep_awake BEFORE hilog',
)

// 3. Default install path keeps-awake via sign.py.
const def = caseArm(devsh, '\\*')
ok(/sign\.py/.test(def), 'dev.sh default install path runs scripts/sign.py (keep-awake via sign.py)')

// 4. sign.py install hooks: keep_awake defined, referenced via keep_awake.sh, called before + after install.
ok(/def keep_awake\(/.test(signpy), 'sign.py defines keep_awake()')
ok(/KEEP_AWAKE\s*=.*keep_awake\.sh/.test(signpy), 'sign.py wires KEEP_AWAKE to scripts/keep_awake.sh')
ok(/def install_hap[\s\S]*?keep_awake\(dev\)/.test(signpy), 'sign.py keeps-awake AFTER install (install_hap)')
ok((signpy.match(/keep_awake\(dev\)/g) || []).length >= 2, 'sign.py keeps-awake both before and after install (>=2 keep_awake(dev) calls)')

// 5. keep_awake.sh issues the power management commands.
ok(/power-shell wakeup/.test(keepawake), 'keep_awake.sh issues power-shell wakeup')
ok(/power-shell timeout -o/.test(keepawake), 'keep_awake.sh issues power-shell timeout override')

if (failures === 0) {
  console.log('✓ dev.sh keep-awake contract: launch/log/default-install + sign.py + keep_awake.sh all keep the device awake')
  process.exit(0)
}
console.error(`✗ dev.sh keep-awake contract: ${failures} failure(s)`)
process.exit(1)
