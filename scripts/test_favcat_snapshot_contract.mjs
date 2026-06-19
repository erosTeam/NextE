#!/usr/bin/env node
/**
 * Contract for persisted Favorites favcat selector metadata.
 *
 * Goal: after a successful favorites.php parse, NextE stores the real 0-9 favcat names/counts. On the
 * next cold start the pinned favcat bar can render those real labels before the network returns, while
 * the default "Favorites N" seed remains the fallback.
 *
 * Run: node scripts/test_favcat_snapshot_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const settings = read('shared/src/main/ets/settings/FavcatListSettings.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const favState = read('shared/src/main/ets/state/FavSelectionState.ets')
const favVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const favcatPage = read('feature/user/src/main/ets/components/FavcatPage.ets')
const favcatBar = read('entry/src/main/ets/components/FavcatBar.ets')
const favSelector = read('feature/user/src/main/ets/pages/FavoriteSelectorPage.ets')
const feController = read('../eros_fe/lib/pages/controller/favorite_sel_controller.dart')
const feConst = read('../eros_fe/lib/const/const.dart')

ok('FE favorite selector loads/persists favcat profile state',
  /_initFavItemBeans/.test(feController) && /Global\.profile[\s\S]*user\.copyWith\(favcat: value\.oN\)/.test(feController))
ok('FE has the 10 default favorite slots fallback',
  /static const List<Map<String, String>> favList/.test(feConst) && /Favorites 0/.test(feConst) && /Favorites 9/.test(feConst))
ok('FE computes the all-favorites count from remote slots only',
  /int get _allNetworkFavcatCount/.test(feController) &&
    /favcat\.favId != 'a' && favcat\.favId != 'l'/.test(feController) &&
    /totNum: _allNetworkFavcatCount/.test(feController))

ok('StorageKeys registers favorites.favcats',
  /static readonly FAVORITES_FAVCATS: string = 'favorites\.favcats'/.test(keys))
ok('FavcatListSettings is exported from shared barrel',
  /export \{ FavcatListSettings \} from '\.\/settings\/FavcatListSettings'/.test(sharedIndex))
ok('SettingsBootstrap restores FavcatListSettings before first page mount',
  /import \{ FavcatListSettings \} from '\.\/FavcatListSettings'/.test(bootstrap) &&
    /await FavcatListSettings\.restore\(context\)/.test(bootstrap))

ok('FavSelectionState still seeds fallback Favorites 0..9',
  /for \(let i = 0; i < 10; i\+\+\) \{[\s\S]*new Favcat\(`\$\{i\}`, `Favorites \$\{i\}`, 0\)/.test(favState))
ok('FavSelectionState computes all-favorites aggregate from remote 0-9 slots only',
  /remoteTotalCount\(\): number \{[\s\S]*FavSelectionState\.isRemoteSlot\(f\.favId\)[\s\S]*total \+= f\.totNum/.test(favState) &&
    /private static isRemoteSlot\(favId: string\): boolean \{[\s\S]*n >= 0 && n <= 9/.test(favState))
ok('FavcatListSettings writes restored snapshot into FavSelectionState',
  /connectFavSelection\(\)\.favList = restored/.test(settings))
ok('FavcatListSettings uses the shared preferences store and key',
  /preferences\.getPreferences\([\s\S]*StorageKeys\.STORE_SETTINGS/.test(settings) &&
    /StorageKeys\.FAVORITES_FAVCATS/.test(settings))
ok('FavcatListSettings persists only remote 0-9 slots',
  /isRemoteSlot\(f\.favId\)/.test(settings) && /n >= 0 && n <= 9/.test(settings))
ok('FavcatListSettings avoids persisting an empty snapshot over a good one',
  /if \(snap\.length === 0\) \{[\s\S]*return[\s\S]*\}/.test(settings))
ok('FavcatListSettings parses defensively and sorts by numeric favId',
  /JSON\.parse\(raw\)/.test(settings) &&
    /Array\.isArray\(parsed\)/.test(settings) &&
    /seen\.has\(favId\)/.test(settings) &&
    /out\.sort\(\(a: Favcat, b: Favcat\)/.test(settings))

ok('FavoritesViewModel can seed metadata before the network response',
  /seedFavList\(favcats: Favcat\[\]\): void \{[\s\S]*this\.favList\.length === 0[\s\S]*this\.mergeFavList\(favcats\)/.test(favVm))
ok('FavcatPage seeds each retained VM from the restored shared favList',
  /this\.vm\.seedFavList\(this\.favSel\.favList\)/.test(favcatPage))
ok('FavcatPage persists merged parsed favcats back to preferences',
  /FavcatListSettings\.persist\(this\.ctx\(\), merged\)/.test(favcatPage))
ok('FavcatPage obtains a UIAbilityContext for persistence',
  /private ctx\(\): common\.UIAbilityContext \{[\s\S]*this\.getUIContext\(\)\.getHostContext\(\) as common\.UIAbilityContext/.test(favcatPage))
ok('FavcatBar shows the synthetic all-favorites aggregate count',
  /new TabItem\('a',\s*\$r\('app\.string\.favorites_all'\),\s*this\.fav\.remoteTotalCount\(\)\)/.test(favcatBar) &&
    /new TabItem\(fc\.favId,\s*fc\.favTitle\)/.test(favcatBar))
ok('FavoriteSelectorPage shows the same aggregate for 全部',
  /new Favcat\('a',\s*AppStrings\.get\('favorites_all'\),\s*this\.fav\.remoteTotalCount\(\)\)/.test(favSelector))

// Executable mirror for the shape invariants.
const isRemoteSlot = (id) => {
  const n = Number.parseInt(id, 10)
  return `${n}` === id && n >= 0 && n <= 9
}
const snapshot = (favcats) =>
  favcats
    .filter((f) => isRemoteSlot(f.favId))
    .map((f) => ({
      favId: f.favId,
      favTitle: f.favTitle.length > 0 ? f.favTitle : `Favorites ${f.favId}`,
      totNum: f.totNum >= 0 ? f.totNum : 0,
    }))
const parse = (raw) => {
  const parsed = JSON.parse(raw)
  if (!Array.isArray(parsed)) return []
  const seen = new Set()
  const out = []
  for (const s of parsed) {
    const favId = typeof s.favId === 'string' ? s.favId : ''
    if (!isRemoteSlot(favId) || seen.has(favId)) continue
    seen.add(favId)
    out.push({
      favId,
      favTitle: typeof s.favTitle === 'string' && s.favTitle.length > 0 ? s.favTitle : `Favorites ${favId}`,
      totNum: typeof s.totNum === 'number' && s.totNum >= 0 ? s.totNum : 0,
    })
  }
  return out.sort((a, b) => Number.parseInt(a.favId, 10) - Number.parseInt(b.favId, 10))
}
const remoteTotalCount = (favcats) =>
  favcats.reduce((total, f) => (isRemoteSlot(f.favId) && f.totNum > 0 ? total + f.totNum : total), 0)
const snap = snapshot([
  { favId: 'a', favTitle: 'All', totNum: -1 },
  { favId: '2', favTitle: 'Manga', totNum: 609 },
  { favId: 'l', favTitle: 'Local', totNum: 3 },
  { favId: '0', favTitle: '', totNum: -5 },
])
assert.deepStrictEqual(snap, [
  { favId: '2', favTitle: 'Manga', totNum: 609 },
  { favId: '0', favTitle: 'Favorites 0', totNum: 0 },
])
assert.deepStrictEqual(parse(JSON.stringify(snap)), [
  { favId: '0', favTitle: 'Favorites 0', totNum: 0 },
  { favId: '2', favTitle: 'Manga', totNum: 609 },
])
assert.strictEqual(remoteTotalCount([
  { favId: 'a', favTitle: 'All', totNum: 999 },
  { favId: '2', favTitle: 'Manga', totNum: 609 },
  { favId: 'l', favTitle: 'Local', totNum: 3 },
  { favId: '0', favTitle: 'Default', totNum: 4 },
]), 613)
passed += 3

console.log(`✓ favcat snapshot contract: ${passed} assertions passed`)
