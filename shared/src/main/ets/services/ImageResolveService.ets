import { EhHttpClient } from '../network/EhHttpClient'
import { EhApiPhpService } from '../network/EhApiPhpService'
import { EhImagePageParser, ImagePageResult } from '../parser/EhImagePageParser'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { EhUrlRouter, ImagePageRef } from '../utils/EhUrlRouter'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * Resolves a gallery page's full-image URL (eros_fe view image resolve).
 *
 * Two paths, matching eros_fe:
 *  • SLOW (first page, or fallback): GET the /s/ HTML and scrape `<img id="img" src>` + the gallery
 *    showKey + the `nl()` reload key.
 *  • FAST (every later page once the showKey is known): a single POST /api.php method=showpage, no
 *    full HTML page. The showKey is gallery-wide, so the first /s/ resolve unlocks the fast path for
 *    the rest; a showpage failure (key mismatch / quota) falls back to the /s/ path.
 * Full-image bytes are loaded by the reader's Image component; this only yields the URL.
 */
export class ImageResolveService {
  private static instance: ImageResolveService
  // gid → gallery showKey, learned from the first /s/ resolve and reused for the showpage fast path.
  private showKeys: Map<string, string> = new Map()
  // sUrl → last resolved full-image metadata. Reader pages/components are recreated often; the resolved
  // URL should not be tied only to one EhGalleryImage instance or every reopen repeats the /s/ HTML
  // parse before the platform image cache can even see the same URL.
  private resolved: Map<string, ImagePageResult> = new Map()
  // sUrl → in-flight resolve promise. Dedups concurrent resolves of the SAME page so the reader's
  // N-ahead precache and the on-demand page component don't fire two requests for one image; both
  // share the single request. Cleared when it settles so a later retry / 换源 isn't blocked.
  private inFlight: Map<string, Promise<string>> = new Map()

  // EH serves a "509 bandwidth exceeded" placeholder gif as a normal-looking <img>/i3 when the IP is
  // rate-limited (eros_fe REG_509_URL). It must be treated as a failure, not shown as the image.
  private static readonly RE_509: RegExp = /\.org\/.+\/509s?\.gif/

  static getInstance(): ImageResolveService {
    if (!ImageResolveService.instance) {
      ImageResolveService.instance = new ImageResolveService()
    }
    return ImageResolveService.instance
  }

  private static is509(url: string): boolean {
    return ImageResolveService.RE_509.test(url)
  }

  /**
   * Resolve (idempotently) the full-image URL for a page. `changeSource` re-sources a broken/509
   * image (eros_fe 换源): it bypasses the cached URL + showpage fast path and re-fetches the /s/ HTML
   * with `?nl={reloadKey}` to get a DIFFERENT image host.
   */
  async resolve(image: EhGalleryImage, changeSource: boolean = false): Promise<string> {
    if (!changeSource && image.imageUrl.length > 0) {
      return image.imageUrl
    }
    if (image.sUrl.length === 0) {
      throw new Error('image has no /s/ page url')
    }
    if (!changeSource) {
      const cached: ImagePageResult | undefined = this.resolved.get(image.sUrl)
      if (cached !== undefined && cached.imageUrl.length > 0) {
        this.applyResult(image, cached)
        DiagnosticLogger.info('reader', 'resolve_memory_cache', image.sUrl)
        return image.imageUrl
      }
    }
    // Coalesce concurrent resolves of the same page (precache + on-demand). 换源 always forces a fresh
    // fetch (different host), so it skips the shared-promise cache.
    if (!changeSource) {
      const existing: Promise<string> | undefined = this.inFlight.get(image.sUrl)
      if (existing !== undefined) {
        return existing
      }
    }
    const p: Promise<string> = this.doResolve(image, changeSource)
    if (!changeSource) {
      this.inFlight.set(image.sUrl, p)
      const key: string = image.sUrl
      // Drop the in-flight entry on settle (both paths return void, so this chain never rejects).
      p.then(
        (): void => {
          this.inFlight.delete(key)
        },
        (): void => {
          this.inFlight.delete(key)
        },
      )
    }
    return p
  }

  async resolveOriginal(image: EhGalleryImage, changeSource: boolean = false): Promise<string> {
    if (!changeSource && image.originImageUrl.length > 0) {
      DiagnosticLogger.info('reader', 'resolve_original_cache', `page ${image.page} fullimg true`)
      return image.originImageUrl
    }
    if (image.sUrl.length === 0) {
      throw new Error('image has no /s/ page url')
    }
    const cached: ImagePageResult | undefined = changeSource ? undefined : this.resolved.get(image.sUrl)
    if (cached !== undefined && cached.originImageUrl.length > 0) {
      this.applyResult(image, cached)
      DiagnosticLogger.info('reader', 'resolve_original_memory_cache', `page ${image.page} fullimg true`)
      return image.originImageUrl
    }
    await this.doResolve(image, changeSource)
    if (image.originImageUrl.length === 0) {
      throw new Error('original image unavailable')
    }
    DiagnosticLogger.info('reader', 'resolve_original', `page ${image.page} fullimg ${image.originImageUrl.indexOf('/fullimg') >= 0}`)
    return image.originImageUrl
  }

  private async doResolve(image: EhGalleryImage, changeSource: boolean): Promise<string> {
    const ref: ImagePageRef | null = EhUrlRouter.parseImagePage(image.sUrl)
    const sIdx: number = image.sUrl.indexOf('/s/')
    const base: string = sIdx > 0 ? image.sUrl.substring(0, sIdx) : ''

    // Fast path: known gallery showKey → resolve via /api.php showpage (no HTML page). Skipped when
    // re-sourcing — 换源 needs the /s/ HTML to pick a different host via ?nl=.
    if (!changeSource && ref !== null && base.length > 0) {
      const key: string | undefined = this.showKeys.get(ref.gid)
      if (key !== undefined && key.length > 0) {
        try {
          const sp: ImagePageResult = await EhApiPhpService.showPage(
            base,
            Number.parseInt(ref.gid, 10),
            ref.page,
            ref.imgkey,
            key,
          )
          if (sp.imageUrl.length > 0) {
            if (ImageResolveService.is509(sp.imageUrl)) {
              throw new Error('image509')
            }
            image.imageUrl = sp.imageUrl
            image.originImageUrl = sp.originImageUrl
            image.reloadKey = sp.reloadKey
            this.cacheResult(image.sUrl, image)
            DiagnosticLogger.info('reader', 'resolve_showpage', `gid ${ref.gid} p ${ref.page}`)
            return sp.imageUrl
          }
        } catch (err) {
          // key mismatch / quota / transport — fall back to the /s/ HTML path below.
          DiagnosticLogger.warn('reader', 'showpage_fallback', (err as Error).message)
        }
      }
    }

    // Slow path: GET the /s/ HTML, scrape, and remember the gallery showKey for the rest. When
    // re-sourcing, append ?nl={reloadKey} so EH serves the image from a different host.
    const sUrl: string =
      changeSource && image.reloadKey.length > 0
        ? `${image.sUrl}?nl=${image.reloadKey}`
        : image.sUrl
    const resp = await EhHttpClient.getInstance().getText(sUrl)
    if (resp.statusCode !== 200) {
      throw new Error(`image page HTTP ${resp.statusCode}`)
    }
    const r: ImagePageResult = EhImagePageParser.parse(resp.body)
    if (r.imageUrl.length === 0) {
      throw new Error('image page has no full image url')
    }
    if (ImageResolveService.is509(r.imageUrl)) {
      throw new Error('image509')
    }
    image.imageUrl = r.imageUrl
    image.showKey = r.showKey
    image.originImageUrl = r.originImageUrl
    image.reloadKey = r.reloadKey
    this.resolved.set(image.sUrl, ImageResolveService.copyResult(r))
    if (ref !== null && r.showKey.length > 0) {
      this.showKeys.set(ref.gid, r.showKey)
    }
    DiagnosticLogger.info('reader', 'resolve_spage', `gid ${ref !== null ? ref.gid : '?'} p ${ref !== null ? ref.page : 0}`)
    return r.imageUrl
  }

  private applyResult(image: EhGalleryImage, result: ImagePageResult): void {
    image.imageUrl = result.imageUrl
    image.originImageUrl = result.originImageUrl
    image.reloadKey = result.reloadKey
    if (result.showKey.length > 0) {
      image.showKey = result.showKey
    }
  }

  private cacheResult(sUrl: string, image: EhGalleryImage): void {
    const result: ImagePageResult = new ImagePageResult()
    result.imageUrl = image.imageUrl
    result.showKey = image.showKey
    result.originImageUrl = image.originImageUrl
    result.reloadKey = image.reloadKey
    this.resolved.set(sUrl, result)
  }

  private static copyResult(result: ImagePageResult): ImagePageResult {
    const out: ImagePageResult = new ImagePageResult()
    out.imageUrl = result.imageUrl
    out.showKey = result.showKey
    out.originImageUrl = result.originImageUrl
    out.reloadKey = result.reloadKey
    out.galleryGid = result.galleryGid
    out.galleryToken = result.galleryToken
    out.ser = result.ser
    out.fileCount = result.fileCount
    return out
  }
}
