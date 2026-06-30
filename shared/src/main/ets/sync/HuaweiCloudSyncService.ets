import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { SyncSettings } from '../settings/SyncSettings'
import { SYNC_STATUS_FAILED, SYNC_STATUS_OK, connectSyncSettings } from '../state/SyncSettingsState'
import { LocalDataStore } from '../storage/LocalDataStore'
import { cloudSyncTablesForSelection } from './CloudSyncFeatures'
import { HUAWEI_CLOUD_SYNC_BUILD_ENABLED } from './HuaweiCloudSyncBuildFlag'
import { SyncService } from './SyncService'
import { SyncLocalDataAdapter } from './SyncLocalDataAdapter'
import { SyncDatasetSelection } from './SyncTypes'

const SYNC_PERMISSION: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC'
const CLOUD_DISABLED_CODE: number = 3
const CLOUD_SYNC_TIMEOUT_MS: number = 30000

export class HuaweiCloudSyncService {
  private static lastMarkedSignature: string = ''
  private static autoSyncListenerBound: boolean = false

  static available(): boolean {
    return HUAWEI_CLOUD_SYNC_BUILD_ENABLED
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
      return false
    }
    const tables: string[] = HuaweiCloudSyncService.tablesForSelection(selection)
    if (tables.length <= 0) {
      DiagnosticLogger.warn('sync', 'huawei_cloud_no_tables', 'selection is empty')
      return false
    }
    await SyncLocalDataAdapter.prepareHuaweiCloudTables(context, selection)
    const signature: string = tables.join(',')
    if (HuaweiCloudSyncService.lastMarkedSignature === signature) {
      return true
    }
    try {
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const config: relationalStore.DistributedConfig = { autoSync: true }
      await store.setDistributedTables(
        tables,
        relationalStore.DistributedType.DISTRIBUTED_CLOUD,
        config,
      )
      HuaweiCloudSyncService.lastMarkedSignature = signature
      HuaweiCloudSyncService.bindAutoSyncProgress(context, store)
      DiagnosticLogger.info('sync', 'huawei_cloud_tables_marked', `tables=${signature}`)
      return true
    } catch (error) {
      DiagnosticLogger.warn('sync', 'huawei_cloud_mark_tables_failed', (error as Error).message)
      return false
    }
  }

  static async cloudSyncNow(
    context: common.UIAbilityContext,
    selection: SyncDatasetSelection = SyncSettings.selection(SyncSettings.current()),
  ): Promise<boolean> {
    if (!HuaweiCloudSyncService.available()) {
      return false
    }
    const state = connectSyncSettings()
    state.huaweiCloudSyncing = true
    state.huaweiCloudLastCloudDisabled = false
    try {
      const tables: string[] = HuaweiCloudSyncService.tablesForSelection(selection)
      if (tables.length <= 0) {
        await SyncSettings.markHuaweiCloudRun(context, SYNC_STATUS_FAILED, false)
        return false
      }
      const marked: boolean = await HuaweiCloudSyncService.markDistributedTables(context, selection)
      if (!marked) {
        await SyncSettings.markHuaweiCloudRun(context, SYNC_STATUS_FAILED, false)
        return false
      }
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const code: number = await HuaweiCloudSyncService.waitCloudSyncFinish(store, tables, context)
      const ok: boolean = code === 0
      const cloudDisabled: boolean = code === CLOUD_DISABLED_CODE
      await SyncSettings.markHuaweiCloudRun(
        context,
        ok ? SYNC_STATUS_OK : SYNC_STATUS_FAILED,
        cloudDisabled,
      )
      DiagnosticLogger.info('sync', 'huawei_cloud_sync_done', `ok=${ok},code=${code}`)
      return ok
    } catch (error) {
      await SyncSettings.markHuaweiCloudRun(context, SYNC_STATUS_FAILED, false)
      DiagnosticLogger.warn('sync', 'huawei_cloud_sync_failed', (error as Error).message)
      return false
    } finally {
      state.huaweiCloudSyncing = false
    }
  }

  static async runScheduledSync(context: common.UIAbilityContext, reason: string): Promise<boolean> {
    DiagnosticLogger.info('sync', 'huawei_cloud_scheduled_request', `reason=${reason}`)
    return await HuaweiCloudSyncService.cloudSyncNow(context)
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
        finish(-1)
      }, CLOUD_SYNC_TIMEOUT_MS)
      store
        .cloudSync(
          relationalStore.SyncMode.SYNC_MODE_TIME_FIRST,
          (progress: relationalStore.ProgressDetails) => {
            DiagnosticLogger.info(
              'sync',
              'huawei_cloud_progress',
              `schedule=${progress.schedule},code=${progress.code}`,
            )
            if (progress.schedule === relationalStore.Progress.SYNC_FINISH) {
              clearTimeout(timer)
              HuaweiCloudSyncService.logTableDetails('huawei_cloud_table_detail', progress, tables)
              HuaweiCloudSyncService.refreshAfterDownload(context, progress, tables)
              finish(progress.code)
            }
          },
        )
        .catch((error: Error) => {
          clearTimeout(timer)
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
        HuaweiCloudSyncService.logTableDetails('huawei_cloud_auto_table_detail', progress, tables)
        HuaweiCloudSyncService.refreshAfterDownload(context, progress, tables)
        SyncSettings.markHuaweiCloudRun(
          context,
          progress.code === 0 ? SYNC_STATUS_OK : SYNC_STATUS_FAILED,
          progress.code === CLOUD_DISABLED_CODE,
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
