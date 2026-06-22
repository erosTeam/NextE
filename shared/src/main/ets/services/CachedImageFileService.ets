import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'

export interface CachedImageProgress {
  loaded: number
  total: number
}

export interface CachedImageFileResult {
  filePath: string
  displayUri: string
  bytes: number
  fromCache: boolean
}

const CACHE_DIR_NAME: string = 'reader-image-cache'
const DEFAULT_IMAGE_EXTENSION: string = 'jpg'

export class CachedImageFileService {
  static async load(
    context: common.UIAbilityContext,
    url: string,
    cacheKey: string,
    onProgress: (progress: CachedImageProgress) => void,
  ): Promise<CachedImageFileResult> {
    if (url.length === 0) {
      throw new Error('image URL is empty')
    }
    const filePath: string = CachedImageFileService.filePath(context, url, cacheKey)
    const cachedBytes: number = CachedImageFileService.fileSize(filePath)
    if (cachedBytes > 0) {
      onProgress({ loaded: cachedBytes, total: cachedBytes })
      DiagnosticLogger.info('image-cache', 'hit', `${cachedBytes} bytes -> ${CachedImageFileService.displayUri(filePath)}`)
      return { filePath, displayUri: CachedImageFileService.displayUri(filePath), bytes: cachedBytes, fromCache: true }
    }

    const tmpPath: string = `${filePath}.part`
    CachedImageFileService.removeIfExists(tmpPath)
    const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
      url,
      tmpPath,
      (loaded: number, total: number) => {
        onProgress({ loaded, total })
      },
    )
    CachedImageFileService.removeIfExists(filePath)
    fileIo.renameSync(tmpPath, filePath)
    const finalBytes: number = bytes > 0 ? bytes : CachedImageFileService.fileSize(filePath)
    onProgress({ loaded: finalBytes, total: finalBytes })
    DiagnosticLogger.info('image-cache', 'stored', `${finalBytes} bytes -> ${CachedImageFileService.displayUri(filePath)}`)
    return { filePath, displayUri: CachedImageFileService.displayUri(filePath), bytes: finalBytes, fromCache: false }
  }

  static remove(context: common.UIAbilityContext, url: string, cacheKey: string): void {
    CachedImageFileService.removeIfExists(CachedImageFileService.filePath(context, url, cacheKey))
  }

  static filePath(context: common.UIAbilityContext, url: string, cacheKey: string): string {
    const dir: string = `${context.cacheDir}/${CACHE_DIR_NAME}`
    CachedImageFileService.ensureDir(dir)
    const key: string = cacheKey.length > 0 ? cacheKey : url
    return `${dir}/${CachedImageFileService.hashKey(key)}.${CachedImageFileService.extensionFromUrl(url)}`
  }

  static displayUri(path: string): string {
    if (path.startsWith('file://')) {
      return path
    }
    if (path.startsWith('/')) {
      return `file://${path}`
    }
    return `file:///${path}`
  }

  private static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      if (!fileIo.accessSync(dir)) {
        throw error as Error
      }
    }
  }

  private static fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size
    } catch (_err) {
      return 0
    }
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_err) {
    }
  }

  private static hashKey(value: string): string {
    let hash: number = 5381
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) >>> 0
    }
    return hash.toString(16)
  }

  private static extensionFromUrl(url: string): string {
    const queryIndex: number = url.indexOf('?')
    const clean: string = queryIndex >= 0 ? url.substring(0, queryIndex) : url
    const slashIndex: number = clean.lastIndexOf('/')
    const fileName: string = slashIndex >= 0 ? clean.substring(slashIndex + 1) : clean
    const dotIndex: number = fileName.lastIndexOf('.')
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return DEFAULT_IMAGE_EXTENSION
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
    return DEFAULT_IMAGE_EXTENSION
  }
}
