import { EhHttpClient, EhTextResponse } from '../network/EhHttpClient'
import { EhImagePageParser, ImagePageResult } from '../parser/EhImagePageParser'
import { EhUrlRouter, ImagePageRef } from '../utils/EhUrlRouter'

/** Resolved route target for an EH image-page URL (/s/{imgkey}/{gid}-{page}). */
export class ImagePageRouteTarget {
  gid: string = ''
  token: string = ''
  index: number = 0
}

/**
 * Resolves a pasted/deep-linked EH image-page URL to the parent gallery + 0-based reader index.
 * eros_fe handles /s/ links by fetching the image page, parsing its parent /g/ token and serial, then
 * opening the gallery at that page. The URL itself carries gid+page but not the gallery token.
 */
export class ImagePageRouteService {
  static async resolve(url: string): Promise<ImagePageRouteTarget> {
    const ref: ImagePageRef | null = EhUrlRouter.parseImagePage(url)
    if (ref === null) {
      throw new Error('not an EH image-page URL')
    }
    const resp: EhTextResponse = await EhHttpClient.getInstance().getText(url)
    if (resp.statusCode !== 200) {
      throw new Error(`image page HTTP ${resp.statusCode}`)
    }
    const parsed: ImagePageResult = EhImagePageParser.parse(resp.body)
    if (parsed.galleryToken.length === 0) {
      throw new Error('image page has no parent gallery token')
    }
    const target: ImagePageRouteTarget = new ImagePageRouteTarget()
    target.gid = parsed.galleryGid.length > 0 ? parsed.galleryGid : ref.gid
    target.token = parsed.galleryToken
    const ser: number = parsed.ser > 0 ? parsed.ser : ref.page
    target.index = Math.max(0, ser - 1)
    return target
  }
}
