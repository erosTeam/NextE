import { EhGallery } from '../model/EhGallery'
import { GalleryList } from '../model/GalleryList'
import { SimpleTag } from '../model/SimpleTag'
import { EhConstants } from '../constants/EhConstants'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

// Length of the 'language:' tag-namespace prefix (EH language tags are `language:<name>`).
const LANG_PREFIX_LEN: number = 9

/**
 * Parses an EH gallery-list page (compact table layout `itg gltc`, the default —
 * eros_fe's gallery_list_parser target) into a GalleryList.
 *
 * Regexes are validated against a real e-hentai.org fixture and MUST stay in sync with
 * scripts/test_gallery_list_parser_contract.mjs (identical patterns). Fragile, verify-live
 * bits: the rating CSS-sprite math `(80-x)/16 - (y==21?0.5:0)` and the favcat border-color
 * → slot map (EhConstants.favCat). Run on a TaskPool worker for large pages (pass the HTML
 * string in, get a serializable GalleryList out).
 */
export class EhGalleryListParser {
  // EH category class is `cn ct1`..`ct9`,`cta`,`ctb`… (NOT only digits).
  private static readonly RE_URL: RegExp =
    /href="(https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-f]+)\/)"/
  private static readonly RE_TITLE: RegExp = /<div class="glink">([\s\S]*?)<\/div>/
  private static readonly RE_CAT: RegExp =
    /<td class="gl1c glcat"[^>]*>\s*<div class="cn ct\w+"[^>]*>([^<]+)<\/div>/
  // EH lazy-loads list thumbnails: below-fold rows put a `data:image/gif` placeholder in
  // `src` and the real CDN URL in `data-src`; the first (eager) row has the real URL in `src`.
  // Prefer data-src, fall back to a non-data: src.
  private static readonly RE_THUMB_DATASRC: RegExp =
    /<div class="glthumb"[^>]*>[\s\S]*?<img[^>]*?\sdata-src="([^"]+)"/
  private static readonly RE_THUMB_SRC: RegExp =
    /<div class="glthumb"[^>]*>[\s\S]*?<img[^>]*?\ssrc="([^"]+)"/
  private static readonly RE_THUMB_DIM: RegExp =
    /<div class="glthumb"[^>]*>[\s\S]*?<img[^>]*style="[^"]*height:(\d+)px;width:(\d+)px/
  // `ir` plus an optional personal-vote variant (`ir irr|irg|irb`); a personally-rated gallery's
  // class is e.g. `ir irb`, which the old `class="ir"` (exact) failed to match → its rating parsed
  // as 0. `ir[^"]*` matches both. The variant (when present) is captured into colorRating.
  private static readonly RE_RATING: RegExp =
    /<div class="ir[^"]*"[^>]*background-position:\s*-?(\d+)px\s+-?(\d+)px/
  private static readonly RE_RATING_CLASS: RegExp =
    /<div class="[^"]*\b(ir[a-z])\b[^"]*"[^>]*background-position/
  private static readonly RE_FAVCAT: RegExp =
    /id="posted_\d+"[^>]*style="[^"]*border-color:(#\w{3})/
  private static readonly RE_FAVNOTE: RegExp = /<div class="glfnote"[^>]*>Note:\s*([^<]+)<\/div>/
  // On favorites.php the posted div carries the favcat NAME in its title attr (no border-color).
  private static readonly RE_FAVTITLE: RegExp = /id="posted_\d+"[^>]*title="([^"]+)"/
  // Capture the FULL posted-div content (not just text) — an expunged/replaced gallery wraps its
  // timestamp in a child element (e.g. `<s>…</s>`), which `[^<]+` would miss, dropping postTime AND
  // the expunged signal. We strip tags for postTime and treat any child tag as the expunged marker.
  private static readonly RE_POSTED: RegExp = /id="posted_\d+"[^>]*>([\s\S]*?)<\/div>/
  private static readonly RE_PAGES: RegExp = /(\d+) pages/
  private static readonly RE_UPLOADER: RegExp = /\/uploader\/([^"/]+)"/
  private static readonly RE_NEXT_ID_FIRST: RegExp =
    /<a[^>]*\bid=["'][ud]next["'][^>]*\bhref=["'][^"']*[?&](?:amp;)?next=([^"'&]+)[^"']*["'][^>]*>/
  private static readonly RE_NEXT_HREF_FIRST: RegExp =
    /<a[^>]*\bhref=["'][^"']*[?&](?:amp;)?next=([^"'&]+)[^"']*["'][^>]*\bid=["'][ud]next["'][^>]*>/
  private static readonly RE_PREV_ID_FIRST: RegExp =
    /<a[^>]*\bid=["'][ud]prev["'][^>]*\bhref=["'][^"']*[?&](?:amp;)?prev=([^"'&]+)[^"']*["'][^>]*>/
  private static readonly RE_PREV_HREF_FIRST: RegExp =
    /<a[^>]*\bhref=["'][^"']*[?&](?:amp;)?prev=([^"'&]+)[^"']*["'][^>]*\bid=["'][ud]prev["'][^>]*>/
  // Page-number nav table (toplist / search / favorites use it instead of gid cursors).
  private static readonly RE_PTT: RegExp =
    /<table[^>]*class="[^"]*\bptt\b[^"]*"[^>]*>[\s\S]*?<\/table>/

  static parse(html: string): GalleryList {
    const list: GalleryList = new GalleryList()
    list.nextGid = EhGalleryListParser.navCursor(
      html,
      EhGalleryListParser.RE_NEXT_ID_FIRST,
      EhGalleryListParser.RE_NEXT_HREF_FIRST,
    )
    list.prevGid = EhGalleryListParser.navCursor(
      html,
      EhGalleryListParser.RE_PREV_ID_FIRST,
      EhGalleryListParser.RE_PREV_HREF_FIRST,
    )
    // Page-number paging (table.ptt): eros_fe uses the current ptds cell's adjacent visible page
    // labels, then subtracts 1. Keep href parsing only as a fallback for arrow-only cells.
    const pttM: RegExpMatchArray | null = html.match(EhGalleryListParser.RE_PTT)
    if (pttM !== null && pttM[0] !== undefined) {
      // EH escapes the page links (?tl=11&amp;p=1) — unescape so the &p= regex matches.
      const pttBlock: string = pttM[0].replace(/&amp;/g, '&')
      const pageRe: RegExp = /[?&](?:p|page)=(\d+)/g
      let max: number = 0
      let pm: RegExpExecArray | null = pageRe.exec(pttBlock)
      while (pm !== null) {
        const p: number = pm[1] !== undefined ? Number.parseInt(pm[1], 10) : 0
        if (p > max) {
          max = p
        }
        pm = pageRe.exec(pttBlock)
      }
      list.maxPage = max
      EhGalleryListParser.parsePttNeighbors(pttBlock, list)
    }
    // toplist.php renders `<table class="itg gltc" style="max-width:1250px">` — the front/watched
    // page omits the style attr, so a regex that demanded `">` straight after the class silently
    // missed the toplist table (→ empty list). `[^>]*>` tolerates any extra attributes.
    const tableM: RegExpMatchArray | null = html.match(
      /<table class="itg[^"]*"[^>]*>([\s\S]*?)<\/table>/,
    )
    if (tableM === null || tableM[1] === undefined) {
      return list
    }
    const gals: EhGallery[] = []
    HtmlSelectorUtils.rows(tableM[1]).forEach((row: string) => {
      const g: EhGallery | null = EhGalleryListParser.parseRow(row)
      if (g !== null) {
        gals.push(g)
      }
    })
    list.gallerys = gals
    return list
  }

  private static navCursor(html: string, idFirst: RegExp, hrefFirst: RegExp): string {
    const idHit: string = HtmlSelectorUtils.group1(html, idFirst)
    if (idHit.length > 0) {
      return idHit
    }
    return HtmlSelectorUtils.group1(html, hrefFirst)
  }

  private static parsePttNeighbors(pttBlock: string, list: GalleryList): void {
    const cellRe: RegExp = /<td([^>]*)>([\s\S]*?)<\/td>/g
    const pages: number[] = []
    let currentIndex: number = -1
    let cm: RegExpExecArray | null = cellRe.exec(pttBlock)
    while (cm !== null) {
      const attrs: string = cm[1] !== undefined ? cm[1] : ''
      const content: string = cm[2] !== undefined ? cm[2] : ''
      if (/\bclass="[^"]*\bptds\b[^"]*"/.test(attrs)) {
        currentIndex = pages.length
      }
      pages.push(EhGalleryListParser.pttCellPage(content))
      cm = cellRe.exec(pttBlock)
    }
    if (currentIndex < 0) {
      return
    }
    if (currentIndex + 1 < pages.length) {
      list.nextPage = pages[currentIndex + 1]
    }
    if (currentIndex > 0) {
      list.prevPage = pages[currentIndex - 1]
    }
  }

  private static pttCellPage(content: string): number {
    const text: string = content.replace(/<[^>]*>/g, '').trim()
    const page: number = Number.parseInt(text, 10)
    if (page > 0) {
      return page - 1
    }
    const hrefPage: string = HtmlSelectorUtils.group1(content, /[?&](?:p|page)=(\d+)/)
    return hrefPage.length > 0 ? Number.parseInt(hrefPage, 10) : -1
  }

  private static parseRow(row: string): EhGallery | null {
    const urlM: RegExpMatchArray | null = row.match(EhGalleryListParser.RE_URL)
    if (urlM === null || urlM[2] === undefined || urlM[3] === undefined) {
      return null // header row or non-gallery row
    }
    const g: EhGallery = new EhGallery(urlM[2], urlM[3])
    g.url = urlM[1]
    g.englishTitle = HtmlSelectorUtils.htmlUnescape(
      HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_TITLE).trim(),
    )
    g.category = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_CAT).trim()
    let thumb: string = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_THUMB_DATASRC)
    if (thumb.length === 0) {
      const src: string = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_THUMB_SRC)
      thumb = src.startsWith('data:') ? '' : src
    }
    g.thumbUrl = thumb
    // Posted div may wrap an expunged gallery's timestamp in a child tag (e.g. `<s>`): a child tag
    // marks expunged; strip tags to recover the date either way.
    const rawPosted: string = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_POSTED)
    g.expunged = rawPosted.indexOf('<') >= 0
    g.postTime = rawPosted.replace(/<[^>]*>/g, '').trim()
    g.fileCount = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_PAGES)
    g.uploader = HtmlSelectorUtils.urlDecode(
      HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_UPLOADER),
    )

    const dimM: RegExpMatchArray | null = row.match(EhGalleryListParser.RE_THUMB_DIM)
    if (dimM !== null && dimM[1] !== undefined && dimM[2] !== undefined) {
      g.imgHeight = Number.parseInt(dimM[1], 10)
      g.imgWidth = Number.parseInt(dimM[2], 10)
    }

    const ratM: RegExpMatchArray | null = row.match(EhGalleryListParser.RE_RATING)
    if (ratM !== null && ratM[1] !== undefined && ratM[2] !== undefined) {
      const x: number = Number.parseInt(ratM[1], 10)
      const y: number = Number.parseInt(ratM[2], 10)
      g.rating = (80 - x) / 16 - (y === 21 ? 0.5 : 0)
      // The list `ir` sprite is the gallery's COMMUNITY rating — eros_fe shows this via
      // ratingFallBack (the display rating), distinct from a personal vote.
      g.ratingFallBack = g.rating
      // Personal-vote color variant (ir*), if the user has rated this gallery.
      const clsM: RegExpMatchArray | null = row.match(EhGalleryListParser.RE_RATING_CLASS)
      const variant: string = clsM !== null && clsM[1] !== undefined ? clsM[1].trim() : ''
      g.colorRating = variant
      g.isRated = variant.length > 0
    }

    const favColor: string = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_FAVCAT)
    if (favColor.length > 0) {
      const slot: string | undefined = EhConstants.favCat().get(favColor)
      g.favcat = slot !== undefined ? slot : ''
    }

    const favNote: string = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_FAVNOTE).trim()
    if (favNote.length > 0) {
      g.favNote = favNote
    }

    // On favorites.php the posted div carries the favcat NAME (title attr) instead of a
    // border-color, so favcat (slot) can't be derived here — the FavoritesViewModel resolves
    // favTitle → slot against the parsed favcat list to color the heart.
    const favTitle: string = HtmlSelectorUtils.group1(row, EhGalleryListParser.RE_FAVTITLE).trim()
    if (favTitle.length > 0) {
      g.favTitle = favTitle
    }

    // Inline tags shown on the list row: <div class="gt" title="namespace:tag" style="...">label</div>.
    // eros_fe reads EH's inline tag colors from the style attr: first #rrggbb = text, fourth = bg.
    const tagTitles: string[] = []
    const tags: SimpleTag[] = []
    const tagOpenRe: RegExp = /<div class="gt[lc]?"([^>]*)>/g
    let tagM: RegExpExecArray | null = tagOpenRe.exec(row)
    while (tagM !== null) {
      const attrs: string = tagM[1] !== undefined ? tagM[1] : ''
      const nsTag: string = HtmlSelectorUtils.group1(attrs, /title="([^"]+)"/)
      if (nsTag.length === 0) {
        tagM = tagOpenRe.exec(row)
        continue
      }
      tagTitles.push(nsTag)
      const idx: number = nsTag.indexOf(':')
      const text: string = idx >= 0 ? nsTag.substring(idx + 1) : nsTag
      // Keep the namespace (female/parody/…) for usertag lookup and language detection, expanding
      // any short prefix (a→artist).
      const ns: string = idx >= 0 ? EhConstants.expandNamespace(nsTag.substring(0, idx)) : ''
      const tag: SimpleTag = new SimpleTag(text, '', ns)
      const style: string = HtmlSelectorUtils.group1(attrs, /style="([^"]+)"/)
      const colors: string[] = []
      const colorRe: RegExp = /#[0-9a-fA-F]{6}/g
      let colorM: RegExpExecArray | null = colorRe.exec(style)
      while (colorM !== null) {
        colors.push(colorM[0])
        colorM = colorRe.exec(style)
      }
      if (colors.length > 0) {
        tag.color = colors[0]
      }
      if (colors.length > 3) {
        tag.backgroundColor = colors[3]
      }
      tags.push(tag)
      tagM = tagOpenRe.exec(row)
    }
    g.simpleTags = tags

    // Language indicator (eros_fe `translated`): the `language:<name>` tag resolves to a 2-letter
    // code (chinese→ZH). The separate `language:translated` marker isn't a language, so the
    // iso936 lookup naturally skips it. Shown as a small badge on the card.
    const langTitle: string | undefined = tagTitles.find(
      (nsTag: string) =>
        nsTag.startsWith('language:') &&
        EhConstants.languageAbbr(nsTag.substring(LANG_PREFIX_LEN)).length > 0,
    )
    if (langTitle !== undefined) {
      const name: string = langTitle.substring(LANG_PREFIX_LEN)
      g.language = name
      g.translated = EhConstants.languageAbbr(name)
    }
    return g
  }
}
