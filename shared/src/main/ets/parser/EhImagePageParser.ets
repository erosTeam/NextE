/** Parsed result of an EH image page (/s/{imgkey}/{gid}-{page}). */
export class ImagePageResult {
  imageUrl: string = ''       // <img id="img" src> — the full image (one-shot per-IP token)
  showKey: string = ''        // enables the fast /api.php method=showpage path for the rest
  originImageUrl: string = '' // "download original" /fullimg URL when available
  reloadKey: string = ''      // nl('xxxx') param → append ?nl=xxxx to re-source on 509/broken
  galleryGid: string = ''     // parent /g/{gid}/{token} parsed from the image page
  galleryToken: string = ''
  ser: number = 0             // 1-based image serial shown in the EH image-page chrome
}

/** Shape of the /api.php method=showpage JSON response (only the fields NextE needs). */
class ShowPageResponse {
  i3: string = '' // <img ... src="URL" style...> — the full image
  i6: string = '' // origin (<a href=...fullimg...>) + nl('sourceId') reload key
  error: string = '' // present on failure (e.g. 'Key mismatch')
}

/**
 * Parses an EH image page into the full-image URL (+ showKey / origin / nl reload key).
 * The reader resolves each page's /s/ URL through this; the showKey then lets later pages
 * use the cheaper /api.php showpage path (M2+). Validated against a real fixture; mirror in
 * scripts/test_image_page_parser_contract.mjs.
 */
export class EhImagePageParser {
  private static readonly RE_IMG: RegExp = /<img id="img" src="([^"]+)"/
  private static readonly RE_SHOWKEY: RegExp = /showkey="([^"]+)"/
  private static readonly RE_ORIGIN: RegExp = /<a href="(https:\/\/[^"]*\/fullimg[^"]*)"/
  private static readonly RE_NL: RegExp = /onclick="return nl\('([^']+)'\)/
  private static readonly RE_GALLERY: RegExp = /https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-z]+)\/?/
  private static readonly RE_SER: RegExp = /<div[^>]*class="sn"[^>]*>[\s\S]*?<span>(\d+)<\/span>/

  static parse(html: string): ImagePageResult {
    const r: ImagePageResult = new ImagePageResult()
    const img: RegExpMatchArray | null = html.match(EhImagePageParser.RE_IMG)
    if (img !== null && img[1] !== undefined) {
      r.imageUrl = img[1]
    }
    const sk: RegExpMatchArray | null = html.match(EhImagePageParser.RE_SHOWKEY)
    if (sk !== null && sk[1] !== undefined) {
      r.showKey = sk[1]
    }
    const og: RegExpMatchArray | null = html.match(EhImagePageParser.RE_ORIGIN)
    if (og !== null && og[1] !== undefined) {
      r.originImageUrl = og[1]
    }
    const nl: RegExpMatchArray | null = html.match(EhImagePageParser.RE_NL)
    if (nl !== null && nl[1] !== undefined) {
      r.reloadKey = nl[1]
    }
    const gallery: RegExpMatchArray | null = html.match(EhImagePageParser.RE_GALLERY)
    if (gallery !== null && gallery[1] !== undefined && gallery[2] !== undefined) {
      r.galleryGid = gallery[1]
      r.galleryToken = gallery[2]
    }
    const ser: RegExpMatchArray | null = html.match(EhImagePageParser.RE_SER)
    if (ser !== null && ser[1] !== undefined) {
      r.ser = Number.parseInt(ser[1], 10)
    }
    return r
  }

  private static readonly RE_SP_IMG: RegExp = /<img[^>]*src="([^"]+)" style/
  private static readonly RE_SP_ORIGIN: RegExp = /<a href="([^"]+fullimg[^"]+)"/
  private static readonly RE_SP_NL: RegExp = /nl\('([^']+)'\)/

  /**
   * Parse the /api.php method=showpage JSON response (eros_fe paraShowPageJson). `i3` holds the full
   * image `<img src>`; `i6` holds the origin link + the `nl('sourceId')` reload key. Throws on the
   * response `error` (e.g. 'Key mismatch') so the caller can fall back to the /s/ HTML path. The
   * showKey is reused (not returned here), so r.showKey stays empty — the caller keeps the known one.
   */
  static parseShowPage(body: string): ImagePageResult {
    const r: ImagePageResult = new ImagePageResult()
    let obj: ShowPageResponse
    try {
      obj = JSON.parse(body) as ShowPageResponse
    } catch (e) {
      throw new Error('showpage: invalid JSON')
    }
    const err: string = typeof obj.error === 'string' ? obj.error : ''
    if (err.length > 0) {
      throw new Error(`showpage error: ${err}`)
    }
    const i3: string = typeof obj.i3 === 'string' ? obj.i3 : ''
    const i6: string = typeof obj.i6 === 'string' ? obj.i6 : ''
    const img: RegExpMatchArray | null = i3.match(EhImagePageParser.RE_SP_IMG)
    if (img !== null && img[1] !== undefined) {
      r.imageUrl = img[1]
    }
    const og: RegExpMatchArray | null = i6.match(EhImagePageParser.RE_SP_ORIGIN)
    if (og !== null && og[1] !== undefined) {
      r.originImageUrl = og[1].replace(/&amp;/g, '&')
    }
    const nl: RegExpMatchArray | null = i6.match(EhImagePageParser.RE_SP_NL)
    if (nl !== null && nl[1] !== undefined) {
      r.reloadKey = nl[1]
    }
    return r
  }
}
