import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit'
import {
  DownloadArchiverTask,
  DownloadArchiverParseSource,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
} from '../model/DownloadGalleryTask'
import { EhGallery } from '../model/EhGallery'
import { EhGalleryImage } from '../model/EhGalleryImage'
import {
  DownloadQueueState,
  connectDownloadQueue,
  isDownloadQueuePageActive,
  publishDownloadQueueChanged,
} from '../state/DownloadQueueState'
import {
  connectDownloadSettings,
  DownloadOriginalMode,
  DownloadSettingsState,
} from '../state/DownloadSettingsState'
import { connectSiteMode } from '../state/SiteModeState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'
import { EhApiService, GalleryDetailResult } from '../network/EhApiService'
import { EhErrorKind } from '../network/EhError'
import { EhErrorText } from '../i18n/EhErrorText'
import { AppStrings } from '../i18n/AppStrings'
import { ImageResolveService } from '../services/ImageResolveService'
import { ArchiveBotResolveResult, ArchiveBotService } from '../services/ArchiveBotService'
import { DownloadNotificationService } from '../services/DownloadNotificationService'
import { DownloadQueueRepository } from '../storage/DownloadQueueRepository'
import { DownloadSettings } from './DownloadSettings'

const MAX_GALLERY_TASKS: number = 200
const MAX_ARCHIVER_TASKS: number = 100
const DOWNLOAD_GALLERY_DIR: string = 'download-gallery'
const DOWNLOAD_ARCHIVER_DIR: string = 'download-archiver'
const DOWNLOAD_EXPORT_DIR: string = 'download-exports'
const DOWNLOAD_DIRECTORY_UNAVAILABLE: string = 'Download directory unavailable'
const ARCHIVER_ACCEPT: string = 'application/zip,application/octet-stream,*/*'
const ARCHIVER_READ_TIMEOUT_MS: number = 30 * 60 * 1000
const ARCHIVER_READ_CACHE_DIR: string = 'download-archiver-read'
const DOWNLOAD_METADATA_FILE: string = 'metadata.json'
const ARCHIVER_METADATA_SUFFIX: string = '.metadata.json'
const NO_MEDIA_MARKER_FILE: string = '.nomedia'
const ARCHIVE_BOT_SETTINGS_INCOMPLETE: string = 'Archive bot settings are incomplete'
const DOWNLOAD_PATH_TITLE_MAX_LENGTH: number = 96
const DOWNLOAD_PERF_APPLY_WARN_MS: number = 16
const DOWNLOAD_PERF_PERSIST_WARN_MS: number = 24
const DOWNLOAD_PERF_METADATA_WARN_MS: number = 16
const DOWNLOAD_PERF_METADATA_WARN_BYTES: number = 64 * 1024
const DOWNLOAD_PERF_SIGNAL_WINDOW_MS: number = 2000
const DOWNLOAD_PROGRESS_METADATA_FLUSH_MS: number = 5000
const DOWNLOAD_QUEUE_PROGRESS_INTERVAL_MS: number = 250

export class DownloadDirectoryImportResult {
  galleryTasks: number = 0
  archiverTasks: number = 0
  scannedGalleryTasks: number = 0
  scannedArchiverTasks: number = 0
}

class DownloadImageSeedMetadata {
  page: number = 0
  imgkey: string = ''
  imagePageUrl: string = ''
  thumbUrl: string = ''
  imageUrl: string = ''
  originImageUrl: string = ''
  showKey: string = ''
  reloadKey: string = ''
  filePath: string = ''
  bytesWritten: number = 0
  downloadedAt: number = 0
  downloadError: string = ''
}

class DownloadGalleryTaskMetadata {
  gid: string = ''
  token: string = ''
  title: string = ''
  titleJp: string = ''
  thumbUrl: string = ''
  imgWidth: number = 0
  imgHeight: number = 0
  pageCount: number = 0
  category: string = ''
  uploader: string = ''
  upgradeFromGid: string = ''
  queuedAt: number = 0
  preparedAt: number = 0
  firstPageCount: number = 0
  previewPageCount: number = 0
  imageSeeds: DownloadImageSeedMetadata[] = []
  prepareError: string = ''
  preferOriginal: boolean = false
  status: string = DownloadGalleryTaskStatus.QUEUED
}

class DownloadArchiverTaskMetadata {
  tag: string = ''
  gid: string = ''
  token: string = ''
  title: string = ''
  thumbUrl: string = ''
  imgWidth: number = 0
  imgHeight: number = 0
  dltype: string = ''
  resolution: string = ''
  parseSource: string = DownloadArchiverParseSource.OFFICIAL
  url: string = ''
  fileName: string = ''
  filePath: string = ''
  queuedAt: number = 0
  downloadedAt: number = 0
  bytesWritten: number = 0
  bytesTotal: number = 0
  progress: number = 0
  error: string = ''
  status: string = DownloadGalleryTaskStatus.QUEUED
}

class DownloadSeedResult {
  originalSeed: DownloadImageSeed = new DownloadImageSeed()
  image: EhGalleryImage = new EhGalleryImage()
  filePath: string = ''
  bytes: number = 0
  error: string = ''
  applied: boolean = false
}

class DownloadGalleryActiveProgress {
  page: number = 0
  loaded: number = 0
  total: number = 0
  updatedAt: number = 0
}

/** Single writer for the local Gallery download queue. */
export class DownloadQueueSettings {
  private static galleryPreparations: Map<string, Promise<void>> = new Map<string, Promise<void>>()
  private static galleryDownloads: Map<string, Promise<void>> = new Map<string, Promise<void>>()
  private static archiverDownloads: Map<string, Promise<void>> = new Map<string, Promise<void>>()
  private static cancelledGalleryDownloads: Set<string> = new Set<string>()
  private static cancelledArchiverDownloads: Set<string> = new Set<string>()
  private static galleryProgressPulses: Map<string, number> = new Map<string, number>()
  private static galleryProgressLogPulses: Map<string, number> = new Map<string, number>()
  private static galleryProgressSignalWindows: Map<string, number> = new Map<string, number>()
  private static galleryProgressSignalCounts: Map<string, number> = new Map<string, number>()
  private static galleryActiveProgress: Map<string, DownloadGalleryActiveProgress> =
    new Map<string, DownloadGalleryActiveProgress>()
  private static galleryMetadataFlushTimers: Map<string, number> = new Map<string, number>()
  private static pendingGalleryMetadataTasks: Map<string, DownloadGalleryTask> = new Map<string, DownloadGalleryTask>()
  private static archiverProgressPulses: Map<string, number> = new Map<string, number>()
  private static archiverProgressLogPulses: Map<string, number> = new Map<string, number>()
  private static loggedDownloadDirs: Set<string> = new Set<string>()
  private static downloadPublicRoot: string = ''
  private static downloadRootRequest: Promise<boolean> | null = null
  private static pendingResume: Promise<void> | null = null

  private static setGalleryTasks(state: DownloadQueueState, tasks: DownloadGalleryTask[]): void {
    const next: DownloadGalleryTask[] = []
    tasks.forEach((task: DownloadGalleryTask) => {
      const existing: DownloadGalleryTask | null = DownloadQueueSettings.findExistingGalleryTask(
        state.galleryTasks,
        task.gid,
        task.token,
        task.preferOriginal,
      )
      if (existing === null) {
        next.push(task.copy())
        return
      }
      existing.assignFrom(task)
      next.push(existing)
    })
    state.replaceGalleryTasks(next)
  }

  private static setArchiverTasks(state: DownloadQueueState, tasks: DownloadArchiverTask[]): void {
    const next: DownloadArchiverTask[] = []
    tasks.forEach((task: DownloadArchiverTask) => {
      const existing: DownloadArchiverTask | null = DownloadQueueSettings.findExistingArchiverTask(
        state.archiverTasks,
        task.tag,
      )
      if (existing === null) {
        next.push(task.copy())
        return
      }
      existing.assignFrom(task)
      next.push(existing)
    })
    state.replaceArchiverTasks(next)
  }

  private static findExistingGalleryTask(
    tasks: DownloadGalleryTask[],
    gid: string,
    token: string,
    preferOriginal: boolean,
  ): DownloadGalleryTask | null {
    for (let i: number = 0; i < tasks.length; i++) {
      const task: DownloadGalleryTask = tasks[i]
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        return task
      }
    }
    return null
  }

  private static findExistingArchiverTask(
    tasks: DownloadArchiverTask[],
    tag: string,
  ): DownloadArchiverTask | null {
    for (let i: number = 0; i < tasks.length; i++) {
      const task: DownloadArchiverTask = tasks[i]
      if (task.tag === tag) {
        return task
      }
    }
    return null
  }

  private static findGalleryTaskIn(
    tasks: DownloadGalleryTask[],
    gid: string,
    token: string,
    preferOriginal: boolean | null = null,
  ): DownloadGalleryTask | undefined {
    return tasks.find((task: DownloadGalleryTask) => {
      if (task.gid !== gid) {
        return false
      }
      if (token.length > 0 && task.token !== token) {
        return false
      }
      if (preferOriginal !== null && task.preferOriginal !== preferOriginal) {
        return false
      }
      return true
    })
  }

  private static findArchiverTaskIn(
    tasks: DownloadArchiverTask[],
    tag: string,
  ): DownloadArchiverTask | undefined {
    return tasks.find((task: DownloadArchiverTask) => task.tag === tag)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await DownloadQueueSettings.migrateLegacyPreferences(context)
      const galleryTasks: DownloadGalleryTask[] = DownloadQueueSettings.mergeRestoredGalleryTasks(
        DownloadQueueSettings.normalizeRestoredGalleryTasks(await DownloadQueueRepository.load(context)),
        DownloadQueueSettings.normalizeRestoredGalleryTasks(DownloadQueueSettings.loadGalleryMetadataTasks(context)),
      )
      const archiverTasks: DownloadArchiverTask[] = DownloadQueueSettings.hydrateArchiverTasksFromGalleryTasks(
        DownloadQueueSettings.mergeRestoredArchiverTasks(
          DownloadQueueSettings.normalizeRestoredArchiverTasks(await DownloadQueueRepository.loadArchiver(context)),
          DownloadQueueSettings.normalizeRestoredArchiverTasks(DownloadQueueSettings.loadArchiverMetadataTasks(context)),
        ),
        galleryTasks,
      )
      const state = connectDownloadQueue()
      DownloadQueueSettings.setGalleryTasks(state, galleryTasks)
      DownloadQueueSettings.setArchiverTasks(state, archiverTasks)
      await DownloadQueueSettings.persist(context, galleryTasks)
      await DownloadQueueSettings.persistArchiver(context, archiverTasks)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_restore_failed', (error as Error).message)
    }
  }

  static async importTasksFromDownloadDirectory(context: common.UIAbilityContext): Promise<DownloadDirectoryImportResult> {
    const result: DownloadDirectoryImportResult = new DownloadDirectoryImportResult()
    if (!await DownloadQueueSettings.ensureDownloadStorageReady(context)) {
      DiagnosticLogger.warn('download', 'download_directory_import_unavailable', DOWNLOAD_DIRECTORY_UNAVAILABLE)
      return result
    }
    const state: DownloadQueueState = connectDownloadQueue()
    const currentGalleryTasks: DownloadGalleryTask[] =
      DownloadQueueSettings.normalizeRestoredGalleryTasks(state.galleryTasks)
    const currentArchiverTasks: DownloadArchiverTask[] =
      DownloadQueueSettings.normalizeRestoredArchiverTasks(state.archiverTasks)
    const scannedGalleryTasks: DownloadGalleryTask[] =
      DownloadQueueSettings.normalizeRestoredGalleryTasks(DownloadQueueSettings.loadGalleryMetadataTasks(context))
    const scannedArchiverTasks: DownloadArchiverTask[] =
      DownloadQueueSettings.normalizeRestoredArchiverTasks(DownloadQueueSettings.loadArchiverMetadataTasks(context))
    result.scannedGalleryTasks = scannedGalleryTasks.length
    result.scannedArchiverTasks = scannedArchiverTasks.length
    result.galleryTasks = DownloadQueueSettings.countNewGalleryTasks(currentGalleryTasks, scannedGalleryTasks)
    result.archiverTasks = DownloadQueueSettings.countNewArchiverTasks(currentArchiverTasks, scannedArchiverTasks)

    const galleryTasks: DownloadGalleryTask[] =
      DownloadQueueSettings.mergeRestoredGalleryTasks(currentGalleryTasks, scannedGalleryTasks)
    const archiverTasks: DownloadArchiverTask[] = DownloadQueueSettings.hydrateArchiverTasksFromGalleryTasks(
      DownloadQueueSettings.mergeRestoredArchiverTasks(currentArchiverTasks, scannedArchiverTasks),
      galleryTasks,
    )
    DownloadQueueSettings.setGalleryTasks(state, galleryTasks)
    DownloadQueueSettings.setArchiverTasks(state, archiverTasks)
    await DownloadQueueSettings.persist(context, galleryTasks)
    await DownloadQueueSettings.persistArchiver(context, archiverTasks)
    DiagnosticLogger.info(
      'download',
      'download_directory_import_done',
      `gallery=${result.galleryTasks}/${result.scannedGalleryTasks} archiver=${result.archiverTasks}/${result.scannedArchiverTasks}`,
    )
    return result
  }

  /**
   * Add or refresh a gallery queue task. Raw and resampled downloads are separate tasks.
   */
  static async enqueueGallery(
    context: common.UIAbilityContext,
    task: DownloadGalleryTask,
  ): Promise<boolean> {
    if (task.gid.length === 0) {
      DiagnosticLogger.warn('download', 'gallery_enqueue_skipped_empty_gid', `tokenHash=${DiagnosticLogger.ownerHash(task.token)}`)
      return false
    }
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    let existed: boolean = false
    task.queuedAt = Date.now()
    task.status = DownloadGalleryTaskStatus.QUEUED
    const key: string = DownloadQueueSettings.taskKey(task.gid, task.token, task.preferOriginal)
    if (!DownloadQueueSettings.galleryDownloads.has(key)) {
      DownloadQueueSettings.cancelledGalleryDownloads.delete(key)
    }
    const refreshed: DownloadGalleryTask = task.copy()
    next.push(refreshed)
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      if (DownloadQueueSettings.sameGalleryTask(it, task.gid, task.token, task.preferOriginal)) {
        existed = true
        if (it.title.length > 0) {
          refreshed.title = it.title
        }
        if (it.titleJp.length > 0) {
          refreshed.titleJp = it.titleJp
        }
        if (it.thumbUrl.length > 0) {
          refreshed.thumbUrl = it.thumbUrl
        }
        if (it.imgWidth > 0) {
          refreshed.imgWidth = it.imgWidth
        }
        if (it.imgHeight > 0) {
          refreshed.imgHeight = it.imgHeight
        }
        if (it.pageCount > 0) {
          refreshed.pageCount = it.pageCount
        }
        if (it.category.length > 0) {
          refreshed.category = it.category
        }
        if (it.uploader.length > 0) {
          refreshed.uploader = it.uploader
        }
        refreshed.imageSeeds = it.imageSeeds.map((seed: DownloadImageSeed) => seed.copy())
        refreshed.firstPageCount = it.firstPageCount
        refreshed.previewPageCount = it.previewPageCount
        refreshed.preparedAt = it.preparedAt
        refreshed.prepareError = it.prepareError
        refreshed.preferOriginal = task.preferOriginal
        refreshed.status = it.status
        refreshed.syncProgressCounts()
        return
      }
      if (next.length < MAX_GALLERY_TASKS) {
        next.push(it.copy())
      }
    })
    DownloadQueueSettings.setGalleryTasks(state, next)
    await DownloadQueueSettings.persist(context, next)
    DiagnosticLogger.info(
      'download',
      existed ? 'gallery_enqueue_duplicate' : 'gallery_enqueue_added',
      `gid=${task.gid} tokenHash=${DiagnosticLogger.ownerHash(task.token)} quality=${DownloadQueueSettings.galleryQuality(task.preferOriginal)} tasks=${next.length}`,
    )
    return !existed
  }

  static async removeGallery(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean = false,
  ): Promise<void> {
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    if (DownloadQueueSettings.galleryDownloads.has(key)) {
      DownloadQueueSettings.cancelledGalleryDownloads.add(key)
    }
    const state = connectDownloadQueue()
    let removed: DownloadGalleryTask | null = null
    const next: DownloadGalleryTask[] = []
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      if (DownloadQueueSettings.sameGalleryTask(it, gid, token, preferOriginal)) {
        removed = it.copy()
        return
      }
      next.push(it.copy())
    })
    DownloadQueueSettings.setGalleryTasks(state, next)
    await DownloadQueueSettings.persist(context, next)
    if (removed !== null) {
      DownloadQueueSettings.cancelScheduledGalleryMetadata(removed)
      DownloadQueueSettings.deleteGalleryContent(context, removed)
    }
  }

  static async pauseGalleryDownload(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean = false,
  ): Promise<void> {
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    if (!DownloadQueueSettings.galleryDownloads.has(key)) {
      return
    }
    DownloadQueueSettings.cancelledGalleryDownloads.add(key)
    await DownloadQueueSettings.updateGalleryTaskAfterPause(context, gid, token, preferOriginal)
  }

  static async resumeAllGalleryDownloads(context: common.UIAbilityContext): Promise<void> {
    const tasks: DownloadGalleryTask[] = connectDownloadQueue().galleryTasks.map(
      (task: DownloadGalleryTask) => task.copy(),
    )
    for (let i: number = 0; i < tasks.length; i++) {
      const key: string = DownloadQueueSettings.taskKey(tasks[i].gid, tasks[i].token, tasks[i].preferOriginal)
      if (DownloadQueueSettings.canResumeGalleryTask(tasks[i]) && !DownloadQueueSettings.galleryDownloads.has(key)) {
        DownloadQueueSettings.downloadGalleryImages(context, tasks[i].gid, tasks[i].token, tasks[i].preferOriginal)
          .catch((error: Error) => {
            DiagnosticLogger.warn('download', 'gallery_resume_all_task_failed', error.message)
          })
      }
    }
  }

  static async pauseAllGalleryDownloads(context: common.UIAbilityContext): Promise<void> {
    const tasks: DownloadGalleryTask[] = connectDownloadQueue().galleryTasks.map(
      (task: DownloadGalleryTask) => task.copy(),
    )
    for (let i: number = 0; i < tasks.length; i++) {
      if (tasks[i].status === DownloadGalleryTaskStatus.DOWNLOADING) {
        await DownloadQueueSettings.pauseGalleryDownload(context, tasks[i].gid, tasks[i].token, tasks[i].preferOriginal)
      }
    }
  }

  static async enqueueArchiver(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<boolean> {
    if (task.tag.length === 0) {
      return false
    }
    if (task.url.length === 0 && task.parseSource !== DownloadArchiverParseSource.BOT) {
      return false
    }
    const state = connectDownloadQueue()
    const next: DownloadArchiverTask[] = []
    let shouldDownload: boolean = true
    const refreshed: DownloadArchiverTask = task.copy()
    DownloadQueueSettings.fillArchiverTaskFromGalleryTask(
      refreshed,
      DownloadQueueSettings.findGalleryTaskIn(state.galleryTasks, refreshed.gid, refreshed.token),
    )
    refreshed.queuedAt = Date.now()
    refreshed.status = DownloadGalleryTaskStatus.QUEUED
    if (!DownloadQueueSettings.archiverDownloads.has(task.tag)) {
      DownloadQueueSettings.cancelledArchiverDownloads.delete(task.tag)
    }
    next.push(refreshed)
    state.archiverTasks.forEach((it: DownloadArchiverTask) => {
      if (it.tag === task.tag) {
        if (it.title.length > 0) {
          refreshed.title = it.title
        }
        if (it.thumbUrl.length > 0) {
          refreshed.thumbUrl = it.thumbUrl
        }
        if (it.imgWidth > 0) {
          refreshed.imgWidth = it.imgWidth
        }
        if (it.imgHeight > 0) {
          refreshed.imgHeight = it.imgHeight
        }
        if (
          it.status === DownloadGalleryTaskStatus.COMPLETE &&
            it.filePath.length > 0 &&
            DownloadQueueSettings.downloadedFileSize(it.filePath) > 0
        ) {
          refreshed.fileName = it.fileName
          refreshed.filePath = it.filePath
          refreshed.bytesWritten = it.bytesWritten
          refreshed.bytesTotal = it.bytesTotal
          refreshed.progress = it.progress
          refreshed.downloadedAt = it.downloadedAt
          refreshed.status = it.status
          refreshed.error = it.error
          shouldDownload = false
        } else if (it.status === DownloadGalleryTaskStatus.DOWNLOADING) {
          refreshed.fileName = it.fileName
          refreshed.filePath = it.filePath
          refreshed.bytesWritten = it.bytesWritten
          refreshed.bytesTotal = it.bytesTotal
          refreshed.progress = it.progress
          refreshed.downloadedAt = it.downloadedAt
          refreshed.status = DownloadGalleryTaskStatus.DOWNLOADING
          refreshed.error = ''
        }
        return
      }
      if (next.length < MAX_ARCHIVER_TASKS) {
        next.push(it.copy())
      }
    })
    DownloadQueueSettings.setArchiverTasks(state, next)
    await DownloadQueueSettings.persistArchiver(context, next)
    return shouldDownload
  }

  static async removeArchiver(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    if (DownloadQueueSettings.archiverDownloads.has(tag)) {
      DownloadQueueSettings.cancelledArchiverDownloads.add(tag)
    }
    const state = connectDownloadQueue()
    let removed: DownloadArchiverTask | null = null
    const next: DownloadArchiverTask[] = []
    state.archiverTasks.forEach((it: DownloadArchiverTask) => {
      if (it.tag === tag) {
        removed = it.copy()
        return
      }
      next.push(it.copy())
    })
    DownloadQueueSettings.setArchiverTasks(state, next)
    await DownloadQueueSettings.persistArchiver(context, next)
    if (removed !== null) {
      DownloadQueueSettings.deleteArchiverContent(context, removed)
    }
  }

  static async switchArchiverToBot(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    await DownloadQueueSettings.updateArchiverTask(context, tag, (task: DownloadArchiverTask) => {
      if (task.status === DownloadGalleryTaskStatus.COMPLETE ||
        task.status === DownloadGalleryTaskStatus.DOWNLOADING ||
        task.parseSource === DownloadArchiverParseSource.BOT ||
        !DownloadQueueSettings.isOriginalArchiverTask(task)) {
        return
      }
      task.parseSource = DownloadArchiverParseSource.BOT
      task.url = ''
      task.fileName = ''
      task.filePath = ''
      task.bytesWritten = 0
      task.bytesTotal = 0
      task.progress = 0
      task.error = ''
      task.status = DownloadGalleryTaskStatus.QUEUED
    })
  }

  static async pauseArchiverDownload(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    if (!DownloadQueueSettings.archiverDownloads.has(tag)) {
      return
    }
    DownloadQueueSettings.cancelledArchiverDownloads.add(tag)
    await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
      it.status = DownloadGalleryTaskStatus.PAUSED
      it.error = ''
    })
  }

  static async resumeAllArchiverDownloads(context: common.UIAbilityContext): Promise<void> {
    const tasks: DownloadArchiverTask[] = connectDownloadQueue().archiverTasks.map(
      (task: DownloadArchiverTask) => task.copy(),
    )
    for (let i: number = 0; i < tasks.length; i++) {
      if (DownloadQueueSettings.canResumeArchiverTask(tasks[i]) &&
        !DownloadQueueSettings.archiverDownloads.has(tasks[i].tag)) {
        DownloadQueueSettings.downloadArchiver(context, tasks[i].tag)
          .catch((error: Error) => {
            DiagnosticLogger.warn('download', 'archiver_resume_all_task_failed', error.message)
          })
      }
    }
  }

  static async pauseAllArchiverDownloads(context: common.UIAbilityContext): Promise<void> {
    const tasks: DownloadArchiverTask[] = connectDownloadQueue().archiverTasks.map(
      (task: DownloadArchiverTask) => task.copy(),
    )
    for (let i: number = 0; i < tasks.length; i++) {
      if (tasks[i].status === DownloadGalleryTaskStatus.DOWNLOADING) {
        await DownloadQueueSettings.pauseArchiverDownload(context, tasks[i].tag)
      }
    }
  }

  static async downloadArchiver(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    const running: Promise<void> | undefined = DownloadQueueSettings.archiverDownloads.get(tag)
    if (running !== undefined) {
      await running
      const next: DownloadArchiverTask | null = DownloadQueueSettings.findArchiverTask(tag)
      if (next !== null && DownloadQueueSettings.shouldContinueAfterJoinedArchiverDownload(next)) {
        await DownloadQueueSettings.downloadArchiver(context, tag)
      }
      return
    }
    DownloadQueueSettings.cancelledArchiverDownloads.delete(tag)
    const task: Promise<void> = DownloadQueueSettings.startArchiverDownload(context, tag)
    DownloadQueueSettings.archiverDownloads.set(tag, task)
    try {
      await task
    } finally {
      DownloadQueueSettings.archiverDownloads.delete(tag)
      DownloadQueueSettings.cancelledArchiverDownloads.delete(tag)
    }
  }

  private static async startArchiverDownload(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    if (!await DownloadQueueSettings.ensureDownloadStorageReady(context)) {
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.status = DownloadGalleryTaskStatus.ERROR
        it.error = DOWNLOAD_DIRECTORY_UNAVAILABLE
      })
      return
    }
    await DownloadQueueSettings.runArchiverDownload(context, tag)
  }

  static async resumePendingDownloads(
    context: common.UIAbilityContext,
  ): Promise<void> {
    if (DownloadQueueSettings.pendingResume !== null) {
      await DownloadQueueSettings.pendingResume
      return
    }
    const task: Promise<void> = DownloadQueueSettings.runPendingResume(context)
    DownloadQueueSettings.pendingResume = task
    try {
      await task
    } catch (error) {
      DiagnosticLogger.warn('download', 'pending_resume_failed', (error as Error).message)
    } finally {
      DownloadQueueSettings.pendingResume = null
    }
  }

  private static async runPendingResume(
    context: common.UIAbilityContext,
  ): Promise<void> {
    const galleryTasks: DownloadGalleryTask[] = connectDownloadQueue().galleryTasks.map(
      (task: DownloadGalleryTask) => task.copy(),
    )
    const archiverTasks: DownloadArchiverTask[] = connectDownloadQueue().archiverTasks.map(
      (task: DownloadArchiverTask) => task.copy(),
    )
    let hasPendingTask: boolean = false
    for (let i: number = 0; i < galleryTasks.length; i++) {
      if (DownloadQueueSettings.shouldAutoResumeGalleryTask(galleryTasks[i])) {
        hasPendingTask = true
        break
      }
    }
    if (!hasPendingTask) {
      for (let i: number = 0; i < archiverTasks.length; i++) {
        if (DownloadQueueSettings.shouldAutoResumeArchiverTask(archiverTasks[i])) {
          hasPendingTask = true
          break
        }
      }
    }
    if (!hasPendingTask) {
      return
    }
    if (!await DownloadQueueSettings.ensureDownloadStorageReady(context)) {
      DiagnosticLogger.warn('download', 'pending_resume_storage_deferred', DOWNLOAD_DIRECTORY_UNAVAILABLE)
      return
    }
    for (let i: number = 0; i < galleryTasks.length; i++) {
      if (DownloadQueueSettings.shouldAutoResumeGalleryTask(galleryTasks[i])) {
        try {
          await DownloadQueueSettings.downloadGalleryImages(
            context,
            galleryTasks[i].gid,
            galleryTasks[i].token,
            galleryTasks[i].preferOriginal,
          )
        } catch (error) {
          DiagnosticLogger.warn('download', 'gallery_resume_failed', (error as Error).message)
        }
      }
    }
    for (let i: number = 0; i < archiverTasks.length; i++) {
      if (DownloadQueueSettings.shouldAutoResumeArchiverTask(archiverTasks[i])) {
        try {
          await DownloadQueueSettings.downloadArchiver(context, archiverTasks[i].tag)
        } catch (error) {
          DiagnosticLogger.warn('download', 'archiver_resume_failed', (error as Error).message)
        }
      }
    }
  }

  private static async runArchiverDownload(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    const task: DownloadArchiverTask | null = DownloadQueueSettings.findArchiverTask(tag)
    if (task === null || DownloadQueueSettings.cancelledArchiverDownloads.has(tag)) {
      return
    }
    if (task.url.length === 0 && task.parseSource === DownloadArchiverParseSource.BOT) {
      await DownloadQueueSettings.resolveArchiverBotUrl(context, tag, task)
    }
    const resolvedTask: DownloadArchiverTask | null = DownloadQueueSettings.findArchiverTask(tag)
    if (resolvedTask === null || resolvedTask.url.length === 0 ||
      DownloadQueueSettings.cancelledArchiverDownloads.has(tag)) {
      return
    }
    DiagnosticLogger.info(
      'download',
      'archiver_download_start',
      `gid=${resolvedTask.gid} source=${resolvedTask.parseSource} tagHash=${DiagnosticLogger.ownerHash(tag)}`,
    )
    const dir: string = DownloadQueueSettings.ensureArchiverDownloadDir(context)
    const fileName: string = resolvedTask.fileName.length > 0
      ? resolvedTask.fileName
      : DownloadQueueSettings.archiverFileName(resolvedTask)
    const filePath: string = `${dir}/${fileName}`
    const partialPath: string = DownloadQueueSettings.archiverPartialPath(filePath)
    const partialBytes: number = DownloadQueueSettings.downloadedFileSize(partialPath)
    await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
      it.status = DownloadGalleryTaskStatus.DOWNLOADING
      it.fileName = fileName
      it.filePath = filePath
      it.bytesWritten = partialBytes > 0 ? partialBytes : it.bytesWritten
      it.error = ''
    }, false)
    const attempts: number = Math.max(1, Math.round(connectDownloadSettings().retryCount) + 1)
    try {
      const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStreamResumable(
        resolvedTask.url,
        partialPath,
        (loaded: number, total: number) => {
          DownloadQueueSettings.updateArchiverProgress(tag, loaded, total)
        },
        () => DownloadQueueSettings.cancelledArchiverDownloads.has(tag),
        resolvedTask.bytesTotal,
        ARCHIVER_ACCEPT,
        attempts,
        ARCHIVER_READ_TIMEOUT_MS,
      )
      if (DownloadQueueSettings.cancelledArchiverDownloads.has(tag)) {
        DownloadQueueSettings.archiverProgressPulses.delete(tag)
        DiagnosticLogger.info(
          'download',
          'archiver_download_cancelled',
          `gid=${resolvedTask.gid} tagHash=${DiagnosticLogger.ownerHash(tag)} bytes=${bytes}`,
        )
        return
      }
      await DownloadQueueSettings.finalizeArchiverPartial(partialPath, filePath)
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.status = DownloadGalleryTaskStatus.COMPLETE
        it.fileName = fileName
        it.filePath = filePath
        it.bytesWritten = bytes
        it.bytesTotal = it.bytesTotal > 0 ? it.bytesTotal : bytes
        it.progress = 100
        it.downloadedAt = Date.now()
        it.error = ''
      })
      DownloadQueueSettings.archiverProgressPulses.delete(tag)
      DiagnosticLogger.info(
        'download',
        'archiver_download_done',
        `gid=${resolvedTask.gid} source=${resolvedTask.parseSource} tagHash=${DiagnosticLogger.ownerHash(tag)} bytes=${bytes}`,
      )
      await DownloadNotificationService.publishDownloadComplete(fileName)
    } catch (error) {
      if (DownloadQueueSettings.cancelledArchiverDownloads.has(tag)) {
        DownloadQueueSettings.archiverProgressPulses.delete(tag)
        DiagnosticLogger.info(
          'download',
          'archiver_download_cancelled',
          `gid=${resolvedTask.gid} tagHash=${DiagnosticLogger.ownerHash(tag)}`,
        )
        return
      }
      const restartFromHead: boolean = DownloadQueueSettings.isArchiverResumeUnsupportedError(error as Object)
      if (restartFromHead) {
        DownloadQueueSettings.deleteSandboxPath(partialPath, 'archiver_partial_restart_delete_failed')
      }
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.status = DownloadGalleryTaskStatus.ERROR
        it.fileName = fileName
        it.filePath = filePath
        if (restartFromHead) {
          it.bytesWritten = 0
          it.progress = 0
        }
        it.error = DownloadQueueSettings.userError(error as Object)
      })
      DownloadQueueSettings.archiverProgressPulses.delete(tag)
      DiagnosticLogger.warn(
        'download',
        'archiver_download_failed',
        `gid=${resolvedTask.gid} source=${resolvedTask.parseSource} tagHash=${DiagnosticLogger.ownerHash(tag)} error=${(error as Error).message}`,
      )
    }
  }

  private static async resolveArchiverBotUrl(
    context: common.UIAbilityContext,
    tag: string,
    task: DownloadArchiverTask,
  ): Promise<void> {
    const settings: DownloadSettingsState = connectDownloadSettings()
    if (!DownloadSettings.archiveBotReady(settings)) {
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.status = DownloadGalleryTaskStatus.PAUSED
        it.error = ARCHIVE_BOT_SETTINGS_INCOMPLETE
      })
      DiagnosticLogger.warn(
        'download',
        'archive_bot_resolve_paused_not_ready',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(tag)}`,
      )
      return
    }
    await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
      it.status = DownloadGalleryTaskStatus.PREPARING
      it.error = ''
    }, false)
    try {
      DiagnosticLogger.info(
        'download',
        'archive_bot_resolve_start',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(tag)}`,
      )
      const result: ArchiveBotResolveResult = await ArchiveBotService.requestResolve(
        settings,
        task.gid,
        task.token,
        true,
      )
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.url = DownloadQueueSettings.normalizeArchiverDownloadUrl(result.url)
        it.error = ''
      })
      DiagnosticLogger.info(
        'download',
        'archive_bot_resolve_done',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(tag)}`,
      )
    } catch (error) {
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.status = DownloadGalleryTaskStatus.ERROR
        it.error = DownloadQueueSettings.userError(error as Object)
      })
      DiagnosticLogger.warn(
        'download',
        'archive_bot_resolve_failed',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(tag)} error=${(error as Error).message}`,
      )
    }
  }

  static async refreshGallerySeedsFromRemote(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    isEx: boolean,
    preferOriginal: boolean = false,
  ): Promise<void> {
    const before: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token, preferOriginal)
    const beforeSeeds: number = before !== null ? before.imageSeeds.length : 0
    const beforeDownloaded: number = before !== null ? before.downloadedCount() : 0
    DiagnosticLogger.info(
      'download',
      'gallery_seed_refresh_start',
      `gid=${gid} tokenHash=${DiagnosticLogger.ownerHash(token)} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)} seeds=${beforeSeeds} downloaded=${beforeDownloaded}`,
    )
    try {
      const detail: GalleryDetailResult = await EhApiService.getInstance().getGalleryDetail(gid, token, isEx)
      await DownloadQueueSettings.updateGalleryTaskMetadata(context, gid, token, preferOriginal, detail.gallery)
      await DownloadQueueSettings.prepareGallerySeeds(
        context,
        gid,
        token,
        isEx,
        detail.images,
        detail.previewPageCount,
        preferOriginal,
      )
      const after: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token, preferOriginal)
      DiagnosticLogger.info(
        'download',
        'gallery_seed_refresh_done',
        `gid=${gid} seeds=${after !== null ? after.imageSeeds.length : 0} downloaded=${after !== null ? after.downloadedCount() : 0}`,
      )
    } catch (error) {
      await DownloadQueueSettings.updateDownloadTaskStatus(
        context,
        gid,
        token,
        preferOriginal,
        DownloadGalleryTaskStatus.ERROR,
        DownloadQueueSettings.userError(error as Object),
      )
      DiagnosticLogger.warn(
        'download',
        'gallery_seed_refresh_failed',
        `gid=${gid} error=${(error as Error).message}`,
      )
    }
  }

  /**
   * Prepare the EH-correct image-page seed list for a gallery task: preview pages yield `/s/`
   * imagePageUrl entries; a later downloader resolves each image page to the real one-shot image URL.
   */
  static async prepareGallerySeeds(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    isEx: boolean,
    firstPageImages: EhGalleryImage[],
    previewPageCount: number,
    preferOriginal: boolean = false,
  ): Promise<void> {
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    const running: Promise<void> | undefined = DownloadQueueSettings.galleryPreparations.get(key)
    if (running !== undefined) {
      await running
      return
    }
    const task: Promise<void> = DownloadQueueSettings.runPrepareGallerySeeds(
      context,
      gid,
      token,
      isEx,
      firstPageImages,
      previewPageCount,
      preferOriginal,
    )
    DownloadQueueSettings.galleryPreparations.set(key, task)
    try {
      await task
    } finally {
      DownloadQueueSettings.galleryPreparations.delete(key)
    }
  }

  private static async runPrepareGallerySeeds(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    isEx: boolean,
    firstPageImages: EhGalleryImage[],
    previewPageCount: number,
    preferOriginal: boolean,
  ): Promise<void> {
    DiagnosticLogger.info(
      'download',
      'gallery_prepare_start',
      `gid=${gid} tokenHash=${DiagnosticLogger.ownerHash(token)} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)} firstImages=${firstPageImages.length} previewPages=${previewPageCount}`,
    )
    let seedImages: EhGalleryImage[] = firstPageImages.map((image: EhGalleryImage) => image.copy())
    let resolvedPreviewPageCount: number = previewPageCount
    if (seedImages.length === 0) {
      try {
        const detail: GalleryDetailResult = await EhApiService.getInstance().getGalleryDetail(gid, token, isEx)
        await DownloadQueueSettings.updateGalleryTaskMetadata(context, gid, token, preferOriginal, detail.gallery)
        seedImages = detail.images.map((image: EhGalleryImage) => image.copy())
        resolvedPreviewPageCount = detail.previewPageCount
        DiagnosticLogger.info(
          'download',
          'gallery_prepare_detail_seed_loaded',
          `gid=${gid} images=${seedImages.length} previewPages=${resolvedPreviewPageCount}`,
        )
      } catch (error) {
        await DownloadQueueSettings.updateDownloadTaskStatus(
          context,
          gid,
          token,
          preferOriginal,
          DownloadGalleryTaskStatus.ERROR,
          DownloadQueueSettings.userError(error as Object),
        )
        DiagnosticLogger.warn(
          'download',
          'gallery_prepare_failed',
          `gid=${gid} error=${(error as Error).message}`,
        )
        return
      }
    }
    const initialSeeds: DownloadImageSeed[] = DownloadQueueSettings.imagesToSeeds(seedImages)
    await DownloadQueueSettings.updatePreparedTask(
      context,
      gid,
      token,
      DownloadGalleryTaskStatus.PREPARING,
      initialSeeds,
      seedImages.length,
      resolvedPreviewPageCount,
      '',
      preferOriginal,
    )

    try {
      const allImages: EhGalleryImage[] = seedImages.map((image: EhGalleryImage) => image.copy())
      const firstPageCount: number = Math.max(1, initialSeeds.length > 0 ? initialSeeds.length : seedImages.length)
      const totalPreviewPages: number = DownloadQueueSettings.expectedPreviewPageCount(
        gid,
        token,
        firstPageCount,
        resolvedPreviewPageCount,
        preferOriginal,
      )
      for (let p = 1; p < totalPreviewPages; p++) {
        const more: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
          gid,
          token,
          isEx,
          p,
        )
        more.forEach((image: EhGalleryImage) => {
          allImages.push(image.copy())
        })
      }
      await DownloadQueueSettings.updatePreparedTask(
        context,
        gid,
        token,
        DownloadGalleryTaskStatus.READY,
        DownloadQueueSettings.imagesToSeeds(allImages),
        firstPageCount,
        totalPreviewPages,
        '',
        preferOriginal,
      )
      DiagnosticLogger.info(
        'download',
        'gallery_prepare_done',
        `gid=${gid} seeds=${DownloadQueueSettings.imagesToSeeds(allImages).length} previewPages=${totalPreviewPages}`,
      )
    } catch (error) {
      await DownloadQueueSettings.updateDownloadTaskStatus(
        context,
        gid,
        token,
        preferOriginal,
        DownloadGalleryTaskStatus.ERROR,
        DownloadQueueSettings.userError(error as Object),
      )
      DiagnosticLogger.warn(
        'download',
        'gallery_prepare_failed',
        `gid=${gid} error=${(error as Error).message}`,
      )
      return
    }
    await DownloadQueueSettings.downloadGalleryImages(context, gid, token, preferOriginal)
  }

  static async downloadGalleryImages(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean = false,
  ): Promise<void> {
    const found: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token, preferOriginal)
    if (found !== null && (
      found.imageSeeds.length === 0 ||
      DownloadQueueSettings.shouldRefreshIncompleteSeedList(found)
    )) {
      await DownloadQueueSettings.refreshGallerySeedsFromRemote(context, gid, token, connectSiteMode().isEx, preferOriginal)
      return
    }
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    const running: Promise<void> | undefined = DownloadQueueSettings.galleryDownloads.get(key)
    if (running !== undefined) {
      await running
      const next: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token, preferOriginal)
      if (next !== null && DownloadQueueSettings.shouldContinueAfterJoinedGalleryDownload(next)) {
        await DownloadQueueSettings.downloadGalleryImages(context, gid, token, preferOriginal)
      }
      return
    }
    DownloadQueueSettings.cancelledGalleryDownloads.delete(key)
    const task: Promise<void> = DownloadQueueSettings.startGalleryImageDownload(context, gid, token, preferOriginal)
    DownloadQueueSettings.galleryDownloads.set(key, task)
    try {
      await task
    } finally {
      DownloadQueueSettings.galleryDownloads.delete(key)
      DownloadQueueSettings.cancelledGalleryDownloads.delete(key)
    }
  }

  private static async startGalleryImageDownload(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
  ): Promise<void> {
    if (!await DownloadQueueSettings.ensureDownloadStorageReady(context)) {
      await DownloadQueueSettings.updateDownloadTaskStatus(
        context,
        gid,
        token,
        preferOriginal,
        DownloadGalleryTaskStatus.ERROR,
        DOWNLOAD_DIRECTORY_UNAVAILABLE,
      )
      return
    }
    await DownloadQueueSettings.runGalleryImageDownload(context, gid, token, preferOriginal)
  }

  private static async runGalleryImageDownload(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
  ): Promise<void> {
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    let batchIndex: number = 0
    let failedBatchRetries: number = 0
    DiagnosticLogger.info(
      'download',
      'gallery_download_start',
      `gid=${gid} tokenHash=${DiagnosticLogger.ownerHash(token)} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)}`,
    )
    while (true) {
      if (DownloadQueueSettings.cancelledGalleryDownloads.has(key)) {
        DiagnosticLogger.info(
          'download',
          'gallery_download_cancelled',
          `gid=${gid} batch=${batchIndex}`,
        )
        return
      }
      const task: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token, preferOriginal)
      if (task === null) {
        return
      }
      const pending: DownloadImageSeed[] = DownloadQueueSettings.pendingSeeds(
        task,
        connectDownloadSettings().concurrency,
      )
      if (pending.length === 0) {
        const doneStatus: string = DownloadQueueSettings.galleryDoneStatus(task)
        await DownloadQueueSettings.updateDownloadTaskStatus(
          context,
          gid,
          token,
          preferOriginal,
          doneStatus,
          '',
        )
        if (doneStatus === DownloadGalleryTaskStatus.PARTIAL) {
          DiagnosticLogger.warn(
            'download',
            'gallery_download_incomplete_seeds',
            `gid=${gid} downloaded=${task.downloadedCount()} seeds=${task.imageSeeds.length} pageCount=${task.pageCount}`,
          )
        } else {
          await DownloadNotificationService.publishDownloadComplete(task.displayTitle())
        }
        DiagnosticLogger.info(
          'download',
          'gallery_download_done',
          `gid=${gid} status=${doneStatus} downloaded=${task.downloadedCount()} seeds=${task.imageSeeds.length} expected=${task.expectedFileCount()} pageCount=${task.pageCount}`,
        )
        return
      }
      if (batchIndex > 0) {
        await DownloadQueueSettings.delay(connectDownloadSettings().requestIntervalSeconds * 1000)
        if (DownloadQueueSettings.cancelledGalleryDownloads.has(key)) {
          return
        }
      }
      await DownloadQueueSettings.updateDownloadTaskStatus(
        context,
        gid,
        token,
        preferOriginal,
        DownloadGalleryTaskStatus.DOWNLOADING,
        '',
      )
      const batchStartedAt: number = Date.now()
      const useOriginal: boolean = task.preferOriginal ||
        connectDownloadSettings().originalMode === DownloadOriginalMode.ALWAYS
      const retryCount: number = connectDownloadSettings().retryCount
      const jobs: Promise<DownloadSeedResult>[] = []
      pending.forEach((seed: DownloadImageSeed) => {
        jobs.push(
          DownloadQueueSettings.downloadSeedToFile(
            context,
            gid,
            token,
            preferOriginal,
            DownloadQueueSettings.galleryTaskPathTitle(task),
            seed,
            useOriginal,
            retryCount,
          )
            .then(async (result: DownloadSeedResult) => {
              if (!DownloadQueueSettings.cancelledGalleryDownloads.has(key)) {
                await DownloadQueueSettings.applyDownloadResults(context, gid, token, preferOriginal, [result])
                result.applied = true
              }
              return result
            }),
        )
      })
      const results: DownloadSeedResult[] = await Promise.all(jobs)
      if (DownloadQueueSettings.cancelledGalleryDownloads.has(key)) {
        DownloadQueueSettings.deleteDownloadSeedResults(results)
        return
      }
      const hasError: boolean = DownloadQueueSettings.hasDownloadResultError(results)
      DiagnosticLogger.info(
        'download',
        'gallery_download_batch_done',
        DownloadQueueSettings.galleryBatchSummary(gid, batchIndex, results),
      )
      if (hasError) {
        if (failedBatchRetries < connectDownloadSettings().retryCount) {
          failedBatchRetries++
          DiagnosticLogger.warn(
            'download',
            'gallery_download_batch_auto_retry',
            `gid=${gid} batch=${batchIndex} retry=${failedBatchRetries}/${connectDownloadSettings().retryCount}`,
          )
          await DownloadQueueSettings.delay(connectDownloadSettings().requestIntervalSeconds * 1000)
          continue
        }
        return
      }
      failedBatchRetries = 0
      await DownloadQueueSettings.delayForSpeedLimit(batchStartedAt, results)
      batchIndex++
    }
  }

  static async downloadFirstGalleryImage(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
  ): Promise<void> {
    await DownloadQueueSettings.downloadGalleryImages(context, gid, token)
  }

  private static async downloadSeedToFile(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
    title: string,
    seed: DownloadImageSeed,
    useOriginal: boolean,
    retryCount: number,
  ): Promise<DownloadSeedResult> {
    const result: DownloadSeedResult = new DownloadSeedResult()
    result.originalSeed = seed.copy()
    const attempts: number = Math.max(1, Math.round(retryCount) + 1)
    for (let i: number = 0; i < attempts; i++) {
      let tmpPath: string = ''
      try {
        const image: EhGalleryImage = DownloadQueueSettings.seedToImage(seed)
        const shouldRefreshImageUrl: boolean = i > 0
        let imageUrl: string
        if (useOriginal) {
          try {
            imageUrl = await ImageResolveService.getInstance().resolveOriginal(image, shouldRefreshImageUrl)
          } catch (error) {
            const message: string = (error as Error).message
            if (message !== 'original image unavailable') {
              throw new Error(message)
            }
            DiagnosticLogger.warn(
              'download',
              'gallery_original_fallback',
              `gid=${gid} page=${seed.page}`,
            )
            imageUrl = await ImageResolveService.getInstance().resolve(image, shouldRefreshImageUrl)
          }
        } else {
          imageUrl = await ImageResolveService.getInstance().resolve(image, shouldRefreshImageUrl)
        }
        const dir: string = DownloadQueueSettings.ensureGalleryDownloadDir(context, gid, preferOriginal, title)
        result.image = image.copy()
        result.filePath = `${dir}/${DownloadQueueSettings.fileNameForSeed(seed, imageUrl)}`
        const directPublicWrite: boolean = DownloadQueueSettings.isPublicDownloadPath(result.filePath)
        const writePath: string = directPublicWrite ? result.filePath : `${result.filePath}.part`
        tmpPath = writePath
        DownloadQueueSettings.deleteSandboxPath(writePath, directPublicWrite ? 'gallery_replace_delete_failed' : 'gallery_temp_delete_failed')
        result.bytes = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
          imageUrl,
          writePath,
          (loaded: number, total: number) => {
            DownloadQueueSettings.updateGalleryStreamProgress(gid, token, preferOriginal, seed, loaded, total)
          },
        )
        if (!directPublicWrite) {
          DownloadQueueSettings.deleteSandboxPath(result.filePath, 'gallery_replace_delete_failed')
          fs.renameSync(writePath, result.filePath)
        }
        result.error = ''
        return result
      } catch (error) {
        DiagnosticLogger.warn(
          'download',
          'gallery_seed_download_failed',
          `gid=${gid} page=${seed.page} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)} error=${(error as Error).message}`,
        )
        DownloadQueueSettings.deleteSandboxPath(tmpPath, 'gallery_temp_delete_failed')
        result.error = DownloadQueueSettings.userError(error as Object)
      }
    }
    return result
  }

  private static async applyDownloadResults(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
    results: DownloadSeedResult[],
  ): Promise<boolean> {
    const startedAt: number = Date.now()
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    let hasError: boolean = false
    let firstError: string = ''
    const state = connectDownloadQueue()
    let updatedTask: DownloadGalleryTask | null = null
    let matched: boolean = false
    const changedSeeds: DownloadImageSeed[] = []
    for (let i: number = 0; i < state.galleryTasks.length; i++) {
      const task: DownloadGalleryTask = state.galleryTasks[i]
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        matched = true
        results.forEach((result: DownloadSeedResult) => {
          const seedIndex: number = DownloadQueueSettings.findSeedIndex(task.imageSeeds, result.originalSeed)
          if (seedIndex < 0) {
            return
          }
          const seed: DownloadImageSeed = task.imageSeeds[seedIndex]
          const wasDownloaded: boolean = seed.filePath.length > 0
          if (result.error.length > 0) {
            seed.downloadError = result.error
            if (firstError.length === 0) {
              firstError = result.error
            }
            hasError = true
          } else {
            seed.imageUrl = result.image.imageUrl
            seed.originImageUrl = result.image.originImageUrl
            seed.showKey = result.image.showKey
            seed.reloadKey = result.image.reloadKey
            seed.filePath = result.filePath
            seed.bytesWritten = result.bytes
            seed.downloadedAt = Date.now()
            seed.downloadError = ''
          }
          const isDownloaded: boolean = seed.filePath.length > 0
          if (isDownloaded && !wasDownloaded) {
            task.downloadedFiles = Math.min(task.seededCount(), task.downloadedFiles + 1)
          } else if (!isDownloaded && wasDownloaded) {
            task.downloadedFiles = Math.max(0, task.downloadedFiles - 1)
          }
          if (task.activeDownloadPage === seed.page) {
            task.clearActiveDownloadProgress()
          }
          DownloadQueueSettings.clearGalleryActiveProgress(key, seed.page)
          changedSeeds.push(seed)
        })
        if (firstError.length > 0) {
          task.prepareError = firstError
        }
        hasError = hasError || task.prepareError.length > 0
        if (task.seededFiles <= 0 || (task.downloadedFiles <= 0 && task.downloadedCount() > 0)) {
          task.syncProgressCounts()
        }
        const pendingCount: number = task.pendingDownloadCount()
        task.status = hasError
          ? DownloadGalleryTaskStatus.ERROR
          : pendingCount === 0
            ? DownloadQueueSettings.galleryDoneStatus(task)
            : DownloadGalleryTaskStatus.DOWNLOADING
        DiagnosticLogger.info(
          'download',
          'gallery_download_apply_results',
          `gid=${gid} downloaded=${task.downloadedCount()} pending=${pendingCount} expected=${task.expectedFileCount()} pageCount=${task.pageCount} status=${task.status}`,
        )
        updatedTask = task
      }
    }
    if (matched) {
      if (isDownloadQueuePageActive()) {
        publishDownloadQueueChanged()
      }
      if (updatedTask !== null) {
        await DownloadQueueSettings.persistGalleryTaskDelta(context, updatedTask, changedSeeds)
      }
    }
    const costMs: number = Date.now() - startedAt
    const seedCount: number = updatedTask !== null ? updatedTask.imageSeeds.length : 0
    if (costMs >= DOWNLOAD_PERF_APPLY_WARN_MS) {
      DiagnosticLogger.info(
        'download',
        'download_perf_apply_results',
        `gid=${gid} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)} results=${results.length} seeds=${seedCount} matched=${matched} costMs=${costMs}`,
      )
    }
    return hasError
  }

  private static findSeedIndex(seeds: DownloadImageSeed[], target: DownloadImageSeed): number {
    const directIndex: number = target.page - 1
    if (
      directIndex >= 0 &&
      directIndex < seeds.length &&
      DownloadQueueSettings.sameSeed(seeds[directIndex], target)
    ) {
      return directIndex
    }
    for (let i: number = 0; i < seeds.length; i++) {
      if (DownloadQueueSettings.sameSeed(seeds[i], target)) {
        return i
      }
    }
    return -1
  }

  private static firstSeedError(seeds: DownloadImageSeed[]): string {
    for (let i: number = 0; i < seeds.length; i++) {
      if (seeds[i].downloadError.length > 0) {
        return seeds[i].downloadError
      }
    }
    return ''
  }

  private static pendingSeeds(task: DownloadGalleryTask, limit: number): DownloadImageSeed[] {
    const out: DownloadImageSeed[] = []
    const safeLimit: number = Math.max(1, Math.min(8, Math.round(limit)))
    for (let i: number = 0; i < task.imageSeeds.length && out.length < safeLimit; i++) {
      const seed: DownloadImageSeed = task.imageSeeds[i]
      if (seed.filePath.length === 0 && seed.imagePageUrl.length > 0) {
        out.push(seed.copy())
      }
    }
    return out
  }

  private static pendingSeedCount(seeds: DownloadImageSeed[]): number {
    let count: number = 0
    seeds.forEach((seed: DownloadImageSeed) => {
      if (seed.filePath.length === 0 && seed.imagePageUrl.length > 0) {
        count++
      }
    })
    return count
  }

  private static shouldContinueAfterJoinedGalleryDownload(task: DownloadGalleryTask): boolean {
    if (
      task.status === DownloadGalleryTaskStatus.ERROR ||
      task.status === DownloadGalleryTaskStatus.PAUSED
    ) {
      return false
    }
    if (DownloadQueueSettings.pendingSeedCount(task.imageSeeds) > 0) {
      return true
    }
    return DownloadQueueSettings.shouldRefreshIncompleteSeedList(task)
  }

  private static expectedPreviewPageCount(
    gid: string,
    token: string,
    firstPageCount: number,
    parsedPreviewPageCount: number,
    preferOriginal: boolean,
  ): number {
    let total: number = Math.max(parsedPreviewPageCount, 1)
    const task: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token, preferOriginal)
    const pageCount: number = task !== null ? task.pageCount : 0
    if (pageCount > 0 && firstPageCount > 0) {
      total = Math.max(total, Math.ceil(pageCount / firstPageCount))
    }
    return total
  }

  private static shouldRefreshIncompleteSeedList(task: DownloadGalleryTask): boolean {
    if (task.pageCount <= 0 || task.imageSeeds.length <= 0) {
      return false
    }
    if (task.seededCount() >= task.pageCount) {
      return false
    }
    return DownloadQueueSettings.pendingSeedCount(task.imageSeeds) === 0
  }

  private static galleryDoneStatus(task: DownloadGalleryTask): string {
    if (task.imageSeeds.length === 0) {
      return DownloadGalleryTaskStatus.READY
    }
    if (task.isDownloadComplete()) {
      return DownloadGalleryTaskStatus.COMPLETE
    }
    return DownloadGalleryTaskStatus.PARTIAL
  }

  private static canResumeGalleryTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.QUEUED ||
      task.status === DownloadGalleryTaskStatus.READY ||
      task.status === DownloadGalleryTaskStatus.PAUSED ||
      task.status === DownloadGalleryTaskStatus.PARTIAL ||
      task.status === DownloadGalleryTaskStatus.ERROR
  }

  private static canResumeArchiverTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.QUEUED ||
      task.status === DownloadGalleryTaskStatus.PREPARING ||
      task.status === DownloadGalleryTaskStatus.PAUSED ||
      task.status === DownloadGalleryTaskStatus.ERROR
  }

  private static shouldContinueAfterJoinedArchiverDownload(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.QUEUED && task.url.length > 0
  }

  private static deleteDownloadSeedResults(results: DownloadSeedResult[]): void {
    results.forEach((result: DownloadSeedResult) => {
      if (!result.applied && result.filePath.length > 0) {
        DownloadQueueSettings.deleteSandboxPath(result.filePath, 'gallery_cancelled_file_delete_failed')
      }
    })
  }

  private static hasDownloadResultError(results: DownloadSeedResult[]): boolean {
    return results.some((result: DownloadSeedResult) => result.error.length > 0)
  }

  private static galleryBatchSummary(gid: string, batchIndex: number, results: DownloadSeedResult[]): string {
    let ok: number = 0
    let failed: number = 0
    let bytes: number = 0
    let firstError: string = ''
    results.forEach((result: DownloadSeedResult) => {
      if (result.error.length > 0) {
        failed++
        if (firstError.length === 0) {
          firstError = result.error.replace(/\s+/g, ' ').substring(0, 160)
        }
      } else {
        ok++
        bytes += Math.max(0, result.bytes)
      }
    })
    const errorPart: string = firstError.length > 0 ? ` firstError=${firstError}` : ''
    return `gid=${gid} batch=${batchIndex} ok=${ok} failed=${failed} bytes=${bytes}${errorPart}`
  }

  private static async updatePreparedTask(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    status: string,
    seeds: DownloadImageSeed[],
    firstPageCount: number,
    previewPageCount: number,
    prepareError: string,
    preferOriginal: boolean,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    let updatedTask: DownloadGalleryTask | null = null
    for (let i: number = 0; i < state.galleryTasks.length; i++) {
      const it: DownloadGalleryTask = state.galleryTasks[i]
      const task: DownloadGalleryTask = it.copy()
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        task.status = status
        task.imageSeeds = DownloadQueueSettings.mergePreparedSeeds(
          task.imageSeeds,
          seeds,
          status === DownloadGalleryTaskStatus.PREPARING,
        )
        if (status === DownloadGalleryTaskStatus.READY) {
          const parent: DownloadGalleryTask | undefined = DownloadQueueSettings.findGalleryTaskIn(
            state.galleryTasks,
            task.upgradeFromGid,
            '',
            task.preferOriginal,
          )
          if (parent !== undefined) {
            task.imageSeeds = await DownloadQueueSettings.inheritDownloadedSeedsFromParent(
              context,
              task.gid,
              task.imageSeeds,
              task.preferOriginal,
              parent,
            )
          }
        }
        task.firstPageCount = firstPageCount
        task.previewPageCount = previewPageCount
        task.prepareError = prepareError
        task.preparedAt = status === DownloadGalleryTaskStatus.READY ? Date.now() : task.preparedAt
        task.syncProgressCounts()
        updatedTask = task.copy()
      }
      next.push(task)
    }
    DownloadQueueSettings.setGalleryTasks(state, next)
    if (updatedTask !== null) {
      if (status === DownloadGalleryTaskStatus.DOWNLOADING) {
        await DownloadQueueSettings.persistGalleryTaskHeader(context, updatedTask, false)
      } else {
        await DownloadQueueSettings.persistGalleryTask(context, updatedTask)
      }
    }
  }

  private static async updateGalleryTaskMetadata(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
    gallery: EhGallery,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    let updatedTask: DownloadGalleryTask | null = null
    const pageCount: number = gallery.fileCountNumber()
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        if (gallery.title().length > 0) {
          task.title = gallery.title()
        }
        if (gallery.japaneseTitle.length > 0) {
          task.titleJp = gallery.japaneseTitle
        }
        if (gallery.thumbUrl.length > 0 || gallery.thumbUrlL.length > 0) {
          task.thumbUrl = gallery.thumbUrl.length > 0 ? gallery.thumbUrl : gallery.thumbUrlL
        }
        if (gallery.imgWidth > 0) {
          task.imgWidth = gallery.imgWidth
        }
        if (gallery.imgHeight > 0) {
          task.imgHeight = gallery.imgHeight
        }
        if (pageCount > 0) {
          task.pageCount = pageCount
        }
        if (gallery.category.length > 0) {
          task.category = gallery.category
        }
        if (gallery.uploader.length > 0) {
          task.uploader = gallery.uploader
        }
        updatedTask = task.copy()
      }
      next.push(task)
    })
    DownloadQueueSettings.setGalleryTasks(state, next)
    if (updatedTask !== null) {
      await DownloadQueueSettings.persistGalleryTask(context, updatedTask)
    }
  }

  private static async persist(
    context: common.UIAbilityContext,
    tasks: DownloadGalleryTask[],
  ): Promise<void> {
    try {
      await DownloadQueueRepository.replaceAll(context, tasks)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_save_failed', (error as Error).message)
    }
    DownloadQueueSettings.writeGalleryMetadataTasks(context, tasks)
  }

  private static async persistGalleryTask(
    context: common.UIAbilityContext,
    task: DownloadGalleryTask,
  ): Promise<void> {
    const startedAt: number = Date.now()
    try {
      await DownloadQueueRepository.replaceGalleryTask(context, task)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_task_save_failed', (error as Error).message)
    }
    DownloadQueueSettings.writeGalleryMetadataTask(context, task)
    const costMs: number = Date.now() - startedAt
    if (costMs >= DOWNLOAD_PERF_PERSIST_WARN_MS || task.imageSeeds.length >= 120) {
      DiagnosticLogger.info(
        'download',
        'download_perf_persist_gallery_task',
        `gid=${task.gid} quality=${DownloadQueueSettings.galleryQuality(task.preferOriginal)} seeds=${task.imageSeeds.length} downloaded=${task.downloadedFiles} costMs=${costMs}`,
      )
    }
  }

  private static async persistGalleryTaskHeader(
    context: common.UIAbilityContext,
    task: DownloadGalleryTask,
    flushMetadata: boolean,
  ): Promise<void> {
    const startedAt: number = Date.now()
    try {
      await DownloadQueueRepository.updateGalleryTaskDelta(context, task, [])
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_task_header_save_failed', (error as Error).message)
    }
    if (flushMetadata) {
      DownloadQueueSettings.writeGalleryMetadataTask(context, task)
    }
    const costMs: number = Date.now() - startedAt
    if (costMs >= DOWNLOAD_PERF_PERSIST_WARN_MS) {
      DiagnosticLogger.info(
        'download',
        'download_perf_persist_gallery_header',
        `gid=${task.gid} quality=${DownloadQueueSettings.galleryQuality(task.preferOriginal)} seeds=${task.imageSeeds.length} downloaded=${task.downloadedFiles} metadata=${flushMetadata} costMs=${costMs}`,
      )
    }
  }

  private static async persistGalleryTaskDelta(
    context: common.UIAbilityContext,
    task: DownloadGalleryTask,
    changedSeeds: DownloadImageSeed[],
  ): Promise<void> {
    const startedAt: number = Date.now()
    try {
      await DownloadQueueRepository.updateGalleryTaskDelta(context, task, changedSeeds)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_queue_task_delta_save_failed', (error as Error).message)
    }
    DownloadQueueSettings.scheduleGalleryMetadataTask(context, task)
    const costMs: number = Date.now() - startedAt
    if (costMs >= DOWNLOAD_PERF_PERSIST_WARN_MS) {
      DiagnosticLogger.info(
        'download',
        'download_perf_persist_gallery_delta',
        `gid=${task.gid} quality=${DownloadQueueSettings.galleryQuality(task.preferOriginal)} seeds=${task.imageSeeds.length} changedSeeds=${changedSeeds.length} downloaded=${task.downloadedFiles} costMs=${costMs}`,
      )
    }
  }

  private static async persistArchiver(
    context: common.UIAbilityContext,
    tasks: DownloadArchiverTask[],
  ): Promise<void> {
    try {
      await DownloadQueueRepository.replaceAllArchiver(context, tasks)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_archiver_queue_save_failed', (error as Error).message)
    }
    DownloadQueueSettings.writeArchiverMetadataTasks(context, tasks)
  }

  private static async persistArchiverTask(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<void> {
    try {
      await DownloadQueueRepository.replaceArchiverTask(context, task)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_archiver_task_save_failed', (error as Error).message)
    }
    DownloadQueueSettings.writeArchiverMetadataTask(context, task)
  }

  static async migrateLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    const raw: string = store.getSync(StorageKeys.DOWNLOAD_GALLERY_QUEUE, '') as string
    if (raw.length === 0) {
      return
    }
    const tasks: DownloadGalleryTask[] = DownloadQueueSettings.parse(raw)
    if (tasks.length > 0) {
      await DownloadQueueRepository.replaceAll(context, tasks)
    }
    store.deleteSync(StorageKeys.DOWNLOAD_GALLERY_QUEUE)
    store.flushSync()
  }

  private static findTask(gid: string, token: string, preferOriginal: boolean): DownloadGalleryTask | null {
    const state = connectDownloadQueue()
    const hit: DownloadGalleryTask | undefined = state.galleryTasks.find((task: DownloadGalleryTask) => {
      return DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)
    })
    return hit !== undefined ? hit.copy() : null
  }

  private static findArchiverTask(tag: string): DownloadArchiverTask | null {
    const state = connectDownloadQueue()
    const hit: DownloadArchiverTask | undefined = state.archiverTasks.find((task: DownloadArchiverTask) => {
      return task.tag === tag
    })
    return hit !== undefined ? hit.copy() : null
  }

  private static sameGalleryTask(
    task: DownloadGalleryTask,
    gid: string,
    token: string,
    preferOriginal: boolean,
  ): boolean {
    return task.gid === gid && task.token === token && task.preferOriginal === preferOriginal
  }

  private static galleryQuality(preferOriginal: boolean): string {
    return preferOriginal ? 'original' : 'resample'
  }

  private static taskKey(gid: string, token: string, preferOriginal: boolean): string {
    return `${gid}:${token}:${DownloadQueueSettings.galleryQuality(preferOriginal)}`
  }

  private static seedToImage(seed: DownloadImageSeed): EhGalleryImage {
    const image: EhGalleryImage = new EhGalleryImage()
    image.page = seed.page
    image.imgkey = seed.imgkey
    image.sUrl = seed.imagePageUrl
    image.thumbUrl = seed.thumbUrl
    image.imageUrl = seed.imageUrl
    image.originImageUrl = seed.originImageUrl
    image.showKey = seed.showKey
    image.reloadKey = seed.reloadKey
    return image
  }

  private static galleryTaskPathTitle(task: DownloadGalleryTask): string {
    return task.title.length > 0 ? task.title : task.titleJp
  }

  private static legacyGalleryDirName(gid: string, preferOriginal: boolean): string {
    const base: string = DownloadQueueSettings.safePathPart(gid)
    return preferOriginal ? `${base}-original` : base
  }

  private static galleryDirName(gid: string, preferOriginal: boolean, title: string): string {
    const base: string = DownloadQueueSettings.safePathPart(gid)
    const titlePart: string = DownloadQueueSettings.pathTitlePart(title)
    const namedBase: string = titlePart.length > 0 ? `${base}-${titlePart}` : base
    return preferOriginal ? `${namedBase}-original` : namedBase
  }

  private static galleryDirNameCandidates(gid: string, preferOriginal: boolean, title: string): string[] {
    const out: string[] = []
    DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.galleryDirName(gid, preferOriginal, title))
    DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.legacyGalleryDirName(gid, preferOriginal))
    return out
  }

  private static joinPath(parent: string, child: string): string {
    return parent.endsWith('/') ? `${parent}${child}` : `${parent}/${child}`
  }

  private static pushUniquePath(paths: string[], path: string): void {
    if (path.length > 0 && paths.indexOf(path) < 0) {
      paths.push(path)
    }
  }

  private static publicDownloadRootDir(): string {
    if (DownloadQueueSettings.downloadPublicRoot.length > 0) {
      return DownloadQueueSettings.downloadPublicRoot
    }
    throw new Error('download directory unavailable')
  }

  private static isPublicDownloadPath(path: string): boolean {
    try {
      const root: string = DownloadQueueSettings.publicDownloadRootDir()
      return path === root || path.startsWith(root + '/')
    } catch (_error) {
      return false
    }
  }

  private static downloadRootCandidates(context: common.UIAbilityContext): string[] {
    const out: string[] = []
    if (DownloadQueueSettings.downloadPublicRoot.length > 0) {
      DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.downloadPublicRoot)
    }
    DownloadQueueSettings.pushUniquePath(out, context.filesDir)
    return out
  }

  private static downloadWriteRootCandidates(): string[] {
    const out: string[] = []
    DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.publicDownloadRootDir())
    return out
  }

  private static async ensureDownloadDirectoryReady(context: common.UIAbilityContext): Promise<boolean> {
    if (DownloadQueueSettings.downloadPublicRoot.length > 0) {
      return true
    }
    if (DownloadQueueSettings.downloadRootRequest !== null) {
      return await DownloadQueueSettings.downloadRootRequest
    }
    const request: Promise<boolean> = DownloadQueueSettings.requestDownloadRootWithDownloadMode(context)
    DownloadQueueSettings.downloadRootRequest = request
    try {
      return await request
    } finally {
      DownloadQueueSettings.downloadRootRequest = null
    }
  }

  static async ensureDownloadStorageReady(context: common.UIAbilityContext): Promise<boolean> {
    if (!await DownloadQueueSettings.ensureDownloadDirectoryReady(context)) {
      return false
    }
    try {
      const roots: string[] = DownloadQueueSettings.downloadWriteRootCandidates()
      for (let i: number = 0; i < roots.length; i++) {
        const galleryDir: string = DownloadQueueSettings.joinPath(roots[i], DOWNLOAD_GALLERY_DIR)
        const archiverDir: string = DownloadQueueSettings.joinPath(roots[i], DOWNLOAD_ARCHIVER_DIR)
        if (!DownloadQueueSettings.ensureDirectoryExists(galleryDir) ||
          !DownloadQueueSettings.ensureDirectoryExists(archiverDir)) {
          throw new Error('download storage directory unavailable')
        }
        if (!DownloadQueueSettings.reconcileNoMediaMarker(galleryDir) ||
          !DownloadQueueSettings.reconcileNoMediaMarker(archiverDir)) {
          throw new Error('download media marker unavailable')
        }
        DownloadQueueSettings.logDownloadDirResolved('gallery-root', galleryDir, context)
        DownloadQueueSettings.logDownloadDirResolved('archiver-root', archiverDir, context)
      }
      return true
    } catch (error) {
      DiagnosticLogger.warn('download', 'download_storage_ready_failed', (error as Error).message)
      return false
    }
  }

  static async ensureDownloadExportDir(context: common.UIAbilityContext): Promise<string> {
    if (!await DownloadQueueSettings.ensureDownloadDirectoryReady(context)) {
      throw new Error('download directory unavailable')
    }
    const root: string = DownloadQueueSettings.publicDownloadRootDir()
    const dir: string = DownloadQueueSettings.joinPath(root, DOWNLOAD_EXPORT_DIR)
    if (!DownloadQueueSettings.ensureDirectoryExists(dir)) {
      throw new Error('download export directory unavailable')
    }
    DownloadQueueSettings.logDownloadDirResolved('export-root', dir, context)
    return dir
  }

  private static ensureDirectoryExists(dir: string): boolean {
    try {
      fs.mkdirSync(dir, true)
      return true
    } catch (_error) {
      try {
        return fs.accessSync(dir)
      } catch (_accessError) {
        return false
      }
    }
  }

  static reconcileNoMediaMarkersIfReady(): void {
    if (DownloadQueueSettings.downloadPublicRoot.length === 0) {
      return
    }
    try {
      const root: string = DownloadQueueSettings.publicDownloadRootDir()
      const galleryDir: string = DownloadQueueSettings.joinPath(root, DOWNLOAD_GALLERY_DIR)
      const archiverDir: string = DownloadQueueSettings.joinPath(root, DOWNLOAD_ARCHIVER_DIR)
      if (DownloadQueueSettings.ensureDirectoryExists(galleryDir)) {
        DownloadQueueSettings.reconcileNoMediaMarker(galleryDir)
      }
      if (DownloadQueueSettings.ensureDirectoryExists(archiverDir)) {
        DownloadQueueSettings.reconcileNoMediaMarker(archiverDir)
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'download_no_media_reconcile_failed', (error as Error).message)
    }
  }

  private static reconcileNoMediaMarker(dir: string): boolean {
    const marker: string = DownloadQueueSettings.joinPath(dir, NO_MEDIA_MARKER_FILE)
    try {
      if (connectDownloadSettings().hideFromMediaLibrary) {
        if (!fs.accessSync(marker)) {
          DownloadQueueSettings.writeTextFile(marker, '', 'download_no_media_marker_write_failed')
        }
        return fs.accessSync(marker)
      }
      if (fs.accessSync(marker)) {
        fs.unlinkSync(marker)
      }
      return !fs.accessSync(marker)
    } catch (error) {
      DiagnosticLogger.warn('download', 'download_no_media_marker_sync_failed', (error as Error).message)
      return false
    }
  }

  private static async requestDownloadRootWithDownloadMode(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const options = new picker.DocumentSaveOptions()
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      const documentPicker = new picker.DocumentViewPicker(context)
      const result: Array<string> = await documentPicker.save(options)
      if (result.length === 0) {
        throw new Error('download mode returned no uri')
      }
      const root: string = DownloadQueueSettings.pathFromDownloadModeUri(result[0])
      if (root.length === 0) {
        throw new Error('download mode returned empty path')
      }
      if (!DownloadQueueSettings.ensureDirectoryExists(root)) {
        throw new Error('download mode app directory unavailable')
      }
      DownloadQueueSettings.downloadPublicRoot = root
      DiagnosticLogger.info(
        'download',
        'download_mode_root_resolved',
        `uriHash=${DiagnosticLogger.ownerHash(result[0])} path=${root}`,
      )
      return true
    } catch (error) {
      DiagnosticLogger.warn('download', 'download_mode_root_failed', (error as Error).message)
      return false
    }
  }

  private static pathFromDownloadModeUri(uri: string): string {
    const marker: string = '.nexte-download-root'
    const markerPath: string = new fileUri.FileUri(DownloadQueueSettings.joinPath(uri.trim(), marker)).path
    const suffix: string = `/${marker}`
    if (!markerPath.endsWith(suffix)) {
      throw new Error('download mode uri path conversion failed')
    }
    return DownloadQueueSettings.normalizeDownloadRoot(
      markerPath.substring(0, markerPath.length - suffix.length),
    )
  }

  private static normalizeDownloadRoot(path: string): string {
    let out: string = path.trim()
    while (out.endsWith('/') && out.length > 1) {
      out = out.substring(0, out.length - 1)
    }
    if (out.endsWith('/NextE/NextE')) {
      out = out.substring(0, out.length - '/NextE'.length)
    }
    return out
  }

  private static logDownloadDirResolved(kind: string, dir: string, context: common.UIAbilityContext): void {
    const key: string = `${kind}:${dir}`
    if (DownloadQueueSettings.loggedDownloadDirs.has(key)) {
      return
    }
    DownloadQueueSettings.loggedDownloadDirs.add(key)
    const location: string = DownloadQueueSettings.isPublicDownloadPath(dir)
      ? 'public'
      : (dir === context.filesDir || dir.startsWith(context.filesDir + '/') ? 'private' : 'other')
    DiagnosticLogger.info('download', 'download_dir_resolved', `kind=${kind} location=${location} path=${dir}`)
  }

  private static galleryRootDirs(context: common.UIAbilityContext): string[] {
    const out: string[] = []
    const roots: string[] = DownloadQueueSettings.downloadRootCandidates(context)
    for (let i: number = 0; i < roots.length; i++) {
      DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.joinPath(roots[i], DOWNLOAD_GALLERY_DIR))
    }
    return out
  }

  private static archiverRootDirs(context: common.UIAbilityContext): string[] {
    const out: string[] = []
    const roots: string[] = DownloadQueueSettings.downloadRootCandidates(context)
    for (let i: number = 0; i < roots.length; i++) {
      DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.joinPath(roots[i], DOWNLOAD_ARCHIVER_DIR))
    }
    return out
  }

  private static galleryWriteRootDirs(): string[] {
    const out: string[] = []
    const roots: string[] = DownloadQueueSettings.downloadWriteRootCandidates()
    for (let i: number = 0; i < roots.length; i++) {
      DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.joinPath(roots[i], DOWNLOAD_GALLERY_DIR))
    }
    return out
  }

  private static archiverWriteRootDirs(): string[] {
    const out: string[] = []
    const roots: string[] = DownloadQueueSettings.downloadWriteRootCandidates()
    for (let i: number = 0; i < roots.length; i++) {
      DownloadQueueSettings.pushUniquePath(out, DownloadQueueSettings.joinPath(roots[i], DOWNLOAD_ARCHIVER_DIR))
    }
    return out
  }

  private static legacyGalleryRootDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${DOWNLOAD_GALLERY_DIR}`
  }

  private static legacyArchiverRootDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${DOWNLOAD_ARCHIVER_DIR}`
  }

  private static ensureGalleryDownloadDir(
    context: common.UIAbilityContext,
    gid: string,
    preferOriginal: boolean,
    title: string = '',
  ): string {
    const roots: string[] = DownloadQueueSettings.galleryWriteRootDirs()
    const names: string[] = DownloadQueueSettings.galleryDirNameCandidates(gid, preferOriginal, title)
    let lastError: Error | null = null
    for (let i: number = 0; i < roots.length; i++) {
      for (let j: number = 0; j < names.length; j++) {
        const existingDir: string = DownloadQueueSettings.joinPath(roots[i], names[j])
        try {
          if (fs.accessSync(existingDir)) {
            DownloadQueueSettings.logDownloadDirResolved('gallery', existingDir, context)
            return existingDir
          }
        } catch (_error) {
        }
      }
      const dir: string = DownloadQueueSettings.joinPath(roots[i], names[0])
      try {
        fs.mkdirSync(dir, true)
        DownloadQueueSettings.logDownloadDirResolved('gallery', dir, context)
        return dir
      } catch (error) {
        if (fs.accessSync(dir)) {
          DownloadQueueSettings.logDownloadDirResolved('gallery', dir, context)
          return dir
        }
        DiagnosticLogger.warn(
          'download',
          'download_dir_candidate_failed',
          `kind=gallery path=${dir} error=${(error as Error).message}`,
        )
        lastError = error as Error
      }
    }
    throw lastError ?? new Error('download directory unavailable')
  }

  private static ensureArchiverDownloadDir(context: common.UIAbilityContext): string {
    const roots: string[] = DownloadQueueSettings.archiverWriteRootDirs()
    let lastError: Error | null = null
    for (let i: number = 0; i < roots.length; i++) {
      const dir: string = roots[i]
      try {
        fs.mkdirSync(dir, true)
        DownloadQueueSettings.logDownloadDirResolved('archiver', dir, context)
        return dir
      } catch (error) {
        if (fs.accessSync(dir)) {
          DownloadQueueSettings.logDownloadDirResolved('archiver', dir, context)
          return dir
        }
        DiagnosticLogger.warn(
          'download',
          'download_dir_candidate_failed',
          `kind=archiver path=${dir} error=${(error as Error).message}`,
        )
        lastError = error as Error
      }
    }
    throw lastError ?? new Error('download directory unavailable')
  }

  private static galleryMetadataPath(context: common.UIAbilityContext, task: DownloadGalleryTask): string {
    return `${DownloadQueueSettings.ensureGalleryDownloadDir(
      context,
      task.gid,
      task.preferOriginal,
      DownloadQueueSettings.galleryTaskPathTitle(task),
    )}/${DOWNLOAD_METADATA_FILE}`
  }

  private static archiverMetadataPath(context: common.UIAbilityContext, task: DownloadArchiverTask): string {
    return `${DownloadQueueSettings.ensureArchiverDownloadDir(context)}/${DownloadQueueSettings.safePathPart(task.tag)}${ARCHIVER_METADATA_SUFFIX}`
  }

  private static writeGalleryMetadataTasks(context: common.UIAbilityContext, tasks: DownloadGalleryTask[]): void {
    tasks.forEach((task: DownloadGalleryTask) => {
      DownloadQueueSettings.writeGalleryMetadataTask(context, task)
    })
  }

  private static scheduleGalleryMetadataTask(context: common.UIAbilityContext, task: DownloadGalleryTask): void {
    if (task.gid.length === 0) {
      return
    }
    const key: string = DownloadQueueSettings.taskKey(task.gid, task.token, task.preferOriginal)
    DownloadQueueSettings.pendingGalleryMetadataTasks.set(key, task)
    if (DownloadQueueSettings.galleryMetadataFlushTimers.has(key)) {
      return
    }
    const timer: number = setTimeout((): void => {
      DownloadQueueSettings.galleryMetadataFlushTimers.delete(key)
      const pending: DownloadGalleryTask | undefined = DownloadQueueSettings.pendingGalleryMetadataTasks.get(key)
      DownloadQueueSettings.pendingGalleryMetadataTasks.delete(key)
      if (pending !== undefined) {
        DownloadQueueSettings.writeGalleryMetadataTask(context, pending)
      }
    }, DOWNLOAD_PROGRESS_METADATA_FLUSH_MS)
    DownloadQueueSettings.galleryMetadataFlushTimers.set(key, timer)
  }

  private static cancelScheduledGalleryMetadata(task: DownloadGalleryTask): void {
    if (task.gid.length === 0) {
      return
    }
    const key: string = DownloadQueueSettings.taskKey(task.gid, task.token, task.preferOriginal)
    const timer: number | undefined = DownloadQueueSettings.galleryMetadataFlushTimers.get(key)
    if (timer !== undefined) {
      clearTimeout(timer)
      DownloadQueueSettings.galleryMetadataFlushTimers.delete(key)
    }
    DownloadQueueSettings.pendingGalleryMetadataTasks.delete(key)
  }

  private static writeGalleryMetadataTask(context: common.UIAbilityContext, task: DownloadGalleryTask): void {
    if (task.gid.length === 0) {
      return
    }
    DownloadQueueSettings.cancelScheduledGalleryMetadata(task)
    try {
      const startedAt: number = Date.now()
      const text: string = JSON.stringify([DownloadQueueSettings.galleryTaskMetadata(task)])
      DownloadQueueSettings.writeTextFile(
        DownloadQueueSettings.galleryMetadataPath(context, task),
        text,
        'gallery_metadata_write_failed',
      )
      const costMs: number = Date.now() - startedAt
      if (costMs >= DOWNLOAD_PERF_METADATA_WARN_MS || text.length >= DOWNLOAD_PERF_METADATA_WARN_BYTES) {
        DiagnosticLogger.info(
          'download',
          'download_perf_gallery_metadata',
          `gid=${task.gid} quality=${DownloadQueueSettings.galleryQuality(task.preferOriginal)} seeds=${task.imageSeeds.length} jsonBytes=${text.length} costMs=${costMs}`,
        )
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'gallery_metadata_write_failed', (error as Error).message)
    }
  }

  private static writeArchiverMetadataTasks(context: common.UIAbilityContext, tasks: DownloadArchiverTask[]): void {
    tasks.forEach((task: DownloadArchiverTask) => {
      DownloadQueueSettings.writeArchiverMetadataTask(context, task)
    })
  }

  private static writeArchiverMetadataTask(context: common.UIAbilityContext, task: DownloadArchiverTask): void {
    if (task.tag.length === 0) {
      return
    }
    try {
      DownloadQueueSettings.writeTextFile(
        DownloadQueueSettings.archiverMetadataPath(context, task),
        JSON.stringify([DownloadQueueSettings.archiverTaskMetadata(task)]),
        'archiver_metadata_write_failed',
      )
    } catch (error) {
      DiagnosticLogger.warn('download', 'archiver_metadata_write_failed', (error as Error).message)
    }
  }

  private static loadGalleryMetadataTasks(context: common.UIAbilityContext): DownloadGalleryTask[] {
    const out: DownloadGalleryTask[] = []
    const roots: string[] = DownloadQueueSettings.galleryRootDirs(context)
    const legacyRoot: string = DownloadQueueSettings.legacyGalleryRootDir(context)
    DownloadQueueSettings.pushUniquePath(roots, legacyRoot)
    try {
      for (let r: number = 0; r < roots.length && out.length < MAX_GALLERY_TASKS; r++) {
        const root: string = roots[r]
        if (!fs.accessSync(root)) {
          continue
        }
        const names: string[] = fs.listFileSync(root)
        for (let i: number = 0; i < names.length && out.length < MAX_GALLERY_TASKS; i++) {
          const path: string = `${root}/${names[i]}/${DOWNLOAD_METADATA_FILE}`
          if (fs.accessSync(path)) {
            const tasks: DownloadGalleryTask[] = DownloadQueueSettings.parse(fs.readTextSync(path))
            tasks.forEach((task: DownloadGalleryTask) => {
              if (out.length < MAX_GALLERY_TASKS) {
                out.push(task)
              }
            })
          }
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'gallery_metadata_restore_failed', (error as Error).message)
    }
    return out
  }

  private static loadArchiverMetadataTasks(context: common.UIAbilityContext): DownloadArchiverTask[] {
    const out: DownloadArchiverTask[] = []
    const roots: string[] = DownloadQueueSettings.archiverRootDirs(context)
    const legacyRoot: string = DownloadQueueSettings.legacyArchiverRootDir(context)
    DownloadQueueSettings.pushUniquePath(roots, legacyRoot)
    try {
      for (let r: number = 0; r < roots.length && out.length < MAX_ARCHIVER_TASKS; r++) {
        const root: string = roots[r]
        if (!fs.accessSync(root)) {
          continue
        }
        const names: string[] = fs.listFileSync(root)
        for (let i: number = 0; i < names.length && out.length < MAX_ARCHIVER_TASKS; i++) {
          if (!names[i].endsWith(ARCHIVER_METADATA_SUFFIX)) {
            continue
          }
          const tasks: DownloadArchiverTask[] = DownloadQueueSettings.parseArchiver(fs.readTextSync(`${root}/${names[i]}`))
          tasks.forEach((task: DownloadArchiverTask) => {
            if (out.length < MAX_ARCHIVER_TASKS) {
              out.push(task)
            }
          })
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'archiver_metadata_restore_failed', (error as Error).message)
    }
    return out
  }

  private static mergeRestoredGalleryTasks(
    primary: DownloadGalleryTask[],
    fallback: DownloadGalleryTask[],
  ): DownloadGalleryTask[] {
    const out: DownloadGalleryTask[] = primary.map((task: DownloadGalleryTask) => task.copy())
    fallback.forEach((task: DownloadGalleryTask) => {
      const exists: boolean = out.some((it: DownloadGalleryTask) => {
        return DownloadQueueSettings.sameGalleryTask(it, task.gid, task.token, task.preferOriginal)
      })
      if (!exists && out.length < MAX_GALLERY_TASKS) {
        out.push(task.copy())
      }
    })
    return out
  }

  private static mergeRestoredArchiverTasks(
    primary: DownloadArchiverTask[],
    fallback: DownloadArchiverTask[],
  ): DownloadArchiverTask[] {
    const out: DownloadArchiverTask[] = primary.map((task: DownloadArchiverTask) => task.copy())
    fallback.forEach((task: DownloadArchiverTask) => {
      const exists: boolean = out.some((it: DownloadArchiverTask) => it.tag === task.tag)
      if (!exists && out.length < MAX_ARCHIVER_TASKS) {
        out.push(task.copy())
      }
    })
    return out
  }

  private static countNewGalleryTasks(
    primary: DownloadGalleryTask[],
    fallback: DownloadGalleryTask[],
  ): number {
    let count: number = 0
    fallback.forEach((task: DownloadGalleryTask) => {
      const exists: boolean = primary.some((it: DownloadGalleryTask) => {
        return DownloadQueueSettings.sameGalleryTask(it, task.gid, task.token, task.preferOriginal)
      })
      if (!exists) {
        count++
      }
    })
    return count
  }

  private static countNewArchiverTasks(
    primary: DownloadArchiverTask[],
    fallback: DownloadArchiverTask[],
  ): number {
    let count: number = 0
    fallback.forEach((task: DownloadArchiverTask) => {
      const exists: boolean = primary.some((it: DownloadArchiverTask) => it.tag === task.tag)
      if (!exists) {
        count++
      }
    })
    return count
  }

  private static hydrateArchiverTasksFromGalleryTasks(
    archiverTasks: DownloadArchiverTask[],
    galleryTasks: DownloadGalleryTask[],
  ): DownloadArchiverTask[] {
    const out: DownloadArchiverTask[] = []
    archiverTasks.forEach((task: DownloadArchiverTask) => {
      const next: DownloadArchiverTask = task.copy()
      DownloadQueueSettings.fillArchiverTaskFromGalleryTask(
        next,
        DownloadQueueSettings.findGalleryTaskIn(galleryTasks, next.gid, next.token),
      )
      out.push(next)
    })
    return out
  }

  private static fillArchiverTaskFromGalleryTask(
    task: DownloadArchiverTask,
    galleryTask: DownloadGalleryTask | undefined,
  ): void {
    if (galleryTask === undefined) {
      return
    }
    if (task.token.length === 0 && galleryTask.token.length > 0) {
      task.token = galleryTask.token
    }
    if (task.title.length === 0) {
      if (galleryTask.title.length > 0) {
        task.title = galleryTask.title
      } else if (galleryTask.titleJp.length > 0) {
        task.title = galleryTask.titleJp
      }
    }
    if (task.thumbUrl.length === 0 && galleryTask.thumbUrl.length > 0) {
      task.thumbUrl = galleryTask.thumbUrl
    }
    if (task.imgWidth <= 0 && galleryTask.imgWidth > 0) {
      task.imgWidth = galleryTask.imgWidth
    }
    if (task.imgHeight <= 0 && galleryTask.imgHeight > 0) {
      task.imgHeight = galleryTask.imgHeight
    }
  }

  private static writeTextFile(path: string, text: string, event: string): void {
    let file: fs.File | null = null
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, text)
    } catch (error) {
      DiagnosticLogger.warn('download', event, (error as Error).message)
    } finally {
      if (file !== null) {
        fs.closeSync(file)
      }
    }
  }

  private static galleryTaskMetadata(task: DownloadGalleryTask): DownloadGalleryTaskMetadata {
    const out: DownloadGalleryTaskMetadata = new DownloadGalleryTaskMetadata()
    out.gid = task.gid
    out.token = task.token
    out.title = task.title
    out.titleJp = task.titleJp
    out.thumbUrl = task.thumbUrl
    out.imgWidth = task.imgWidth
    out.imgHeight = task.imgHeight
    out.pageCount = task.pageCount
    out.category = task.category
    out.uploader = task.uploader
    out.upgradeFromGid = task.upgradeFromGid
    out.queuedAt = task.queuedAt
    out.preparedAt = task.preparedAt
    out.firstPageCount = task.firstPageCount
    out.previewPageCount = task.previewPageCount
    out.imageSeeds = task.imageSeeds.map((seed: DownloadImageSeed) => DownloadQueueSettings.seedMetadata(seed))
    out.prepareError = task.prepareError
    out.preferOriginal = task.preferOriginal
    out.status = task.status
    return out
  }

  private static seedMetadata(seed: DownloadImageSeed): DownloadImageSeedMetadata {
    const out: DownloadImageSeedMetadata = new DownloadImageSeedMetadata()
    out.page = seed.page
    out.imgkey = seed.imgkey
    out.imagePageUrl = seed.imagePageUrl
    out.thumbUrl = seed.thumbUrl
    out.imageUrl = seed.imageUrl
    out.originImageUrl = seed.originImageUrl
    out.showKey = seed.showKey
    out.reloadKey = seed.reloadKey
    out.filePath = seed.filePath
    out.bytesWritten = seed.bytesWritten
    out.downloadedAt = seed.downloadedAt
    out.downloadError = seed.downloadError
    return out
  }

  private static archiverTaskMetadata(task: DownloadArchiverTask): DownloadArchiverTaskMetadata {
    const out: DownloadArchiverTaskMetadata = new DownloadArchiverTaskMetadata()
    out.tag = task.tag
    out.gid = task.gid
    out.token = task.token
    out.title = task.title
    out.thumbUrl = task.thumbUrl
    out.imgWidth = task.imgWidth
    out.imgHeight = task.imgHeight
    out.dltype = task.dltype
    out.resolution = task.resolution
    out.parseSource = task.parseSource
    out.url = task.url
    out.fileName = task.fileName
    out.filePath = task.filePath
    out.queuedAt = task.queuedAt
    out.downloadedAt = task.downloadedAt
    out.bytesWritten = task.bytesWritten
    out.bytesTotal = task.bytesTotal
    out.progress = task.progress
    out.error = task.error
    out.status = task.status
    return out
  }

  private static deleteGalleryContent(context: common.UIAbilityContext, task: DownloadGalleryTask): void {
    if (task.gid.length === 0) {
      return
    }
    const roots: string[] = DownloadQueueSettings.galleryRootDirs(context)
    DownloadQueueSettings.pushUniquePath(roots, DownloadQueueSettings.legacyGalleryRootDir(context))
    const names: string[] = DownloadQueueSettings.galleryDirNameCandidates(
      task.gid,
      task.preferOriginal,
      DownloadQueueSettings.galleryTaskPathTitle(task),
    )
    for (let i: number = 0; i < roots.length; i++) {
      for (let j: number = 0; j < names.length; j++) {
        DownloadQueueSettings.deleteSandboxPath(
          DownloadQueueSettings.joinPath(roots[i], names[j]),
          'gallery_content_delete_failed',
        )
      }
    }
  }

  private static deleteArchiverContent(context: common.UIAbilityContext, task: DownloadArchiverTask): void {
    DownloadQueueSettings.deleteSandboxPath(DownloadQueueSettings.archiverMetadataPath(context, task), 'archiver_metadata_delete_failed')
    const roots: string[] = DownloadQueueSettings.archiverRootDirs(context)
    DownloadQueueSettings.pushUniquePath(roots, DownloadQueueSettings.legacyArchiverRootDir(context))
    for (let i: number = 0; i < roots.length; i++) {
      DownloadQueueSettings.deleteSandboxPath(
        DownloadQueueSettings.joinPath(roots[i], `${DownloadQueueSettings.safePathPart(task.tag)}${ARCHIVER_METADATA_SUFFIX}`),
        'archiver_metadata_delete_failed',
      )
    }
    DownloadQueueSettings.deleteSandboxPath(task.filePath, 'archiver_file_delete_failed')
    DownloadQueueSettings.deleteSandboxPath(DownloadQueueSettings.archiverPartialPath(task.filePath), 'archiver_partial_file_delete_failed')
    DownloadQueueSettings.deleteArchiverExtracts(context, task)
  }

  private static deleteArchiverExtracts(context: common.UIAbilityContext, task: DownloadArchiverTask): void {
    if (task.tag.length === 0) {
      return
    }
    const root: string = `${context.cacheDir}/${ARCHIVER_READ_CACHE_DIR}`
    const prefix: string = `${DownloadQueueSettings.safePathPart(task.tag)}-`
    try {
      if (!fs.accessSync(root)) {
        return
      }
      const names: string[] = fs.listFileSync(root)
      for (let i: number = 0; i < names.length; i++) {
        if (names[i].startsWith(prefix)) {
          DownloadQueueSettings.deleteSandboxPath(`${root}/${names[i]}`, 'archiver_extract_delete_failed')
        }
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'archiver_extract_scan_failed', (error as Error).message)
    }
  }

  private static deleteSandboxPath(path: string, event: string): void {
    if (path.length === 0) {
      return
    }
    try {
      if (!fs.accessSync(path)) {
        return
      }
      const stat: fs.Stat = fs.statSync(path)
      if (stat.isDirectory()) {
        fs.rmdirSync(path)
      } else {
        fs.unlinkSync(path)
      }
    } catch (error) {
      DiagnosticLogger.warn('download', event, (error as Error).message)
    }
  }

  private static safePathPart(value: string): string {
    return value.replace(/[/:*"<>|,?\\]/g, '_')
  }

  private static pathTitlePart(value: string): string {
    const safe: string = DownloadQueueSettings.safePathPart(value).trim().replace(/\s+/g, ' ')
    if (safe.length <= DOWNLOAD_PATH_TITLE_MAX_LENGTH) {
      return safe
    }
    return safe.substring(0, DOWNLOAD_PATH_TITLE_MAX_LENGTH).trim()
  }

  private static fileNameForSeed(seed: DownloadImageSeed, imageUrl: string): string {
    return `${DownloadQueueSettings.pageFilePrefix(seed.page)}${DownloadQueueSettings.fileExtFromUrl(imageUrl)}`
  }

  private static pageFilePrefix(page: number): string {
    let text: string = `${page > 0 ? page : 1}`
    while (text.length < 4) {
      text = `0${text}`
    }
    return text
  }

  private static fileExtFromUrl(url: string): string {
    const q: number = url.indexOf('?')
    const clean: string = q >= 0 ? url.substring(0, q) : url
    const slash: number = clean.lastIndexOf('/')
    const name: string = slash >= 0 ? clean.substring(slash + 1) : clean
    const dot: number = name.lastIndexOf('.')
    if (dot >= 0 && dot < name.length - 1 && name.length - dot <= 6) {
      return name.substring(dot)
    }
    return '.jpg'
  }

  private static archiverFileName(task: DownloadArchiverTask): string {
    const titlePart: string = DownloadQueueSettings.pathTitlePart(task.title)
    const typePart: string = DownloadQueueSettings.safePathPart(task.dltype)
    let name: string = DownloadQueueSettings.safePathPart(task.gid)
    if (titlePart.length > 0) {
      name = `${name}-${titlePart}`
    }
    if (typePart.length > 0) {
      name = `${name}-${typePart}`
    }
    const ext: string = DownloadQueueSettings.fileExtFromUrl(task.url)
    return ext === '.jpg' ? `${name}.zip` : `${name}${ext}`
  }

  private static archiverPartialPath(filePath: string): string {
    return filePath.length > 0 ? `${filePath}.part` : ''
  }

  private static normalizeArchiverDownloadUrl(url: string): string {
    const trimmed: string = url.trim()
    if (trimmed.length === 0) {
      return ''
    }
    if (trimmed.indexOf('autostart=') < 0 && trimmed.indexOf('start=') >= 0) {
      return trimmed
    }
    let out: string = trimmed.replace(/([?&])autostart=[^&]*&?/g, '$1')
    if (out.endsWith('?') || out.endsWith('&')) {
      out = out.substring(0, out.length - 1)
    }
    return out.indexOf('?') >= 0 ? `${out}&start=1` : `${out}?start=1`
  }

  private static updateGalleryStreamProgress(
    gid: string,
    token: string,
    preferOriginal: boolean,
    seed: DownloadImageSeed,
    loaded: number,
    total: number,
  ): void {
    const key: string = DownloadQueueSettings.taskKey(gid, token, preferOriginal)
    if (DownloadQueueSettings.cancelledGalleryDownloads.has(key)) {
      return
    }
    if (loaded <= 0) {
      return
    }
    const pulseKey: string = key
    const now: number = Date.now()
    const last: number = DownloadQueueSettings.galleryProgressPulses.get(pulseKey) ?? 0
    if (now - last < DOWNLOAD_QUEUE_PROGRESS_INTERVAL_MS) {
      return
    }
    DownloadQueueSettings.galleryProgressPulses.set(pulseKey, now)
    DownloadQueueSettings.recordGalleryActiveProgress(key, seed.page, loaded, total, now)
    if (!isDownloadQueuePageActive()) {
      DownloadQueueSettings.recordGalleryProgressSignalRate(key, gid, preferOriginal, now)
      return
    }
    DownloadQueueSettings.syncGalleryActiveProgressToQueue(key, gid, token, preferOriginal, now)
  }

  static syncActiveGalleryProgressToQueue(): void {
    if (!isDownloadQueuePageActive()) {
      return
    }
    const now: number = Date.now()
    const state = connectDownloadQueue()
    let updated: boolean = false
    DownloadQueueSettings.galleryActiveProgress.forEach((progress: DownloadGalleryActiveProgress, key: string) => {
      for (let i: number = 0; i < state.galleryTasks.length; i++) {
        const task: DownloadGalleryTask = state.galleryTasks[i]
        if (DownloadQueueSettings.taskKey(task.gid, task.token, task.preferOriginal) === key) {
          DownloadQueueSettings.applyGalleryActiveProgress(task, progress)
          updated = true
          break
        }
      }
    })
    if (updated) {
      publishDownloadQueueChanged()
    }
  }

  private static syncGalleryActiveProgressToQueue(
    key: string,
    gid: string,
    token: string,
    preferOriginal: boolean,
    now: number,
  ): void {
    const progress: DownloadGalleryActiveProgress | undefined = DownloadQueueSettings.galleryActiveProgress.get(key)
    if (progress === undefined) {
      return
    }
    const state = connectDownloadQueue()
    let logged: boolean = false
    let updated: boolean = false
    for (let i: number = 0; i < state.galleryTasks.length; i++) {
      const task: DownloadGalleryTask = state.galleryTasks[i]
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        DownloadQueueSettings.applyGalleryActiveProgress(task, progress)
        updated = true
        const logKey: string = key
        const lastLog: number = DownloadQueueSettings.galleryProgressLogPulses.get(logKey) ?? 0
        if ((progress.total > 0 && progress.loaded >= progress.total) || now - lastLog >= 2000) {
          DownloadQueueSettings.galleryProgressLogPulses.set(logKey, now)
          DiagnosticLogger.info(
            'download',
            'gallery_download_stream_progress',
            `gid=${gid} page=${progress.page} loaded=${progress.loaded} total=${progress.total} downloaded=${task.downloadedCount()} expected=${task.expectedFileCount()}`,
          )
          logged = true
        }
      }
    }
    if (updated) {
      publishDownloadQueueChanged()
      DownloadQueueSettings.recordGalleryProgressSignalRate(key, gid, preferOriginal, now)
    }
    if (!logged && progress.total > 0 && progress.loaded >= progress.total) {
      DownloadQueueSettings.galleryProgressLogPulses.set(key, now)
    }
  }

  private static recordGalleryActiveProgress(
    key: string,
    page: number,
    loaded: number,
    total: number,
    now: number,
  ): void {
    let progress: DownloadGalleryActiveProgress | undefined = DownloadQueueSettings.galleryActiveProgress.get(key)
    if (progress === undefined) {
      progress = new DownloadGalleryActiveProgress()
      DownloadQueueSettings.galleryActiveProgress.set(key, progress)
    }
    progress.page = page
    progress.loaded = loaded
    progress.total = total
    progress.updatedAt = now
  }

  private static applyGalleryActiveProgress(
    task: DownloadGalleryTask,
    progress: DownloadGalleryActiveProgress,
  ): void {
    task.activeDownloadPage = progress.page
    task.activeBytesWritten = progress.loaded
    task.activeBytesTotal = progress.total
    task.status = DownloadGalleryTaskStatus.DOWNLOADING
  }

  private static clearGalleryActiveProgress(key: string, page: number): void {
    const progress: DownloadGalleryActiveProgress | undefined = DownloadQueueSettings.galleryActiveProgress.get(key)
    if (progress !== undefined && progress.page === page) {
      DownloadQueueSettings.galleryActiveProgress.delete(key)
    }
  }

  private static recordGalleryProgressSignalRate(
    key: string,
    gid: string,
    preferOriginal: boolean,
    now: number,
  ): void {
    const windowStartedAt: number = DownloadQueueSettings.galleryProgressSignalWindows.get(key) ?? now
    const count: number = (DownloadQueueSettings.galleryProgressSignalCounts.get(key) ?? 0) + 1
    if (now - windowStartedAt < DOWNLOAD_PERF_SIGNAL_WINDOW_MS) {
      DownloadQueueSettings.galleryProgressSignalWindows.set(key, windowStartedAt)
      DownloadQueueSettings.galleryProgressSignalCounts.set(key, count)
      return
    }
    DiagnosticLogger.info(
      'download',
      'download_perf_gallery_signal_rate',
      `gid=${gid} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)} keyHash=${DiagnosticLogger.ownerHash(key)} signals=${count} windowMs=${now - windowStartedAt}`,
    )
    DownloadQueueSettings.galleryProgressSignalWindows.set(key, now)
    DownloadQueueSettings.galleryProgressSignalCounts.set(key, 0)
  }

  private static updateArchiverProgress(tag: string, loaded: number, total: number): void {
    if (DownloadQueueSettings.cancelledArchiverDownloads.has(tag)) {
      return
    }
    if (loaded <= 0) {
      return
    }
    const now: number = Date.now()
    const complete: boolean = total > 0 && loaded >= total
    const last: number = DownloadQueueSettings.archiverProgressPulses.get(tag) ?? 0
    if (!complete && now - last < DOWNLOAD_QUEUE_PROGRESS_INTERVAL_MS) {
      return
    }
    DownloadQueueSettings.archiverProgressPulses.set(tag, now)
    const state = connectDownloadQueue()
    let updated: boolean = false
    state.archiverTasks.forEach((task: DownloadArchiverTask) => {
      if (task.tag === tag) {
        updated = true
        task.bytesWritten = loaded
        task.bytesTotal = total
        task.progress = total > 0 ? Math.max(0, Math.min(100, loaded * 100 / total)) : 0
        task.status = DownloadGalleryTaskStatus.DOWNLOADING
        const lastLog: number = DownloadQueueSettings.archiverProgressLogPulses.get(tag) ?? 0
        if ((total > 0 && loaded >= total) || now - lastLog >= 2000) {
          DownloadQueueSettings.archiverProgressLogPulses.set(tag, now)
          DiagnosticLogger.info(
            'download',
            'archiver_download_stream_progress',
            `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(tag)} loaded=${loaded} total=${total} progress=${task.progress}`,
          )
        }
      }
    })
    if (updated && isDownloadQueuePageActive()) {
      publishDownloadQueueChanged()
    }
  }

  private static async updateArchiverTask(
    context: common.UIAbilityContext,
    tag: string,
    update: (task: DownloadArchiverTask) => void,
    persist: boolean = true,
  ): Promise<void> {
    const state = connectDownloadQueue()
    let updatedTask: DownloadArchiverTask | null = null
    state.archiverTasks.forEach((task: DownloadArchiverTask) => {
      if (task.tag === tag) {
        update(task)
        updatedTask = task
      }
    })
    if (updatedTask !== null) {
      publishDownloadQueueChanged()
    }
    if (persist && updatedTask !== null) {
      await DownloadQueueSettings.persistArchiverTask(context, updatedTask)
    }
  }

  private static async finalizeArchiverPartial(partialPath: string, filePath: string): Promise<void> {
    DownloadQueueSettings.deleteSandboxPath(filePath, 'archiver_replace_delete_failed')
    try {
      fs.renameSync(partialPath, filePath)
      return
    } catch (error) {
      DiagnosticLogger.warn('download', 'archiver_partial_rename_failed', (error as Error).message)
    }
    let src: fs.File | null = null
    let dest: fs.File | null = null
    try {
      src = fs.openSync(partialPath, fs.OpenMode.READ_ONLY)
      dest = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      await fs.copyFile(src.fd, dest.fd)
    } finally {
      if (src !== null) {
        fs.closeSync(src)
      }
      if (dest !== null) {
        fs.closeSync(dest)
      }
    }
    if (DownloadQueueSettings.downloadedFileSize(filePath) <= 0) {
      throw new Error('archive finalize copy failed')
    }
    DownloadQueueSettings.deleteSandboxPath(partialPath, 'archiver_partial_delete_failed')
  }

  private static async updateDownloadTaskStatus(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
    status: string,
    error: string,
  ): Promise<void> {
    const state = connectDownloadQueue()
    let updatedTask: DownloadGalleryTask | null = null
    let matched: boolean = false
    let exactMatched: boolean = false
    for (let i: number = 0; i < state.galleryTasks.length; i++) {
      const task: DownloadGalleryTask = state.galleryTasks[i]
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        exactMatched = true
        break
      }
    }
    state.galleryTasks.forEach((task: DownloadGalleryTask) => {
      const exact: boolean = DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)
      const gidFallback: boolean = !exactMatched && task.gid === gid && task.preferOriginal === preferOriginal
      if (exact || gidFallback) {
        matched = true
        const hadPrepareError: boolean = task.prepareError.length > 0
        if (gidFallback && token.length > 0) {
          task.token = token
        }
        task.status = status
        task.prepareError = error
        if (status === DownloadGalleryTaskStatus.DOWNLOADING && hadPrepareError) {
          DownloadQueueSettings.clearPendingSeedErrors(task.imageSeeds)
          task.syncProgressCounts()
        }
        if (status !== DownloadGalleryTaskStatus.DOWNLOADING) {
          task.clearActiveDownloadProgress()
        }
        updatedTask = task
      }
    })
    if (status === DownloadGalleryTaskStatus.ERROR || !matched) {
      DiagnosticLogger.info(
        'download',
        'gallery_status_update',
        `gid=${gid} tokenHash=${DiagnosticLogger.ownerHash(token)} quality=${DownloadQueueSettings.galleryQuality(preferOriginal)} status=${status} matched=${matched} exact=${exactMatched} errorHash=${DiagnosticLogger.ownerHash(error)}`,
      )
    }
    if (matched) {
      publishDownloadQueueChanged()
    }
    if (updatedTask !== null) {
      if (status === DownloadGalleryTaskStatus.DOWNLOADING) {
        await DownloadQueueSettings.persistGalleryTaskHeader(context, updatedTask, false)
      } else {
        await DownloadQueueSettings.persistGalleryTask(context, updatedTask)
      }
    }
  }

  private static clearPendingSeedErrors(seeds: DownloadImageSeed[]): void {
    seeds.forEach((seed: DownloadImageSeed) => {
      if (
        seed.filePath.length === 0 &&
        seed.imagePageUrl.length > 0 &&
        seed.downloadError.length > 0
      ) {
        seed.downloadError = ''
      }
    })
  }

  private static async updateGalleryTaskAfterPause(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    preferOriginal: boolean,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    let updatedTask: DownloadGalleryTask | null = null
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (DownloadQueueSettings.sameGalleryTask(task, gid, token, preferOriginal)) {
        task.status = DownloadGalleryTaskStatus.PAUSED
        task.prepareError = ''
        updatedTask = task.copy()
      }
      next.push(task)
    })
    DownloadQueueSettings.setGalleryTasks(state, next)
    if (updatedTask !== null) {
      await DownloadQueueSettings.persistGalleryTask(context, updatedTask)
    }
  }

  private static async delayForSpeedLimit(startedAt: number, results: DownloadSeedResult[]): Promise<void> {
    let bytes: number = 0
    results.forEach((result: DownloadSeedResult) => {
      if (result.error.length === 0 && result.bytes > 0) {
        bytes += result.bytes
      }
    })
    await DownloadQueueSettings.delayBytesForSpeedLimit(startedAt, bytes)
  }

  private static async delayBytesForSpeedLimit(startedAt: number, bytes: number): Promise<void> {
    const kbps: number = connectDownloadSettings().speedLimitKbps
    if (kbps <= 0) {
      return
    }
    if (bytes <= 0) {
      return
    }
    const expectedMs: number = Math.ceil(bytes * 1000 / (kbps * 1024))
    const remainMs: number = expectedMs - (Date.now() - startedAt)
    if (remainMs > 0) {
      await DownloadQueueSettings.delay(remainMs)
    }
  }

  private static sameSeed(a: DownloadImageSeed, b: DownloadImageSeed): boolean {
    if (a.imgkey.length > 0 && b.imgkey.length > 0) {
      return a.imgkey === b.imgkey
    }
    if (a.page > 0 && b.page > 0) {
      return a.page === b.page
    }
    // ponytail: URL fallback only covers legacy seed records without a parsed page number.
    if (a.imagePageUrl.length > 0 && b.imagePageUrl.length > 0) {
      return a.imagePageUrl === b.imagePageUrl
    }
    return false
  }

  private static async inheritDownloadedSeedsFromParent(
    context: common.UIAbilityContext,
    gid: string,
    seeds: DownloadImageSeed[],
    preferOriginal: boolean,
    parent: DownloadGalleryTask,
  ): Promise<DownloadImageSeed[]> {
    const inherited: DownloadImageSeed[] = []
    for (let i: number = 0; i < seeds.length; i++) {
      const seed: DownloadImageSeed = seeds[i]
      const out: DownloadImageSeed = seed.copy()
      if (out.filePath.length > 0 || out.imgkey.length === 0) {
        inherited.push(out)
        continue
      }
      const previous: DownloadImageSeed | undefined = parent.imageSeeds.find((it: DownloadImageSeed) => {
        return it.imgkey === out.imgkey &&
          it.filePath.length > 0 &&
          DownloadQueueSettings.downloadedFileSize(it.filePath) > 0
      })
      if (previous === undefined) {
        inherited.push(out)
        continue
      }
      const inheritedPath: string = await DownloadQueueSettings.copyInheritedSeedFile(
        context,
        gid,
        preferOriginal,
        DownloadQueueSettings.galleryTaskPathTitle(parent),
        out,
        previous,
      )
      if (inheritedPath.length === 0) {
        inherited.push(out)
        continue
      }
      out.imageUrl = previous.imageUrl
      out.originImageUrl = previous.originImageUrl
      out.showKey = previous.showKey
      out.reloadKey = previous.reloadKey
      out.filePath = inheritedPath
      out.bytesWritten = DownloadQueueSettings.downloadedFileSize(inheritedPath)
      out.downloadedAt = previous.downloadedAt
      out.downloadError = ''
      inherited.push(out)
    }
    return inherited
  }

  private static async copyInheritedSeedFile(
    context: common.UIAbilityContext,
    gid: string,
    preferOriginal: boolean,
    title: string,
    seed: DownloadImageSeed,
    previous: DownloadImageSeed,
  ): Promise<string> {
    const ext: string = DownloadQueueSettings.fileExtFromUrl(previous.filePath)
    const targetPath: string =
      `${DownloadQueueSettings.ensureGalleryDownloadDir(context, gid, preferOriginal, title)}/${DownloadQueueSettings.pageFilePrefix(seed.page)}${ext}`
    if (DownloadQueueSettings.downloadedFileSize(targetPath) > 0) {
      return targetPath
    }
    let src: fs.File | null = null
    let dest: fs.File | null = null
    try {
      src = fs.openSync(previous.filePath, fs.OpenMode.READ_ONLY)
      dest = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      await fs.copyFile(src.fd, dest.fd)
      return DownloadQueueSettings.downloadedFileSize(targetPath) > 0 ? targetPath : ''
    } catch (error) {
      DiagnosticLogger.warn('download', 'gallery_incremental_copy_failed', (error as Error).message)
      DownloadQueueSettings.deleteSandboxPath(targetPath, 'gallery_incremental_copy_delete_failed')
      return ''
    } finally {
      if (src !== null) {
        fs.closeSync(src)
      }
      if (dest !== null) {
        fs.closeSync(dest)
      }
    }
  }

  private static normalizeRestoredGalleryTasks(tasks: DownloadGalleryTask[]): DownloadGalleryTask[] {
    return tasks.map((task: DownloadGalleryTask) => {
      const out: DownloadGalleryTask = task.copy()
      out.imageSeeds = DownloadQueueSettings.normalizeRestoredSeeds(out.imageSeeds)
      out.syncProgressCounts()
      if (
        out.status === DownloadGalleryTaskStatus.PREPARING ||
        out.status === DownloadGalleryTaskStatus.DOWNLOADING
      ) {
        DownloadQueueSettings.normalizeRestoredGalleryStatus(out)
        out.prepareError = ''
      } else if (
        out.status === DownloadGalleryTaskStatus.COMPLETE &&
          (
            out.pendingDownloadCount() > 0 ||
            (out.pageCount > 0 && out.downloadedCount() < out.pageCount)
          )
      ) {
        DownloadQueueSettings.normalizeRestoredGalleryStatus(out)
        out.prepareError = ''
      }
      return out
    })
  }

  private static normalizeRestoredSeeds(seeds: DownloadImageSeed[]): DownloadImageSeed[] {
    const out: DownloadImageSeed[] = []
    seeds.forEach((seed: DownloadImageSeed) => {
      const item: DownloadImageSeed = seed.copy()
      if (item.filePath.length > 0) {
        const bytes: number = DownloadQueueSettings.downloadedFileSize(item.filePath)
        if (bytes > 0) {
          item.bytesWritten = bytes
          item.downloadError = ''
        } else {
          item.filePath = ''
          item.bytesWritten = 0
          item.downloadedAt = 0
        }
      }
      out.push(item)
    })
    return out
  }

  private static normalizeRestoredGalleryStatus(task: DownloadGalleryTask): void {
    if (task.downloadedCount() > 0) {
      task.status = DownloadGalleryTaskStatus.PARTIAL
    } else if (task.seededCount() > 0) {
      task.status = DownloadGalleryTaskStatus.READY
    } else {
      task.status = DownloadGalleryTaskStatus.QUEUED
    }
  }

  private static downloadedFileSize(path: string): number {
    try {
      if (!fs.accessSync(path)) {
        return 0
      }
      const stat: fs.Stat = fs.statSync(path)
      if (stat.isFile() && stat.size > 0) {
        return stat.size
      }
    } catch (_error) {}
    return 0
  }

  private static isArchiverResumeUnsupportedError(error: Object): boolean {
    const raw: string = (error as Error).message
    return raw.indexOf('binary resume unsupported') >= 0 || raw.indexOf('invalid content range') >= 0
  }

  private static isArchiverLinkExpiredError(error: Object): boolean {
    const raw: string = (error as Error).message
    return raw.indexOf('binary HTTP 410') >= 0 || raw.indexOf('binary HTTP 404') >= 0
  }

  private static isArchiverRateLimitedError(error: Object): boolean {
    const raw: string = (error as Error).message
    return raw.indexOf('binary HTTP 429') >= 0
  }

  private static userError(error: Object): string {
    const raw: string = (error as Error).message
    if (raw.indexOf(' login status=') >= 0) {
      return EhErrorText.message(EhErrorKind.LoginRequired)
    }
    if (raw.indexOf(' maybe-hidden status=') >= 0) {
      return EhErrorText.message(EhErrorKind.MaybeHidden)
    }
    if (DownloadQueueSettings.isArchiverResumeUnsupportedError(error)) {
      return AppStrings.get('download_error_resume_unsupported')
    }
    if (DownloadQueueSettings.isArchiverLinkExpiredError(error)) {
      return AppStrings.get('download_error_archive_link_expired')
    }
    if (DownloadQueueSettings.isArchiverRateLimitedError(error)) {
      return AppStrings.get('download_error_archive_rate_limited')
    }
    const message: string = EhErrorText.forUser(error)
    if (message.length > 0) {
      return message
    }
    return raw
  }

  private static normalizeRestoredArchiverTasks(tasks: DownloadArchiverTask[]): DownloadArchiverTask[] {
    return tasks.map((task: DownloadArchiverTask) => {
      const out: DownloadArchiverTask = task.copy()
      out.parseSource = DownloadQueueSettings.normalizeArchiverParseSource(out.parseSource)
      if (out.status === DownloadGalleryTaskStatus.DOWNLOADING) {
        out.status = DownloadGalleryTaskStatus.QUEUED
        out.error = ''
      } else if (out.status === DownloadGalleryTaskStatus.COMPLETE) {
        DownloadQueueSettings.normalizeRestoredArchiverComplete(out)
      }
      return out
    })
  }

  private static shouldAutoResumeGalleryTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.QUEUED ||
      task.status === DownloadGalleryTaskStatus.READY ||
      task.status === DownloadGalleryTaskStatus.PARTIAL ||
      (connectDownloadSettings().autoRetryFailed && task.status === DownloadGalleryTaskStatus.ERROR)
  }

  private static shouldAutoResumeArchiverTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.QUEUED ||
      task.status === DownloadGalleryTaskStatus.PREPARING ||
      (connectDownloadSettings().autoRetryFailed && task.status === DownloadGalleryTaskStatus.ERROR)
  }

  private static normalizeRestoredArchiverComplete(task: DownloadArchiverTask): void {
    const bytes: number = DownloadQueueSettings.downloadedFileSize(task.filePath)
    if (bytes > 0) {
      task.bytesWritten = bytes
      task.bytesTotal = task.bytesTotal > 0 ? task.bytesTotal : bytes
      task.progress = 100
      task.error = ''
      return
    }
    task.status = DownloadGalleryTaskStatus.ERROR
    task.filePath = ''
    task.fileName = ''
    task.bytesWritten = 0
    task.bytesTotal = 0
    task.progress = 0
    task.downloadedAt = 0
    task.error = 'archive file missing'
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, Math.max(0, Math.round(ms)))
    })
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
            task.imgWidth = typeof rec.imgWidth === 'number' ? rec.imgWidth : 0
            task.imgHeight = typeof rec.imgHeight === 'number' ? rec.imgHeight : 0
            task.pageCount = typeof rec.pageCount === 'number' ? rec.pageCount : 0
            task.category = typeof rec.category === 'string' ? rec.category : ''
            task.uploader = typeof rec.uploader === 'string' ? rec.uploader : ''
            task.upgradeFromGid = typeof rec.upgradeFromGid === 'string' ? rec.upgradeFromGid : ''
            task.queuedAt = typeof rec.queuedAt === 'number' ? rec.queuedAt : 0
            task.preparedAt = typeof rec.preparedAt === 'number' ? rec.preparedAt : 0
            task.firstPageCount = typeof rec.firstPageCount === 'number' ? rec.firstPageCount : 0
            task.previewPageCount = typeof rec.previewPageCount === 'number' ? rec.previewPageCount : 0
            task.imageSeeds = DownloadQueueSettings.parseSeeds(rec)
            task.syncProgressCounts()
            task.prepareError = typeof rec.prepareError === 'string' ? rec.prepareError : ''
            task.preferOriginal = typeof rec.preferOriginal === 'boolean' ? rec.preferOriginal : false
            task.status = DownloadQueueSettings.normalizeStatus(rec.status)
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

  private static parseArchiver(raw: string): DownloadArchiverTask[] {
    const out: DownloadArchiverTask[] = []
    try {
      const arr: Object = JSON.parse(raw) as Object
      if (Array.isArray(arr)) {
        ;(arr as Object[]).forEach((v: Object) => {
          const rec = v as DownloadArchiverTask
          if (rec !== null && typeof rec.tag === 'string' && rec.tag.length > 0) {
            const task: DownloadArchiverTask = new DownloadArchiverTask()
            task.tag = rec.tag
            task.gid = typeof rec.gid === 'string' ? rec.gid : ''
            task.token = typeof rec.token === 'string' ? rec.token : ''
            task.title = typeof rec.title === 'string' ? rec.title : ''
            task.thumbUrl = typeof rec.thumbUrl === 'string' ? rec.thumbUrl : ''
            task.imgWidth = typeof rec.imgWidth === 'number' ? rec.imgWidth : 0
            task.imgHeight = typeof rec.imgHeight === 'number' ? rec.imgHeight : 0
            task.dltype = typeof rec.dltype === 'string' ? rec.dltype : ''
            task.resolution = typeof rec.resolution === 'string' ? rec.resolution : ''
            task.parseSource = typeof rec.parseSource === 'string'
              ? DownloadQueueSettings.normalizeArchiverParseSource(rec.parseSource)
              : DownloadArchiverParseSource.OFFICIAL
            task.url = typeof rec.url === 'string' ? rec.url : ''
            task.fileName = typeof rec.fileName === 'string' ? rec.fileName : ''
            task.filePath = typeof rec.filePath === 'string' ? rec.filePath : ''
            task.queuedAt = typeof rec.queuedAt === 'number' ? rec.queuedAt : 0
            task.downloadedAt = typeof rec.downloadedAt === 'number' ? rec.downloadedAt : 0
            task.bytesWritten = typeof rec.bytesWritten === 'number' ? rec.bytesWritten : 0
            task.bytesTotal = typeof rec.bytesTotal === 'number' ? rec.bytesTotal : 0
            task.progress = typeof rec.progress === 'number' ? rec.progress : 0
            task.error = typeof rec.error === 'string' ? rec.error : ''
            task.status = DownloadQueueSettings.normalizeStatus(rec.status)
            if (out.length < MAX_ARCHIVER_TASKS) {
              out.push(task)
            }
          }
        })
      }
    } catch (error) {
      DiagnosticLogger.warn('settings', 'download_archiver_queue_parse_failed', (error as Error).message)
    }
    return out
  }

  private static imagesToSeeds(images: EhGalleryImage[]): DownloadImageSeed[] {
    const seeds: DownloadImageSeed[] = []
    images.forEach((image: EhGalleryImage) => {
      if (image.sUrl.length > 0) {
        seeds.push(DownloadImageSeed.fromGalleryImage(image))
      }
    })
    return DownloadQueueSettings.mergeSeeds(seeds)
  }

  private static mergeSeeds(seeds: DownloadImageSeed[]): DownloadImageSeed[] {
    const out: DownloadImageSeed[] = []
    seeds.forEach((seed: DownloadImageSeed) => {
      if (seed.imagePageUrl.length === 0) {
        return
      }
      const exists: boolean = out.some((it: DownloadImageSeed) => {
        return it.page === seed.page || it.imagePageUrl === seed.imagePageUrl
      })
      if (!exists) {
        out.push(seed.copy())
      }
    })
    out.sort((a: DownloadImageSeed, b: DownloadImageSeed) => a.page - b.page)
    return out
  }

  private static mergePreparedSeeds(
    existing: DownloadImageSeed[],
    incoming: DownloadImageSeed[],
    keepExistingNotInIncoming: boolean = false,
  ): DownloadImageSeed[] {
    const merged: DownloadImageSeed[] = DownloadQueueSettings.mergeSeeds(incoming).map((seed: DownloadImageSeed) => {
      const out: DownloadImageSeed = seed.copy()
      const previous: DownloadImageSeed | undefined = existing.find((it: DownloadImageSeed) => {
        return DownloadQueueSettings.sameSeed(out, it)
      })
      if (previous !== undefined && previous.filePath.length > 0) {
        out.imageUrl = previous.imageUrl
        out.originImageUrl = previous.originImageUrl
        out.showKey = previous.showKey
        out.reloadKey = previous.reloadKey
        out.filePath = previous.filePath
        out.bytesWritten = previous.bytesWritten
        out.downloadedAt = previous.downloadedAt
        out.downloadError = previous.downloadError
      }
      return out
    })
    if (!keepExistingNotInIncoming) {
      return merged
    }
    existing.forEach((seed: DownloadImageSeed) => {
      const exists: boolean = merged.some((it: DownloadImageSeed) => {
        return DownloadQueueSettings.sameSeed(it, seed)
      })
      if (!exists) {
        merged.push(seed.copy())
      }
    })
    return DownloadQueueSettings.mergeSeeds(merged)
  }

  private static parseSeeds(rec: DownloadGalleryTask): DownloadImageSeed[] {
    const out: DownloadImageSeed[] = []
    if (Array.isArray(rec.imageSeeds)) {
      rec.imageSeeds.forEach((raw: DownloadImageSeed) => {
        if (raw !== null && typeof raw.imagePageUrl === 'string' && raw.imagePageUrl.length > 0) {
          const seed: DownloadImageSeed = new DownloadImageSeed()
          seed.page = typeof raw.page === 'number' ? raw.page : 0
          seed.imgkey = typeof raw.imgkey === 'string' ? raw.imgkey : ''
          seed.imagePageUrl = raw.imagePageUrl
          seed.thumbUrl = typeof raw.thumbUrl === 'string' ? raw.thumbUrl : ''
          seed.imageUrl = typeof raw.imageUrl === 'string' ? raw.imageUrl : ''
          seed.originImageUrl = typeof raw.originImageUrl === 'string' ? raw.originImageUrl : ''
          seed.showKey = typeof raw.showKey === 'string' ? raw.showKey : ''
          seed.reloadKey = typeof raw.reloadKey === 'string' ? raw.reloadKey : ''
          seed.filePath = typeof raw.filePath === 'string' ? raw.filePath : ''
          seed.bytesWritten = typeof raw.bytesWritten === 'number' ? raw.bytesWritten : 0
          seed.downloadedAt = typeof raw.downloadedAt === 'number' ? raw.downloadedAt : 0
          seed.downloadError = typeof raw.downloadError === 'string' ? raw.downloadError : ''
          out.push(seed)
        }
      })
    }
    return DownloadQueueSettings.mergeSeeds(out)
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

  private static normalizeArchiverParseSource(value: string): string {
    if (value === DownloadArchiverParseSource.BOT) {
      return DownloadArchiverParseSource.BOT
    }
    return DownloadArchiverParseSource.OFFICIAL
  }

  private static isOriginalArchiverTask(task: DownloadArchiverTask): boolean {
    const resolution: string = task.resolution.toLowerCase()
    return task.dltype === 'org' || resolution.includes('original')
  }
}
