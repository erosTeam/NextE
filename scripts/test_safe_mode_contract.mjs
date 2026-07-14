#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const assert = (condition, message) => {
  if (!condition) {
    console.error(`FAIL: ${message}`)
    process.exitCode = 1
  }
}

const safeFlag = read('shared/src/main/ets/safe/SafeModeBuildFlag.ets')
assert(
  safeFlag.includes('SAFE_MODE_BUILD_ENABLED: boolean = false'),
  'normal source default must keep safe mode disabled',
)

const buildScript = read('scripts/build_hvigor_signed.sh')
assert(buildScript.includes('NEXTE_SAFE_MODE'), 'signed build must expose NEXTE_SAFE_MODE')
assert(
  buildScript.includes('SAFE_MODE_BUILD_ENABLED: boolean = true') &&
    buildScript.includes('restore_build_flags'),
  'safe-mode build flag must be temporary and restored after build',
)

const gate = read('shared/src/main/ets/safe/SafeModeGate.ets')
assert(gate.includes("SAFE_MODE_PROFILE_UUID: string = 'safe-mode-noh'"), 'safe profile uuid is stable')
assert(gate.includes("SAFE_MODE_PROFILE_NAME: string = 'NoH'"), 'safe profile label is NoH')
assert(gate.includes('SAFE_MODE_NON_H_SELECTED_CATS: number = 256'), 'safe profile must include only Non-H')
for (const blocked of [
  "'Search'",
  "'EhLogin'",
  "'AccountLogin'",
  "'FavoriteSelector'",
  "'TabManager'",
  "'GalleryComments'",
  "'SyncSettings'",
]) {
  assert(gate.includes(blocked), `routeAllowed must block ${blocked}`)
}

if (process.exitCode) {
  process.exit(process.exitCode)
}

console.log('safe mode contract: OK')
