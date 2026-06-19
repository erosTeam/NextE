import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { EhHttpClient } from '../network/EhHttpClient'

const DEFAULT_IMAGE_EXTENSION: string = 'jpg'

export class ImageSaveUtil {
  static async saveNetworkImageToGallery(
    context: common.UIAbilityContext,
    url: string,
    titleSeed: string,
  ): Promise<void> {
    if (url.length === 0) {
      throw new Error('image URL is empty')
    }
    const extension: string = ImageSaveUtil.extensionFromUrl(url)
    const title: string = ImageSaveUtil.safeTitle(titleSeed, extension)
    const filePath: string = `${context.cacheDir}/${title}.${extension}`
    await EhHttpClient.getInstance().downloadBinaryToFile(url, filePath)
    const uri: string = fileUri.getUriFromPath(filePath)
    const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
    const request: photoAccessHelper.MediaAssetChangeRequest =
      photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, uri)
    await helper.applyChanges(request)
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

  private static safeTitle(seed: string, extension: string): string {
    let out: string = ''
    for (let i = 0; i < seed.length; i++) {
      const ch: string = seed.charAt(i)
      if (ImageSaveUtil.isSafeFileChar(ch)) {
        out += ch
      } else {
        out += '_'
      }
    }
    const suffix: string = `.${extension}`
    if (out.toLowerCase().endsWith(suffix)) {
      out = out.substring(0, out.length - suffix.length)
    }
    out = out.trim()
    if (out.length === 0) {
      out = `nexte-reader-${Date.now()}`
    }
    if (out.length > 80) {
      out = out.substring(0, 80)
    }
    return out
  }

  private static isSafeFileChar(ch: string): boolean {
    const code: number = ch.charCodeAt(0)
    const isDigit: boolean = code >= 48 && code <= 57
    const isUpper: boolean = code >= 65 && code <= 90
    const isLower: boolean = code >= 97 && code <= 122
    return isDigit || isUpper || isLower || ch === '-' || ch === '_'
  }
}
