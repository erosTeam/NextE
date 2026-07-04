import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { notificationManager } from '@kit.NotificationKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { AppStrings } from '../i18n/AppStrings'
import { connectDownloadSettings } from '../state/DownloadSettingsState'

const DOWNLOAD_COMPLETE_NOTIFICATION_ID: number = 1301

function notificationText(title: string): string {
  const trimmed: string = title.trim()
  return AppStrings.get('download_notify_complete_body')
    .replace('%s', trimmed.length > 0 ? trimmed : AppStrings.get('settings_download'))
}

export class DownloadNotificationService {
  static async requestEnable(context: common.UIAbilityContext): Promise<void> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled()
      if (enabled) {
        return
      }
      await notificationManager.requestEnableNotification(context)
      DiagnosticLogger.info('download', 'notification_permission_requested', 'enabled')
    } catch (error) {
      const businessError: BusinessError = error as BusinessError
      DiagnosticLogger.warn(
        'download',
        'notification_permission_request_failed',
        `code=${businessError.code} message=${businessError.message}`,
      )
    }
  }

  static async publishDownloadComplete(title: string): Promise<void> {
    if (!connectDownloadSettings().notifyOnComplete) {
      return
    }
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled()
      if (!enabled) {
        DiagnosticLogger.warn('download', 'notification_publish_skipped', 'disabled')
        return
      }
      const request: notificationManager.NotificationRequest = {
        id: DOWNLOAD_COMPLETE_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: AppStrings.get('download_notify_complete_title'),
            text: notificationText(title),
          },
        },
      }
      await notificationManager.publish(request)
      DiagnosticLogger.info('download', 'notification_publish_done', DiagnosticLogger.ownerHash(title))
    } catch (error) {
      const businessError: BusinessError = error as BusinessError
      DiagnosticLogger.warn(
        'download',
        'notification_publish_failed',
        `code=${businessError.code} message=${businessError.message}`,
      )
    }
  }
}
