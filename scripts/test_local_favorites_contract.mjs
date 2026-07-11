#!/usr/bin/env node
/**
 * Contract for the first-stage local Favorites slot.
 *
 * Grounding:
 * - eros_fe/lib/common/controller/localfav_controller.dart keeps a local gallery list and persists it
 *   in the user profile.
 * - eros_fe/lib/pages/tab/controller/favorite/favorite_sublist_controller.dart returns that local list
 *   when favcat == 'l', without requesting favorites.php.
 * - NextE keeps the same user-visible `l` slot while using AppStorageV2 + RDB and the retained
 *   subtab host already used by Favorites.
 *
 * Run: node scripts/test_local_favorites_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const localState = read('shared/src/main/ets/state/LocalFavState.ets')
const localSettings = read('shared/src/main/ets/settings/LocalFavSettings.ets')
const storageKeys = read('shared/src/main/ets/constants/StorageKeys.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const vm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const page = read('feature/user/src/main/ets/pages/FavoritesPage.ets')
const favcatPage = read('feature/user/src/main/ets/components/FavcatPage.ets')
const bar = read('entry/src/main/ets/components/FavcatBar.ets')
const index = read('entry/src/main/ets/pages/Index.ets')

const locales = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('LocalFavState is V2 and stores EhGallery items',
  /@ObservedV2[\s\S]*class LocalFavState[\s\S]*@Trace items: EhGallery\[\] = \[\]/.test(localState))
ok('LocalFavState connects through AppStorageV2',
  /AppStorageV2\.connect\(LocalFavState, LOCAL_FAV_V2_KEY/.test(localState))
ok('Local favorites preference key is centralized',
  /LOCAL_FAVORITES: string = 'favorites\.local'/.test(storageKeys))
ok('LocalFavSettings restores into LocalFavState',
  /LocalFavoriteRepository\.load\(context\)/.test(localSettings) &&
    /connectLocalFav\(\)\.items = await LocalFavoriteRepository\.load\(context\)/.test(localSettings))
ok('LocalFavSettings persists gallery snapshots through RDB',
  /LocalFavoriteRepository\.replaceAll\(context, LocalFavSettings\.snapshotGalleries\(items\)\)/.test(localSettings) &&
    !/store\.putSync\(StorageKeys\.LOCAL_FAVORITES/.test(localSettings))
ok('legacy local favorite Preferences rows are migrated once',
  /migrateLegacyPreferences/.test(localSettings) &&
    /store\.getSync\(StorageKeys\.LOCAL_FAVORITES, ''\)/.test(localSettings) &&
    /store\.deleteSync\(StorageKeys\.LOCAL_FAVORITES\)/.test(localSettings))
const localRepo = read('shared/src/main/ets/storage/LocalFavoriteRepository.ets')
const localStore = read('shared/src/main/ets/storage/LocalDataStore.ets')
ok('local favorites RDB table exists',
  /CREATE TABLE IF NOT EXISTS local_favorites/.test(localStore) &&
    /last_view_time INTEGER/.test(localStore) &&
    /deleted_at INTEGER DEFAULT 0/.test(localStore))
ok('local favorite repository loads newest-first and tombstones scoped rows',
  /ORDER BY last_view_time DESC, gid DESC/.test(localRepo) &&
    /UPDATE local_favorites SET deleted_at = \?/.test(localRepo) &&
    /ON CONFLICT\(scope_key, gid\) DO UPDATE/.test(localRepo))
const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
ok('backup localData includes local favorites',
  /localFavorites: BackupLocalFavoriteEntry\[\]/.test(backupTypes) &&
    /LocalFavSettings\.exportForBackup\(context\)/.test(backupAdapter) &&
    /LocalFavSettings\.restoreBackup\(context, favorites\)/.test(backupAdapter))
ok('SettingsBootstrap restores local favorites at startup',
  /LocalFavSettings\.restore\(context\)/.test(bootstrap))
ok('Shared barrel exports local favorites state and settings',
  /export \{ LocalFavState, connectLocalFav \}/.test(sharedIndex) &&
  /export \{ LocalFavSettings \}/.test(sharedIndex))

ok('FavoritesViewModel has an explicit local favcat branch',
  /private isLocalFavcat\(\): boolean \{[\s\S]*return this\.favcat === 'l'/.test(vm))
ok('Local favorites load reads AppStorageV2 rows and never pages',
  /this\.hasMore = false[\s\S]*if \(this\.isLocalFavcat\(\)\) \{[\s\S]*connectLocalFav\(\)\.items[\s\S]*const translated: EhGallery\[\] = await this\.translateRows\(localRows\)[\s\S]*this\.dataSource\.setData\(translated\)[\s\S]*return true/.test(vm))
ok('Local favorites loadMore is a no-op',
  /if \(this\.isLocalFavcat\(\) \|\| this\.isLoading/.test(vm))
ok('Local favorites order changes are no-ops',
  /async applyOrder[\s\S]*if \(this\.isLocalFavcat\(\)\) \{[\s\S]*return/.test(vm))

ok('FavoritesPage logged out key set is local only',
  /if \(!this\.auth\.isLogin\) \{[\s\S]*return \['l'\]/.test(page))
ok('FavoritesPage logged in key set includes local after remote slots',
  /const keys: string\[\] = \['a'\][\s\S]*this\.favSel\.favList\.forEach[\s\S]*keys\.push\('l'\)/.test(page))
ok('FavoritesPage passes an effective selected key to retained host',
  /selectedKey: this\.effectiveSelectedFavcat\(\)/.test(page))
ok('FavoritesPage no longer gates the whole tab with login error state',
  !/PageErrorState\(\{[\s\S]*favorites_login_hint/.test(page))
ok('FavcatPage reloads the retained local page when local favorites change',
  /@Local localFav: LocalFavState = connectLocalFav\(\)/.test(favcatPage) &&
  /@Monitor\('localFav\.items'\)[\s\S]*if \(this\.loadedOnce && this\.favcatKey === 'l'\) \{[\s\S]*await this\.vm\.load\(\)/.test(favcatPage))

ok('FavcatBar logged out tab list is local only',
  /if \(!this\.auth\.isLogin\) \{[\s\S]*new TabItem\('l', \$r\('app\.string\.favorites_local'\), this\.localFav\.count\(\), EhConstants\.favCatColor\('l'\)\)/.test(bar))
ok('FavcatBar logged in tabs append local slot',
  /items\.push\(new TabItem\('l', \$r\('app\.string\.favorites_local'\), this\.localFav\.count\(\), EhConstants\.favCatColor\('l'\)\)\)/.test(bar))
ok('Index always pins the Favorites favcat bottomBuilder',
  /content\['bottomBuilder'\] = this\.bottomBuilder\(this\.favcatBarContent\)[\s\S]*if \(this\.auth\.isLogin\) \{[\s\S]*content\['menu'\] = this\.favoritesMenu\(\)/.test(index))
ok('Index does not expose remote favorites actions while logged out',
  /if \(this\.auth\.isLogin\) \{[\s\S]*content\['menu'\] = this\.favoritesMenu\(\)[\s\S]*\} else \{[\s\S]*content\['menu'\] = this\.emptyMenu\(\)/.test(index))

for (const file of locales) {
  ok(`${file} defines favorites_local`, /"name": "favorites_local"/.test(read(file)))
}

console.log(`✓ local favorites contract: ${passed} assertions passed`)
