import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'

const COMIC_RESPONSES_MAX_IMAGE_BYTES: number = 20 * 1024 * 1024

/** Builds one verified image data URL immediately before a Responses request. */
export class ComicResponsesImagePayload {
  static dataUrl(
    imageFilePath: string,
    expectedImageHash: string,
    expectedMimeType: string = '',
  ): string {
    const normalizedExpectedMime: string = expectedMimeType.trim().toLowerCase()
    if (normalizedExpectedMime.length > 0 &&
      normalizedExpectedMime !== 'image/jpeg' &&
      normalizedExpectedMime !== 'image/png' &&
      normalizedExpectedMime !== 'image/webp' &&
      normalizedExpectedMime !== 'image/gif') {
      throw new Error('Comic provider image MIME type is unsupported')
    }
    let file: fileIo.File | null = null
    try {
      const stat: fileIo.Stat = fileIo.statSync(imageFilePath)
      if (stat.size <= 0 || stat.size > COMIC_RESPONSES_MAX_IMAGE_BYTES) {
        throw new Error('Comic provider image file size is invalid')
      }
      file = fileIo.openSync(imageFilePath, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size)
      const read: number = fileIo.readSync(file.fd, buffer, { length: stat.size })
      if (read !== stat.size) {
        throw new Error('Comic provider image file read was incomplete')
      }
      const bytes: Uint8Array = new Uint8Array(buffer)
      if (ComicResponsesImagePayload.imageHash(bytes) !== expectedImageHash) {
        throw new Error('Comic provider image identity changed before request')
      }
      const detectedMime: string = ComicResponsesImagePayload.detectImageMime(bytes)
      if (normalizedExpectedMime.length > 0 && detectedMime !== normalizedExpectedMime) {
        throw new Error('Comic provider image MIME type does not match the file')
      }
      const encoded: string = new util.Base64Helper().encodeToStringSync(bytes)
      return 'data:' + detectedMime + ';base64,' + encoded
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static imageHash(bytes: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: bytes })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  private static detectImageMime(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return 'image/jpeg'
    }
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4e && bytes[3] === 0x47) {
      return 'image/png'
    }
    if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return 'image/gif'
    }
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
      bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'image/webp'
    }
    throw new Error('Comic provider image MIME type is unsupported')
  }
}
