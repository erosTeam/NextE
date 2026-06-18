import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { DownloadGalleryTask, DownloadGalleryTaskStatus } from '../model/DownloadGalleryTask'
import { connectDownloadQueue } from '../state/DownloadQueueState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const MAX_GALLERY_TASKS: number = 200

/** Single writer for the local Gallery download queue. */
export class DownloadQueueSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.DOWNLOAD_GALLERY_QUEUE, '[]') as string
      connectDownloadQueue().galleryTasks = DownloadQueueSettings.parse(raw)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_restore_failed', (error as Error).message)
    }
  }

  /**
   * Add or refresh a gallery queue task. Returns true when a new task was inserted; duplicate gid/token
   * keeps a single entry and refreshes its metadata, matching eros_fe's unique GalleryTask gid.
   */
  static async enqueueGallery(
    context: common.UIAbilityContext,
    task: DownloadGalleryTask,
  ): Promise<boolean> {
    if (task.gid.length === 0) {
      return false
    }
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    let existed: boolean = false
    task.queuedAt = Date.now()
    task.status = DownloadGalleryTaskStatus.QUEUED
    next.push(task.copy())
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      if (it.gid === task.gid && it.token === task.token) {
        existed = true
        return
      }
      if (next.length < MAX_GALLERY_TASKS) {
        next.push(it.copy())
      }
    })
    state.galleryTasks = next
    await DownloadQueueSettings.persist(context, next)
    return !existed
  }

  static async removeGallery(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = state.galleryTasks
      .filter((it: DownloadGalleryTask) => it.gid !== gid || it.token !== token)
      .map((it: DownloadGalleryTask) => it.copy())
    state.galleryTasks = next
    await DownloadQueueSettings.persist(context, next)
  }

  private static async persist(
    context: common.UIAbilityContext,
    tasks: DownloadGalleryTask[],
  ): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.DOWNLOAD_GALLERY_QUEUE, JSON.stringify(tasks))
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_save_failed', (error as Error).message)
    }
  }

  private static parse(raw: string): DownloadGalleryTask[] {
    const out: DownloadGalleryTask[] = []
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        ;(arr as Object[]).forEach((v: Object) => {
          const rec = v as DownloadGalleryTask
          if (rec !== null && typeof rec.gid === 'string' && rec.gid.length > 0) {
            const task: DownloadGalleryTask = new DownloadGalleryTask()
            task.gid = rec.gid
            task.token = typeof rec.token === 'string' ? rec.token : ''
            task.title = typeof rec.title === 'string' ? rec.title : ''
            task.titleJp = typeof rec.titleJp === 'string' ? rec.titleJp : ''
            task.thumbUrl = typeof rec.thumbUrl === 'string' ? rec.thumbUrl : ''
            task.pageCount = typeof rec.pageCount === 'number' ? rec.pageCount : 0
            task.category = typeof rec.category === 'string' ? rec.category : ''
            task.uploader = typeof rec.uploader === 'string' ? rec.uploader : ''
            task.queuedAt = typeof rec.queuedAt === 'number' ? rec.queuedAt : 0
            task.status = DownloadGalleryTaskStatus.QUEUED
            if (out.length < MAX_GALLERY_TASKS) {
              out.push(task)
            }
          }
        })
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_parse_failed', (error as Error).message)
    }
    return out
  }
}
