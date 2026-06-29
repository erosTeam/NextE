import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  SYNC_STATUS_FAILED,
  SYNC_STATUS_IDLE,
  SYNC_STATUS_OK,
  connectSyncSettings,
} from '../state/SyncSettingsState'
import { SyncDatasetSelection } from '../sync/SyncTypes'

export class SyncSettingsSnapshot {
  webdavUrl: string = ''
  webdavUsername: string = ''
  webdavPassword: string = ''
  webdavEnabled: boolean = false
  datasetReadProgress: boolean = true
  datasetViewedHistory: boolean = true
  datasetLocalFavorites: boolean = true
  datasetSearchHistory: boolean = true
  datasetLocalBlock: boolean = true
  datasetCustomProfiles: boolean = true
  lastRunAt: number = 0
  lastStatus: string = SYNC_STATUS_IDLE
  huaweiCloudEnabled: boolean = false
  huaweiCloudLastRunAt: number = 0
  huaweiCloudLastStatus: string = SYNC_STATUS_IDLE
  huaweiCloudLastCloudDisabled: boolean = false
}

/** Sync provider settings. WebDAV password is intentionally local-only and never exported. */
export class SyncSettings {
  static apply(snapshot: SyncSettingsSnapshot): void {
    const state = connectSyncSettings()
    state.webdavUrl = snapshot.webdavUrl
    state.webdavUsername = snapshot.webdavUsername
    state.webdavPassword = snapshot.webdavPassword
    state.webdavEnabled = snapshot.webdavEnabled
    state.datasetReadProgress = snapshot.datasetReadProgress
    state.datasetViewedHistory = snapshot.datasetViewedHistory
    state.datasetLocalFavorites = snapshot.datasetLocalFavorites
    state.datasetSearchHistory = snapshot.datasetSearchHistory
    state.datasetLocalBlock = snapshot.datasetLocalBlock
    state.datasetCustomProfiles = snapshot.datasetCustomProfiles
    state.lastRunAt = Math.max(0, snapshot.lastRunAt)
    state.lastStatus = SyncSettings.normalizeStatus(snapshot.lastStatus)
    state.huaweiCloudEnabled = snapshot.huaweiCloudEnabled
    state.huaweiCloudLastRunAt = Math.max(0, snapshot.huaweiCloudLastRunAt)
    state.huaweiCloudLastStatus = SyncSettings.normalizeStatus(snapshot.huaweiCloudLastStatus)
    state.huaweiCloudLastCloudDisabled = snapshot.huaweiCloudLastCloudDisabled
  }

  static current(): SyncSettingsSnapshot {
    const state = connectSyncSettings()
    const snapshot = new SyncSettingsSnapshot()
    snapshot.webdavUrl = state.webdavUrl
    snapshot.webdavUsername = state.webdavUsername
    snapshot.webdavPassword = state.webdavPassword
    snapshot.webdavEnabled = state.webdavEnabled
    snapshot.datasetReadProgress = state.datasetReadProgress
    snapshot.datasetViewedHistory = state.datasetViewedHistory
    snapshot.datasetLocalFavorites = state.datasetLocalFavorites
    snapshot.datasetSearchHistory = state.datasetSearchHistory
    snapshot.datasetLocalBlock = state.datasetLocalBlock
    snapshot.datasetCustomProfiles = state.datasetCustomProfiles
    snapshot.lastRunAt = state.lastRunAt
    snapshot.lastStatus = SyncSettings.normalizeStatus(state.lastStatus)
    snapshot.huaweiCloudEnabled = state.huaweiCloudEnabled
    snapshot.huaweiCloudLastRunAt = state.huaweiCloudLastRunAt
    snapshot.huaweiCloudLastStatus = SyncSettings.normalizeStatus(state.huaweiCloudLastStatus)
    snapshot.huaweiCloudLastCloudDisabled = state.huaweiCloudLastCloudDisabled
    return snapshot
  }

  static selection(snapshot: SyncSettingsSnapshot): SyncDatasetSelection {
    const selection = new SyncDatasetSelection()
    selection.readProgress = snapshot.datasetReadProgress
    selection.viewedHistory = snapshot.datasetViewedHistory
    selection.localFavorites = snapshot.datasetLocalFavorites
    selection.searchHistory = snapshot.datasetSearchHistory
    selection.localBlock = snapshot.datasetLocalBlock
    selection.imageBlock = snapshot.datasetLocalBlock
    selection.customProfiles = snapshot.datasetCustomProfiles
    return selection
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const snapshot = new SyncSettingsSnapshot()
      snapshot.webdavUrl = store.getSync(StorageKeys.SYNC_WEBDAV_URL, '') as string
      snapshot.webdavUsername = store.getSync(StorageKeys.SYNC_WEBDAV_USERNAME, '') as string
      snapshot.webdavPassword = store.getSync(StorageKeys.SYNC_WEBDAV_PASSWORD, '') as string
      snapshot.webdavEnabled =
        store.getSync(StorageKeys.SYNC_WEBDAV_ENABLED, snapshot.webdavUrl.trim().length > 0) as boolean
      snapshot.datasetReadProgress =
        store.getSync(StorageKeys.SYNC_DATASET_READ_PROGRESS, true) as boolean
      snapshot.datasetViewedHistory =
        store.getSync(StorageKeys.SYNC_DATASET_VIEWED_HISTORY, true) as boolean
      snapshot.datasetLocalFavorites =
        store.getSync(StorageKeys.SYNC_DATASET_LOCAL_FAVORITES, true) as boolean
      snapshot.datasetSearchHistory =
        store.getSync(StorageKeys.SYNC_DATASET_SEARCH_HISTORY, true) as boolean
      snapshot.datasetLocalBlock =
        store.getSync(StorageKeys.SYNC_DATASET_LOCAL_BLOCK, true) as boolean
      snapshot.datasetCustomProfiles =
        store.getSync(StorageKeys.SYNC_DATASET_CUSTOM_PROFILES, true) as boolean
      snapshot.lastRunAt = store.getSync(StorageKeys.SYNC_LAST_RUN_AT, 0) as number
      snapshot.lastStatus = store.getSync(StorageKeys.SYNC_LAST_STATUS, SYNC_STATUS_IDLE) as string
      snapshot.huaweiCloudEnabled =
        store.getSync(StorageKeys.SYNC_HUAWEI_CLOUD_ENABLED, false) as boolean
      snapshot.huaweiCloudLastRunAt =
        store.getSync(StorageKeys.SYNC_HUAWEI_CLOUD_LAST_RUN_AT, 0) as number
      snapshot.huaweiCloudLastStatus =
        store.getSync(StorageKeys.SYNC_HUAWEI_CLOUD_LAST_STATUS, SYNC_STATUS_IDLE) as string
      snapshot.huaweiCloudLastCloudDisabled =
        store.getSync(StorageKeys.SYNC_HUAWEI_CLOUD_LAST_CLOUD_DISABLED, false) as boolean
      SyncSettings.apply(snapshot)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'sync_restore_failed', (error as Error).message)
      SyncSettings.apply(new SyncSettingsSnapshot())
    }
  }

  static async save(context: common.UIAbilityContext, snapshot: SyncSettingsSnapshot): Promise<void> {
    snapshot.webdavUrl = snapshot.webdavUrl.trim()
    snapshot.webdavUsername = snapshot.webdavUsername.trim()
    snapshot.lastRunAt = Math.max(0, snapshot.lastRunAt)
    snapshot.lastStatus = SyncSettings.normalizeStatus(snapshot.lastStatus)
    snapshot.huaweiCloudLastRunAt = Math.max(0, snapshot.huaweiCloudLastRunAt)
    snapshot.huaweiCloudLastStatus = SyncSettings.normalizeStatus(snapshot.huaweiCloudLastStatus)
    SyncSettings.apply(snapshot)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.SYNC_WEBDAV_URL, snapshot.webdavUrl)
      store.putSync(StorageKeys.SYNC_WEBDAV_USERNAME, snapshot.webdavUsername)
      store.putSync(StorageKeys.SYNC_WEBDAV_ENABLED, snapshot.webdavEnabled)
      store.putSync(StorageKeys.SYNC_WEBDAV_PASSWORD, snapshot.webdavPassword)
      store.putSync(StorageKeys.SYNC_DATASET_READ_PROGRESS, snapshot.datasetReadProgress)
      store.putSync(StorageKeys.SYNC_DATASET_VIEWED_HISTORY, snapshot.datasetViewedHistory)
      store.putSync(StorageKeys.SYNC_DATASET_LOCAL_FAVORITES, snapshot.datasetLocalFavorites)
      store.putSync(StorageKeys.SYNC_DATASET_SEARCH_HISTORY, snapshot.datasetSearchHistory)
      store.putSync(StorageKeys.SYNC_DATASET_LOCAL_BLOCK, snapshot.datasetLocalBlock)
      store.putSync(StorageKeys.SYNC_DATASET_CUSTOM_PROFILES, snapshot.datasetCustomProfiles)
      store.putSync(StorageKeys.SYNC_LAST_RUN_AT, snapshot.lastRunAt)
      store.putSync(StorageKeys.SYNC_LAST_STATUS, snapshot.lastStatus)
      store.putSync(StorageKeys.SYNC_HUAWEI_CLOUD_ENABLED, snapshot.huaweiCloudEnabled)
      store.putSync(StorageKeys.SYNC_HUAWEI_CLOUD_LAST_RUN_AT, snapshot.huaweiCloudLastRunAt)
      store.putSync(StorageKeys.SYNC_HUAWEI_CLOUD_LAST_STATUS, snapshot.huaweiCloudLastStatus)
      store.putSync(
        StorageKeys.SYNC_HUAWEI_CLOUD_LAST_CLOUD_DISABLED,
        snapshot.huaweiCloudLastCloudDisabled,
      )
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'sync_save_failed', (error as Error).message)
    }
  }

  static async markRun(
    context: common.UIAbilityContext,
    status: string,
    timeMs: number = Date.now(),
  ): Promise<void> {
    const snapshot = SyncSettings.current()
    snapshot.lastRunAt = Math.max(0, timeMs)
    snapshot.lastStatus = SyncSettings.normalizeStatus(status)
    await SyncSettings.save(context, snapshot)
  }

  static async markHuaweiCloudRun(
    context: common.UIAbilityContext,
    status: string,
    cloudDisabled: boolean = false,
    timeMs: number = Date.now(),
  ): Promise<void> {
    const snapshot = SyncSettings.current()
    snapshot.huaweiCloudLastRunAt = Math.max(0, timeMs)
    snapshot.huaweiCloudLastStatus = SyncSettings.normalizeStatus(status)
    snapshot.huaweiCloudLastCloudDisabled = cloudDisabled
    await SyncSettings.save(context, snapshot)
  }

  static configured(snapshot: SyncSettingsSnapshot): boolean {
    return snapshot.webdavEnabled && snapshot.webdavUrl.trim().length > 0
  }

  static normalizeStatus(status: string): string {
    if (status === SYNC_STATUS_OK || status === SYNC_STATUS_FAILED) {
      return status
    }
    return SYNC_STATUS_IDLE
  }
}
