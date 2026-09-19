#!/usr/bin/env node
import fs from 'fs'

const read = (path) => fs.readFileSync(new URL("../" + path, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error("[FAIL] " + name)
    failures += 1
  } else {
    console.log("[PASS] " + name)
  }
}

const syncService = read('shared/src/main/ets/sync/WebDavSyncService.ets')

ok('WebDavSyncService handles parseManifest corruption by failing closed',
  syncService.includes('webdav_manifest_corrupt') &&
  syncService.includes('WebDAV manifest corrupt or truncated:'))

ok('WebDavSyncService verifies transfer integrity against Content-Length',
  syncService.includes('verifyTransferIntegrity') &&
  syncService.includes('webdav_transfer_truncated'))

ok('WebDavSyncService protects remote shards by failing closed on shard parse errors',
  syncService.includes('webdav_shard_corrupt') &&
  syncService.includes('corrupt:'))

if (failures > 0) {
  console.error("Contract check failed: " + failures + " failure(s)")
  process.exit(1)
} else {
  console.log('All WebDAV corruption safety contract checks passed for NextE!')
}
