import { EhGalleryImage } from '../model/EhGalleryImage'

/**
 * Parses the #gdt preview block (gt200 unified `<a>` layout) of a detail / preview page
 * into EhGalleryImage[]. Each entry carries the page number, imgkey, the /s/ image-page
 * URL, and the preview thumbnail. One detail page yields ~20 previews; the reader pages
 * through ?p=1.. for the rest. The /s/ URL is what ImageResolveService turns into a full
 * image. EH can serve unified `<a>`, legacy `gdtm` sprite, or legacy `gdtl` large-thumb layouts.
 */
export class EhGalleryImageParser {
  // ExHentai wraps the preview in an extra `<div>` (`<a ...><div><div title="Page N">`) that
  // e-hentai omits (`<a ...><div title="Page N">`); the optional `(?:<div[^>]*>)?` matches both.
  // The preview div is a SPRITE sub-rect: `style="width:Wpx;height:Hpx;background:... url(SHEET) -Xpx 0"`.
  // Groups: 1=/s/ URL, 2=imgkey, 3=gid, 4=page, 5=width, 6=height, 7=sprite URL, 8=offsetX.
  private static readonly RE_PREVIEW: RegExp =
    /<a href="(https:\/\/e[-x]?hentai\.org\/s\/([0-9a-f]+)\/(\d+)-(\d+))">(?:<div[^>]*>)?<div title="Page \d+[^"]*" style="(?:width:(\d+)px;\s*height:(\d+)px;\s*)?background:[^;]*?url\((https:\/\/[^)]+)\)(?:\s*-?(\d+)px)?/g
  // Older small-thumb layout: `<div class="gdtm"><div style="...url(SHEET) -Xpx..."><a ...><img alt="SER">`.
  // Groups: 1=width, 2=height, 3=sprite URL, 4=offsetX, 5=/s/ URL, 6=imgkey, 7=gid, 8=page, 9=ser alt.
  private static readonly RE_SMALL_PREVIEW: RegExp =
    /<div class="gdtm"[\s\S]*?<div[^>]*style="(?:width:(\d+)px;\s*height:(\d+)px;\s*)?background:[^;]*?url\((https:\/\/[^)]+)\)(?:\s*-?(\d+)px)?[\s\S]*?<a href="(https:\/\/e[-x]?hentai\.org\/s\/([0-9a-f]+)\/(\d+)-(\d+))"[\s\S]*?<img[^>]*alt="(\d+)"/g
  // Legacy large-thumb layout: `<div class="gdtl"><a href="/s/..."><img alt="SER" src="...-W-H-..."></a>`.
  // The source URL carries original thumb dimensions in the third/fourth dash-separated tail fields
  // (eros_fe `parseGalleryImage` gdtl branch); these drive PreviewThumbTile aspect sizing.
  // Groups: 1=/s/ URL, 2=imgkey, 3=gid, 4=page, 5=ser alt, 6=thumb URL.
  private static readonly RE_LARGE_PREVIEW: RegExp =
    /<div class="gdtl"[\s\S]*?<a href="(https:\/\/e[-x]?hentai\.org\/s\/([0-9a-f]+)\/(\d+)-(\d+))"[\s\S]*?<img[^>]*alt="(\d+)"[^>]*src="(https:\/\/[^"]+)"/g
  // The `ptt` preview-page nav lists page LABELS 1..N (label N → ?p=N-1); the max label is the
  // total number of preview pages. Absent (single-page gallery) → 1.
  private static readonly RE_PTT: RegExp = /<table class="ptt"[^>]*>([\s\S]*?)<\/table>/
  private static readonly RE_PAGE_LABEL: string = '<a[^>]*>(\\d+)</a>'

  static parse(html: string): EhGalleryImage[] {
    const images: EhGalleryImage[] = []
    const re: RegExp = new RegExp(EhGalleryImageParser.RE_PREVIEW.source, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (m[1] !== undefined && m[2] !== undefined && m[4] !== undefined && m[7] !== undefined) {
        const img: EhGalleryImage = new EhGalleryImage(Number.parseInt(m[4], 10))
        img.sUrl = m[1]
        img.imgkey = m[2]
        img.thumbUrl = m[7]
        img.thumbWidth = m[5] !== undefined ? Number.parseInt(m[5], 10) : 0
        img.thumbHeight = m[6] !== undefined ? Number.parseInt(m[6], 10) : 0
        img.thumbOffsetX = m[8] !== undefined ? Number.parseInt(m[8], 10) : 0
        images.push(img)
      }
      m = re.exec(html)
    }
    EhGalleryImageParser.parseSmallThumbs(html, images)
    EhGalleryImageParser.parseLargeThumbs(html, images)
    EhGalleryImageParser.fillSpriteExtents(images)
    return images
  }

  private static hasImage(images: EhGalleryImage[], sUrl: string): boolean {
    for (let i: number = 0; i < images.length; i++) {
      if (images[i].sUrl === sUrl) {
        return true
      }
    }
    return false
  }

  private static parseSmallThumbs(html: string, images: EhGalleryImage[]): void {
    const re: RegExp = new RegExp(EhGalleryImageParser.RE_SMALL_PREVIEW.source, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (
        m[3] !== undefined &&
        m[5] !== undefined &&
        m[6] !== undefined &&
        m[8] !== undefined &&
        m[9] !== undefined &&
        !EhGalleryImageParser.hasImage(images, m[5])
      ) {
        const img: EhGalleryImage = new EhGalleryImage(Number.parseInt(m[9], 10))
        if (img.page <= 0) {
          img.page = Number.parseInt(m[8], 10)
        }
        img.sUrl = m[5]
        img.imgkey = m[6]
        img.thumbUrl = m[3]
        img.thumbWidth = m[1] !== undefined ? Number.parseInt(m[1], 10) : 0
        img.thumbHeight = m[2] !== undefined ? Number.parseInt(m[2], 10) : 0
        img.thumbOffsetX = m[4] !== undefined ? Number.parseInt(m[4], 10) : 0
        images.push(img)
      }
      m = re.exec(html)
    }
  }

  private static parseLargeThumbs(html: string, images: EhGalleryImage[]): void {
    const re: RegExp = new RegExp(EhGalleryImageParser.RE_LARGE_PREVIEW.source, 'g')
    let m: RegExpExecArray | null = re.exec(html)
    while (m !== null) {
      if (
        m[1] !== undefined &&
        m[2] !== undefined &&
        m[4] !== undefined &&
        m[5] !== undefined &&
        m[6] !== undefined
      ) {
        const img: EhGalleryImage = new EhGalleryImage(Number.parseInt(m[5], 10))
        if (img.page <= 0) {
          img.page = Number.parseInt(m[4], 10)
        }
        img.sUrl = m[1]
        img.imgkey = m[2]
        img.thumbUrl = m[6]
        const dims: number[] = EhGalleryImageParser.parseLargeThumbDims(m[6])
        img.thumbWidth = dims[0]
        img.thumbHeight = dims[1]
        images.push(img)
      }
      m = re.exec(html)
    }
  }

  private static parseLargeThumbDims(url: string): number[] {
    const parts: string[] = url.split('-')
    if (parts.length < 3) {
      return [0, 0]
    }
    const w: number = Number.parseInt(parts[parts.length - 3], 10)
    const h: number = Number.parseInt(parts[parts.length - 2], 10)
    return [Number.isNaN(w) ? 0 : w, Number.isNaN(h) ? 0 : h]
  }

  /**
   * EH packs each preview page's thumbnails into one sprite sheet. The per-thumb style gives only
   * the sub-rect (offset + size); the full sheet extent (needed to crop+scale) is derived here as
   * the max right-edge / height across all thumbs sharing a sprite URL.
   */
  private static fillSpriteExtents(images: EhGalleryImage[]): void {
    const widths: Map<string, number> = new Map<string, number>()
    const heights: Map<string, number> = new Map<string, number>()
    const counts: Map<string, number> = new Map<string, number>()
    const hasOffset: Map<string, boolean> = new Map<string, boolean>()
    images.forEach((img: EhGalleryImage) => {
      const curCount: number | undefined = counts.get(img.thumbUrl)
      counts.set(img.thumbUrl, curCount !== undefined ? curCount + 1 : 1)
      if (img.thumbOffsetX > 0) {
        hasOffset.set(img.thumbUrl, true)
      }
      const right: number = img.thumbOffsetX + img.thumbWidth
      const curW: number | undefined = widths.get(img.thumbUrl)
      if (curW === undefined || right > curW) {
        widths.set(img.thumbUrl, right)
      }
      const curH: number | undefined = heights.get(img.thumbUrl)
      if (curH === undefined || img.thumbHeight > curH) {
        heights.set(img.thumbUrl, img.thumbHeight)
      }
    })
    images.forEach((img: EhGalleryImage) => {
      const count: number | undefined = counts.get(img.thumbUrl)
      const offset: boolean | undefined = hasOffset.get(img.thumbUrl)
      if ((count === undefined || count <= 1) && offset !== true) {
        img.spriteWidth = 0
        img.spriteHeight = 0
        return
      }
      const w: number | undefined = widths.get(img.thumbUrl)
      const h: number | undefined = heights.get(img.thumbUrl)
      img.spriteWidth = w !== undefined ? w : 0
      img.spriteHeight = h !== undefined ? h : 0
    })
  }

  /** Total number of preview pages (max label in the `ptt` nav); 1 when there's no nav. */
  static parsePageCount(html: string): number {
    const ptt: RegExpMatchArray | null = html.match(EhGalleryImageParser.RE_PTT)
    if (ptt === null || ptt[1] === undefined) {
      return 1
    }
    let max: number = 1
    const re: RegExp = new RegExp(EhGalleryImageParser.RE_PAGE_LABEL, 'g')
    let m: RegExpExecArray | null = re.exec(ptt[1])
    while (m !== null) {
      if (m[1] !== undefined) {
        const n: number = Number.parseInt(m[1], 10)
        if (n > max) {
          max = n
        }
      }
      m = re.exec(ptt[1])
    }
    return max
  }
}
