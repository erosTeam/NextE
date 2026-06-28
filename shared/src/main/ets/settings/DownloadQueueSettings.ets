import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { fileIo as fs } from '@kit.CoreFileKit'
import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
} from '../model/DownloadGalleryTask'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { connectDownloadQueue } from '../state/DownloadQueueState'
import {
  connectDownloadSettings,
  DownloadOriginalMode,
} from '../state/DownloadSettingsState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'
import { EhApiService } from '../network/EhApiService'
import { ImageResolveService } from '../services/ImageResolveService'
import { DownloadQueueRepository } from '../storage/DownloadQueueRepository'

const MAX_GALLERY_TASKS: number = 200
const MAX_ARCHIVER_TASKS: number = 100

class DownloadSeedResult {
  originalSeed: DownloadImageSeed = new DownloadImageSeed()
  image: EhGalleryImage = new EhGalleryImage()
  filePath: string = ''
  bytes: number = 0
  error: string = ''
}

/** Single writer for the local Gallery download queue. */
export class DownloadQueueSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await DownloadQueueSettings.migrateLegacyPreferences(context)
      connectDownloadQueue().galleryTasks = await DownloadQueueRepository.load(context)
      connectDownloadQueue().archiverTasks = await DownloadQueueRepository.loadArchiver(context)
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
    const refreshed: DownloadGalleryTask = task.copy()
    next.push(refreshed)
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      if (it.gid === task.gid && it.token === task.token) {
        existed = true
        refreshed.imageSeeds = it.imageSeeds.map((seed: DownloadImageSeed) => seed.copy())
        refreshed.firstPageCount = it.firstPageCount
        refreshed.previewPageCount = it.previewPageCount
        refreshed.preparedAt = it.preparedAt
        refreshed.prepareError = it.prepareError
        refreshed.preferOriginal = it.preferOriginal
        refreshed.status = it.status
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

  static async enqueueArchiver(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<boolean> {
    if (task.tag.length === 0 || task.url.length === 0) {
      return false
    }
    const state = connectDownloadQueue()
    const next: DownloadArchiverTask[] = []
    let existed: boolean = false
    const refreshed: DownloadArchiverTask = task.copy()
    refreshed.queuedAt = Date.now()
    refreshed.status = DownloadGalleryTaskStatus.QUEUED
    next.push(refreshed)
    state.archiverTasks.forEach((it: DownloadArchiverTask) => {
      if (it.tag === task.tag) {
        existed = true
        if (it.filePath.length > 0) {
          refreshed.fileName = it.fileName
          refreshed.filePath = it.filePath
          refreshed.bytesWritten = it.bytesWritten
          refreshed.bytesTotal = it.bytesTotal
          refreshed.progress = it.progress
          refreshed.downloadedAt = it.downloadedAt
          refreshed.status = it.status
          refreshed.error = it.error
        }
        return
      }
      if (next.length < MAX_ARCHIVER_TASKS) {
        next.push(it.copy())
      }
    })
    state.archiverTasks = next
    await DownloadQueueSettings.persistArchiver(context, next)
    return !existed
  }

  static async removeArchiver(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadArchiverTask[] = state.archiverTasks
      .filter((it: DownloadArchiverTask) => it.tag !== tag)
      .map((it: DownloadArchiverTask) => it.copy())
    state.archiverTasks = next
    await DownloadQueueSettings.persistArchiver(context, next)
  }

  static async downloadArchiver(
    context: common.UIAbilityContext,
    tag: string,
  ): Promise<void> {
    const task: DownloadArchiverTask | null = DownloadQueueSettings.findArchiverTask(tag)
    if (task === null || task.url.length === 0) {
      return
    }
    await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
      it.status = DownloadGalleryTaskStatus.DOWNLOADING
      it.error = ''
    }, false)
    const dir: string = DownloadQueueSettings.ensureArchiverDownloadDir(context)
    const fileName: string = DownloadQueueSettings.archiverFileName(task)
    const filePath: string = `${dir}/${fileName}`
    try {
      const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
        task.url,
        filePath,
        (loaded: number, total: number) => {
          DownloadQueueSettings.updateArchiverProgress(tag, loaded, total)
        },
      )
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
    } catch (error) {
      await DownloadQueueSettings.updateArchiverTask(context, tag, (it: DownloadArchiverTask) => {
        it.status = DownloadGalleryTaskStatus.ERROR
        it.fileName = fileName
        it.filePath = filePath
        it.error = (error as Error).message
      })
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
  ): Promise<void> {
    const initialSeeds: DownloadImageSeed[] = DownloadQueueSettings.imagesToSeeds(firstPageImages)
    await DownloadQueueSettings.updatePreparedTask(
      context,
      gid,
      token,
      DownloadGalleryTaskStatus.PREPARING,
      initialSeeds,
      firstPageImages.length,
      previewPageCount,
      '',
    )

    try {
      const allImages: EhGalleryImage[] = firstPageImages.map((image: EhGalleryImage) => image.copy())
      const totalPreviewPages: number = Math.max(previewPageCount, 1)
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
        firstPageImages.length,
        totalPreviewPages,
        '',
      )
    } catch (error) {
      await DownloadQueueSettings.updatePreparedTask(
        context,
        gid,
        token,
        DownloadGalleryTaskStatus.ERROR,
        initialSeeds,
        firstPageImages.length,
        Math.max(previewPageCount, 1),
        (error as Error).message,
      )
      return
    }
    await DownloadQueueSettings.downloadGalleryImages(context, gid, token)
  }

  static async downloadGalleryImages(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
  ): Promise<void> {
    while (true) {
      const task: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token)
      if (task === null) {
        return
      }
      const pending: DownloadImageSeed[] = DownloadQueueSettings.pendingSeeds(
        task,
        connectDownloadSettings().concurrency,
      )
      if (pending.length === 0) {
        await DownloadQueueSettings.updateDownloadTaskStatus(
          context,
          gid,
          token,
          task.imageSeeds.length > 0 ? DownloadGalleryTaskStatus.COMPLETE : DownloadGalleryTaskStatus.READY,
          '',
        )
        return
      }
      await DownloadQueueSettings.updateDownloadTaskStatus(
        context,
        gid,
        token,
        DownloadGalleryTaskStatus.DOWNLOADING,
        '',
      )
      const useOriginal: boolean = task.preferOriginal ||
        connectDownloadSettings().originalMode === DownloadOriginalMode.ALWAYS
      const jobs: Promise<DownloadSeedResult>[] = []
      pending.forEach((seed: DownloadImageSeed) => {
        jobs.push(DownloadQueueSettings.downloadSeedToFile(context, gid, seed, useOriginal))
      })
      const results: DownloadSeedResult[] = await Promise.all(jobs)
      const hasError: boolean = await DownloadQueueSettings.applyDownloadResults(
        context,
        gid,
        token,
        results,
      )
      if (hasError) {
        return
      }
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
    seed: DownloadImageSeed,
    useOriginal: boolean,
  ): Promise<DownloadSeedResult> {
    const result: DownloadSeedResult = new DownloadSeedResult()
    result.originalSeed = seed.copy()
    try {
      const image: EhGalleryImage = DownloadQueueSettings.seedToImage(seed)
      const imageUrl: string = useOriginal
        ? await ImageResolveService.getInstance().resolveOriginal(image)
        : await ImageResolveService.getInstance().resolve(image)
      const dir: string = DownloadQueueSettings.ensureGalleryDownloadDir(context, gid)
      result.image = image.copy()
      result.filePath = `${dir}/${DownloadQueueSettings.fileNameForSeed(seed, imageUrl)}`
      result.bytes = await EhHttpClient.getInstance().downloadBinaryToFile(imageUrl, result.filePath)
    } catch (error) {
      result.error = (error as Error).message
    }
    return result
  }

  private static async applyDownloadResults(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    results: DownloadSeedResult[],
  ): Promise<boolean> {
    let hasError: boolean = false
    let firstError: string = ''
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (task.gid === gid && task.token === token) {
        task.imageSeeds = task.imageSeeds.map((seed: DownloadImageSeed) => {
          const out: DownloadImageSeed = seed.copy()
          const result: DownloadSeedResult | undefined = results.find((it: DownloadSeedResult) => {
            return DownloadQueueSettings.sameSeed(out, it.originalSeed)
          })
          if (result !== undefined) {
            if (result.error.length > 0) {
              out.downloadError = result.error
              if (firstError.length === 0) {
                firstError = result.error
              }
              hasError = true
            } else {
              out.imageUrl = result.image.imageUrl
              out.originImageUrl = result.image.originImageUrl
              out.showKey = result.image.showKey
              out.reloadKey = result.image.reloadKey
              out.filePath = result.filePath
              out.bytesWritten = result.bytes
              out.downloadedAt = Date.now()
              out.downloadError = ''
            }
          }
          return out
        })
        task.status = hasError
          ? DownloadGalleryTaskStatus.ERROR
          : DownloadQueueSettings.pendingSeedCount(task.imageSeeds) === 0
            ? DownloadGalleryTaskStatus.COMPLETE
            : DownloadGalleryTaskStatus.PARTIAL
        task.prepareError = firstError
      }
      next.push(task)
    })
    state.galleryTasks = next
    await DownloadQueueSettings.persist(context, next)
    return hasError
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

  private static async updatePreparedTask(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    status: string,
    seeds: DownloadImageSeed[],
    firstPageCount: number,
    previewPageCount: number,
    prepareError: string,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (task.gid === gid && task.token === token) {
        task.status = status
        task.imageSeeds = DownloadQueueSettings.mergePreparedSeeds(task.imageSeeds, seeds)
        task.firstPageCount = firstPageCount
        task.previewPageCount = previewPageCount
        task.prepareError = prepareError
        task.preparedAt = status === DownloadGalleryTaskStatus.READY ? Date.now() : task.preparedAt
      }
      next.push(task)
    })
    state.galleryTasks = next
    await DownloadQueueSettings.persist(context, next)
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

  private static findTask(gid: string, token: string): DownloadGalleryTask | null {
    const state = connectDownloadQueue()
    const hit: DownloadGalleryTask | undefined = state.galleryTasks.find((task: DownloadGalleryTask) => {
      return task.gid === gid && task.token === token
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

  private static ensureGalleryDownloadDir(context: common.UIAbilityContext, gid: string): string {
    const root: string = `${context.filesDir}/download-gallery`
    const dir: string = `${root}/${DownloadQueueSettings.safePathPart(gid)}`
    try {
      fs.mkdirSync(dir, true)
    } catch (error) {
      if (!fs.accessSync(dir)) {
        throw error as Error
      }
    }
    return dir
  }

  private static ensureArchiverDownloadDir(context: common.UIAbilityContext): string {
    const dir: string = `${context.filesDir}/download-archiver`
    try {
      fs.mkdirSync(dir, true)
    } catch (error) {
      if (!fs.accessSync(dir)) {
        throw error as Error
      }
    }
    return dir
  }

  private static safePathPart(value: string): string {
    return value.replace(/[/:*"<>|,?\\]/g, '_')
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
    const name: string = `${DownloadQueueSettings.safePathPart(task.gid)}-${DownloadQueueSettings.safePathPart(task.dltype)}`
    const ext: string = DownloadQueueSettings.fileExtFromUrl(task.url)
    return ext === '.jpg' ? `${name}.zip` : `${name}${ext}`
  }

  private static updateArchiverProgress(tag: string, loaded: number, total: number): void {
    const state = connectDownloadQueue()
    const next: DownloadArchiverTask[] = []
    state.archiverTasks.forEach((it: DownloadArchiverTask) => {
      const task: DownloadArchiverTask = it.copy()
      if (task.tag === tag) {
        task.bytesWritten = loaded
        task.bytesTotal = total
        task.progress = total > 0 ? Math.max(0, Math.min(100, Math.round(loaded * 100 / total))) : 0
        task.status = DownloadGalleryTaskStatus.DOWNLOADING
      }
      next.push(task)
    })
    state.archiverTasks = next
  }

  private static async updateArchiverTask(
    context: common.UIAbilityContext,
    tag: string,
    update: (task: DownloadArchiverTask) => void,
    persist: boolean = true,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadArchiverTask[] = []
    state.archiverTasks.forEach((it: DownloadArchiverTask) => {
      const task: DownloadArchiverTask = it.copy()
      if (task.tag === tag) {
        update(task)
      }
      next.push(task)
    })
    state.archiverTasks = next
    if (persist) {
      await DownloadQueueSettings.persistArchiver(context, next)
    }
  }

  private static async updateDownloadTaskStatus(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    status: string,
    error: string,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (task.gid === gid && task.token === token) {
        task.status = status
        task.prepareError = error
      }
      next.push(task)
    })
    state.galleryTasks = next
    await DownloadQueueSettings.persist(context, next)
  }

  private static sameSeed(a: DownloadImageSeed, b: DownloadImageSeed): boolean {
    if (a.imagePageUrl.length > 0 && b.imagePageUrl.length > 0) {
      return a.imagePageUrl === b.imagePageUrl
    }
    return a.page === b.page
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
            task.preparedAt = typeof rec.preparedAt === 'number' ? rec.preparedAt : 0
            task.firstPageCount = typeof rec.firstPageCount === 'number' ? rec.firstPageCount : 0
            task.previewPageCount = typeof rec.previewPageCount === 'number' ? rec.previewPageCount : 0
            task.imageSeeds = DownloadQueueSettings.parseSeeds(rec)
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
  ): DownloadImageSeed[] {
    const merged: DownloadImageSeed[] = DownloadQueueSettings.mergeSeeds(incoming)
    return merged.map((seed: DownloadImageSeed) => {
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
      status === DownloadGalleryTaskStatus.PARTIAL ||
      status === DownloadGalleryTaskStatus.COMPLETE ||
      status === DownloadGalleryTaskStatus.ERROR
    ) {
      return status
    }
    return DownloadGalleryTaskStatus.QUEUED
  }
}
