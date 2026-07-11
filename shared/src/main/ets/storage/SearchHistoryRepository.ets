import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const DEFAULT_LIMIT: number = 100
const SQL_SELECT_ACTIVE: string =
  'SELECT query_text FROM search_history WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY position_index ASC, updated_at DESC LIMIT ?'
const SQL_UPSERT: string =
  'INSERT INTO search_history (scope_key, query_text, position_index, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, 0) ON CONFLICT(scope_key, query_text) DO UPDATE SET ' +
  'position_index = excluded.position_index, updated_at = excluded.updated_at, deleted_at = 0 ' +
  'WHERE excluded.updated_at >= CASE WHEN COALESCE(search_history.deleted_at, 0) > ' +
  'COALESCE(search_history.updated_at, 0) THEN COALESCE(search_history.deleted_at, 0) ' +
  'ELSE COALESCE(search_history.updated_at, 0) END'
const SQL_RESTORE_UPSERT: string =
  'INSERT INTO search_history (scope_key, query_text, position_index, updated_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, 0) ON CONFLICT(scope_key, query_text) DO UPDATE SET ' +
  'position_index = excluded.position_index, updated_at = excluded.updated_at, deleted_at = 0'
const SQL_TOMBSTONE_SCOPE: string =
  'UPDATE search_history SET deleted_at = ? ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_QUERY: string =
  'INSERT INTO search_history (scope_key, query_text, position_index, updated_at, deleted_at) ' +
  'VALUES (?, ?, 0, 0, ?) ON CONFLICT(scope_key, query_text) DO UPDATE SET ' +
  'deleted_at = excluded.deleted_at WHERE excluded.deleted_at >= ' +
  'CASE WHEN COALESCE(search_history.deleted_at, 0) > COALESCE(search_history.updated_at, 0) ' +
  'THEN COALESCE(search_history.deleted_at, 0) ELSE COALESCE(search_history.updated_at, 0) END'
const SQL_SELECT_MAX_EFFECTIVE_TIME: string =
  'SELECT MAX(CASE WHEN COALESCE(deleted_at, 0) > COALESCE(updated_at, 0) ' +
  'THEN COALESCE(deleted_at, 0) ELSE COALESCE(updated_at, 0) END) AS effective_at ' +
  'FROM search_history WHERE scope_key = ?'
const SQL_HAS_PERSISTED_STATE: string =
  'SELECT 1 AS has_state FROM search_history WHERE scope_key = ? LIMIT 1'
const SQL_SELECT_MIN_POSITION: string =
  'SELECT MIN(COALESCE(position_index, 0)) AS min_position FROM search_history ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_OVERFLOW: string =
  'UPDATE search_history SET deleted_at = ? WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'AND query_text NOT IN (SELECT query_text FROM search_history WHERE scope_key = ? ' +
  'AND COALESCE(deleted_at, 0) = 0 ORDER BY position_index ASC, updated_at DESC LIMIT ?) ' +
  'AND COALESCE(updated_at, 0) <= ?'

export class SearchHistoryRepository {
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

  static async load(context: common.UIAbilityContext, limit: number = DEFAULT_LIMIT): Promise<string[]> {
    const out: string[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ACTIVE, [
      SCOPE_GLOBAL,
      limit,
    ])
    try {
      while (resultSet.goToNextRow()) {
        const index: number = resultSet.getColumnIndex('query_text')
        const query: string = resultSet.isColumnNull(index) ? '' : resultSet.getString(index)
        if (query.length > 0 && out.indexOf(query) < 0) {
          out.push(query)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async replaceAll(context: common.UIAbilityContext, items: string[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const snapshot: string[] = SearchHistoryRepository.snapshotItems(items)
    store.beginTransaction()
    try {
      // Backup, clear, and legacy migration intentionally replace the entire snapshot. Advance the
      // shared logical clock first so an omitted query's tombstone wins over any older sync record.
      const replacedAt: number = await SearchHistoryRepository.nextMutationTime(store, Date.now())
      await store.executeSql(SQL_TOMBSTONE_SCOPE, [replacedAt, SCOPE_GLOBAL])
      for (let i: number = 0; i < snapshot.length; i++) {
        await SearchHistoryRepository.writeQuery(
          store,
          snapshot[i],
          i,
          replacedAt + snapshot.length - i,
          SQL_RESTORE_UPSERT,
        )
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Ordinary searches write only the queried row and tombstone rows beyond the retained window. */
  static async upsertAndTrim(
    context: common.UIAbilityContext,
    query: string,
    limit: number = DEFAULT_LIMIT,
  ): Promise<number> {
    const normalized: string = query.trim()
    if (normalized.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const retained: number = Math.max(1, Math.floor(limit))
    store.beginTransaction()
    try {
      const updatedAt: number = await SearchHistoryRepository.nextMutationTime(store, Date.now())
      const positionIndex: number = await SearchHistoryRepository.nextPositionIndex(store)
      await SearchHistoryRepository.writeQuery(store, normalized, positionIndex, updatedAt, SQL_UPSERT)
      await store.executeSql(SQL_TOMBSTONE_OVERFLOW, [
        updatedAt,
        SCOPE_GLOBAL,
        SCOPE_GLOBAL,
        retained,
        updatedAt,
      ])
      store.commit()
      return updatedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Persist a tombstone even when no durable row exists yet, fencing older sync records. */
  static async tombstone(
    context: common.UIAbilityContext,
    query: string,
    requestedTime: number = Date.now(),
  ): Promise<number> {
    const normalized: string = query.trim()
    if (normalized.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      const deletedAt: number = await SearchHistoryRepository.nextMutationTime(store, requestedTime)
      await store.executeSql(SQL_TOMBSTONE_QUERY, [SCOPE_GLOBAL, normalized, deletedAt])
      store.commit()
      return deletedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

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

  /** A lower position is newer, so one row moves to the front without reindexing every other row. */
  private static async nextPositionIndex(store: relationalStore.RdbStore): Promise<number> {
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_MIN_POSITION, [
      SCOPE_GLOBAL,
    ])
    try {
      if (resultSet.goToNextRow()) {
        const index: number = resultSet.getColumnIndex('min_position')
        if (!resultSet.isColumnNull(index)) {
          return Math.floor(resultSet.getDouble(index)) - 1
        }
      }
    } finally {
      resultSet.close()
    }
    return 0
  }

  private static async writeQuery(
    store: relationalStore.RdbStore,
    query: string,
    positionIndex: number,
    updatedAt: number,
    sql: string,
  ): Promise<void> {
    await store.executeSql(sql, [SCOPE_GLOBAL, query, positionIndex, updatedAt])
  }

  private static snapshotItems(items: string[]): string[] {
    const out: string[] = []
    for (let i: number = 0; i < items.length && out.length < DEFAULT_LIMIT; i++) {
      const query: string = items[i].trim()
      if (query.length > 0 && out.indexOf(query) < 0) {
        out.push(query)
      }
    }
    return out
  }
}
