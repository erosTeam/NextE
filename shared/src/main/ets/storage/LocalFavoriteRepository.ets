import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { EhGallery } from '../model/EhGallery'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_ACTIVE: string =
  'SELECT gid, token, url, thumb_url, thumb_url_l, img_width, img_height, english_title, ' +
  'japanese_title, category, uploader, post_time, file_count, rating, rating_fallback, ' +
  'color_rating, fav_note, fav_title, expunged, last_view_time FROM local_favorites ' +
  'WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0 ORDER BY last_view_time DESC, gid DESC'
const SQL_UPSERT: string =
  'INSERT INTO local_favorites ' +
  '(scope_key, gid, token, url, thumb_url, thumb_url_l, img_width, img_height, english_title, ' +
  'japanese_title, category, uploader, post_time, file_count, rating, rating_fallback, ' +
  'color_rating, fav_note, fav_title, expunged, last_view_time, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ' +
  'ON CONFLICT(scope_key, gid) DO UPDATE SET token = excluded.token, url = excluded.url, ' +
  'thumb_url = excluded.thumb_url, thumb_url_l = excluded.thumb_url_l, img_width = excluded.img_width, ' +
  'img_height = excluded.img_height, english_title = excluded.english_title, japanese_title = excluded.japanese_title, ' +
  'category = excluded.category, uploader = excluded.uploader, post_time = excluded.post_time, ' +
  'file_count = excluded.file_count, rating = excluded.rating, rating_fallback = excluded.rating_fallback, ' +
  'color_rating = excluded.color_rating, fav_note = excluded.fav_note, fav_title = excluded.fav_title, ' +
  'expunged = excluded.expunged, last_view_time = excluded.last_view_time, deleted_at = 0 ' +
  'WHERE excluded.last_view_time >= CASE WHEN COALESCE(local_favorites.deleted_at, 0) > ' +
  'COALESCE(local_favorites.last_view_time, 0) THEN COALESCE(local_favorites.deleted_at, 0) ' +
  'ELSE COALESCE(local_favorites.last_view_time, 0) END'
const SQL_RESTORE_UPSERT: string =
  'INSERT INTO local_favorites ' +
  '(scope_key, gid, token, url, thumb_url, thumb_url_l, img_width, img_height, english_title, ' +
  'japanese_title, category, uploader, post_time, file_count, rating, rating_fallback, ' +
  'color_rating, fav_note, fav_title, expunged, last_view_time, deleted_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0) ' +
  'ON CONFLICT(scope_key, gid) DO UPDATE SET token = excluded.token, url = excluded.url, ' +
  'thumb_url = excluded.thumb_url, thumb_url_l = excluded.thumb_url_l, img_width = excluded.img_width, ' +
  'img_height = excluded.img_height, english_title = excluded.english_title, japanese_title = excluded.japanese_title, ' +
  'category = excluded.category, uploader = excluded.uploader, post_time = excluded.post_time, ' +
  'file_count = excluded.file_count, rating = excluded.rating, rating_fallback = excluded.rating_fallback, ' +
  'color_rating = excluded.color_rating, fav_note = excluded.fav_note, fav_title = excluded.fav_title, ' +
  'expunged = excluded.expunged, last_view_time = excluded.last_view_time, deleted_at = 0'
const SQL_TOMBSTONE_SCOPE: string =
  'UPDATE local_favorites SET deleted_at = ? WHERE scope_key = ? AND COALESCE(deleted_at, 0) = 0'
const SQL_TOMBSTONE_GID: string =
  'INSERT INTO local_favorites (scope_key, gid, last_view_time, deleted_at) VALUES (?, ?, 0, ?) ' +
  'ON CONFLICT(scope_key, gid) DO UPDATE SET deleted_at = excluded.deleted_at ' +
  'WHERE excluded.deleted_at >= CASE WHEN COALESCE(local_favorites.deleted_at, 0) > ' +
  'COALESCE(local_favorites.last_view_time, 0) THEN COALESCE(local_favorites.deleted_at, 0) ' +
  'ELSE COALESCE(local_favorites.last_view_time, 0) END'
const SQL_SELECT_MAX_EFFECTIVE_TIME: string =
  'SELECT MAX(CASE WHEN COALESCE(deleted_at, 0) > COALESCE(last_view_time, 0) ' +
  'THEN COALESCE(deleted_at, 0) ELSE COALESCE(last_view_time, 0) END) AS effective_at ' +
  'FROM local_favorites WHERE scope_key = ?'

export class LocalFavoriteRepository {
  static async load(context: common.UIAbilityContext): Promise<EhGallery[]> {
    const out: EhGallery[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ACTIVE, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const item: EhGallery = LocalFavoriteRepository.readGallery(resultSet)
        if (item.gid.length > 0) {
          out.push(item)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async replaceAll(context: common.UIAbilityContext, items: EhGallery[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      // A backup/migration snapshot is intentionally authoritative. Advance beyond every existing
      // active row and tombstone first so rows omitted from the snapshot cannot be resurrected by
      // a previously observed future timestamp during the next sync merge.
      const replacedAt: number = await LocalFavoriteRepository.nextMutationTime(store, Date.now())
      await store.executeSql(SQL_TOMBSTONE_SCOPE, [replacedAt, SCOPE_GLOBAL])
      for (let i: number = 0; i < items.length; i++) {
        const item: EhGallery = items[i]
        if (item.gid.length > 0) {
          // Preserve the supplied snapshot order while giving every restored active row a version
          // newer than the scope tombstone. Existing future snapshot timestamps stay intact.
          const originalTime: number = item.lastViewTime > 0 ? Math.floor(item.lastViewTime) : 0
          const snapshotTime: number = Math.max(originalTime, replacedAt + items.length - i)
          await LocalFavoriteRepository.writeItem(
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

  /** Normal local-favorite adds must touch just their own durable row. */
  static async upsert(context: common.UIAbilityContext, item: EhGallery): Promise<number> {
    if (item.gid.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      const lastViewTime: number = await LocalFavoriteRepository.nextMutationTime(
        store,
        item.lastViewTime,
      )
      await LocalFavoriteRepository.writeItem(store, item, lastViewTime, SQL_UPSERT)
      store.commit()
      return lastViewTime
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Persist a tombstone even when a delayed add has not created its row yet. */
  static async tombstone(
    context: common.UIAbilityContext,
    gid: string,
    requestedTime: number = Date.now(),
  ): Promise<number> {
    if (gid.length === 0) {
      return 0
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      const deletedAt: number = await LocalFavoriteRepository.nextMutationTime(store, requestedTime)
      await store.executeSql(SQL_TOMBSTONE_GID, [SCOPE_GLOBAL, gid, deletedAt])
      store.commit()
      return deletedAt
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  /** Advance above every active row and tombstone so a rapid toggle has a stable LWW version. */
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

  private static async writeItem(
    store: relationalStore.RdbStore,
    item: EhGallery,
    lastViewTime: number,
    sql: string,
  ): Promise<void> {
    await store.executeSql(sql, [
      SCOPE_GLOBAL,
      item.gid,
      item.token,
      item.url,
      item.thumbUrl,
      item.thumbUrlL,
      item.imgWidth,
      item.imgHeight,
      item.englishTitle,
      item.japaneseTitle,
      item.category,
      item.uploader,
      item.postTime,
      item.fileCount,
      item.rating,
      item.ratingFallBack,
      item.colorRating,
      item.favNote,
      item.favTitle.length > 0 ? item.favTitle : 'Local',
      item.expunged ? 1 : 0,
      lastViewTime,
    ])
  }

  private static readGallery(resultSet: relationalStore.ResultSet): EhGallery {
    const g: EhGallery = new EhGallery(
      LocalFavoriteRepository.stringColumn(resultSet, 'gid'),
      LocalFavoriteRepository.stringColumn(resultSet, 'token'),
    )
    g.url = LocalFavoriteRepository.stringColumn(resultSet, 'url')
    g.thumbUrl = LocalFavoriteRepository.stringColumn(resultSet, 'thumb_url')
    g.thumbUrlL = LocalFavoriteRepository.stringColumn(resultSet, 'thumb_url_l')
    g.imgWidth = Math.floor(LocalFavoriteRepository.numberColumn(resultSet, 'img_width'))
    g.imgHeight = Math.floor(LocalFavoriteRepository.numberColumn(resultSet, 'img_height'))
    g.englishTitle = LocalFavoriteRepository.stringColumn(resultSet, 'english_title')
    g.japaneseTitle = LocalFavoriteRepository.stringColumn(resultSet, 'japanese_title')
    g.category = LocalFavoriteRepository.stringColumn(resultSet, 'category')
    g.uploader = LocalFavoriteRepository.stringColumn(resultSet, 'uploader')
    g.postTime = LocalFavoriteRepository.stringColumn(resultSet, 'post_time')
    g.fileCount = LocalFavoriteRepository.stringColumn(resultSet, 'file_count')
    g.rating = LocalFavoriteRepository.numberColumn(resultSet, 'rating')
    g.ratingFallBack = LocalFavoriteRepository.numberColumn(resultSet, 'rating_fallback')
    g.colorRating = LocalFavoriteRepository.stringColumn(resultSet, 'color_rating')
    g.favNote = LocalFavoriteRepository.stringColumn(resultSet, 'fav_note')
    g.favcat = 'l'
    g.favTitle = LocalFavoriteRepository.stringColumn(resultSet, 'fav_title')
    if (g.favTitle.length === 0) {
      g.favTitle = 'Local'
    }
    g.expunged = LocalFavoriteRepository.numberColumn(resultSet, 'expunged') > 0
    g.lastViewTime = Math.floor(LocalFavoriteRepository.numberColumn(resultSet, 'last_view_time'))
    return g
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
