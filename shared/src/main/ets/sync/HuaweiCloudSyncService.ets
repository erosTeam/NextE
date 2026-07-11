import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { GalleryReadProgressSettings } from '../settings/GalleryReadProgressSettings'
import { LocalFavSettings } from '../settings/LocalFavSettings'
import { SyncSettings } from '../settings/SyncSettings'
import { ViewedHistorySettings } from '../settings/ViewedHistorySettings'
import { SYNC_STATUS_FAILED, SYNC_STATUS_OK, connectSyncSettings } from '../state/SyncSettingsState'
import { LocalDataStore } from '../storage/LocalDataStore'
import { cloudSyncTablesForSelection } from './CloudSyncFeatures'
import { HUAWEI_CLOUD_SYNC_BUILD_ENABLED } from './HuaweiCloudSyncBuildFlag'
import { SyncService } from './SyncService'
import { SyncLocalDataAdapter } from './SyncLocalDataAdapter'
import { SyncDatasetSelection } from './SyncTypes'

const SYNC_PERMISSION: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC'
const CLOUD_DISABLED_CODE: number = 3
const CLOUD_SYNC_TIMEOUT_MS: number = 240000
const IMAGE_BLOCK_USER_RULES_TABLE: string = 'image_block_user_rules'

export class HuaweiCloudSyncService {
  private static lastMarkedSignature: string = ''
  private static autoSyncListenerBound: boolean = false
  private static lastRunDetail: string = ''

  static available(): boolean {
    return HUAWEI_CLOUD_SYNC_BUILD_ENABLED
  }

  static lastRunDetailMessage(): string {
    return HuaweiCloudSyncService.lastRunDetail
  }

  static tablesForSelection(selection: SyncDatasetSelection): string[] {
    return cloudSyncTablesForSelection(selection)
  }

  static async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    if (!HuaweiCloudSyncService.available()) {
      return false
    }
    try {
      const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const result = await at.requestPermissionsFromUser(context, [SYNC_PERMISSION])
      const authResults: number[] = result.authResults
      const granted: boolean = authResults.length > 0 && authResults[0] === 0
      DiagnosticLogger.info('sync', 'huawei_cloud_permission', `granted=${granted}`)
      return granted
    } catch (error) {
      DiagnosticLogger.warn('sync', 'huawei_cloud_permission_failed', (error as Error).message)
      return false
    }
  }

  static async markDistributedTables(
    context: common.UIAbilityContext,
    selection: SyncDatasetSelection = SyncSettings.selection(SyncSettings.current()),
  ): Promise<boolean> {
    if (!HuaweiCloudSyncService.available()) {
      HuaweiCloudSyncService.lastRunDetail = 'provider unavailable'
      return false
    }
    const tables: string[] = HuaweiCloudSyncService.tablesForSelection(selection)
    if (tables.length <= 0) {
      HuaweiCloudSyncService.lastRunDetail = 'no selected tables'
      DiagnosticLogger.warn('sync', 'huawei_cloud_no_tables', 'selection is empty')
      return false
    }
    const signature: string = tables.join(',')
    if (HuaweiCloudSyncService.lastMarkedSignature !== signature) {
      try {
        const store: relationalStore.RdbStore = await LocalDataStore.open(context)
        const config: relationalStore.DistributedConfig = { autoSync: false }
        await store.setDistributedTables(
          tables,
          relationalStore.DistributedType.DISTRIBUTED_CLOUD,
          config,
        )
        HuaweiCloudSyncService.lastMarkedSignature = signature
        HuaweiCloudSyncService.bindAutoSyncProgress(context, store)
        DiagnosticLogger.info('sync', 'huawei_cloud_tables_marked', `tables=${signature}`)
      } catch (error) {
        const message: string = (error as Error).message
        HuaweiCloudSyncService.lastRunDetail = message
        DiagnosticLogger.warn('sync', 'huawei_cloud_mark_tables_failed', message)
        return false
      }
    }
    if (tables.includes(IMAGE_BLOCK_USER_RULES_TABLE)) {
      await SyncLocalDataAdapter.prepareHuaweiCloudTables(context, selection)
    }
    return true
  }

  static async cloudSyncNow(
    context: common.UIAbilityContext,
    selection: SyncDatasetSelection = SyncSettings.selection(SyncSettings.current()),
  ): Promise<boolean> {
    if (!HuaweiCloudSyncService.available()) {
      HuaweiCloudSyncService.lastRunDetail = 'provider unavailable'
      return false
    }
    HuaweiCloudSyncService.lastRunDetail = ''
    const state = connectSyncSettings()
    state.huaweiCloudSyncing = true
    state.huaweiCloudLastCloudDisabled = false
    state.huaweiCloudLastDetail = ''
    try {
      const tables: string[] = HuaweiCloudSyncService.tablesForSelection(selection)
      if (tables.length <= 0) {
        HuaweiCloudSyncService.lastRunDetail = 'no selected tables'
        await SyncSettings.markHuaweiCloudRun(
          context,
          SYNC_STATUS_FAILED,
          false,
          HuaweiCloudSyncService.lastRunDetail,
        )
        return false
      }
      if (selection.readProgress) {
        await GalleryReadProgressSettings.flushForSync(context)
      }
      if (selection.viewedHistory) {
        await ViewedHistorySettings.flushForSync(context)
      }
      if (selection.localFavorites) {
        await LocalFavSettings.flushForSync(context)
      }
      const marked: boolean = await HuaweiCloudSyncService.markDistributedTables(context, selection)
      if (!marked) {
        if (HuaweiCloudSyncService.lastRunDetail.length <= 0) {
          HuaweiCloudSyncService.lastRunDetail = 'setDistributedTables failed'
        }
        await SyncSettings.markHuaweiCloudRun(
          context,
          SYNC_STATUS_FAILED,
          false,
          HuaweiCloudSyncService.lastRunDetail,
        )
        return false
      }
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const code: number = await HuaweiCloudSyncService.waitCloudSyncFinish(store, tables, context)
      let ok: boolean = code === 0
      const cloudDisabled: boolean = code === CLOUD_DISABLED_CODE
      if (!ok && HuaweiCloudSyncService.lastRunDetail.length <= 0) {
        HuaweiCloudSyncService.lastRunDetail = `code=${code}`
      }
      await SyncSettings.markHuaweiCloudRun(
        context,
        ok ? SYNC_STATUS_OK : SYNC_STATUS_FAILED,
        cloudDisabled,
        ok ? '' : HuaweiCloudSyncService.lastRunDetail,
      )
      DiagnosticLogger.info(
        'sync',
        'huawei_cloud_sync_done',
        `ok=${ok},code=${code},detail=${HuaweiCloudSyncService.lastRunDetail}`,
      )
      return ok
    } catch (error) {
      HuaweiCloudSyncService.lastRunDetail = (error as Error).message
      await SyncSettings.markHuaweiCloudRun(
        context,
        SYNC_STATUS_FAILED,
        false,
        HuaweiCloudSyncService.lastRunDetail,
      )
      DiagnosticLogger.warn('sync', 'huawei_cloud_sync_failed', HuaweiCloudSyncService.lastRunDetail)
      return false
    } finally {
      state.huaweiCloudSyncing = false
    }
  }

  static async runScheduledSync(context: common.UIAbilityContext, reason: string): Promise<boolean> {
    DiagnosticLogger.info('sync', 'huawei_cloud_scheduled_request', `reason=${reason}`)
    return await HuaweiCloudSyncService.cloudSyncNow(
      context,
      SyncSettings.selection(SyncSettings.current()),
    )
  }

  static async tryEnableStartup(context: common.UIAbilityContext): Promise<void> {
    if (!HuaweiCloudSyncService.available()) {
      return
    }
    const snapshot = SyncSettings.current()
    if (!snapshot.huaweiCloudEnabled) {
      return
    }
    const marked: boolean = await HuaweiCloudSyncService.markDistributedTables(
      context,
      SyncSettings.selection(snapshot),
    )
    if (!marked) {
      return
    }
    DiagnosticLogger.info('sync', 'huawei_cloud_startup_ready', 'distributed tables marked')
  }

  private static waitCloudSyncFinish(
    store: relationalStore.RdbStore,
    tables: string[],
    context: common.UIAbilityContext,
    mode: relationalStore.SyncMode = relationalStore.SyncMode.SYNC_MODE_TIME_FIRST,
  ): Promise<number> {
    return new Promise<number>((resolve: (value: number) => void) => {
      let settled: boolean = false
      const finish = (value: number): void => {
        if (!settled) {
          settled = true
          resolve(value)
        }
      }
      const timer = setTimeout(() => {
        HuaweiCloudSyncService.lastRunDetail = `timeout=${CLOUD_SYNC_TIMEOUT_MS}ms`
        finish(-1)
      }, CLOUD_SYNC_TIMEOUT_MS)
      store
        .cloudSync(
          mode,
          tables,
          (progress: relationalStore.ProgressDetails) => {
            DiagnosticLogger.info(
              'sync',
              'huawei_cloud_progress',
              `schedule=${progress.schedule},code=${progress.code}`,
            )
            if (progress.schedule === relationalStore.Progress.SYNC_FINISH) {
              clearTimeout(timer)
              HuaweiCloudSyncService.lastRunDetail =
                HuaweiCloudSyncService.progressDetailMessage(progress, tables)
              HuaweiCloudSyncService.logTableDetails('huawei_cloud_table_detail', progress, tables)
              HuaweiCloudSyncService.refreshAfterDownload(context, progress, tables)
              finish(progress.code)
            }
          },
        )
        .catch((error: Error) => {
          clearTimeout(timer)
          HuaweiCloudSyncService.lastRunDetail =
            error.message.length > 0 ? error.message : 'cloudSync call rejected'
          DiagnosticLogger.warn('sync', 'huawei_cloud_call_failed', error.message)
          finish(-1)
        })
    })
  }

  private static bindAutoSyncProgress(
    context: common.UIAbilityContext,
    store: relationalStore.RdbStore,
  ): void {
    if (HuaweiCloudSyncService.autoSyncListenerBound) {
      return
    }
    HuaweiCloudSyncService.autoSyncListenerBound = true
    store.on('autoSyncProgress', (progress: relationalStore.ProgressDetails) => {
      DiagnosticLogger.info(
        'sync',
        'huawei_cloud_auto_progress',
        `schedule=${progress.schedule},code=${progress.code}`,
      )
      if (progress.schedule === relationalStore.Progress.SYNC_FINISH) {
        const selection = SyncSettings.selection(SyncSettings.current())
        const tables = HuaweiCloudSyncService.tablesForSelection(selection)
        HuaweiCloudSyncService.lastRunDetail =
          HuaweiCloudSyncService.progressDetailMessage(progress, tables)
        HuaweiCloudSyncService.logTableDetails('huawei_cloud_auto_table_detail', progress, tables)
        HuaweiCloudSyncService.refreshAfterDownload(context, progress, tables)
        SyncSettings.markHuaweiCloudRun(
          context,
          progress.code === 0 ? SYNC_STATUS_OK : SYNC_STATUS_FAILED,
          progress.code === CLOUD_DISABLED_CODE,
          progress.code === 0 ? '' : HuaweiCloudSyncService.lastRunDetail,
        ).catch((error: Error) => {
          DiagnosticLogger.warn('sync', 'huawei_cloud_auto_record_failed', error.message)
        })
      }
    })
  }

  private static refreshAfterDownload(
    context: common.UIAbilityContext,
    progress: relationalStore.ProgressDetails,
    tables: string[],
  ): void {
    if (!HuaweiCloudSyncService.hasDownloads(progress, tables)) {
      return
    }
    SyncServiceBridge.refresh(context, SyncSettings.selection(SyncSettings.current()))
  }

  private static hasDownloads(progress: relationalStore.ProgressDetails, tables: string[]): boolean {
    const details: Record<string, relationalStore.TableDetails> = progress.details
    if (!details) {
      return false
    }
    let total: number = 0
    tables.forEach((table: string) => {
      const detail: relationalStore.TableDetails | undefined = details[table]
      if (detail !== undefined && detail !== null) {
        total = total + detail.download.total
      }
    })
    return total > 0
  }

  private static logTableDetails(
    event: string,
    progress: relationalStore.ProgressDetails,
    tables: string[],
  ): void {
    const details: Record<string, relationalStore.TableDetails> = progress.details
    if (!details) {
      return
    }
    tables.forEach((table: string) => {
      const detail: relationalStore.TableDetails | undefined = details[table]
      if (detail === undefined || detail === null) {
        DiagnosticLogger.info('sync', event, `table=${table},present=false`)
        return
      }
      DiagnosticLogger.info(
        'sync',
        event,
        `table=${table},up=${detail.upload.successful}/${detail.upload.total},down=${detail.download.successful}/${detail.download.total},fail=${detail.upload.failed + detail.download.failed}`,
      )
    })
  }

  private static progressDetailMessage(
    progress: relationalStore.ProgressDetails,
    tables: string[],
  ): string {
    const details: Record<string, relationalStore.TableDetails> = progress.details
    const parts: string[] = [`code=${progress.code}`]
    if (!details) {
      parts.push('details=none')
      return parts.join('; ')
    }
    tables.forEach((table: string) => {
      const detail: relationalStore.TableDetails | undefined = details[table]
      if (detail === undefined || detail === null) {
        if (progress.code !== 0) {
          parts.push(`${table}:missing`)
        }
        return
      }
      const failed: number = detail.upload.failed + detail.download.failed
      if (failed > 0) {
        parts.push(
          `${table}:up=${detail.upload.successful}/${detail.upload.total},` +
            `down=${detail.download.successful}/${detail.download.total},fail=${failed}`,
        )
      }
    })
    if (progress.code !== 0 && parts.length === 1) {
      parts.push('failed table details unavailable')
    }
    return parts.join('; ')
  }
}

class SyncServiceBridge {
  static refresh(context: common.UIAbilityContext, selection: SyncDatasetSelection): void {
    SyncLocalDataAdapter.applyHuaweiCloudTables(context, selection)
      .then(() => SyncService.refreshSelectedState(context, selection))
      .catch((error: Error) => {
        DiagnosticLogger.warn('sync', 'huawei_cloud_refresh_state_failed', error.message)
      })
  }
}
