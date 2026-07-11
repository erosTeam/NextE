import { common } from '@kit.AbilityKit'
import { HuaweiCloudSyncScheduler } from './HuaweiCloudSyncScheduler'
import { WebDavSyncScheduler } from './WebDavSyncScheduler'

export class SyncScheduler {
  /**
   * Backup restore is a local transaction: it must not start a provider run with partially restored
   * settings or publish its snapshot before the user explicitly resumes sync later.
   */
  static suspendAutomaticSync(): void {
    HuaweiCloudSyncScheduler.suspendAutomaticSync()
    WebDavSyncScheduler.suspendAutomaticSync()
  }

  static resumeAutomaticSync(): void {
    HuaweiCloudSyncScheduler.resumeAutomaticSync()
    WebDavSyncScheduler.resumeAutomaticSync()
  }

  static rememberContext(context: common.UIAbilityContext): void {
    HuaweiCloudSyncScheduler.rememberContext(context)
    WebDavSyncScheduler.rememberContext(context)
  }

  static requestAfterLocalWrite(context: common.UIAbilityContext, reason: string): void {
    HuaweiCloudSyncScheduler.requestAfterLocalWrite(context, reason)
    WebDavSyncScheduler.requestAfterLocalWrite(context, reason)
  }

  static requestAfterForeground(context: common.UIAbilityContext, reason: string): void {
    HuaweiCloudSyncScheduler.requestAfterForeground(context, reason)
    WebDavSyncScheduler.requestAfterForeground(context, reason)
  }
}
