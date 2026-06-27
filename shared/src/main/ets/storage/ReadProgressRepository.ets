import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { ReadProgressEntry } from '../state/GalleryReadProgressState'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_ACTIVE: string =
  'SELECT gid, page_index, updated_at FROM gallery_read_progress ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ORDER BY updated_at DESC'
const SQL_UPSERT: string =
  'INSERT OR REPLACE INTO gallery_read_progress ' +
  '(scope_key, gid, page_index, updated_at, deleted_at) VALUES (?, ?, ?, ?, 0)'
const SQL_DELETE_SCOPE: string = 'DELETE FROM gallery_read_progress WHERE scope_key = ?'

export class ReadProgressRepository {
  static async load(context: common.UIAbilityContext): Promise<ReadProgressEntry[]> {
    const out: ReadProgressEntry[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ACTIVE, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const gidIndex: number = resultSet.getColumnIndex('gid')
        const pageIndex: number = resultSet.getColumnIndex('page_index')
        const updatedIndex: number = resultSet.getColumnIndex('updated_at')
        const gid: string = resultSet.isColumnNull(gidIndex) ? '' : resultSet.getString(gidIndex)
        const page: number = resultSet.isColumnNull(pageIndex) ? 0 : resultSet.getDouble(pageIndex)
        const updatedAt: number = resultSet.isColumnNull(updatedIndex) ? 0 : resultSet.getDouble(updatedIndex)
        if (gid.length > 0 && page >= 0) {
          out.push(new ReadProgressEntry(gid, Math.floor(page), Math.floor(updatedAt)))
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
          entry.t > 0 ? entry.t : Date.now(),
        ])
      }
    }
  }

  static async replaceAll(context: common.UIAbilityContext, entries: ReadProgressEntry[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_DELETE_SCOPE, [SCOPE_GLOBAL])
    for (let i: number = 0; i < entries.length; i++) {
      const entry: ReadProgressEntry = entries[i]
      if (entry.g.length > 0 && entry.i >= 0) {
        await store.executeSql(SQL_UPSERT, [
          SCOPE_GLOBAL,
          entry.g,
          entry.i,
          entry.t > 0 ? entry.t : Date.now(),
        ])
      }
    }
  }
}
