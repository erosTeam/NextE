import { deviceInfo } from '@kit.BasicServicesKit'
import { imageSuperResolution, visionBase } from '@kit.CoreVisionKit'
import { image } from '@kit.ImageKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

class ReaderSystemDecodedSource {
  pixelMap: image.PixelMap

  constructor(pixelMap: image.PixelMap) {
    this.pixelMap = pixelMap
  }
}

class ReaderSystemImageData implements visionBase.ImageData {
  pixelMap: image.PixelMap

  constructor(pixelMap: image.PixelMap) {
    this.pixelMap = pixelMap
  }
}

/** Serial Core Vision image super-resolution backend for Reader pages. */
export class ReaderSystemSuperResolutionService {
  private static queue: Promise<void> = Promise.resolve()
  private static analyzer: imageSuperResolution.ImageSRAnalyzer | null = null

  static process(sourcePath: string, maxSourceEdge: number): Promise<image.PixelMap | undefined> {
    const task: Promise<image.PixelMap | undefined> =
      ReaderSystemSuperResolutionService.queue.then(
        (): Promise<image.PixelMap | undefined> =>
          ReaderSystemSuperResolutionService.processSerial(sourcePath, maxSourceEdge),
      )
    ReaderSystemSuperResolutionService.queue = task.then(
      (): void => {},
      (): void => {},
    )
    return task
  }

  private static async processSerial(
    sourcePath: string,
    maxSourceEdge: number,
  ): Promise<image.PixelMap | undefined> {
    let sourcePixelMap: image.PixelMap | undefined = undefined
    let outputPixelMap: image.PixelMap | undefined = undefined
    try {
      const decoded: ReaderSystemDecodedSource =
        await ReaderSystemSuperResolutionService.decodeSourcePixelMap(sourcePath, maxSourceEdge)
      sourcePixelMap = decoded.pixelMap
      const analyzer: imageSuperResolution.ImageSRAnalyzer =
        await ReaderSystemSuperResolutionService.ensureAnalyzer()
      // Keep API-26 calls inside direct positive gates for the compatibility checker.
      if (deviceInfo.apiAvailable('26.0.0') &&
        canIUse('SystemCapability.AI.Vision.VisionBase')) {
        const request: visionBase.Request = {
          inputData: new ReaderSystemImageData(decoded.pixelMap),
        }
        const response: imageSuperResolution.ISPResponse = await analyzer.process(request)
        outputPixelMap = response.pixelMap
      }
      await sourcePixelMap.release()
      sourcePixelMap = undefined
      return outputPixelMap
    } catch (error) {
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'system_process_failed',
        ReaderSystemSuperResolutionService.describeError(error as Object),
      )
      const failedAnalyzer: imageSuperResolution.ImageSRAnalyzer | null =
        ReaderSystemSuperResolutionService.analyzer
      ReaderSystemSuperResolutionService.analyzer = null
      if (failedAnalyzer !== null && deviceInfo.apiAvailable('26.0.0') &&
        canIUse('SystemCapability.AI.Vision.VisionBase')) {
        try {
          await failedAnalyzer.destroy()
        } catch (_destroyError) {}
      }
      if (outputPixelMap !== undefined) {
        try {
          await outputPixelMap.release()
        } catch (_releaseError) {}
      }
      return undefined
    } finally {
      if (sourcePixelMap !== undefined) {
        try {
          await sourcePixelMap.release()
        } catch (_releaseError) {}
      }
    }
  }

  private static async ensureAnalyzer(): Promise<imageSuperResolution.ImageSRAnalyzer> {
    if (ReaderSystemSuperResolutionService.analyzer !== null) {
      return ReaderSystemSuperResolutionService.analyzer
    }
    if (deviceInfo.apiAvailable('26.0.0') &&
      canIUse('SystemCapability.AI.Vision.VisionBase')) {
      const analyzer: imageSuperResolution.ImageSRAnalyzer =
        await imageSuperResolution.ImageSRAnalyzer.create()
      ReaderSystemSuperResolutionService.analyzer = analyzer
      return analyzer
    }
    throw new Error('Reader system super-resolution is unsupported')
  }

  private static async decodeSourcePixelMap(
    sourcePath: string,
    maxSourceEdge: number,
  ): Promise<ReaderSystemDecodedSource> {
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      source = image.createImageSource(sourcePath)
      const sourceInfo: image.ImageInfo = await source.getImageInfo()
      const sourceWidth: number = sourceInfo.size.width
      const sourceHeight: number = sourceInfo.size.height
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw new Error('Reader system super-resolution decode failed')
      }
      const longestEdge: number = Math.max(sourceWidth, sourceHeight)
      const scale: number = longestEdge > maxSourceEdge ? maxSourceEdge / longestEdge : 1
      const decodeOptions: image.DecodingOptions = {
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      }
      if (scale < 1) {
        decodeOptions.desiredSize = {
          width: Math.max(1, Math.round(sourceWidth * scale)),
          height: Math.max(1, Math.round(sourceHeight * scale)),
        }
      }
      pixelMap = await source.createPixelMap(decodeOptions)
      if (pixelMap === undefined) {
        throw new Error('Reader system super-resolution decode failed')
      }
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      if (info.size.width > maxSourceEdge || info.size.height > maxSourceEdge) {
        throw new Error('Reader system super-resolution decode failed')
      }
      const decoded: ReaderSystemDecodedSource = new ReaderSystemDecodedSource(pixelMap)
      pixelMap = undefined
      return decoded
    } finally {
      if (pixelMap !== undefined) {
        try {
          await pixelMap.release()
        } catch (_releaseError) {}
      }
      if (source !== undefined) {
        try {
          await source.release()
        } catch (_releaseError) {}
      }
    }
  }

  private static describeError(error: Object): string {
    return error instanceof Error ? `${error.name}: ${error.message}` : JSON.stringify(error)
  }
}
