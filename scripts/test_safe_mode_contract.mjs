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

const index = read('entry/src/main/ets/pages/Index.ets')
assert(index.includes('SafeModeGate.routeAllowed(name)'), 'navigation router must use SafeModeGate')
assert(index.includes('this.safeMode.restricted()') && index.includes('safeGalleryMenu'), 'root shell must gate safe-mode tabs and menu')
assert(index.includes('this.searchAction.clearPending()'), 'global search command must be consumed in safe mode')
assert(index.includes('idx === 1 ? 3') && index.includes('idx === 2 ? 4'), 'safe download/settings tabs must use their normal glyphs')

const home = read('feature/home/src/main/ets/pages/HomePage.ets')
assert(home.includes('SAFE_MODE_PROFILE_UUID') && home.includes('return [SAFE_MODE_PROFILE_UUID]'), 'home source keys must collapse to NoH')

const sourceBar = read('entry/src/main/ets/components/HomeSourceBar.ets')
assert(sourceBar.includes('SAFE_MODE_PROFILE_NAME') && sourceBar.includes('!this.safeMode.restricted()'), 'source bar must show only NoH and hide manager action')

const sourcePage = read('feature/home/src/main/ets/components/GallerySourcePage.ets')
assert(sourcePage.includes('SafeModeGate.safeProfile()'), 'safe source must use a real CustomProfile query path')

const settings = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
assert(settings.includes('if (!this.safeMode.restricted())'), 'settings root must hide restricted entries')
assert(settings.includes("pushPathByName('About'"), 'about must remain reachable for unlock')

const cacheSettings = read('feature/settings/src/main/ets/pages/CacheSettingsPage.ets')
assert(cacheSettings.includes('SafeModeState') && cacheSettings.includes("pushPathByName('SyncSettings'"), 'cache settings still owns normal sync entry')
assert(/if \(!this\.safeMode\.restricted\(\)\)[\s\S]*pushPathByName\('SyncSettings'/.test(cacheSettings), 'cache settings sync entry must be hidden in safe mode')

const layoutSettings = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets')
assert(layoutSettings.includes('SafeModeState') && layoutSettings.includes("pushPathByName('TagTranslationSettings'"), 'layout settings still owns normal tag translation entry')
assert(/if \(!this\.safeMode\.restricted\(\)\)[\s\S]*pushPathByName\('TagTranslationSettings'/.test(layoutSettings), 'layout tag translation entry must be hidden in safe mode')

const about = read('feature/settings/src/main/ets/pages/AboutPage.ets')
assert(about.includes('safeModeTapCount < 5'), 'about version must require five taps')
assert(about.includes('SafeModeSettings.unlock'), 'about version tap must unlock safe mode')

if (process.exitCode) {
  process.exit(process.exitCode)
}

console.log('safe mode contract: OK')
