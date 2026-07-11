#!/usr/bin/env node
/**
 * Contract for local-block RDB persistence, migration, backup, and result-filter boundaries.
 *
 * UI placement, visual rendering, animation, and grounding records are intentionally outside this
 * contract. Those belong to source review and device-path validation instead of source-shape gates.
 */
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const src = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const ok = (cond, msg) => {
  if (!cond) {
    throw new Error(msg)
  }
}

const state = src('shared/src/main/ets/state/LocalBlockState.ets')
const settings = src('shared/src/main/ets/settings/LocalBlockSettings.ets')
const api = src('shared/src/main/ets/network/EhApiService.ets')
const favVm = src('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const bootstrap = src('shared/src/main/ets/settings/SettingsBootstrap.ets')
const keys = src('shared/src/main/ets/constants/StorageKeys.ets')

ok(state.includes('LOCAL_BLOCK_TYPE_TITLE') &&
  state.includes('LOCAL_BLOCK_TYPE_UPLOADER') &&
  state.includes('LOCAL_BLOCK_TYPE_COMMENTATOR') &&
  state.includes('LOCAL_BLOCK_TYPE_COMMENT'),
'state exposes the four local block rule buckets')
ok(keys.includes("LOCAL_BLOCK_RULES: string = 'localBlock.rules'"), 'legacy storage key exists for migration')
ok(bootstrap.includes('await LocalBlockSettings.restore(context)'), 'settings bootstrap restores local block rules')
ok(settings.includes('LocalBlockRepository.load(context)') &&
  settings.includes('LocalBlockRepository.upsertSettings(context, snapshot)') &&
  settings.includes('LocalBlockRepository.upsertRule(context, snapshot)') &&
  settings.includes('LocalBlockRepository.tombstoneRule(context, ruleId)') &&
  !settings.includes('store.putSync(StorageKeys.LOCAL_BLOCK_RULES'),
  'ordinary local block mutations persist through RDB rows, not Preferences JSON')
ok(settings.includes('migrateLegacyPreferences') &&
  settings.includes("store.getSync(StorageKeys.LOCAL_BLOCK_RULES, '')") &&
  settings.includes('store.deleteSync(StorageKeys.LOCAL_BLOCK_RULES)'),
  'legacy local block Preferences rows are migrated once')
{
  const migrationStart = settings.indexOf('static async migrateLegacyPreferences')
  const migrationEnd = settings.indexOf('static async setScoreFilter', migrationStart)
  const migration = settings.substring(migrationStart, migrationEnd)
  ok(/await LocalBlockSettings\.enqueueRdbWrite\([\s\S]*?LocalBlockRepository\.replaceAll\([\s\S]*?context,[\s\S]*?LocalBlockSettings\.parseSnapshot\(raw\)[\s\S]*?catch \(error\) \{[\s\S]*?local_block_migrate_failed[\s\S]*?return[\s\S]*?await LocalBlockSettings\.deleteLegacyPreference\(context\)/.test(migration),
    'failed legacy migration keeps its only Preferences copy; deletion happens only after the RDB replacement succeeds')
  ok(/const revision: number = LocalBlockSettings\.mutationRevision/.test(migration) &&
    /LocalBlockRepository\.hasPersistedState\(context\)/.test(migration) &&
    /revision !== LocalBlockSettings\.mutationRevision/.test(migration),
  'legacy JSON cannot overwrite an already canonical RDB row or an in-flight page mutation')
}
ok(settings.includes('snapshotEquals(LocalBlockSettings.current(), next)') &&
  settings.includes('local_block_apply_unchanged') &&
  settings.includes('local_block_version'),
  'unchanged local block restore/sync does not create a new persisted version')
{
  const store = src('shared/src/main/ets/storage/LocalDataStore.ets')
  const repo = src('shared/src/main/ets/storage/LocalBlockRepository.ets')
  ok(store.includes('CREATE TABLE IF NOT EXISTS local_block_settings') &&
    store.includes('CREATE TABLE IF NOT EXISTS local_block_rules') &&
    store.includes('position_index INTEGER'),
  'local block RDB tables exist')
  ok(repo.includes('ORDER BY position_index ASC, rule_id ASC') &&
    repo.includes('SQL_TOMBSTONE_RULE') &&
    repo.includes('ON CONFLICT(scope_key, rule_id) DO UPDATE'),
  'local block repository preserves order and uses per-rule tombstones')
  const replaceStart = repo.indexOf('static async replaceAll')
  const replaceEnd = repo.indexOf('\n  static async upsertSettings', replaceStart)
  const replaceAll = repo.substring(replaceStart, replaceEnd)
  ok(/store\.beginTransaction\(\)[\s\S]*?nextMutationTime\(store, Date\.now\(\)\)[\s\S]*?SQL_TOMBSTONE_SETTINGS[\s\S]*?SQL_TOMBSTONE_RULES[\s\S]*?SQL_RESTORE_UPSERT_SETTINGS[\s\S]*?store\.commit\(\)[\s\S]*?catch \(error\) \{[\s\S]*?store\.rollBack\(\)[\s\S]*?throw error as Error/.test(replaceAll),
    'local block full replacements are transactional, so a partial write cannot tombstone the prior snapshot')
  const backupTypes = src('shared/src/main/ets/backup/BackupTypes.ets')
  const backupAdapter = src('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
  ok(backupTypes.includes('localBlock: BackupLocalBlockSection') &&
    backupAdapter.includes('LocalBlockSettings.exportForBackup(context)') &&
    backupAdapter.includes('LocalBlockSettings.restoreBackup(context, localBlock)'),
  'backup localData includes local block rules')
}
{
  const scoreStart = settings.indexOf('static async setScoreFilter')
  const scoreEnd = settings.indexOf('\n  static async setCommentDisplayMode', scoreStart)
  const scoreMethod = settings.substring(scoreStart, scoreEnd)
  const modeStart = settings.indexOf('static async setCommentDisplayMode')
  const modeEnd = settings.indexOf('\n  static async upsertRule', modeStart)
  const modeMethod = settings.substring(modeStart, modeEnd)
  const upsertStart = settings.indexOf('static async upsertRule')
  const upsertEnd = settings.indexOf('\n  static async removeRule', upsertStart)
  const upsertMethod = settings.substring(upsertStart, upsertEnd)
  const removeStart = settings.indexOf('static async removeRule')
  const removeEnd = settings.indexOf('\n  static async setRuleEnabled', removeStart)
  const removeMethod = settings.substring(removeStart, removeEnd)
  const enabledStart = settings.indexOf('static async setRuleEnabled')
  const enabledEnd = settings.indexOf('\n  private static async persistSettings', enabledStart)
  const enabledMethod = settings.substring(enabledStart, enabledEnd)
  ok(/persistSettings\(context\)/.test(scoreMethod) && !/replaceAll/.test(scoreMethod) &&
    /persistSettings\(context\)/.test(modeMethod) && !/replaceAll/.test(modeMethod) &&
    /persistRule\(context, next\)/.test(upsertMethod) && !/replaceAll/.test(upsertMethod) &&
    /persistRuleRemoval\(context, ruleId\)/.test(removeMethod) && !/replaceAll/.test(removeMethod) &&
    /persistRule\(context, changed\)/.test(enabledMethod) && !/replaceAll/.test(enabledMethod),
  'ordinary score, display, rule edit, enable, and removal mutations touch only their durable row')
  ok(/private static rdbWriteTail: Promise<void> = Promise\.resolve\(\)/.test(settings) &&
    /private static mutationRevision: number = 0/.test(settings) &&
    /static async flushForSync\(_context: common\.UIAbilityContext\): Promise<void>/.test(settings) &&
    /refreshFromStorage[\s\S]*revision === LocalBlockSettings\.mutationRevision/.test(settings),
  'local block settings serialize writes, drain before export, and protect state from stale refreshes')
  ok(/exportForBackup[\s\S]*flushForSync\(context\)/.test(settings),
    'backup export drains pending incremental local block writes')
}
{
  const repo = src('shared/src/main/ets/storage/LocalBlockRepository.ets')
  const syncAdapter = src('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
  const syncService = src('shared/src/main/ets/sync/SyncService.ets')
  const huaweiCloud = src('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')
  ok(/static async upsertSettings[\s\S]*store\.beginTransaction\(\)[\s\S]*nextMutationTime[\s\S]*SQL_UPSERT_SETTINGS[\s\S]*store\.commit\(\)/.test(repo) &&
    /static async upsertRule[\s\S]*positionForUpsert[\s\S]*SQL_UPSERT_RULE[\s\S]*store\.commit\(\)/.test(repo) &&
    /static async tombstoneRule[\s\S]*SQL_TOMBSTONE_RULE[\s\S]*store\.commit\(\)/.test(repo) &&
    /SQL_SELECT_MAX_EFFECTIVE_TIME/.test(repo) &&
    !/DELETE FROM local_block_/.test(repo),
  'ordinary local block writes are transactional, logical-time ordered, and tombstone-safe')
  ok(/const SQL_UPSERT_SETTINGS[\s\S]*?WHERE excluded\.updated_at >=[\s\S]*?local_block_settings\.deleted_at/.test(repo) &&
    /const SQL_UPSERT_RULE[\s\S]*?WHERE excluded\.updated_at >=[\s\S]*?local_block_rules\.deleted_at/.test(repo) &&
    /SQL_APPLY_LOCAL_BLOCK_SETTINGS[\s\S]*WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /SQL_APPLY_LOCAL_BLOCK_RULE[\s\S]*WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter),
  'normal and remote local block writes reject older effective timestamps')
  ok(/mergeRemoteEnvelope[\s\S]*selection\.localBlock[\s\S]*LocalBlockSettings\.flushForSync\(context\)[\s\S]*exportEnvelope/.test(syncService) &&
    /cloudSyncNow[\s\S]*selection\.localBlock[\s\S]*LocalBlockSettings\.flushForSync\(context\)[\s\S]*markDistributedTables/.test(huaweiCloud),
  'WebDAV and Huawei providers drain pending local block writes before reading RDB')
}
ok(api.includes('filterLocalBlocked') &&
  api.includes('return this.filterLocalBlocked(this.filterHidden') &&
  api.includes('return this.filterLocalBlocked(list)'),
  'remote gallery list results pass through local block filtering')
ok(favVm.includes('LocalBlockService.filterGalleryList(cached.copy())') &&
  favVm.includes('!LocalBlockService.isGalleryBlocked(g)'),
  'favorites cached and local rows pass through local block filtering')

console.log('✓ local block contract: incremental persistence, migration, backup, sync, and result-filter boundaries locked')
