#!/usr/bin/env node
/**
 * Contract: reading progress is durable local data, not a growing Preferences JSON blob.
 * Run: node scripts/test_read_progress_rdb_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
ok('LocalDataStore has a schema version',
  /LOCAL_DATA_SCHEMA_VERSION: number = \d+/.test(store) &&
    /schema_meta/.test(store) &&
    /store\.version = LOCAL_DATA_SCHEMA_VERSION/.test(store))
ok('RDB table stores gallery read progress with sync-ready metadata',
  /gallery_read_progress/.test(store) &&
    /scope_key TEXT/.test(store) &&
    /gid TEXT/.test(store) &&
    /page_index INTEGER/.test(store) &&
    /column_mode TEXT/.test(store) &&
    /updated_at INTEGER/.test(store) &&
    /deleted_at INTEGER DEFAULT 0/.test(store) &&
    /PRIMARY KEY\(scope_key, gid\)/.test(store))

const repo = read('shared/src/main/ets/storage/ReadProgressRepository.ets')
ok('repository loads and tombstones read progress through RDB',
    /class ReadProgressRepository/.test(repo) &&
    /LocalDataStore\.open\(context\)/.test(repo) &&
    /TABLE_GALLERY_READ_PROGRESS: string = 'gallery_read_progress'/.test(repo) &&
    /SELECT gid, page_index, column_mode, updated_at FROM '\s*\+ TABLE_GALLERY_READ_PROGRESS/.test(repo) &&
    /column_mode = excluded\.column_mode/.test(repo) &&
    /ON CONFLICT\(scope_key, gid\) DO UPDATE/.test(repo) &&
    /UPDATE '\s*\+ TABLE_GALLERY_READ_PROGRESS \+ ' SET deleted_at = \?/.test(repo))
ok('repository rejects stale deferred progress writes by effective record time',
  /WHERE excluded\.updated_at >= CASE WHEN COALESCE\(gallery_read_progress\.deleted_at, 0\) >/.test(repo) &&
    /COALESCE\(gallery_read_progress\.updated_at, 0\)/.test(repo))
{
  const replaceStart = repo.indexOf('static async replaceAll')
  const replaceEnd = repo.indexOf('\n  }\n}', replaceStart)
  const replaceAll = repo.substring(replaceStart, replaceEnd)
ok('full read-progress replacements are transactional and advance the effective LWW clock',
    /static async replaceAll\(context: common\.UIAbilityContext, entries: ReadProgressEntry\[\]\): Promise<number>/.test(replaceAll) &&
    /const replacedAt: number = await ReadProgressRepository\.nextMutationTime\(store, Date\.now\(\)\)/.test(replaceAll) &&
    /const snapshotTime: number = Math\.max\(originalTime, replacedAt \+ entries\.length - i\)/.test(replaceAll) &&
    /store\.beginTransaction\(\)[\s\S]*?SQL_TOMBSTONE_SCOPE[\s\S]*?SQL_RESTORE_UPSERT[\s\S]*?store\.commit\(\)[\s\S]*?return replacedAt[\s\S]*?catch \(error\) \{[\s\S]*?store\.rollBack\(\)[\s\S]*?throw error as Error/.test(replaceAll))
}
ok('repository treats active rows and tombstones as one logical clock',
  /SQL_SELECT_MAX_EFFECTIVE_TIME/.test(repo) &&
    /SQL_HAS_PERSISTED_STATE/.test(repo) &&
    /static async hasPersistedState\(/.test(repo) &&
    /private static async nextMutationTime\([\s\S]*?latest \+ 1/.test(repo))
ok('ordinary reader writes are rebased above the effective LWW clock and report their committed time',
  /static async saveEntries\([\s\S]*?\): Promise<ReadProgressEntry\[]>/.test(repo) &&
    /let nextTimestamp: number = 0/.test(repo) &&
    /nextTimestamp = await ReadProgressRepository\.nextMutationTime\(store, Date\.now\(\)\)/.test(repo) &&
    /const updatedAt: number = Math\.max\(requestedTime, nextTimestamp\)/.test(repo) &&
    /out\.push\(new ReadProgressEntry\(entry\.g, entry\.i, updatedAt, entry\.c\)\)/.test(repo) &&
    /store\.beginTransaction\(\)[\s\S]*?store\.commit\(\)[\s\S]*?return out[\s\S]*?catch \(error\) \{[\s\S]*?store\.rollBack\(\)/.test(repo))

function effectiveTime(row) {
  return Math.max(row.updatedAt, row.deletedAt)
}

function replaceSnapshot(rows, entries, now) {
  const out = rows.map((row) => ({ ...row }))
  let latest = 0
  for (const row of out) latest = Math.max(latest, effectiveTime(row))
  const replacedAt = Math.max(now, latest + 1)
  for (const row of out) {
    if (row.deletedAt === 0) row.deletedAt = replacedAt
  }
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i]
    if (!entry.g || entry.i < 0) continue
    const originalTime = entry.t > 0 ? Math.floor(entry.t) : 0
    const snapshotTime = Math.max(originalTime, replacedAt + entries.length - i)
    const index = out.findIndex((row) => row.gid === entry.g)
    const next = { gid: entry.g, updatedAt: snapshotTime, deletedAt: 0 }
    if (index < 0) out.push(next)
    else out[index] = next
  }
  return { rows: out, replacedAt }
}

function applyIncoming(rows, incoming) {
  const out = rows.map((row) => ({ ...row }))
  const index = out.findIndex((row) => row.gid === incoming.gid)
  if (index < 0 || effectiveTime(incoming) >= effectiveTime(out[index])) {
    if (index < 0) out.push({ ...incoming })
    else out[index] = { ...incoming }
  }
  return out
}

function saveDirtyEntries(rows, entries, now) {
  const out = rows.map((row) => ({ ...row }))
  let latest = 0
  for (const row of out) latest = Math.max(latest, effectiveTime(row))
  let nextTimestamp = Math.max(now, latest + 1)
  const persisted = []
  for (const entry of entries) {
    if (!entry.g || entry.i < 0) continue
    const requestedTime = entry.t > 0 ? Math.floor(entry.t) : now
    const updatedAt = Math.max(requestedTime, nextTimestamp)
    nextTimestamp = updatedAt + 1
    const index = out.findIndex((row) => row.gid === entry.g)
    const next = { gid: entry.g, updatedAt, deletedAt: 0 }
    if (index < 0) out.push(next)
    else out[index] = next
    persisted.push({ g: entry.g, i: entry.i, t: updatedAt, c: entry.c })
  }
  return { rows: out, persisted }
}

{
  const omitted = replaceSnapshot([{ gid: 'old', updatedAt: 9000, deletedAt: 0 }], [], 1000)
  const afterOldRemoteActive = applyIncoming(omitted.rows, { gid: 'old', updatedAt: 9000, deletedAt: 0 })
  const oldRow = afterOldRemoteActive.find((row) => row.gid === 'old')
  ok('backup omission tombstones a future active row above its prior LWW time',
    omitted.replacedAt > 9000 && oldRow.deletedAt === omitted.replacedAt)

  const restored = replaceSnapshot([{ gid: 'keep', updatedAt: 0, deletedAt: 9000 }], [
    { g: 'keep', i: 4, t: 3 },
  ], 1000)
  const afterOldRemoteTombstone = applyIncoming(restored.rows, { gid: 'keep', updatedAt: 0, deletedAt: 9000 })
  const restoredRow = afterOldRemoteTombstone.find((row) => row.gid === 'keep')
  ok('backup restore rebases an old record above a future tombstone',
    restoredRow.updatedAt > 9000 && restoredRow.deletedAt === 0)

  const snapshot = replaceSnapshot([], [
    { g: 'first', i: 1, t: 2 },
    { g: 'second', i: 2, t: 3 },
  ], 1000)
  ok('every restored progress row is newer than its replacement tombstone',
    snapshot.rows.every((row) => row.updatedAt > snapshot.replacedAt && row.deletedAt === 0))

  const revisited = saveDirtyEntries([{ gid: 'revisited', updatedAt: 0, deletedAt: 9000 }], [
    { g: 'revisited', i: 7, t: 100, c: 'evenLeft' },
  ], 1000)
  const revisitedRow = revisited.rows.find((row) => row.gid === 'revisited')
  ok('a new local page turn revives a gallery above its future tombstone',
    revisited.persisted[0].t > 9000 && revisitedRow.updatedAt === revisited.persisted[0].t && revisitedRow.deletedAt === 0)
}

const progressState = read('shared/src/main/ets/state/GalleryReadProgressState.ets')
ok('state keeps per-gallery mutation times monotonic and persists column-only choices',
  /private nextUpdatedAt\(gid: string, requestedTime: number\)/.test(progressState) &&
    /adoptPersistedTimestamp\(gid: string, timestamp: number\): ReadProgressEntry \| null/.test(progressState) &&
    /if \(!this\.indexMap\.has\(gid\)\) \{\s*this\.indexMap\.set\(gid, 0\)/.test(progressState))

const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
ok('sync apply cannot overwrite a newer local read-progress mutation with an older merge snapshot',
  /SQL_APPLY_READ_PROGRESS[\s\S]*?WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) >/.test(syncAdapter) &&
    /COALESCE\(gallery_read_progress\.deleted_at, 0\)/.test(syncAdapter))

const settings = read('shared/src/main/ets/settings/GalleryReadProgressSettings.ets')
ok('settings facade reads/writes RDB and keeps legacy migration',
  /ReadProgressRepository\.load\(context\)/.test(settings) &&
  /ReadProgressRepository\.saveEntries\(context, entries\)/.test(settings) &&
    /static async migrateLegacyPreferences[\s\S]*ReadProgressRepository\.saveAll\(context, entries\)/.test(settings) &&
    /migrateLegacyPreferences/.test(settings) &&
    /store\.deleteSync\(StorageKeys\.READING_PROGRESS\)/.test(settings))
ok('legacy migration never lets a stale Preferences blob overwrite RDB state',
  /const state = connectGalleryReadProgress\(\)[\s\S]*?const revision: number = state\.revision/.test(settings) &&
    /if \(state\.revision !== revision\)[\s\S]*?ReadProgressRepository\.hasPersistedState\(context\)[\s\S]*?if \(state\.revision !== revision\)/.test(settings) &&
    /readprogress_migrate_failed/.test(settings) &&
    /await GalleryReadProgressSettings\.deleteLegacyPreference\(context\)/.test(settings))
ok('settings no longer persists reading progress back to Preferences JSON',
  !/store\.putSync\(StorageKeys\.READING_PROGRESS/.test(settings))
ok('settings persists per-gallery double-page pairing through read progress records',
  /static setColumnMode\(context: common\.UIAbilityContext, gid: string, columnMode: string\): void/.test(settings) &&
    /GalleryReadProgressSettings\.markDirty\(state, gid\)/.test(settings) &&
    /ReadProgressRepository\.saveEntries\(context, entries\)/.test(settings))
ok('ordinary reader writes persist only dirty records while full save stays migration-only',
  /private static dirtyEntries: Map<string, ReadProgressEntry>/.test(settings) &&
    /private static dirtySnapshot\(\): ReadProgressEntry\[\]/.test(settings) &&
    /private static rdbWriteTail: Promise<void> = Promise\.resolve\(\)/.test(settings) &&
    /private static enqueueRdbWrite\(work: \(\) => Promise<void>\): Promise<void>/.test(settings) &&
    /private static async persist[\s\S]*dirtySnapshot\(\)[\s\S]*enqueueRdbWrite[\s\S]*saveEntries\(context, entries\)[\s\S]*reconcilePersisted\(state, entries, persisted\)/.test(settings) &&
    /private static reconcilePersisted\([\s\S]*?current\.t === requestedTime[\s\S]*?state\.adoptPersistedTimestamp\(/.test(settings) &&
    /static async restoreBackup[\s\S]*pendingBeforeRestore[\s\S]*clearPending\(\)[\s\S]*enqueueRdbWrite[\s\S]*replaceAll/.test(settings) &&
    /rebaseAfterRestore\(stored, changedWhileRestoring, restoredAt\)[\s\S]*persist\(context, false\)/.test(settings) &&
    /catch \(error\) \{[\s\S]*mergeDirtyEntries\(pendingBeforeRestore\)[\s\S]*schedulePersist\(context\)/.test(settings) &&
    /static async migrateLegacyPreferences[\s\S]*enqueueRdbWrite[\s\S]*saveAll\(context, entries\)/.test(settings) &&
    /static async saveAll[\s\S]*saveEntries\(context, entries\)/.test(repo))
ok('sync refresh flushes current reader state and merges only mutations made during the refresh',
  /static async flushForSync\(context: common\.UIAbilityContext\)/.test(settings) &&
    /static async refreshAfterSync\(context: common\.UIAbilityContext\)/.test(settings) &&
    /entriesChangedSince\(before, state\.snapshot\(\)\)/.test(settings) &&
    /state\.mergeNewest\(changedWhileRefreshing\)/.test(settings))

const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
const backupService = read('shared/src/main/ets/backup/BackupService.ets')
const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
ok('backup has a plaintext localData section for read progress',
  /'preferences' \| 'localData' \| 'secrets'/.test(backupTypes) &&
    /BACKUP_SECTION_NAMES: BackupSectionName\[\] = \['preferences', 'localData'\]/.test(backupTypes) &&
    /interface BackupLocalDataSection/.test(backupTypes) &&
    /readProgress: BackupReadProgressEntry\[\]/.test(backupTypes) &&
    /c\?: string/.test(backupTypes))
ok('backup exports/restores localData and migrates old prefs-only backups',
  /BackupLocalDataAdapter\.exportSection\(context\)/.test(backupService) &&
    /BackupLocalDataAdapter\.restoreSection\(context, envelope\.data\.localData\)/.test(backupService) &&
    /BackupLocalDataAdapter\.restoreLegacyPreferences\(context\)/.test(backupService) &&
    /GalleryReadProgressSettings\.exportForBackup\(context\)/.test(backupAdapter) &&
    /GalleryReadProgressSettings\.restoreBackup\(context, entries\)/.test(backupAdapter))

if (failures === 0) {
  console.log('✓ read-progress RDB contract passed')
  process.exit(0)
}
console.error(`✗ read-progress RDB contract: ${failures} failure(s)`)
process.exit(1)
