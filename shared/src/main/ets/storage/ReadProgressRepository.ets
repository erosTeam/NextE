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

export class ReadProgressRepository {
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
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    for (let i: number = 0; i < entries.length; i++) {
      const entry: ReadProgressEntry = entries[i]
      if (entry.g.length > 0 && entry.i >= 0) {
        await store.executeSql(SQL_UPSERT, [
          SCOPE_GLOBAL,
          entry.g,
          entry.i,
          entry.c,
          entry.t > 0 ? entry.t : Date.now(),
        ])
      }
    }
  }

  static async replaceAll(context: common.UIAbilityContext, entries: ReadProgressEntry[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      await store.executeSql(SQL_TOMBSTONE_SCOPE, [Date.now(), SCOPE_GLOBAL])
      for (let i: number = 0; i < entries.length; i++) {
        const entry: ReadProgressEntry = entries[i]
        if (entry.g.length > 0 && entry.i >= 0) {
          await store.executeSql(SQL_RESTORE_UPSERT, [
            SCOPE_GLOBAL,
            entry.g,
            entry.i,
            entry.c,
            entry.t > 0 ? entry.t : Date.now(),
          ])
        }
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }
}
