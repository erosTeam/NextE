import { taskpool } from '@kit.ArkTS'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import {
  ReaderPageCropBounds,
  ReaderPageCropDetector,
  ReaderPageCropStrength,
} from '../model/ReaderPageCropBounds'

const READER_CROP_CACHE_LIMIT: number = 256

@Concurrent
function hashReaderPageCropFile(filePath: string): string {
  const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
  try {
    const md = cryptoFramework.createMd('SHA256')
    const buffer = new ArrayBuffer(128 * 1024)
    while (true) {
      const length = fileIo.readSync(file.fd, buffer, { length: buffer.byteLength })
      if (length <= 0) break
      md.updateSync({ data: new Uint8Array(buffer, 0, length) })
    }
    const digest = md.digestSync().data
    const parts: string[] = []
    for (let index = 0; index < digest.length; index += 1) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  } finally {
    fileIo.closeSync(file)
  }
}

@Concurrent
async function detectReaderPageCropFile(filePath: string, strength: string): Promise<string> {
  const sampleLongEdge: number = 256
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(filePath)
    const sourceInfo: image.ImageInfo = await source.getImageInfo()
    const sourceWidth: number = Math.floor(sourceInfo.size.width)
    const sourceHeight: number = Math.floor(sourceInfo.size.height)
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return ReaderPageCropBounds.none().serialize()
    }
    const longestEdge: number = Math.max(sourceWidth, sourceHeight)
    const scale: number = longestEdge > sampleLongEdge
      ? sampleLongEdge / longestEdge
      : 1
    const options: image.DecodingOptions = {
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    }
    if (scale < 1) {
      options.desiredSize = {
        width: Math.max(1, Math.round(sourceWidth * scale)),
        height: Math.max(1, Math.round(sourceHeight * scale)),
      }
    }
    pixelMap = await source.createPixelMap(options)
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const width: number = Math.floor(info.size.width)
    const height: number = Math.floor(info.size.height)
    const stride: number = Math.max(Math.floor(info.stride), width * 4)
    const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    await pixelMap.readPixelsToBuffer(buffer)
    return ReaderPageCropDetector.detect(
      width,
      height,
      stride,
      new Uint8Array(buffer),
      sourceWidth,
      sourceHeight,
      strength,
    ).serialize()
  } catch (_error) {
    return ReaderPageCropBounds.none().serialize()
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
  }
}

/** Shared in-flight/LRU owner so the three Reader surfaces never decode the same page concurrently. */
export class ReaderPageCropService {
  private static cache: Map<string, ReaderPageCropBounds> = new Map()
  private static inFlight: Map<string, Promise<ReaderPageCropBounds>> = new Map()
  private static identityInFlight: Map<string, Promise<string>> = new Map()

  /** Reuse preprocessing across asset owners without trusting a reused path or a UI instance ID. */
  static async detectFile(filePath: string, strength: string): Promise<ReaderPageCropBounds> {
    if (filePath.length === 0) return ReaderPageCropBounds.none()
    let identity = ReaderPageCropService.identityInFlight.get(filePath)
    if (identity === undefined) {
      identity = taskpool.execute<[string], string>(hashReaderPageCropFile, filePath)
      ReaderPageCropService.identityInFlight.set(filePath, identity)
    }
    const owned = identity
    try {
      const digest = await owned
      return await ReaderPageCropService.detect(filePath, `content:${digest}`, strength)
    } catch (_error) {
      return ReaderPageCropBounds.none()
    } finally {
      if (ReaderPageCropService.identityInFlight.get(filePath) === owned) {
        ReaderPageCropService.identityInFlight.delete(filePath)
      }
    }
  }

  static detect(
    filePath: string,
    identity: string,
    strength: string = ReaderPageCropStrength.STANDARD,
  ): Promise<ReaderPageCropBounds> {
    if (filePath.length === 0 || identity.length === 0) {
      return Promise.resolve(ReaderPageCropBounds.none())
    }
    const normalizedStrength: string = ReaderPageCropDetector.normalizeStrength(strength)
    const key: string = `${filePath}|${identity}|${normalizedStrength}`
    const cached: ReaderPageCropBounds | undefined = ReaderPageCropService.cache.get(key)
    if (cached !== undefined) {
      ReaderPageCropService.cache.delete(key)
      ReaderPageCropService.cache.set(key, cached)
      return Promise.resolve(cached)
    }
    const pending: Promise<ReaderPageCropBounds> | undefined = ReaderPageCropService.inFlight.get(key)
    if (pending !== undefined) {
      return pending
    }
    const task: Promise<ReaderPageCropBounds> = ReaderPageCropService.execute(filePath, normalizedStrength)
    ReaderPageCropService.inFlight.set(key, task)
    task.then((bounds: ReaderPageCropBounds): void => {
      if (ReaderPageCropService.inFlight.get(key) === task) {
        ReaderPageCropService.inFlight.delete(key)
      }
      ReaderPageCropService.cache.set(key, bounds)
      ReaderPageCropService.trimCache()
    })
    return task
  }

  private static async execute(filePath: string, strength: string): Promise<ReaderPageCropBounds> {
    try {
      const serialized: string = await taskpool.execute<[string, string], string>(
        detectReaderPageCropFile,
        filePath,
        strength,
      )
      return ReaderPageCropBounds.parse(serialized)
    } catch (_error) {
      return ReaderPageCropBounds.none()
    }
  }

  private static trimCache(): void {
    while (ReaderPageCropService.cache.size > READER_CROP_CACHE_LIMIT) {
      let oldest: string = ''
      ReaderPageCropService.cache.forEach((_value: ReaderPageCropBounds, key: string): void => {
        if (oldest.length === 0) {
          oldest = key
        }
      })
      if (oldest.length === 0) {
        return
      }
      ReaderPageCropService.cache.delete(oldest)
    }
  }
}

export {
  ReaderPageCropBounds,
  ReaderPageCropDetector,
  ReaderPageCropStrength,
} from '../model/ReaderPageCropBounds'
