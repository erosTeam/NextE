import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { SyncSettings } from '../settings/SyncSettings'
import {
  SYNC_STATUS_FAILED,
  SYNC_STATUS_OK,
} from '../state/SyncSettingsState'
import { WebDavSyncConfig, WebDavSyncService } from './WebDavSyncService'

const LOCAL_WRITE_DEBOUNCE_MS: number = 15000
const FOREGROUND_DEBOUNCE_MS: number = 3000
const MIN_ATTEMPT_INTERVAL_MS: number = 45000
const RETRY_BASE_MS: number = 60000
const RETRY_MAX_MS: number = 300000

export class WebDavSyncScheduler {
  private static context: common.UIAbilityContext | null = null
  private static timerId: number = 0
  private static scheduledAt: number = 0
  private static inFlight: boolean = false
  private static pendingReason: string = ''
  private static lastAttemptAt: number = 0
  private static failureCount: number = 0

  static rememberContext(context: common.UIAbilityContext): void {
    WebDavSyncScheduler.context = context
  }

  static requestAfterLocalWrite(context: common.UIAbilityContext, reason: string): void {
    WebDavSyncScheduler.request(context, reason, LOCAL_WRITE_DEBOUNCE_MS)
  }

  static requestAfterForeground(context: common.UIAbilityContext, reason: string): void {
    WebDavSyncScheduler.request(context, reason, FOREGROUND_DEBOUNCE_MS)
  }

  private static request(
    context: common.UIAbilityContext,
    reason: string,
    requestedDelayMs: number,
  ): void {
    WebDavSyncScheduler.context = context
    const snapshot = SyncSettings.current()
    if (!SyncSettings.configured(snapshot)) {
      return
    }
    WebDavSyncScheduler.pendingReason = reason
    const delayMs: number = WebDavSyncScheduler.nextDelayMs(Date.now(), requestedDelayMs)
    WebDavSyncScheduler.scheduleTimer(delayMs, reason)
  }

  private static nextDelayMs(now: number, requestedDelayMs: number): number {
    let delayMs: number = Math.max(0, requestedDelayMs)
    if (WebDavSyncScheduler.lastAttemptAt > 0) {
      const nextAllowedAt: number = WebDavSyncScheduler.lastAttemptAt + MIN_ATTEMPT_INTERVAL_MS
      if (nextAllowedAt > now) {
        delayMs = Math.max(delayMs, nextAllowedAt - now)
      }
    }
    if (WebDavSyncScheduler.failureCount > 0 && WebDavSyncScheduler.lastAttemptAt > 0) {
      const retryAt: number = WebDavSyncScheduler.lastAttemptAt + WebDavSyncScheduler.retryDelayMs()
      if (retryAt > now) {
        delayMs = Math.max(delayMs, retryAt - now)
      }
    }
    return delayMs
  }

  private static retryDelayMs(): number {
    let delayMs: number = RETRY_BASE_MS
    let count: number = WebDavSyncScheduler.failureCount
    while (count > 1 && delayMs < RETRY_MAX_MS) {
      delayMs = delayMs * 2
      count = count - 1
    }
    return Math.min(delayMs, RETRY_MAX_MS)
  }

  private static scheduleTimer(delayMs: number, reason: string): void {
    const now: number = Date.now()
    const dueAt: number = now + Math.max(0, delayMs)
    if (WebDavSyncScheduler.timerId > 0 && WebDavSyncScheduler.scheduledAt <= dueAt) {
      DiagnosticLogger.info(
        'sync',
        'webdav_schedule_kept',
        `reason=${reason},dueInMs=${Math.max(0, WebDavSyncScheduler.scheduledAt - now)}`,
      )
      return
    }
    if (WebDavSyncScheduler.timerId > 0) {
      clearTimeout(WebDavSyncScheduler.timerId)
      WebDavSyncScheduler.timerId = 0
    }
    WebDavSyncScheduler.scheduledAt = dueAt
    WebDavSyncScheduler.timerId = setTimeout(() => {
      WebDavSyncScheduler.fire()
    }, Math.max(0, delayMs))
    DiagnosticLogger.info('sync', 'webdav_scheduled', `reason=${reason},delayMs=${Math.max(0, delayMs)}`)
  }

  private static fire(): void {
    WebDavSyncScheduler.timerId = 0
    WebDavSyncScheduler.scheduledAt = 0
    const context: common.UIAbilityContext | null = WebDavSyncScheduler.context
    const reason: string = WebDavSyncScheduler.pendingReason.length > 0 ?
      WebDavSyncScheduler.pendingReason :
      'scheduled'
    WebDavSyncScheduler.pendingReason = ''
    const snapshot = SyncSettings.current()
    if (context === null || !SyncSettings.configured(snapshot)) {
      return
    }
    if (WebDavSyncScheduler.inFlight) {
      WebDavSyncScheduler.pendingReason = reason
      WebDavSyncScheduler.scheduleTimer(MIN_ATTEMPT_INTERVAL_MS, reason)
      return
    }
    const config: WebDavSyncConfig = new WebDavSyncConfig()
    config.directoryUrl = snapshot.webdavUrl
    config.username = snapshot.webdavUsername
    config.password = snapshot.webdavPassword
    config.selection = SyncSettings.selection(snapshot)
    WebDavSyncScheduler.inFlight = true
    WebDavSyncScheduler.lastAttemptAt = Date.now()
    DiagnosticLogger.info('sync', 'webdav_scheduled_start', `reason=${reason}`)
    WebDavSyncService.syncNow(context, config)
      .then(() => {
        WebDavSyncScheduler.finish(true, reason)
        SyncSettings.markRun(context, SYNC_STATUS_OK)
      })
      .catch((error: Error) => {
        WebDavSyncScheduler.finish(false, reason)
        SyncSettings.markRun(context, SYNC_STATUS_FAILED)
        DiagnosticLogger.warn('sync', 'webdav_scheduled_failed', error.message)
      })
      .finally(() => {
        WebDavSyncScheduler.inFlight = false
        if (
          WebDavSyncScheduler.pendingReason.length > 0 &&
          SyncSettings.configured(SyncSettings.current())
        ) {
          const pending: string = WebDavSyncScheduler.pendingReason
          WebDavSyncScheduler.scheduleTimer(
            WebDavSyncScheduler.nextDelayMs(Date.now(), LOCAL_WRITE_DEBOUNCE_MS),
            pending,
          )
        }
      })
  }

  private static finish(ok: boolean, reason: string): void {
    if (ok) {
      WebDavSyncScheduler.failureCount = 0
    } else {
      WebDavSyncScheduler.failureCount = Math.min(WebDavSyncScheduler.failureCount + 1, 4)
    }
    DiagnosticLogger.info(
      'sync',
      'webdav_scheduled_done',
      `ok=${ok},reason=${reason},failureCount=${WebDavSyncScheduler.failureCount}`,
    )
  }
}
