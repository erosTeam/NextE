import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import {
  DownloadArchiverTask,
  DownloadArchiverParseSource,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
} from '../model/DownloadGalleryTask'
import { LocalDataStore } from './LocalDataStore'

const SCOPE_GLOBAL: string = 'global'
const SQL_SELECT_TASKS: string =
  'SELECT gid, token, title, title_jp, thumb_url, page_count, category, uploader, upgrade_from_gid, queued_at, ' +
  'prepared_at, first_page_count, preview_page_count, prepare_error, prefer_original, status FROM download_gallery_tasks ' +
  'WHERE scope_key = ? ORDER BY queued_at DESC, gid DESC'
const SQL_SELECT_SEEDS: string =
  'SELECT page, imgkey, image_page_url, thumb_url, image_url, origin_image_url, show_key, reload_key, ' +
  'file_path, bytes_written, downloaded_at, download_error FROM download_gallery_seeds ' +
  'WHERE scope_key = ? AND gid = ? AND token = ? ORDER BY position_index ASC, page ASC'
const SQL_UPSERT_TASK: string =
  'INSERT OR REPLACE INTO download_gallery_tasks ' +
  '(scope_key, gid, token, title, title_jp, thumb_url, page_count, category, uploader, upgrade_from_gid, queued_at, ' +
  'prepared_at, first_page_count, preview_page_count, prepare_error, prefer_original, status) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
const SQL_UPSERT_SEED: string =
  'INSERT OR REPLACE INTO download_gallery_seeds ' +
  '(scope_key, gid, token, image_page_url, position_index, page, imgkey, thumb_url, image_url, ' +
  'origin_image_url, show_key, reload_key, file_path, bytes_written, downloaded_at, download_error) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
const SQL_DELETE_TASKS: string = 'DELETE FROM download_gallery_tasks WHERE scope_key = ?'
const SQL_DELETE_SEEDS: string = 'DELETE FROM download_gallery_seeds WHERE scope_key = ?'
const SQL_DELETE_SEEDS_FOR_TASK: string =
  'DELETE FROM download_gallery_seeds WHERE scope_key = ? AND gid = ? AND token = ?'
const SQL_SELECT_ARCHIVER_TASKS: string =
  'SELECT tag, gid, token, title, thumb_url, dltype, resolution, parse_source, url, file_name, file_path, queued_at, downloaded_at, ' +
  'bytes_written, bytes_total, progress, error, status FROM download_archiver_tasks ' +
  'WHERE scope_key = ? ORDER BY queued_at DESC, tag DESC'
const SQL_UPSERT_ARCHIVER_TASK: string =
  'INSERT OR REPLACE INTO download_archiver_tasks ' +
  '(scope_key, tag, gid, token, title, thumb_url, dltype, resolution, parse_source, url, file_name, file_path, queued_at, downloaded_at, ' +
  'bytes_written, bytes_total, progress, error, status) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
const SQL_DELETE_ARCHIVER_TASKS: string = 'DELETE FROM download_archiver_tasks WHERE scope_key = ?'

export class DownloadQueueRepository {
  static async load(context: common.UIAbilityContext): Promise<DownloadGalleryTask[]> {
    const out: DownloadGalleryTask[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_TASKS, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const task: DownloadGalleryTask = DownloadQueueRepository.readTask(resultSet)
        if (task.gid.length > 0) {
          task.imageSeeds = await DownloadQueueRepository.loadSeeds(store, task.gid, task.token)
          task.syncProgressCounts()
          out.push(task)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async replaceAll(context: common.UIAbilityContext, tasks: DownloadGalleryTask[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      await store.executeSql(SQL_DELETE_SEEDS, [SCOPE_GLOBAL])
      await store.executeSql(SQL_DELETE_TASKS, [SCOPE_GLOBAL])
      for (let i: number = 0; i < tasks.length; i++) {
        await DownloadQueueRepository.upsertTask(store, tasks[i])
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  static async replaceGalleryTask(context: common.UIAbilityContext, task: DownloadGalleryTask): Promise<void> {
    if (task.gid.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      await store.executeSql(SQL_DELETE_SEEDS_FOR_TASK, [SCOPE_GLOBAL, task.gid, task.token])
      await DownloadQueueRepository.upsertTask(store, task)
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  static async loadArchiver(context: common.UIAbilityContext): Promise<DownloadArchiverTask[]> {
    const out: DownloadArchiverTask[] = []
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_ARCHIVER_TASKS, [SCOPE_GLOBAL])
    try {
      while (resultSet.goToNextRow()) {
        const task: DownloadArchiverTask = DownloadQueueRepository.readArchiverTask(resultSet)
        if (task.tag.length > 0) {
          out.push(task)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  static async replaceAllArchiver(context: common.UIAbilityContext, tasks: DownloadArchiverTask[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      await store.executeSql(SQL_DELETE_ARCHIVER_TASKS, [SCOPE_GLOBAL])
      for (let i: number = 0; i < tasks.length; i++) {
        await DownloadQueueRepository.upsertArchiverTask(store, tasks[i])
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  static async replaceArchiverTask(context: common.UIAbilityContext, task: DownloadArchiverTask): Promise<void> {
    if (task.tag.length === 0) {
      return
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await DownloadQueueRepository.upsertArchiverTask(store, task)
  }

  private static async upsertTask(
    store: relationalStore.RdbStore,
    task: DownloadGalleryTask,
  ): Promise<void> {
    if (task.gid.length === 0) {
      return
    }
    await store.executeSql(SQL_UPSERT_TASK, [
      SCOPE_GLOBAL,
      task.gid,
      task.token,
      task.title,
      task.titleJp,
      task.thumbUrl,
      task.pageCount,
      task.category,
      task.uploader,
      task.upgradeFromGid,
      task.queuedAt,
      task.preparedAt,
      task.firstPageCount,
      task.previewPageCount,
      task.prepareError,
      task.preferOriginal ? 1 : 0,
      DownloadQueueRepository.normalizedGalleryStatusForWrite(task),
    ])
    for (let i: number = 0; i < task.imageSeeds.length; i++) {
      const seed: DownloadImageSeed = task.imageSeeds[i]
      if (seed.imagePageUrl.length > 0) {
        await DownloadQueueRepository.upsertSeed(store, task.gid, task.token, seed, i)
      }
    }
  }

  private static async upsertSeed(
    store: relationalStore.RdbStore,
    gid: string,
    token: string,
    seed: DownloadImageSeed,
    index: number,
  ): Promise<void> {
    await store.executeSql(SQL_UPSERT_SEED, [
      SCOPE_GLOBAL,
      gid,
      token,
      seed.imagePageUrl,
      index,
      seed.page,
      seed.imgkey,
      seed.thumbUrl,
      seed.imageUrl,
      seed.originImageUrl,
      seed.showKey,
      seed.reloadKey,
      seed.filePath,
      seed.bytesWritten,
      seed.downloadedAt,
      seed.downloadError,
    ])
  }

  private static async loadSeeds(
    store: relationalStore.RdbStore,
    gid: string,
    token: string,
  ): Promise<DownloadImageSeed[]> {
    const out: DownloadImageSeed[] = []
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_SEEDS, [
      SCOPE_GLOBAL,
      gid,
      token,
    ])
    try {
      while (resultSet.goToNextRow()) {
        const seed: DownloadImageSeed = DownloadQueueRepository.readSeed(resultSet)
        if (seed.imagePageUrl.length > 0) {
          out.push(seed)
        }
      }
    } finally {
      resultSet.close()
    }
    return out
  }

  private static readTask(resultSet: relationalStore.ResultSet): DownloadGalleryTask {
    const task: DownloadGalleryTask = new DownloadGalleryTask()
    task.gid = DownloadQueueRepository.stringColumn(resultSet, 'gid')
    task.token = DownloadQueueRepository.stringColumn(resultSet, 'token')
    task.title = DownloadQueueRepository.stringColumn(resultSet, 'title')
    task.titleJp = DownloadQueueRepository.stringColumn(resultSet, 'title_jp')
    task.thumbUrl = DownloadQueueRepository.stringColumn(resultSet, 'thumb_url')
    task.pageCount = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'page_count'))
    task.category = DownloadQueueRepository.stringColumn(resultSet, 'category')
    task.uploader = DownloadQueueRepository.stringColumn(resultSet, 'uploader')
    task.upgradeFromGid = DownloadQueueRepository.stringColumn(resultSet, 'upgrade_from_gid')
    task.queuedAt = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'queued_at'))
    task.preparedAt = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'prepared_at'))
    task.firstPageCount = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'first_page_count'))
    task.previewPageCount = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'preview_page_count'))
    task.prepareError = DownloadQueueRepository.stringColumn(resultSet, 'prepare_error')
    task.preferOriginal = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'prefer_original')) === 1
    task.status = DownloadQueueRepository.normalizeStatus(DownloadQueueRepository.stringColumn(resultSet, 'status'))
    return task
  }

  private static readSeed(resultSet: relationalStore.ResultSet): DownloadImageSeed {
    const seed: DownloadImageSeed = new DownloadImageSeed()
    seed.page = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'page'))
    seed.imgkey = DownloadQueueRepository.stringColumn(resultSet, 'imgkey')
    seed.imagePageUrl = DownloadQueueRepository.stringColumn(resultSet, 'image_page_url')
    seed.thumbUrl = DownloadQueueRepository.stringColumn(resultSet, 'thumb_url')
    seed.imageUrl = DownloadQueueRepository.stringColumn(resultSet, 'image_url')
    seed.originImageUrl = DownloadQueueRepository.stringColumn(resultSet, 'origin_image_url')
    seed.showKey = DownloadQueueRepository.stringColumn(resultSet, 'show_key')
    seed.reloadKey = DownloadQueueRepository.stringColumn(resultSet, 'reload_key')
    seed.filePath = DownloadQueueRepository.stringColumn(resultSet, 'file_path')
    seed.bytesWritten = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'bytes_written'))
    seed.downloadedAt = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'downloaded_at'))
    seed.downloadError = DownloadQueueRepository.stringColumn(resultSet, 'download_error')
    return seed
  }

  private static async upsertArchiverTask(
    store: relationalStore.RdbStore,
    task: DownloadArchiverTask,
  ): Promise<void> {
    if (task.tag.length === 0) {
      return
    }
    await store.executeSql(SQL_UPSERT_ARCHIVER_TASK, [
      SCOPE_GLOBAL,
      task.tag,
      task.gid,
      task.token,
      task.title,
      task.thumbUrl,
      task.dltype,
      task.resolution,
      DownloadQueueRepository.normalizeParseSource(task.parseSource),
      task.url,
      task.fileName,
      task.filePath,
      task.queuedAt,
      task.downloadedAt,
      task.bytesWritten,
      task.bytesTotal,
      task.progress,
      task.error,
      DownloadQueueRepository.normalizeStatus(task.status),
    ])
  }

  private static readArchiverTask(resultSet: relationalStore.ResultSet): DownloadArchiverTask {
    const task: DownloadArchiverTask = new DownloadArchiverTask()
    task.tag = DownloadQueueRepository.stringColumn(resultSet, 'tag')
    task.gid = DownloadQueueRepository.stringColumn(resultSet, 'gid')
    task.token = DownloadQueueRepository.stringColumn(resultSet, 'token')
    task.title = DownloadQueueRepository.stringColumn(resultSet, 'title')
    task.thumbUrl = DownloadQueueRepository.stringColumn(resultSet, 'thumb_url')
    task.dltype = DownloadQueueRepository.stringColumn(resultSet, 'dltype')
    task.resolution = DownloadQueueRepository.stringColumn(resultSet, 'resolution')
    task.parseSource = DownloadQueueRepository.normalizeParseSource(
      DownloadQueueRepository.stringColumn(resultSet, 'parse_source'),
    )
    task.url = DownloadQueueRepository.stringColumn(resultSet, 'url')
    task.fileName = DownloadQueueRepository.stringColumn(resultSet, 'file_name')
    task.filePath = DownloadQueueRepository.stringColumn(resultSet, 'file_path')
    task.queuedAt = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'queued_at'))
    task.downloadedAt = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'downloaded_at'))
    task.bytesWritten = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'bytes_written'))
    task.bytesTotal = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'bytes_total'))
    task.progress = Math.floor(DownloadQueueRepository.numberColumn(resultSet, 'progress'))
    task.error = DownloadQueueRepository.stringColumn(resultSet, 'error')
    task.status = DownloadQueueRepository.normalizeStatus(DownloadQueueRepository.stringColumn(resultSet, 'status'))
    return task
  }

  private static normalizeStatus(status: string): string {
    if (
      status === DownloadGalleryTaskStatus.PREPARING ||
      status === DownloadGalleryTaskStatus.READY ||
      status === DownloadGalleryTaskStatus.DOWNLOADING ||
      status === DownloadGalleryTaskStatus.PAUSED ||
      status === DownloadGalleryTaskStatus.PARTIAL ||
      status === DownloadGalleryTaskStatus.COMPLETE ||
      status === DownloadGalleryTaskStatus.ERROR
    ) {
      return status
    }
    return DownloadGalleryTaskStatus.QUEUED
  }

  private static normalizedGalleryStatusForWrite(task: DownloadGalleryTask): string {
    const status: string = DownloadQueueRepository.normalizeStatus(task.status)
    if (status === DownloadGalleryTaskStatus.COMPLETE && !task.isDownloadComplete()) {
      return task.downloadedCount() > 0
        ? DownloadGalleryTaskStatus.PARTIAL
        : DownloadGalleryTaskStatus.READY
    }
    return status
  }

  private static normalizeParseSource(value: string): string {
    if (value === DownloadArchiverParseSource.BOT) {
      return DownloadArchiverParseSource.BOT
    }
    return DownloadArchiverParseSource.OFFICIAL
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
