/** A parsed reference to an EH gallery (/g/{gid}/{token}). */
export interface GalleryRef {
  gid: string
  token: string
}

/** A parsed reference to an EH image page (/s/{imgkey}/{gid}-{page}). */
export interface ImagePageRef {
  imgkey: string
  gid: string
  page: number
}

/**
 * Pure URL → route policy for EH links. The SAME router serves three callers:
 * deep links (EntryAbility), in-content tag/gallery links, and clipboard-link detection
 * on resume — so the /g/ and /s/ parsing lives in exactly one place. The regexes are
 * lifted verbatim from eros_fe and are host-agnostic (e-hentai.org OR exhentai.org).
 */
export class EhUrlRouter {
  private static readonly GALLERY_RE: RegExp = new RegExp('https?://(?:e-|ex)hentai\\.org/g/(\\d+)/([0-9a-z]+)')
  private static readonly IMAGE_RE: RegExp = new RegExp('https?://(?:e-|ex)hentai\\.org/s/([0-9a-z]+)/(\\d+)-(\\d+)')
  private static readonly HOST_RE: RegExp = new RegExp('^https?://(?:e-|ex)hentai\\.org')

  /** True if the URL is an EH gallery or image-page link this router can route. */
  static canHandle(url: string): boolean {
    return EhUrlRouter.GALLERY_RE.test(url) || EhUrlRouter.IMAGE_RE.test(url)
  }

  static parseGallery(url: string): GalleryRef | null {
    const m: RegExpMatchArray | null = url.match(EhUrlRouter.GALLERY_RE)
    if (!m) {
      return null
    }
    return { gid: m[1], token: m[2] }
  }

  static wantsComments(url: string): boolean {
    const lower: string = url.toLowerCase()
    return lower.indexOf('#comments') >= 0 ||
      lower.indexOf('nexte=comments') >= 0 ||
      lower.indexOf('nexte_comments=1') >= 0
  }

  static parseImagePage(url: string): ImagePageRef | null {
    const m: RegExpMatchArray | null = url.match(EhUrlRouter.IMAGE_RE)
    if (!m) {
      return null
    }
    return { imgkey: m[1], gid: m[2], page: Number.parseInt(m[3], 10) }
  }

  static toCurrentHost(url: string, baseUrl: string): string {
    return url.replace(EhUrlRouter.HOST_RE, baseUrl)
  }
}
