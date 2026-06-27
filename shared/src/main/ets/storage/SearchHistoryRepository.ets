import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const DEFAULT_LIMIT: number = 100
const SQL_SELECT_ACTIVE: string =
  'SELECT query_text FROM search_history WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ' +
  'ORDER BY position_index ASC, updated_at DESC LIMIT ?'
const SQL_UPSERT: string =
  'INSERT OR REPLACE INTO search_history ' +
  '(scope_key, query_text, position_index, updated_at, deleted_at) VALUES (?, ?, ?, ?, 0)'
const SQL_DELETE_SCOPE: string = 'DELETE FROM search_history WHERE scope_key = ?'

export class SearchHistoryRepository {
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
    await store.executeSql(SQL_DELETE_SCOPE, [SCOPE_GLOBAL])
    for (let i: number = 0; i < items.length && i < DEFAULT_LIMIT; i++) {
      const query: string = items[i].trim()
      if (query.length === 0) {
        continue
      }
      await store.executeSql(SQL_UPSERT, [SCOPE_GLOBAL, query, i, Date.now()])
    }
  }
}
