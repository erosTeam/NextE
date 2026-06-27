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
  'INSERT OR REPLACE INTO viewed_history ' +
  '(scope_key, gid, token, title, title_jp, thumb_url, category, uploader, rating, file_count, viewed_at, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)'
const SQL_DELETE_SCOPE: string = 'DELETE FROM viewed_history WHERE scope_key = ?'

export class ViewedHistoryRepository {
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
    await store.executeSql(SQL_DELETE_SCOPE, [SCOPE_GLOBAL])
    for (let i: number = 0; i < items.length && i < DEFAULT_LIMIT; i++) {
      await ViewedHistoryRepository.upsert(store, items[i])
    }
  }

  private static async upsert(store: relationalStore.RdbStore, item: ViewedGallery): Promise<void> {
    if (item.gid.length === 0) {
      return
    }
    await store.executeSql(SQL_UPSERT, [
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
      item.time > 0 ? item.time : Date.now(),
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
