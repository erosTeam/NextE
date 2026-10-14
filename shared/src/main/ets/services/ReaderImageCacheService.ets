import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { EhHttpClient } from '../network/EhHttpClient'
import { ImageResolveService } from './ImageResolveService'

const READER_IMAGE_CACHE_DIR: string = 'reader-image-cache'
const META_SUFFIX: string = '.json'
const STAGED_SUFFIX: string = '.tmp'

export class ReaderCachedImage {
  displaySource: string = ''
  filePath: string = ''
  imageUrl: string = ''
  loadedFromCache: boolean = false
}

class ReaderImageCacheMeta {
  imageUrl: string = ''
  originImageUrl: string = ''
  showKey: string = ''
  reloadKey: string = ''
  extension: string = 'jpg'
}

export class ReaderImageCacheService {
  private static fileInFlight: Map<string, Promise<string>> = new Map()

  static async resolveForDisplay(
    context: common.UIAbilityContext,
    image: EhGalleryImage,
    changeSource: boolean = false,
  ): Promise<ReaderCachedImage> {
    if (!changeSource) {
      const cached: ReaderCachedImage | null = ReaderImageCacheService.tryCachedDisplay(context, image)
      if (cached !== null) {
        return cached
      }
      ReaderImageCacheService.applyResolvedMeta(context, image)
    }

    const imageUrl: string = await ImageResolveService.getInstance().resolve(image, changeSource)
    ReaderImageCacheService.saveResolvedMeta(context, image, imageUrl)
    const filePath: string = await ReaderImageCacheService.ensureImageFile(context, image, imageUrl, changeSource)
    const out: ReaderCachedImage = new ReaderCachedImage()
    out.filePath = filePath
    out.displaySource = ReaderImageCacheService.fileImageSource(filePath)
    out.imageUrl = imageUrl
    out.loadedFromCache = false
    return out
  }

  static async cachedFileForImageUrl(
    context: common.UIAbilityContext,
    image: EhGalleryImage,
    imageUrl: string,
  ): Promise<string> {
    if (imageUrl.length <= 0) {
      throw new Error('image URL is empty')
    }
    ReaderImageCacheService.saveResolvedMeta(context, image, imageUrl)
    return ReaderImageCacheService.ensureImageFile(context, image, imageUrl, false)
  }

  static fileImageSource(filePath: string): string {
    if (filePath.startsWith('file://')) {
      return filePath
    }
    return `file://${filePath}`
  }

  private static tryCachedDisplay(
    context: common.UIAbilityContext,
    image: EhGalleryImage,
  ): ReaderCachedImage | null {
    const meta: ReaderImageCacheMeta | null = ReaderImageCacheService.loadResolvedMeta(context, image.sUrl)
    if (meta !== null) {
      ReaderImageCacheService.applyMeta(image, meta)
      const metaPath: string = ReaderImageCacheService.imagePath(context, image, meta.imageUrl, meta.extension)
      if (ReaderImageCacheService.fileExists(metaPath)) {
        const out: ReaderCachedImage = new ReaderCachedImage()
        out.filePath = metaPath
        out.displaySource = ReaderImageCacheService.fileImageSource(metaPath)
        out.imageUrl = meta.imageUrl
        out.loadedFromCache = true
        DiagnosticLogger.info('reader', 'image_file_cache_hit', image.sUrl)
        return out
      }
    }
    if (image.imageUrl.length > 0) {
      const path: string = ReaderImageCacheService.imagePath(
        context,
        image,
        image.imageUrl,
        ReaderImageCacheService.extensionFromUrl(image.imageUrl),
      )
      if (ReaderImageCacheService.fileExists(path)) {
        const out: ReaderCachedImage = new ReaderCachedImage()
        out.filePath = path
        out.displaySource = ReaderImageCacheService.fileImageSource(path)
        out.imageUrl = image.imageUrl
        out.loadedFromCache = true
        DiagnosticLogger.info('reader', 'image_file_cache_hit', image.sUrl)
        return out
      }
    }
    return null
  }

  private static applyResolvedMeta(context: common.UIAbilityContext, image: EhGalleryImage): void {
    const meta: ReaderImageCacheMeta | null = ReaderImageCacheService.loadResolvedMeta(context, image.sUrl)
    if (meta !== null) {
      ReaderImageCacheService.applyMeta(image, meta)
      DiagnosticLogger.info('reader', 'resolve_disk_cache', image.sUrl)
    }
  }

  private static async ensureImageFile(
    context: common.UIAbilityContext,
    image: EhGalleryImage,
    imageUrl: string,
    overwrite: boolean,
  ): Promise<string> {
    const extension: string = ReaderImageCacheService.extensionFromUrl(imageUrl)
    const filePath: string = ReaderImageCacheService.imagePath(context, image, imageUrl, extension)
    if (!overwrite && ReaderImageCacheService.fileExists(filePath)) {
      return filePath
    }
    const existing: Promise<string> | undefined = ReaderImageCacheService.fileInFlight.get(filePath)
    if (existing !== undefined) {
      return existing
    }
    const p: Promise<string> = ReaderImageCacheService.downloadImageFile(imageUrl, filePath)
    ReaderImageCacheService.fileInFlight.set(filePath, p)
    p.then(
      (): void => {
        ReaderImageCacheService.fileInFlight.delete(filePath)
      },
      (): void => {
        ReaderImageCacheService.fileInFlight.delete(filePath)
      },
    )
    return p
  }

  private static async downloadImageFile(imageUrl: string, filePath: string): Promise<string> {
    ReaderImageCacheService.ensureDirForFile(filePath)
    const stagedPath: string = filePath + STAGED_SUFFIX
    try {
      await EhHttpClient.getInstance().downloadBinaryToFile(imageUrl, stagedPath)
      fileIo.renameSync(stagedPath, filePath)
      return filePath
    } catch (error) {
      ReaderImageCacheService.unlinkBestEffort(stagedPath)
      throw error as Error
    }
  }

  private static saveResolvedMeta(
    context: common.UIAbilityContext,
    image: EhGalleryImage,
    imageUrl: string,
  ): void {
    if (image.sUrl.length <= 0 || imageUrl.length <= 0) {
      return
    }
    const meta: ReaderImageCacheMeta = new ReaderImageCacheMeta()
    meta.imageUrl = imageUrl
    meta.originImageUrl = image.originImageUrl
    meta.showKey = image.showKey
    meta.reloadKey = image.reloadKey
    meta.extension = ReaderImageCacheService.extensionFromUrl(imageUrl)
    const filePath: string = ReaderImageCacheService.metaPath(context, image.sUrl)
    ReaderImageCacheService.ensureDirForFile(filePath)
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      fileIo.writeSync(file.fd, JSON.stringify(meta))
    } catch (error) {
      DiagnosticLogger.warn('reader', 'image_meta_cache_save_failed', (error as Error).message)
    } finally {
      ReaderImageCacheService.closeFile(file)
    }
  }

  private static loadResolvedMeta(
    context: common.UIAbilityContext,
    sUrl: string,
  ): ReaderImageCacheMeta | null {
    if (sUrl.length <= 0) {
      return null
    }
    try {
      const raw: string = fileIo.readTextSync(ReaderImageCacheService.metaPath(context, sUrl))
      const parsed = JSON.parse(raw) as ReaderImageCacheMeta
      if (!parsed || parsed.imageUrl.length <= 0) {
        return null
      }
      const meta: ReaderImageCacheMeta = new ReaderImageCacheMeta()
      meta.imageUrl = parsed.imageUrl
      meta.originImageUrl = parsed.originImageUrl || ''
      meta.showKey = parsed.showKey || ''
      meta.reloadKey = parsed.reloadKey || ''
      meta.extension = parsed.extension || ReaderImageCacheService.extensionFromUrl(parsed.imageUrl)
      return meta
    } catch (_error) {
      return null
    }
  }

  private static applyMeta(image: EhGalleryImage, meta: ReaderImageCacheMeta): void {
    image.imageUrl = meta.imageUrl
    image.originImageUrl = meta.originImageUrl
    image.showKey = meta.showKey
    image.reloadKey = meta.reloadKey
  }

  private static imagePath(
    context: common.UIAbilityContext,
    image: EhGalleryImage,
    imageUrl: string,
    extension: string,
  ): string {
    const keySeed: string = image.sUrl.length > 0 ? image.sUrl : imageUrl
    const ext: string = extension.length > 0 ? extension : ReaderImageCacheService.extensionFromUrl(imageUrl)
    return `${ReaderImageCacheService.cacheDir(context)}/${ReaderImageCacheService.cacheKey(keySeed)}.${ext}`
  }

  private static metaPath(context: common.UIAbilityContext, sUrl: string): string {
    return `${ReaderImageCacheService.cacheDir(context)}/${ReaderImageCacheService.cacheKey(sUrl)}${META_SUFFIX}`
  }

  private static cacheDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${READER_IMAGE_CACHE_DIR}`
  }

  private static ensureDirForFile(filePath: string): void {
    const slash: number = filePath.lastIndexOf('/')
    if (slash <= 0) {
      return
    }
    const dir: string = filePath.substring(0, slash)
    try {
      fileIo.mkdirSync(dir, true)
    } catch (_error) {
    }
  }

  private static fileExists(filePath: string): boolean {
    try {
      return fileIo.accessSync(filePath)
    } catch (_error) {
      return false
    }
  }

  private static unlinkBestEffort(filePath: string): void {
    try {
      fileIo.unlinkSync(filePath)
    } catch (_error) {
    }
  }

  private static closeFile(file: fileIo.File | null): void {
    if (file === null) {
      return
    }
    try {
      fileIo.closeSync(file)
    } catch (_error) {
    }
  }

  private static extensionFromUrl(url: string): string {
    let clean: string = url
    const queryIndex: number = clean.indexOf('?')
    if (queryIndex >= 0) {
      clean = clean.substring(0, queryIndex)
    }
    const slashIndex: number = clean.lastIndexOf('/')
    const fileName: string = slashIndex >= 0 ? clean.substring(slashIndex + 1) : clean
    const dotIndex: number = fileName.lastIndexOf('.')
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return 'jpg'
    }
    const ext: string = fileName.substring(dotIndex + 1).toLowerCase()
    if (
      ext === 'jpg' ||
      ext === 'jpeg' ||
      ext === 'png' ||
      ext === 'webp' ||
      ext === 'gif' ||
      ext === 'bmp' ||
      ext === 'heif'
    ) {
      return ext
    }
    return 'jpg'
  }

  private static cacheKey(value: string): string {
    let hash: number = 0x811c9dc5
    for (let i: number = 0; i < value.length; i++) {
      hash = Math.imul((hash ^ value.charCodeAt(i)) >>> 0, 16777619) >>> 0
    }
    return `v1_${hash.toString(16).padStart(8, '0')}`
  }
}
