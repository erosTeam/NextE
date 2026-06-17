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
const agents = path.join(root, 'AGENTS.md')
const loop = path.join(root, 'docs', 'loop.md')
const harnessConfig = path.join(root, '.harness', 'config.json')

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
ok(py.includes('DEFAULT_DEVICE = "192.168.50.197:12345"'), 'default device is NextE .197')
ok(py.includes('NEXTE_DEVICE_LEASE_DIR'), 'NextE env var controls lease root')
ok(py.includes('default="NextE"'), 'project default is NextE')
ok(!py.includes('V2NEXT_DEVICE_LEASE_DIR'), 'no V2NEXT lease env remains in script')
ok(!py.includes('DEFAULT_DEVICE = "192.168.50.237:12345"'), 'no V2Next .237 default remains in script')

const shim = read(leaseShim)
ok(shim.includes('device_lease.py'), 'shell shim delegates to device_lease.py')

const doc = read(leaseDoc)
ok(doc.includes('192.168.50.197:12345'), 'docs mention NextE .197 device')
ok(doc.includes('NEXTE_DEVICE_LEASE_DIR'), 'docs mention NextE lease env var')
ok(doc.includes('scripts/device-lease acquire'), 'docs document acquire')
ok(doc.includes('scripts/device-lease run --lease'), 'docs document run wrapper')
ok(doc.includes('不要使用 --force'), 'docs forbid agent force takeover without approval')
ok(doc.includes('人工调试不受该机制限制'), 'docs preserve manual-debug boundary')
ok(!doc.includes('192.168.50.237:12345'), 'docs do not retain V2Next .237 target')
ok(!doc.includes('V2NEXT_DEVICE_LEASE_DIR'), 'docs do not retain V2Next env var')

const agentDoc = read(agents)
ok(agentDoc.includes('docs/device-lease.md'), 'AGENTS.md links device lease doc')

const loopDoc = read(loop)
ok(loopDoc.includes('node scripts/test_device_lease_contract.mjs'), 'docs/loop.md lists device lease contract')
ok(loopDoc.includes('scripts/device-lease'), 'docs/loop.md points agents to lease tool')

const harness = JSON.parse(read(harnessConfig))
ok(harness.gates.some((gate) => gate.name === 'device-lease' && gate.command === 'node scripts/test_device_lease_contract.mjs'), 'harness registers device-lease gate')

const tmpLeaseRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-device-lease-contract-'))
try {
  const status0 = run(leaseShim, ['status'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(status0.status === 1 && status0.stdout.includes('no active lease'), 'status reports no active lease in empty dir')

  const acquire = run(leaseShim, ['acquire', '--owner', 'contract:test', '--ttl', '30s', '--reason', 'contract smoke'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  const leaseId = acquire.stdout.trim()
  ok(acquire.status === 0 && /^\d{8}-\d{6}-[a-f0-9]{8}$/.test(leaseId), 'acquire returns lease id')

  const denied = run(leaseShim, ['acquire', '--owner', 'contract:other', '--ttl', '30s'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(denied.status === 2 && denied.stderr.includes('device lease denied'), 'second acquire is denied while lease active')

  const wrapped = run(leaseShim, ['run', '--lease', leaseId, '--', 'python3', '-c', 'print("wrapped-ok")'], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(wrapped.status === 0 && wrapped.stdout.trim() === 'wrapped-ok', 'run executes command under lease')

  const release = run(leaseShim, ['release', '--lease', leaseId], { NEXTE_DEVICE_LEASE_DIR: tmpLeaseRoot })
  ok(release.status === 0, 'release succeeds')
} finally {
  fs.rmSync(tmpLeaseRoot, { recursive: true, force: true })
}

if (failures > 0) {
  console.error(`device lease contract failed: ${failures}/${checks} assertions failed`)
  process.exit(1)
}

console.log(`✓ device lease contract: ${checks} assertions passed`)
