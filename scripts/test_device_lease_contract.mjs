#!/usr/bin/env node
/**
 * Contract: NextE agent-controlled device operations must use the advisory device lease.
 * Run: node scripts/test_device_lease_contract.mjs
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..')
const leaseShim = path.join(root, 'scripts', 'device-lease')
const leasePy = path.join(root, 'scripts', 'device_lease.py')
const leaseDoc = path.join(root, 'docs', 'device-lease.md')

let failures = 0
let checks = 0

function ok(condition, message) {
  checks += 1
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  }
}

function read(file) {
  return fs.readFileSync(file, 'utf8')
}

function run(command, args, env = {}) {
  return spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    env: { ...process.env, ...env },
  })
}

ok(fs.existsSync(leaseShim), 'scripts/device-lease exists')
ok(fs.existsSync(leasePy), 'scripts/device_lease.py exists')
ok(fs.existsSync(leaseDoc), 'docs/device-lease.md exists')
ok((fs.statSync(leaseShim).mode & 0o111) !== 0, 'scripts/device-lease is executable')
ok((fs.statSync(leasePy).mode & 0o111) !== 0, 'scripts/device_lease.py is executable')

const py = read(leasePy)
ok(!py.includes('DEFAULT_DEVICE'), 'device lease helper has no default target')
ok(py.includes('"--device"') && py.includes('required=True'), 'device target is mandatory')
ok(py.includes('NEXTE_DEVICE_LEASE_DIR'), 'NextE env var controls lease root')
ok(py.includes('default="NextE"'), 'project default is NextE')

const shim = read(leaseShim)
ok(shim.includes('device_lease.py'), 'shell shim delegates to device_lease.py')

const doc = read(leaseDoc)
ok(doc.includes('没有默认设备'), 'docs forbid a default target')
ok(doc.includes('scripts/device-lease --device "$TARGET"'), 'docs require explicit target')
ok(doc.includes('获取 lease 不构成用户对任意设备操作的许可'), 'docs separate lease from authorization')
ok(doc.includes('`--force` 仅能在用户明确批准后使用'), 'docs forbid unapproved force takeover')

const tmpLeaseRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-device-lease-contract-'))
try {
  const target = 'contract-device'
  const missingTarget = run(leaseShim, ['status'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(missingTarget.status === 2 && missingTarget.stderr.includes('--device'), 'missing explicit target is rejected')

  const status0 = run(leaseShim, ['--device', target, 'status'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(status0.status === 1 && status0.stdout.includes('no active lease'), 'status reports no active lease in empty dir')

  const acquire = run(leaseShim, ['--device', target, 'acquire', '--owner', 'contract:test', '--ttl', '30s', '--reason', 'contract smoke'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  const leaseId = acquire.stdout.trim()
  ok(acquire.status === 0 && /^\d{8}-\d{6}-[a-f0-9]{8}$/.test(leaseId), 'acquire returns lease id')

  const denied = run(leaseShim, ['--device', target, 'acquire', '--owner', 'contract:other', '--ttl', '30s'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(denied.status === 2 && denied.stderr.includes('device lease denied'), 'second acquire is denied while lease active')

  const wrapped = run(leaseShim, ['--device', target, 'run', '--lease', leaseId, '--', 'python3', '-c', 'print("wrapped-ok")'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(wrapped.status === 0 && wrapped.stdout.trim() === 'wrapped-ok', 'run executes command under lease')

  const release = run(leaseShim, ['--device', target, 'release', '--lease', leaseId], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(release.status === 0, 'release succeeds')
} finally {
  fs.rmSync(tmpLeaseRoot, { recursive: true, force: true })
}

if (failures > 0) {
  console.error(`device lease contract failed: ${failures}/${checks} assertions failed`)
  process.exit(1)
}

console.log(`✓ device lease contract: ${checks} assertions passed`)
