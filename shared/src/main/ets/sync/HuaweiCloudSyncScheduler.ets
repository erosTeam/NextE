import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { SyncSettings } from '../settings/SyncSettings'
import { connectSyncSettings } from '../state/SyncSettingsState'

export type HuaweiCloudSyncExecutor = (
  context: common.UIAbilityContext,
  reason: string,
) => Promise<boolean>

const LOCAL_WRITE_DEBOUNCE_MS: number = 15000
const FOREGROUND_DEBOUNCE_MS: number = 3000
const MIN_ATTEMPT_INTERVAL_MS: number = 45000
const RETRY_BASE_MS: number = 60000
const RETRY_MAX_MS: number = 300000

// Coalesce noisy local writes into a near-term cloud sync; system autoSync still remains enabled.
export class HuaweiCloudSyncScheduler {
  private static context: common.UIAbilityContext | null = null
  private static executor: HuaweiCloudSyncExecutor | null = null
  private static timerId: number = 0
  private static scheduledAt: number = 0
  private static inFlight: boolean = false
  private static pendingReason: string = ''
  private static lastAttemptAt: number = 0
  private static failureCount: number = 0

  static bindExecutor(executor: HuaweiCloudSyncExecutor): void {
    HuaweiCloudSyncScheduler.executor = executor
  }

  static rememberContext(context: common.UIAbilityContext): void {
    HuaweiCloudSyncScheduler.context = context
  }

  static requestAfterLocalWrite(context: common.UIAbilityContext, reason: string): void {
    HuaweiCloudSyncScheduler.request(context, reason, LOCAL_WRITE_DEBOUNCE_MS)
  }

  static requestAfterForeground(context: common.UIAbilityContext, reason: string): void {
    HuaweiCloudSyncScheduler.request(context, reason, FOREGROUND_DEBOUNCE_MS)
  }

  private static request(
    context: common.UIAbilityContext,
    reason: string,
    requestedDelayMs: number,
  ): void {
    HuaweiCloudSyncScheduler.context = context
    if (!SyncSettings.current().huaweiCloudEnabled) {
      DiagnosticLogger.info('sync', 'huawei_cloud_schedule_skipped', `reason=${reason},enabled=false`)
      return
    }
    HuaweiCloudSyncScheduler.pendingReason = reason
    const delayMs: number = HuaweiCloudSyncScheduler.nextDelayMs(Date.now(), requestedDelayMs)
    HuaweiCloudSyncScheduler.scheduleTimer(delayMs, reason)
  }

  private static nextDelayMs(now: number, requestedDelayMs: number): number {
    let delayMs: number = Math.max(0, requestedDelayMs)
    if (HuaweiCloudSyncScheduler.lastAttemptAt > 0) {
      const nextAllowedAt: number = HuaweiCloudSyncScheduler.lastAttemptAt + MIN_ATTEMPT_INTERVAL_MS
      if (nextAllowedAt > now) {
        delayMs = Math.max(delayMs, nextAllowedAt - now)
      }
    }
    if (HuaweiCloudSyncScheduler.failureCount > 0 && HuaweiCloudSyncScheduler.lastAttemptAt > 0) {
      const retryAt: number = HuaweiCloudSyncScheduler.lastAttemptAt + HuaweiCloudSyncScheduler.retryDelayMs()
      if (retryAt > now) {
        delayMs = Math.max(delayMs, retryAt - now)
      }
    }
    return delayMs
  }

  private static retryDelayMs(): number {
    let delayMs: number = RETRY_BASE_MS
    let count: number = HuaweiCloudSyncScheduler.failureCount
    while (count > 1 && delayMs < RETRY_MAX_MS) {
      delayMs = delayMs * 2
      count = count - 1
    }
    return Math.min(delayMs, RETRY_MAX_MS)
  }

  private static scheduleTimer(delayMs: number, reason: string): void {
    const now: number = Date.now()
    const dueAt: number = now + Math.max(0, delayMs)
    if (HuaweiCloudSyncScheduler.timerId > 0 && HuaweiCloudSyncScheduler.scheduledAt <= dueAt) {
      DiagnosticLogger.info(
        'sync',
        'huawei_cloud_schedule_kept',
        `reason=${reason},dueInMs=${Math.max(0, HuaweiCloudSyncScheduler.scheduledAt - now)}`,
      )
      return
    }
    if (HuaweiCloudSyncScheduler.timerId > 0) {
      clearTimeout(HuaweiCloudSyncScheduler.timerId)
      HuaweiCloudSyncScheduler.timerId = 0
    }
    HuaweiCloudSyncScheduler.scheduledAt = dueAt
    HuaweiCloudSyncScheduler.timerId = setTimeout(() => {
      HuaweiCloudSyncScheduler.fire()
    }, Math.max(0, delayMs))
    DiagnosticLogger.info(
      'sync',
      'huawei_cloud_scheduled',
      `reason=${reason},delayMs=${Math.max(0, delayMs)}`,
    )
  }

  private static fire(): void {
    HuaweiCloudSyncScheduler.timerId = 0
    HuaweiCloudSyncScheduler.scheduledAt = 0
    const context: common.UIAbilityContext | null = HuaweiCloudSyncScheduler.context
    const executor: HuaweiCloudSyncExecutor | null = HuaweiCloudSyncScheduler.executor
    const reason: string = HuaweiCloudSyncScheduler.pendingReason.length > 0 ?
      HuaweiCloudSyncScheduler.pendingReason :
      'scheduled'
    HuaweiCloudSyncScheduler.pendingReason = ''
    if (
      context === null ||
      executor === null ||
      !SyncSettings.current().huaweiCloudEnabled
    ) {
      return
    }
    if (HuaweiCloudSyncScheduler.inFlight || connectSyncSettings().huaweiCloudSyncing) {
      HuaweiCloudSyncScheduler.pendingReason = reason
      HuaweiCloudSyncScheduler.scheduleTimer(MIN_ATTEMPT_INTERVAL_MS, reason)
      return
    }
    HuaweiCloudSyncScheduler.inFlight = true
    HuaweiCloudSyncScheduler.lastAttemptAt = Date.now()
    DiagnosticLogger.info('sync', 'huawei_cloud_scheduled_start', `reason=${reason}`)
    executor(context, reason)
      .then((ok: boolean) => {
        HuaweiCloudSyncScheduler.finish(ok, reason)
      })
      .catch((error: Error) => {
        HuaweiCloudSyncScheduler.finish(false, reason)
        DiagnosticLogger.warn('sync', 'huawei_cloud_scheduled_failed', error.message)
      })
      .finally(() => {
        HuaweiCloudSyncScheduler.inFlight = false
        if (
          HuaweiCloudSyncScheduler.pendingReason.length > 0 &&
          SyncSettings.current().huaweiCloudEnabled
        ) {
          const pending: string = HuaweiCloudSyncScheduler.pendingReason
          HuaweiCloudSyncScheduler.scheduleTimer(
            HuaweiCloudSyncScheduler.nextDelayMs(Date.now(), LOCAL_WRITE_DEBOUNCE_MS),
            pending,
          )
        }
      })
  }

  private static finish(ok: boolean, reason: string): void {
    if (ok) {
      HuaweiCloudSyncScheduler.failureCount = 0
    } else {
      HuaweiCloudSyncScheduler.failureCount = Math.min(HuaweiCloudSyncScheduler.failureCount + 1, 4)
    }
    DiagnosticLogger.info(
      'sync',
      'huawei_cloud_scheduled_done',
      `ok=${ok},reason=${reason},failureCount=${HuaweiCloudSyncScheduler.failureCount}`,
    )
  }
}
