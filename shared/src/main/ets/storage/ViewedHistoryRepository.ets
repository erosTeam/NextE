import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { ViewedGallery } from '../model/ViewedGallery'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const DEFAULT_LIMIT: number = 200
const SQL_SELECT_ACTIVE: string =
  'SELECT gid, token, title, title_jp, thumb_url, category, uploader, rating, file_count, viewed_at ' +
  'FROM viewed_history WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY viewed_at DESC, gid DESC LIMIT ?'
const SQL_UPSERT: string =
  'INSERT INTO viewed_history ' +
  '(scope_key, gid, token, title, title_jp, thumb_url, category, uploader, rating, file_count, viewed_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, gid) DO UPDATE SET ' +
  'token = excluded.token, title = excluded.title, title_jp = excluded.title_jp, ' +
  'thumb_url = excluded.thumb_url, category = excluded.category, uploader = excluded.uploader, ' +
  'rating = excluded.rating, file_count = excluded.file_count, viewed_at = excluded.viewed_at, deleted_at = 0 ' +
  'WHERE excluded.viewed_at >= CASE WHEN COALESCE(viewed_history.deleted_at, 0) > ' +
  'COALESCE(viewed_history.viewed_at, 0) THEN COALESCE(viewed_history.deleted_at, 0) ' +
  'ELSE COALESCE(viewed_history.viewed_at, 0) END'
const SQL_RESTORE_UPSERT: string =
  'INSERT INTO viewed_history ' +
  '(scope_key, gid, token, title, title_jp, thumb_url, category, uploader, rating, file_count, viewed_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(scope_key, gid) DO UPDATE SET ' +
  'token = excluded.token, title = excluded.title, title_jp = excluded.title_jp, ' +
  'thumb_url = excluded.thumb_url, category = excluded.category, uploader = excluded.uploader, ' +
  'rating = excluded.rating, file_count = excluded.file_count, viewed_at = excluded.viewed_at, deleted_at = 0'
const SQL_TOMBSTONE_SCOPE: string =
  'UPDATE viewed_history SET deleted_at = ? WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_SELECT_MAX_EFFECTIVE_TIME: string =
  'SELECT MAX(CASE WHEN COALESCE(deleted_at, 0) > COALESCE(viewed_at, 0) ' +
  'THEN COALESCE(deleted_at, 0) ELSE COALESCE(viewed_at, 0) END) AS effective_at ' +
  'FROM viewed_history WHERE scope_key = ?'
const SQL_HAS_PERSISTED_STATE: string =
  'SELECT 1 AS has_state FROM viewed_history WHERE scope_key = ? LIMIT 1'
const SQL_TOMBSTONE_OVERFLOW: string =
  'UPDATE viewed_history SET deleted_at = ? WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'AND gid NOT IN (SELECT gid FROM viewed_history WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY viewed_at DESC, gid DESC LIMIT ?) AND COALESCE(viewed_at, 0) <= ?'

export class ViewedHistoryRepository {
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

  static async load(context: common.UIAbilityContext, limit: number = DEFAULT_LIMIT): Promise<ViewedGallery[]> {
    const out: ViewedGallery[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ACTIVE, [
      SCOPE_GLOBAL,
      limit,
    ])
    try {
      while (resultSet.goToNextRow()) {
        const item: ViewedGallery = new ViewedGallery()
        item.gid = ViewedHistoryRepository.stringColumn(resultSet, 'gid')
        if (item.gid.length === 0) {
          continue
        }
        item.token = ViewedHistoryRepository.stringColumn(resultSet, 'token')
        item.title = ViewedHistoryRepository.stringColumn(resultSet, 'title')
        item.titleJp = ViewedHistoryRepository.stringColumn(resultSet, 'title_jp')
        item.thumbUrl = ViewedHistoryRepository.stringColumn(resultSet, 'thumb_url')
        item.category = ViewedHistoryRepository.stringColumn(resultSet, 'category')
        item.uploader = ViewedHistoryRepository.stringColumn(resultSet, 'uploader')
        item.rating = ViewedHistoryRepository.numberColumn(resultSet, 'rating')
        item.fileCount = ViewedHistoryRepository.stringColumn(resultSet, 'file_count')
        item.time = Math.floor(ViewedHistoryRepository.numberColumn(resultSet, 'viewed_at'))
        out.push(item)
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async replaceAll(context: common.UIAbilityContext, items: ViewedGallery[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      // A backup/migration snapshot is authoritative. Advance beyond every active row and tombstone
      // first so omitted records cannot be revived and restored records cannot lose to a previously
      // observed future deletion during the next cross-device merge.
      const replacedAt: number = await ViewedHistoryRepository.nextViewedAt(store, Date.now())
      await store.executeSql(SQL_TOMBSTONE_SCOPE, [replacedAt, SCOPE_GLOBAL])
      for (let i: number = 0; i < items.length && i < DEFAULT_LIMIT; i++) {
        const item: ViewedGallery = items[i]
        if (item.gid.length > 0) {
          // Keep a genuinely future backup timestamp, but otherwise rebase every restored row above
          // this transaction's tombstone. The input order remains deterministic for the snapshot.
          const originalTime: number = item.time > 0 ? Math.floor(item.time) : 0
          const snapshotTime: number = Math.max(originalTime, replacedAt + items.length - i)
          await ViewedHistoryRepository.writeItem(
            store,
            item,
            snapshotTime,
            SQL_RESTORE_UPSERT,
          )
        }
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /**
   * Ordinary detail opens write one row. The same transaction converts only rows outside the retained
   * newest-first window into tombstones, so old devices cannot resurrect them during a later sync.
   */
  static async upsertAndTrim(
    context: common.UIAbilityContext,
    item: ViewedGallery,
    limit: number = DEFAULT_LIMIT,
  ): Promise<number> {
    if (item.gid.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const retained: number = Math.max(1, Math.floor(limit))
    store.beginTransaction()
    try {
      const viewedAt: number = await ViewedHistoryRepository.nextViewedAt(store, item.time)
      await ViewedHistoryRepository.writeItem(store, item, viewedAt, SQL_UPSERT)
      await store.executeSql(SQL_TOMBSTONE_OVERFLOW, [
        viewedAt,
        SCOPE_GLOBAL,
        SCOPE_GLOBAL,
        retained,
        viewedAt,
      ])
      store.commit()
      return viewedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Advance above every active row and tombstone so a clock tie cannot lose a fresh visit. */
  private static async nextViewedAt(
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
    return Math.max(Date.now(), Math.max(0, Math.floor(requestedTime)), latest + 1)
  }

  private static async writeItem(
    store: relationalStore.RdbStore,
    item: ViewedGallery,
    viewedAt: number,
    sql: string,
  ): Promise<void> {
    await store.executeSql(sql, [
      SCOPE_GLOBAL,
      item.gid,
      item.token,
      item.title,
      item.titleJp,
      item.thumbUrl,
      item.category,
      item.uploader,
      item.rating,
      item.fileCount,
      viewedAt,
    ])
  }

  private static stringColumn(resultSet: relationalStore.ResultSet, name: string): string {
    const index: number = resultSet.getColumnIndex(name)
    return resultSet.isColumnNull(index) ? '' : resultSet.getString(index)
  }

  private static numberColumn(resultSet: relationalStore.ResultSet, name: string): number {
    const index: number = resultSet.getColumnIndex(name)
    return resultSet.isColumnNull(index) ? 0 : resultSet.getDouble(index)
  }
}
