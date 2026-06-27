import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { fileIo as fs } from '@kit.CoreFileKit'
import {
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
} from '../model/DownloadGalleryTask'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { connectDownloadQueue } from '../state/DownloadQueueState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'
import { EhApiService } from '../network/EhApiService'
import { ImageResolveService } from '../services/ImageResolveService'
import { DownloadQueueRepository } from '../storage/DownloadQueueRepository'

const MAX_GALLERY_TASKS: number = 200

/** Single writer for the local Gallery download queue. */
export class DownloadQueueSettings {
  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      await DownloadQueueSettings.migrateLegacyPreferences(context)
      connectDownloadQueue().galleryTasks = await DownloadQueueRepository.load(context)
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
      await DownloadQueueSettings.downloadFirstGalleryImage(context, gid, token)
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
    }
  }

  static async downloadFirstGalleryImage(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
  ): Promise<void> {
    const task: DownloadGalleryTask | null = DownloadQueueSettings.findTask(gid, token)
    if (task === null) {
      return
    }
    const seed: DownloadImageSeed | null = DownloadQueueSettings.firstPendingSeed(task)
    if (seed === null) {
      return
    }
    await DownloadQueueSettings.updateDownloadTaskStatus(
      context,
      gid,
      token,
      DownloadGalleryTaskStatus.DOWNLOADING,
      '',
    )
    try {
      const image: EhGalleryImage = DownloadQueueSettings.seedToImage(seed)
      const imageUrl: string = await ImageResolveService.getInstance().resolve(image)
      const dir: string = DownloadQueueSettings.ensureGalleryDownloadDir(context, gid)
      const filePath: string = `${dir}/${DownloadQueueSettings.fileNameForSeed(seed, imageUrl)}`
      const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFile(imageUrl, filePath)
      await DownloadQueueSettings.updateDownloadedSeed(
        context,
        gid,
        token,
        seed,
        image,
        filePath,
        bytes,
      )
    } catch (error) {
      await DownloadQueueSettings.updateFirstDownloadError(
        context,
        gid,
        token,
        seed,
        (error as Error).message,
      )
    }
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
        task.imageSeeds = DownloadQueueSettings.mergeSeeds(seeds)
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

  private static firstPendingSeed(task: DownloadGalleryTask): DownloadImageSeed | null {
    for (let i = 0; i < task.imageSeeds.length; i++) {
      const seed: DownloadImageSeed = task.imageSeeds[i]
      if (seed.filePath.length === 0 && seed.imagePageUrl.length > 0) {
        return seed.copy()
      }
    }
    return null
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

  private static async updateDownloadedSeed(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    originalSeed: DownloadImageSeed,
    image: EhGalleryImage,
    filePath: string,
    bytes: number,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (task.gid === gid && task.token === token) {
        task.imageSeeds = task.imageSeeds.map((seed: DownloadImageSeed) => {
          const out: DownloadImageSeed = seed.copy()
          if (DownloadQueueSettings.sameSeed(out, originalSeed)) {
            out.imageUrl = image.imageUrl
            out.originImageUrl = image.originImageUrl
            out.showKey = image.showKey
            out.reloadKey = image.reloadKey
            out.filePath = filePath
            out.bytesWritten = bytes
            out.downloadedAt = Date.now()
            out.downloadError = ''
          }
          return out
        })
        task.status = DownloadGalleryTaskStatus.PARTIAL
        task.prepareError = ''
      }
      next.push(task)
    })
    state.galleryTasks = next
    await DownloadQueueSettings.persist(context, next)
  }

  private static async updateFirstDownloadError(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    originalSeed: DownloadImageSeed,
    message: string,
  ): Promise<void> {
    const state = connectDownloadQueue()
    const next: DownloadGalleryTask[] = []
    state.galleryTasks.forEach((it: DownloadGalleryTask) => {
      const task: DownloadGalleryTask = it.copy()
      if (task.gid === gid && task.token === token) {
        task.imageSeeds = task.imageSeeds.map((seed: DownloadImageSeed) => {
          const out: DownloadImageSeed = seed.copy()
          if (DownloadQueueSettings.sameSeed(out, originalSeed)) {
            out.downloadError = message
          }
          return out
        })
        task.status = DownloadGalleryTaskStatus.ERROR
        task.prepareError = message
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
      status === DownloadGalleryTaskStatus.ERROR
    ) {
      return status
    }
    return DownloadGalleryTaskStatus.QUEUED
  }
}
