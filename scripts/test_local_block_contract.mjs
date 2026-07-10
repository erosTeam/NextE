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
  settings.includes('LocalBlockRepository.replaceAll(context, LocalBlockSettings.current())') &&
  !settings.includes('store.putSync(StorageKeys.LOCAL_BLOCK_RULES'),
  'local block rules persist through RDB, not Preferences JSON')
ok(settings.includes('migrateLegacyPreferences') &&
  settings.includes("store.getSync(StorageKeys.LOCAL_BLOCK_RULES, '')") &&
  settings.includes('store.deleteSync(StorageKeys.LOCAL_BLOCK_RULES)'),
  'legacy local block Preferences rows are migrated once')
{
  const migrationStart = settings.indexOf('static async migrateLegacyPreferences')
  const migrationEnd = settings.indexOf('static async setScoreFilter', migrationStart)
  const migration = settings.substring(migrationStart, migrationEnd)
  ok(/await LocalBlockRepository\.replaceAll\(context, LocalBlockSettings\.parseSnapshot\(raw\)\)[\s\S]*?catch \(error\) \{[\s\S]*?local_block_migrate_failed[\s\S]*?return[\s\S]*?await LocalBlockSettings\.deleteLegacyPreference\(context\)/.test(migration),
    'failed legacy migration keeps its only Preferences copy; deletion happens only after the RDB replacement succeeds')
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
    repo.includes('UPDATE local_block_settings SET deleted_at = ?, updated_at = ?') &&
    repo.includes('ON CONFLICT(scope_key, rule_id) DO UPDATE'),
  'local block repository preserves order and tombstones scoped rows')
  const replaceStart = repo.indexOf('static async replaceAll')
  const replaceEnd = repo.indexOf('private static async loadRules', replaceStart)
  const replaceAll = repo.substring(replaceStart, replaceEnd)
  ok(/store\.beginTransaction\(\)[\s\S]*?SQL_TOMBSTONE_SETTINGS[\s\S]*?SQL_TOMBSTONE_RULES[\s\S]*?SQL_UPSERT_SETTINGS[\s\S]*?store\.commit\(\)[\s\S]*?catch \(error\) \{[\s\S]*?store\.rollBack\(\)[\s\S]*?throw error as Error/.test(replaceAll),
    'local block full replacements are transactional, so a partial write cannot tombstone the prior snapshot')
  const backupTypes = src('shared/src/main/ets/backup/BackupTypes.ets')
  const backupAdapter = src('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
  ok(backupTypes.includes('localBlock: BackupLocalBlockSection') &&
    backupAdapter.includes('LocalBlockSettings.exportForBackup(context)') &&
    backupAdapter.includes('LocalBlockSettings.restoreBackup(context, localBlock)'),
  'backup localData includes local block rules')
}
ok(/static async setCommentDisplayMode\([\s\S]*state\.commentDisplayMode[\s\S]*await LocalBlockSettings\.save\(context\)/.test(settings),
  'comment display preference persists through LocalBlockSettings')
ok(api.includes('filterLocalBlocked') &&
  api.includes('return this.filterLocalBlocked(this.filterHidden') &&
  api.includes('return this.filterLocalBlocked(list)'),
  'remote gallery list results pass through local block filtering')
ok(favVm.includes('LocalBlockService.filterGalleryList(cached.copy())') &&
  favVm.includes('!LocalBlockService.isGalleryBlocked(g)'),
  'favorites cached and local rows pass through local block filtering')

console.log('✓ local block contract: persistence, migration, backup, and result-filter boundaries locked')
