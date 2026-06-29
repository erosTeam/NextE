import { common } from '@kit.AbilityKit'
import { HuaweiCloudSyncScheduler } from './HuaweiCloudSyncScheduler'
import { WebDavSyncScheduler } from './WebDavSyncScheduler'

export class SyncScheduler {
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
