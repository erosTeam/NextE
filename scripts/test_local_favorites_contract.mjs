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
    /await LocalFavSettings\.refreshFromStorage\(context\)/.test(localSettings) &&
    /connectLocalFav\(\)\.items = items/.test(localSettings))
ok('LocalFavSettings retains full RDB replacement only for explicit gallery snapshots',
  /static async persist[\s\S]*enqueueRdbWrite[\s\S]*LocalFavoriteRepository\.replaceAll\([\s\S]*LocalFavSettings\.snapshotGalleries\(items\)/.test(localSettings) &&
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
const addStart = localSettings.indexOf('static async add')
const addEnd = localSettings.indexOf('\n  static async removeByGid', addStart)
const addMethod = localSettings.slice(addStart, addEnd)
const removeStart = localSettings.indexOf('static async removeByGid')
const removeEnd = localSettings.indexOf('\n  static contains', removeStart)
const removeMethod = localSettings.slice(removeStart, removeEnd)
ok('ordinary local-favorite add/remove touch only their own durable gid',
  /persistAdd\(context, prepared\)/.test(addMethod) &&
    !/persist\(context, next\)/.test(addMethod) &&
    /persistRemoval\(context, gid\)/.test(removeMethod) &&
    !/persist\(context, next\)/.test(removeMethod))
ok('local favorite repository serializes one-row mutations with logical timestamps and tombstones',
  /static async upsert\(context: common\.UIAbilityContext, item: EhGallery\): Promise<number>/.test(localRepo) &&
    /static async tombstone[\s\S]*SQL_TOMBSTONE_GID/.test(localRepo) &&
    /SQL_SELECT_MAX_EFFECTIVE_TIME/.test(localRepo) &&
    /WHERE excluded\.last_view_time >= CASE WHEN COALESCE\(local_favorites\.deleted_at, 0\) >/.test(localRepo) &&
    /INSERT INTO local_favorites \(scope_key, gid, last_view_time, deleted_at\)/.test(localRepo))
ok('legacy migration never lets a stale Preferences snapshot overwrite persisted favorite rows',
  /static async hasPersistedState[\s\S]*SQL_HAS_PERSISTED_STATE[\s\S]*return resultSet\.goToNextRow\(\)/.test(localRepo) &&
    /const revision: number = LocalFavSettings\.mutationRevision[\s\S]*if \(await LocalFavoriteRepository\.hasPersistedState\(context\)\) \{[\s\S]*return[\s\S]*\}[\s\S]*if \(revision !== LocalFavSettings\.mutationRevision\)[\s\S]*LocalFavoriteRepository\.replaceAll/.test(localSettings) &&
    /localfav_migrate_failed[\s\S]*Keep the only legacy copy intact/.test(localSettings))
ok('full local-favorite replacements remain transactional for backup and migration',
  /static async replaceAll[\s\S]*store\.beginTransaction\(\)[\s\S]*nextMutationTime\(store, Date\.now\(\)\)[\s\S]*SQL_TOMBSTONE_SCOPE[\s\S]*replacedAt \+ items\.length - i[\s\S]*SQL_RESTORE_UPSERT[\s\S]*store\.commit\(\)[\s\S]*catch \(error\) \{[\s\S]*store\.rollBack\(\)/.test(localRepo) &&
    /restoreBackup[\s\S]*LocalFavoriteRepository\.replaceAll/.test(localSettings) &&
    /migrateLegacyPreferences[\s\S]*LocalFavoriteRepository\.replaceAll/.test(localSettings))
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const syncService = read('shared/src/main/ets/sync/SyncService.ets')
const huaweiCloud = read('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')
ok('sync cannot overwrite a newer local favorite toggle with an older envelope',
  /SQL_APPLY_LOCAL_FAVORITE[\s\S]*WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /COALESCE\(local_favorites\.last_view_time, 0\)/.test(syncAdapter) &&
    /mergeRemoteEnvelope[\s\S]*selection\.localFavorites[\s\S]*LocalFavSettings\.flushForSync\(context\)[\s\S]*exportEnvelope/.test(syncService) &&
    /cloudSyncNow[\s\S]*selection\.localFavorites[\s\S]*LocalFavSettings\.flushForSync\(context\)[\s\S]*markDistributedTables/.test(huaweiCloud))
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
