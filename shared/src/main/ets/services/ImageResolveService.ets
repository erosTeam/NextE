import { EhHttpClient } from '../network/EhHttpClient'
import { EhApiPhpService } from '../network/EhApiPhpService'
import { EhImagePageParser, ImagePageResult } from '../parser/EhImagePageParser'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { EhUrlRouter, ImagePageRef } from '../utils/EhUrlRouter'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const MAX_RESOLVED_IMAGE_PAGES: number = 512
const MAX_GALLERY_SHOW_KEYS: number = 64

/**
 * Bounded process-local metadata for image-page resolution. It deliberately stores only URLs/keys,
 * never image bytes: evicting a page merely makes a later resolve follow the existing showpage or
 * /s/ path again. Map insertion order provides LRU eviction without affecting the change-source path.
 */
export class ImageResolveMemoryCache {
  private readonly maxResolvedEntries: number
  private readonly maxShowKeyEntries: number
  private resolved: Map<string, ImagePageResult> = new Map()
  private showKeys: Map<string, string> = new Map()

  constructor(
    maxResolvedEntries: number = MAX_RESOLVED_IMAGE_PAGES,
    maxShowKeyEntries: number = MAX_GALLERY_SHOW_KEYS,
  ) {
    this.maxResolvedEntries = maxResolvedEntries > 0 ? maxResolvedEntries : 1
    this.maxShowKeyEntries = maxShowKeyEntries > 0 ? maxShowKeyEntries : 1
  }

  getResolved(sUrl: string): ImagePageResult | undefined {
    const result: ImagePageResult | undefined = this.resolved.get(sUrl)
    if (result === undefined) {
      return undefined
    }
    this.resolved.delete(sUrl)
    this.resolved.set(sUrl, result)
    return ImageResolveMemoryCache.copyResult(result)
  }

  putResolved(sUrl: string, result: ImagePageResult): void {
    if (sUrl.length === 0) {
      return
    }
    this.resolved.delete(sUrl)
    this.resolved.set(sUrl, ImageResolveMemoryCache.copyResult(result))
    this.trimResolved()
  }

  getShowKey(gid: string): string {
    const key: string | undefined = this.showKeys.get(gid)
    if (key === undefined) {
      return ''
    }
    this.showKeys.delete(gid)
    this.showKeys.set(gid, key)
    return key
  }

  putShowKey(gid: string, showKey: string): void {
    if (gid.length === 0 || showKey.length === 0) {
      return
    }
    this.showKeys.delete(gid)
    this.showKeys.set(gid, showKey)
    this.trimShowKeys()
  }

  resolvedCount(): number {
    return this.resolved.size
  }

  showKeyCount(): number {
    return this.showKeys.size
  }

  private trimResolved(): void {
    while (this.resolved.size > this.maxResolvedEntries) {
      this.removeOldestResolved()
    }
  }

  private trimShowKeys(): void {
    while (this.showKeys.size > this.maxShowKeyEntries) {
      this.removeOldestShowKey()
    }
  }

  private removeOldestResolved(): void {
    let found: boolean = false
    let oldest: string = ''
    this.resolved.forEach((_result: ImagePageResult, key: string): void => {
      if (!found) {
        found = true
        oldest = key
      }
    })
    if (found) {
      this.resolved.delete(oldest)
    }
  }

  private removeOldestShowKey(): void {
    let found: boolean = false
    let oldest: string = ''
    this.showKeys.forEach((_showKey: string, gid: string): void => {
      if (!found) {
        found = true
        oldest = gid
      }
    })
    if (found) {
      this.showKeys.delete(oldest)
    }
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

/**
 * Gives an explicit source reload ownership over one `/s/` page's memory-cache entry.
 *
 * A normal resolve and a user-triggered `?nl=` reload may both be in flight. The reload must win
 * even when the older normal request settles last; otherwise the next Reader mount silently returns
 * to the old CDN host from process memory.
 */
export class ImageResolveSourceGate {
  private epochs: Map<string, number> = new Map<string, number>()

  begin(sUrl: string, changeSource: boolean): number {
    const current: number = this.current(sUrl)
    if (!changeSource || sUrl.length === 0) {
      return current
    }
    const next: number = current + 1
    this.epochs.set(sUrl, next)
    return next
  }

  isCurrent(sUrl: string, epoch: number): boolean {
    return this.current(sUrl) === epoch
  }

  private current(sUrl: string): number {
    const value: number | undefined = this.epochs.get(sUrl)
    return value !== undefined ? value : 0
  }
}

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
  // gid → gallery showKey and sUrl → resolved metadata. Reader pages/components are recreated often;
  // retain recent metadata across those components, but never let a long reader/download session grow it
  // without bound. Eviction preserves the existing re-resolve behavior rather than changing source choice.
  private cache: ImageResolveMemoryCache = new ImageResolveMemoryCache()
  private sourceGate: ImageResolveSourceGate = new ImageResolveSourceGate()
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
    const sourceEpoch: number = this.sourceGate.begin(image.sUrl, changeSource)
    if (!changeSource && image.imageUrl.length > 0) {
      return image.imageUrl
    }
    if (image.sUrl.length === 0) {
      throw new Error('image has no /s/ page url')
    }
    if (!changeSource) {
      const cached: ImagePageResult | undefined = this.cache.getResolved(image.sUrl)
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
    const p: Promise<string> = this.doResolve(image, changeSource, sourceEpoch)
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
    const sourceEpoch: number = this.sourceGate.begin(image.sUrl, changeSource)
    if (!changeSource && image.originImageUrl.length > 0) {
      DiagnosticLogger.info('reader', 'resolve_original_cache', `page ${image.page} fullimg true`)
      return image.originImageUrl
    }
    if (image.sUrl.length === 0) {
      throw new Error('image has no /s/ page url')
    }
    const cached: ImagePageResult | undefined = changeSource ? undefined : this.cache.getResolved(image.sUrl)
    if (cached !== undefined && cached.originImageUrl.length > 0) {
      this.applyResult(image, cached)
      DiagnosticLogger.info('reader', 'resolve_original_memory_cache', `page ${image.page} fullimg true`)
      return image.originImageUrl
    }
    await this.doResolve(image, changeSource, sourceEpoch)
    if (image.originImageUrl.length === 0) {
      throw new Error('original image unavailable')
    }
    DiagnosticLogger.info('reader', 'resolve_original', `page ${image.page} fullimg ${image.originImageUrl.indexOf('/fullimg') >= 0}`)
    return image.originImageUrl
  }

  private async doResolve(
    image: EhGalleryImage,
    changeSource: boolean,
    sourceEpoch: number,
  ): Promise<string> {
    const ref: ImagePageRef | null = EhUrlRouter.parseImagePage(image.sUrl)
    const sIdx: number = image.sUrl.indexOf('/s/')
    const base: string = sIdx > 0 ? image.sUrl.substring(0, sIdx) : ''

    // Fast path: known gallery showKey → resolve via /api.php showpage (no HTML page). Skipped when
    // re-sourcing — 换源 needs the /s/ HTML to pick a different host via ?nl=.
    if (!changeSource && ref !== null && base.length > 0) {
      const key: string = this.cache.getShowKey(ref.gid)
      if (key.length > 0) {
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
            this.cacheResult(image.sUrl, image, sourceEpoch)
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
    if (this.sourceGate.isCurrent(image.sUrl, sourceEpoch)) {
      this.cache.putResolved(image.sUrl, r)
    }
    if (ref !== null && r.showKey.length > 0) {
      this.cache.putShowKey(ref.gid, r.showKey)
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

  private cacheResult(sUrl: string, image: EhGalleryImage, sourceEpoch: number): void {
    if (!this.sourceGate.isCurrent(sUrl, sourceEpoch)) {
      return
    }
    const result: ImagePageResult = new ImagePageResult()
    result.imageUrl = image.imageUrl
    result.showKey = image.showKey
    result.originImageUrl = image.originImageUrl
    result.reloadKey = image.reloadKey
    this.cache.putResolved(sUrl, result)
  }
}
