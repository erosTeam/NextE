import { taskpool } from '@kit.ArkTS'
import { image } from '@kit.ImageKit'
import {
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_MAX_THRESHOLD,
} from '../model/ImageBlockRule'

@Concurrent
async function calculateImageFilePHashDct64(
  filePath: string,
  regionX: number,
  regionY: number,
  regionW: number,
  regionH: number,
): Promise<string> {
  const sampleSize: number = 32
  const dctSize: number = 8
  const hexBits: number = 64
  if (filePath.length === 0) {
    return ''
  }
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(filePath)
    const hasRegion: boolean = regionW > 0 && regionH > 0
    const options: image.DecodingOptions = {
      editable: false,
      desiredSize: { width: sampleSize, height: sampleSize },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    }
    if (hasRegion) {
      options.desiredRegion = {
        x: Math.max(0, Math.floor(regionX)),
        y: Math.max(0, Math.floor(regionY)),
        size: {
          width: Math.max(1, Math.floor(regionW)),
          height: Math.max(1, Math.floor(regionH)),
        },
      }
      options.cropAndScaleStrategy = image.CropAndScaleStrategy.CROP_FIRST
    }
    pixelMap = await source.createPixelMap(options)
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const width: number = Math.floor(info.size.width)
    const height: number = Math.floor(info.size.height)
    if (width <= 0 || height <= 0) {
      return ''
    }
    const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    await pixelMap.readPixelsToBuffer(buffer)
    const stride: number = Math.max(Math.floor(info.stride), width * 4)
    const rgba: Uint8Array = new Uint8Array(buffer)
    const gray: number[] = []
    for (let y: number = 0; y < sampleSize; y++) {
      const srcY: number = Math.min(height - 1, Math.floor((y + 0.5) * height / sampleSize))
      for (let x: number = 0; x < sampleSize; x++) {
        const srcX: number = Math.min(width - 1, Math.floor((x + 0.5) * width / sampleSize))
        const offset: number = srcY * stride + srcX * 4
        const r: number = rgba[offset]
        const g: number = rgba[offset + 1]
        const b: number = rgba[offset + 2]
        gray.push(0.299 * r + 0.587 * g + 0.114 * b)
      }
    }
    const cosTable: number[] = []
    for (let u: number = 0; u < dctSize; u++) {
      for (let x: number = 0; x < sampleSize; x++) {
        cosTable.push(Math.cos(((2 * x + 1) * u * Math.PI) / (2 * sampleSize)))
      }
    }
    const coeffs: number[] = []
    for (let v: number = 0; v < dctSize; v++) {
      for (let u: number = 0; u < dctSize; u++) {
        let sum: number = 0
        for (let y: number = 0; y < sampleSize; y++) {
          for (let x: number = 0; x < sampleSize; x++) {
            sum += gray[y * sampleSize + x] *
              cosTable[u * sampleSize + x] *
              cosTable[v * sampleSize + y]
          }
        }
        coeffs.push(sum)
      }
    }
    const sorted: number[] = coeffs.slice(1).sort((a: number, b: number): number => a - b)
    const median: number = sorted[Math.floor(sorted.length / 2)]
    let out: string = ''
    for (let i: number = 0; i < hexBits; i += 4) {
      let nibble: number = 0
      for (let bit: number = 0; bit < 4; bit++) {
        if (coeffs[i + bit] > median) {
          nibble |= 1 << (3 - bit)
        }
      }
      out += nibble.toString(16)
    }
    return out
  } catch (error) {
    return ''
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
  }
}

export class PHashService {
  static async hashImageFileDct64(filePath: string): Promise<string> {
    return PHashService.hashImageFileRegionDct64(filePath, 0, 0, 0, 0)
  }

  static async hashImageFileRegionDct64(
    filePath: string,
    regionX: number,
    regionY: number,
    regionW: number,
    regionH: number,
  ): Promise<string> {
    try {
      return await taskpool.execute<[string, number, number, number, number], string>(
        calculateImageFilePHashDct64,
        filePath,
        regionX,
        regionY,
        regionW,
        regionH,
      )
    } catch (error) {
      return ''
    }
  }

  static isHex64(hash: string): boolean {
    if (hash.length !== 16) {
      return false
    }
    for (let i: number = 0; i < hash.length; i++) {
      if (PHashService.hexValue(hash.charAt(i)) < 0) {
        return false
      }
    }
    return true
  }

  static normalizeHex64(hash: string): string {
    const normalized: string = hash.trim().toLowerCase()
    return PHashService.isHex64(normalized) ? normalized : ''
  }

  static clampThreshold(
    value: number,
    fallback: number = IMAGE_BLOCK_DEFAULT_THRESHOLD,
  ): number {
    if (!Number.isFinite(value)) {
      return fallback
    }
    const threshold: number = Math.floor(value)
    if (threshold < 0) {
      return 0
    }
    if (threshold > IMAGE_BLOCK_MAX_THRESHOLD) {
      return IMAGE_BLOCK_MAX_THRESHOLD
    }
    return threshold
  }

  static hammingDistanceHex(left: string, right: string): number {
    const a: string = PHashService.normalizeHex64(left)
    const b: string = PHashService.normalizeHex64(right)
    if (a.length === 0 || b.length === 0) {
      return -1
    }
    let distance: number = 0
    for (let i: number = 0; i < 16; i++) {
      const diff: number = PHashService.hexValue(a.charAt(i)) ^ PHashService.hexValue(b.charAt(i))
      distance += PHashService.nibblePopcount(diff)
    }
    return distance
  }

  static matches(left: string, right: string, threshold: number): boolean {
    const distance: number = PHashService.hammingDistanceHex(left, right)
    return distance >= 0 && distance <= PHashService.clampThreshold(threshold)
  }

  private static nibblePopcount(value: number): number {
    switch (value) {
      case 0:
        return 0
      case 1:
      case 2:
      case 4:
      case 8:
        return 1
      case 3:
      case 5:
      case 6:
      case 9:
      case 10:
      case 12:
        return 2
      case 7:
      case 11:
      case 13:
      case 14:
        return 3
      case 15:
        return 4
      default:
        return 0
    }
  }

  private static hexValue(char: string): number {
    const code: number = char.charCodeAt(0)
    if (code >= 48 && code <= 57) {
      return code - 48
    }
    if (code >= 97 && code <= 102) {
      return code - 87
    }
    if (code >= 65 && code <= 70) {
      return code - 55
    }
    return -1
  }
}
