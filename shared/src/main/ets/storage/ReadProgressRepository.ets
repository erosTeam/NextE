import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { ReadProgressEntry } from '../state/GalleryReadProgressState'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const TABLE_GALLERY_READ_PROGRESS: string = 'gallery_read_progress'
const SQL_SELECT_ACTIVE: string =
  'SELECT gid, page_index, column_mode, updated_at FROM ' + TABLE_GALLERY_READ_PROGRESS + ' ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ORDER BY updated_at DESC'
const SQL_UPSERT: string =
  'INSERT INTO ' + TABLE_GALLERY_READ_PROGRESS + ' (scope_key, gid, page_index, column_mode, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, gid) DO UPDATE SET ' +
  'page_index = excluded.page_index, column_mode = excluded.column_mode, ' +
  'updated_at = excluded.updated_at, deleted_at = 0 ' +
  'WHERE excluded.updated_at >= CASE WHEN COALESCE(gallery_read_progress.deleted_at, 0) > ' +
  'COALESCE(gallery_read_progress.updated_at, 0) THEN COALESCE(gallery_read_progress.deleted_at, 0) ' +
  'ELSE COALESCE(gallery_read_progress.updated_at, 0) END'
const SQL_RESTORE_UPSERT: string =
  'INSERT INTO ' + TABLE_GALLERY_READ_PROGRESS + ' (scope_key, gid, page_index, column_mode, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, gid) DO UPDATE SET ' +
  'page_index = excluded.page_index, column_mode = excluded.column_mode, ' +
  'updated_at = excluded.updated_at, deleted_at = 0'
const SQL_TOMBSTONE_SCOPE: string =
  'UPDATE ' + TABLE_GALLERY_READ_PROGRESS + ' SET deleted_at = ? WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_MAX_EFFECTIVE_TIME: string =
  'SELECT MAX(CASE WHEN COALESCE(deleted_at, 0) > COALESCE(updated_at, 0) ' +
  'THEN COALESCE(deleted_at, 0) ELSE COALESCE(updated_at, 0) END) AS effective_at ' +
  'FROM ' + TABLE_GALLERY_READ_PROGRESS + ' WHERE scope_key = ?'
const SQL_HAS_PERSISTED_STATE: string =
  'SELECT 1 AS has_state FROM ' + TABLE_GALLERY_READ_PROGRESS + ' WHERE scope_key = ? LIMIT 1'

export class ReadProgressRepository {
  /** Any row, including a tombstone, makes RDB canonical over a stale legacy Preferences snapshot. */
  static async hasPersistedState(context: common.UIAbilityContext): Promise<boolean> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_HAS_PERSISTED_STATE, [SCOPE_GLOBAL])
    try {
      return resultSet.goToNextRow()
    } finally {
      resultSet.close()
    }
  }

  static async load(context: common.UIAbilityContext): Promise<ReadProgressEntry[]> {
    const out: ReadProgressEntry[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ACTIVE, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const gidIndex: number = resultSet.getColumnIndex('gid')
        const pageIndex: number = resultSet.getColumnIndex('page_index')
        const columnModeIndex: number = resultSet.getColumnIndex('column_mode')
        const updatedIndex: number = resultSet.getColumnIndex('updated_at')
        const gid: string = resultSet.isColumnNull(gidIndex) ? '' : resultSet.getString(gidIndex)
        const page: number = resultSet.isColumnNull(pageIndex) ? 0 : resultSet.getDouble(pageIndex)
        const columnMode: string = resultSet.isColumnNull(columnModeIndex) ? '' : resultSet.getString(columnModeIndex)
        const updatedAt: number = resultSet.isColumnNull(updatedIndex) ? 0 : resultSet.getDouble(updatedIndex)
        if (gid.length > 0 && page >= 0) {
          out.push(new ReadProgressEntry(gid, Math.floor(page), Math.floor(updatedAt), columnMode))
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async saveAll(context: common.UIAbilityContext, entries: ReadProgressEntry[]): Promise<void> {
    await ReadProgressRepository.saveEntries(context, entries)
  }

  /**
   * Upsert a bounded dirty batch and return the logical timestamps actually committed. Every local
   * write advances above active rows and tombstones already present in this scope, so revisiting a
   * gallery after a future cross-device tombstone cannot be silently rejected by newest-wins SQL.
   */
  static async saveEntries(
    context: common.UIAbilityContext,
    entries: ReadProgressEntry[],
  ): Promise<ReadProgressEntry[]> {
    const out: ReadProgressEntry[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      let nextTimestamp: number = 0
      for (let i: number = 0; i < entries.length; i++) {
        const entry: ReadProgressEntry = entries[i]
        if (entry.g.length > 0 && entry.i >= 0) {
          if (nextTimestamp === 0) {
            nextTimestamp = await ReadProgressRepository.nextMutationTime(store, Date.now())
          }
          const requestedTime: number = entry.t > 0 ? Math.floor(entry.t) : Date.now()
          const updatedAt: number = Math.max(requestedTime, nextTimestamp)
          nextTimestamp = updatedAt + 1
          await store.executeSql(SQL_UPSERT, [
            SCOPE_GLOBAL,
            entry.g,
            entry.i,
            entry.c,
            updatedAt,
          ])
          out.push(new ReadProgressEntry(entry.g, entry.i, updatedAt, entry.c))
        }
      }
      store.commit()
      return out
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Replace active history and return the tombstone time used by this transaction. */
  static async replaceAll(context: common.UIAbilityContext, entries: ReadProgressEntry[]): Promise<number> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      // A backup/migration snapshot is authoritative. Advance above every active row and tombstone
      // first so omitted records cannot be revived and restored records cannot lose to a previously
      // observed future deletion during the next cross-device merge.
      const replacedAt: number = await ReadProgressRepository.nextMutationTime(store, Date.now())
      await store.executeSql(SQL_TOMBSTONE_SCOPE, [replacedAt, SCOPE_GLOBAL])
      for (let i: number = 0; i < entries.length; i++) {
        const entry: ReadProgressEntry = entries[i]
        if (entry.g.length > 0 && entry.i >= 0) {
          // Keep a genuinely future backup timestamp, but otherwise rebase every restored row above
          // this transaction's tombstone. The input order remains deterministic for the snapshot.
          const originalTime: number = entry.t > 0 ? Math.floor(entry.t) : 0
          const snapshotTime: number = Math.max(originalTime, replacedAt + entries.length - i)
          await store.executeSql(SQL_RESTORE_UPSERT, [
            SCOPE_GLOBAL,
            entry.g,
            entry.i,
            entry.c,
            snapshotTime,
          ])
        }
      }
      store.commit()
      return replacedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Advance above every active row and tombstone before issuing a local logical timestamp. */
  private static async nextMutationTime(
    store: relationalStore.RdbStore,
    requestedTime: number,
  ): Promise<number> {
    let latest: number = 0
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_MAX_EFFECTIVE_TIME, [
      SCOPE_GLOBAL,
    ])
    try {
      if (resultSet.goToNextRow()) {
        const index: number = resultSet.getColumnIndex('effective_at')
        if (!resultSet.isColumnNull(index)) {
          latest = Math.max(0, Math.floor(resultSet.getDouble(index)))
        }
      }
    } finally {
      resultSet.close()
    }
    const requested: number = requestedTime > 0 ? Math.floor(requestedTime) : 0
    return Math.max(Date.now(), requested, latest + 1)
  }
}
