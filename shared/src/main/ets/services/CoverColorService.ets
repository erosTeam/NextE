import { taskpool } from '@kit.ArkTS'
import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'

// Decode the thumbnail to a tiny bitmap purely for color sampling — far cheaper than decoding the full
// cover, and plenty for a dominant-color read (effectKit scales to ~1px internally anyway).
/**
 * Off-UI-thread cover dominant-color extraction. Fetches the public-CDN thumbnail bytes, decodes a small
 * downsampled bitmap, and reads the main color via effectKit. Returns a packed 0xAARRGGBB number (opaque)
 * usable directly as an ArkUI ResourceColor, or 0 on any failure so the caller can fall back to no gradient.
 *
 * The whole pipeline runs inside the worker so the PixelMap never crosses threads (avoids the 501
 * cross-thread-handle invalidation); only a primitive number is marshalled back. PixelMap/ImageSource are
 * released in finally to keep decode memory off the heap.
 */
@Concurrent
async function extractCoverColor(url: string): Promise<number> {
  const decodeSize: number = 32
  const timeoutMs: number = 15000
  const session: http.HttpRequest = http.createHttp()
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    const resp: http.HttpResponse = await session.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
    })
    if (resp.responseCode !== 200 || !(resp.result instanceof ArrayBuffer)) {
      return 0
    }
    source = image.createImageSource(resp.result as ArrayBuffer)
    const options: image.DecodingOptions = {
      editable: false,
      desiredSize: { width: decodeSize, height: decodeSize },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    }
    pixelMap = await source.createPixelMap(options)
    const picker: effectKit.ColorPicker = await effectKit.createColorPicker(pixelMap)
    const color: effectKit.Color = picker.getMainColorSync()
    // Pack opaque ARGB; >>> 0 yields an unsigned 0xAARRGGBB (a signed << 24 would read negative).
    return ((0xff << 24) | (color.red << 16) | (color.green << 8) | color.blue) >>> 0
  } catch (error) {
    return 0
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
    session.destroy()
  }
}

/**
 * In-memory cover dominant-color cache + in-flight dedup. EhThumbnail asks for a thumb URL's color and gets
 * a packed 0xAARRGGBB number once extraction resolves (0 while pending or on failure). The result is cached
 * for the process lifetime, so recycled list rows and re-entry never re-extract; concurrent requests for the
 * same URL share one TaskPool job. Best-effort: failures cache as 0 (no retry storms) — the gradient simply
 * does not show for that cover this session.
 */
export class CoverColorService {
  private static instance: CoverColorService | null = null
  private cache: Map<string, number> = new Map()
  private inFlight: Map<string, Promise<number>> = new Map()

  static getInstance(): CoverColorService {
    if (CoverColorService.instance === null) {
      CoverColorService.instance = new CoverColorService()
    }
    return CoverColorService.instance
  }

  // Synchronous cache peek so a recycled row can paint a known color immediately, with no flash or task.
  cached(url: string): number {
    const hit: number | undefined = this.cache.get(url)
    return hit === undefined ? 0 : hit
  }

  // Returns the cached color, joins an in-flight extraction, or starts one. Resolves to 0 on failure.
  async resolve(url: string): Promise<number> {
    if (url.length === 0) {
      return 0
    }
    const hit: number | undefined = this.cache.get(url)
    if (hit !== undefined) {
      return hit
    }
    const pending: Promise<number> | undefined = this.inFlight.get(url)
    if (pending !== undefined) {
      return pending
    }
    const task: Promise<number> = this.extract(url)
    this.inFlight.set(url, task)
    return task
  }

  private async extract(url: string): Promise<number> {
    let color: number = 0
    try {
      color = await taskpool.execute<[string], number>(extractCoverColor, url)
    } catch (error) {
      color = 0
    }
    this.cache.set(url, color)
    this.inFlight.delete(url)
    return color
  }
}
