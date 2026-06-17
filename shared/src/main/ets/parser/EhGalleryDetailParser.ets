import { EhGallery } from '../model/EhGallery'
import { TagGroup } from '../model/TagGroup'
import { SimpleTag } from '../model/SimpleTag'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

/**
 * Parses a gallery detail page (/g/{gid}/{token}) header + tags into an EhGallery.
 * The ViewModel merges this onto the list-passed gallery so the header shows instantly.
 *
 * Validated against a real e-hentai.org detail fixture; mirror in
 * scripts/test_gallery_detail_parser_contract.mjs. Precise rating comes from the inline
 * `var average_rating` (the #rating_image sprite only rounds to half-stars). apiuid/apikey
 * are scraped here because every /api.php mutating call (rate/vote/tag) needs them.
 */
export class EhGalleryDetailParser {
  private static readonly RE_EN: RegExp = /<h1 id="gn">([\s\S]*?)<\/h1>/
  private static readonly RE_JP: RegExp = /<h1 id="gj">([\s\S]*?)<\/h1>/
  private static readonly RE_CAT: RegExp = /<div id="gdc"><div class="cs ct\w+"[^>]*>([^<]+)<\/div>/
  private static readonly RE_UPLOADER: RegExp =
    /<div id="gdn"[^>]*><a href="[^"]*\/uploader\/([^"]+)"/
  private static readonly RE_COVER: RegExp = /<div id="gd1">[\s\S]*?url\((https:\/\/[^)]+)\)/
  private static readonly RE_COVER_STYLE: RegExp = /<div id="gd1">[\s\S]*?<div[^>]*style="([^"]*url\((https:\/\/[^)]+)\)[^"]*)"/
  private static readonly RE_STYLE_W: RegExp = /width:\s*(\d+)px/
  private static readonly RE_STYLE_H: RegExp = /height:\s*(\d+)px/
  private static readonly RE_POSTED: RegExp = /Posted:<\/td><td class="gdt2">([^<]+)</
  private static readonly RE_LANG: RegExp = /Language:<\/td><td class="gdt2">([^<&]+)/
  private static readonly RE_FILESIZE: RegExp = /File Size:<\/td><td class="gdt2">([^<]+)</
  private static readonly RE_LENGTH: RegExp = /Length:<\/td><td class="gdt2">(\d+)/
  private static readonly RE_FAVCOUNT: RegExp = /id="favcount">([^<]+)</
  private static readonly RE_RATING: RegExp = /var average_rating\s*=\s*([\d.]+)/
  private static readonly RE_RATING_COUNT: RegExp = /id="rating_count"[^>]*>(\d+)</
  // The #rating_image div carries the personal-rating colour variant: class "ir" (community / not
  // personally rated) or "ir irr|irg|irb" once the logged-in user has rated it (eros_fe colorRating).
  private static readonly RE_RATING_CLASS: RegExp = /<div id="rating_image" class="ir( ir[rgb])?"/
  private static readonly RE_APIUID: RegExp = /var apiuid\s*=\s*(-?\d+)/
  private static readonly RE_APIKEY: RegExp = /var apikey\s*=\s*"([0-9a-f]+)"/
  private static readonly RE_TORRENT: RegExp = /Torrent Download \((\d+)\)/
  // Parent: row links to the parent gallery; capture its /g/{gid}/{token}/ URL (absent → "None").
  private static readonly RE_PARENT: RegExp =
    /Parent:<\/td><td class="gdt2"><a href="(https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-f]+)\/)"/
  // The user's OWN favorite state (eros_fe #fav sprite): when favorited, `#fav` holds an inner sprite
  // div whose background-position Y → favcat slot via `(Y-2)/19`, and whose title is the favcat name.
  // When NOT favorited, `#fav` is empty (`<div id="fav"></div>`) — so the inner-div match is the
  // favorited signal, sidestepping the localized "Add to Favorites" text. Y and title are read from
  // the matched div's attribute blob INDEPENDENTLY so EH attribute reordering can't break detection.
  private static readonly RE_FAV_DIV: RegExp = /id="fav">\s*<div([^>]*)>/
  private static readonly RE_FAV_Y: RegExp = /background-position:\s*-?\d+px\s+-?(\d+)px/
  private static readonly RE_FAV_TITLE: RegExp = /title="([^"]*)"/

  static parse(html: string, gid: string, token: string): EhGallery {
    const g: EhGallery = new EhGallery(gid, token)
    g.englishTitle = HtmlSelectorUtils.htmlUnescape(
      HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_EN).trim(),
    )
    g.japaneseTitle = HtmlSelectorUtils.htmlUnescape(
      HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_JP).trim(),
    )
    g.category = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_CAT).trim()
    g.uploader = HtmlSelectorUtils.urlDecode(
      HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_UPLOADER),
    )
    const coverM: RegExpMatchArray | null = html.match(EhGalleryDetailParser.RE_COVER_STYLE)
    if (coverM !== null && coverM[1] !== undefined && coverM[2] !== undefined) {
      const style: string = coverM[1]
      g.thumbUrl = coverM[2]
      const wM: RegExpMatchArray | null = style.match(EhGalleryDetailParser.RE_STYLE_W)
      const hM: RegExpMatchArray | null = style.match(EhGalleryDetailParser.RE_STYLE_H)
      if (wM !== null && wM[1] !== undefined) {
        g.imgWidth = Number.parseInt(wM[1], 10)
      }
      if (hM !== null && hM[1] !== undefined) {
        g.imgHeight = Number.parseInt(hM[1], 10)
      }
    } else {
      g.thumbUrl = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_COVER)
    }
    g.postTime = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_POSTED).trim()
    g.language = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_LANG).trim()
    g.fileSizeText = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_FILESIZE).trim()
    g.fileCount = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_LENGTH)
    g.favoritedCount = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_FAVCOUNT).trim()
    // The user's own favorite state (favcat slot + name) — only present when this gallery is favorited
    // (the #fav inner sprite div exists). Read Y + title from the div's attribute blob independently.
    const favDivM: RegExpMatchArray | null = html.match(EhGalleryDetailParser.RE_FAV_DIV)
    if (favDivM !== null && favDivM[1] !== undefined) {
      const attrs: string = favDivM[1]
      const yM: RegExpMatchArray | null = attrs.match(EhGalleryDetailParser.RE_FAV_Y)
      const titleM: RegExpMatchArray | null = attrs.match(EhGalleryDetailParser.RE_FAV_TITLE)
      if (yM !== null && yM[1] !== undefined && titleM !== null && titleM[1] !== undefined) {
        const y: number = Number.parseInt(yM[1], 10)
        const slot: number = Math.floor((y - 2) / 19)
        if (slot >= 0 && slot <= 9) {
          g.favcat = `${slot}`
        }
        g.favTitle = HtmlSelectorUtils.htmlUnescape(titleM[1].trim())
      }
    }
    g.ratingCount = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_RATING_COUNT)
    g.apiuid = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_APIUID)
    g.apikey = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_APIKEY)

    const ratingStr: string = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_RATING)
    if (ratingStr.length > 0) {
      g.rating = Number.parseFloat(ratingStr)
    }
    // Personal-rating colour variant (irr/irg/irb) from the #rating_image class; '' = community-only.
    const rcM: RegExpMatchArray | null = html.match(EhGalleryDetailParser.RE_RATING_CLASS)
    const ratingVariant: string = rcM !== null && rcM[1] !== undefined ? rcM[1].trim() : ''
    g.colorRating = ratingVariant
    g.isRated = ratingVariant.length > 0

    g.torrentCount = HtmlSelectorUtils.group1(html, EhGalleryDetailParser.RE_TORRENT)
    const parentM: RegExpMatchArray | null = html.match(EhGalleryDetailParser.RE_PARENT)
    if (parentM !== null && parentM[2] !== undefined && parentM[3] !== undefined) {
      g.parentUrl = parentM[1] !== undefined ? parentM[1] : ''
      g.parentGid = parentM[2]
      g.parentToken = parentM[3]
    }

    g.tagGroups = EhGalleryDetailParser.parseTags(html)
    return g
  }

  /** Parse #taglist into namespace-grouped tags. */
  private static parseTags(html: string): TagGroup[] {
    const listM: RegExpMatchArray | null = html.match(/<div id="taglist">([\s\S]*?)<\/table>/)
    if (listM === null || listM[1] === undefined) {
      return []
    }
    const groups: TagGroup[] = []
    const rowRe: RegExp = new RegExp(
      '<tr><td class="tc">([^:]+):</td><td>([\\s\\S]*?)</td></tr>',
      'g',
    )
    let rowM: RegExpExecArray | null = rowRe.exec(listM[1])
    while (rowM !== null) {
      const ns: string = rowM[1] !== undefined ? rowM[1].trim() : ''
      const cell: string = rowM[2] !== undefined ? rowM[2] : ''
      const tags: SimpleTag[] = []
      // Capture the <a> attribute blob so the logged-in user's vote class can be read: EH marks a voted
      // tag <a> with class "tup" (+1) / "tdn" (-1) and leaves it class="" otherwise (eros_fe parses the
      // same attribute). Group 1 = attrs, group 2 = tag text.
      const tagRe: RegExp = new RegExp('<a id="ta_[^"]*"([^>]*)>([^<]+)</a>', 'g')
      let tagM: RegExpExecArray | null = tagRe.exec(cell)
      while (tagM !== null) {
        if (tagM[2] !== undefined) {
          const attrs: string = tagM[1] !== undefined ? tagM[1] : ''
          const tag: SimpleTag = new SimpleTag(tagM[2].trim(), '')
          if (attrs.includes('class="tup"')) {
            tag.vote = 1
          } else if (attrs.includes('class="tdn"')) {
            tag.vote = -1
          }
          tags.push(tag)
        }
        tagM = tagRe.exec(cell)
      }
      if (ns.length > 0 && tags.length > 0) {
        groups.push(new TagGroup(ns, tags))
      }
      rowM = rowRe.exec(listM[1])
    }
    return groups
  }
}
