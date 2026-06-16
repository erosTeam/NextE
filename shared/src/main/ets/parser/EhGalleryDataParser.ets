import { EhGallery } from '../model/EhGallery'
import { SimpleTag } from '../model/SimpleTag'
import { EhConstants } from '../constants/EhConstants'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

// Length of the 'language:' tag-namespace prefix (gdata tags are `namespace:tag`).
const LANG_PREFIX_LEN: number = 9

/**
 * One entry of the /api.php gdata `gmetadata` array (only the fields NextE consumes). Field names
 * MUST match the JSON keys verbatim — `JSON.parse(...) as GMeta` is a structural cast, not a rename.
 * gid is a JSON number, token/rating/filecount/posted/torrentcount are strings, filesize is a number,
 * tags is a `namespace:tag` string array. A failed lookup carries an `error` and no metadata.
 */
class GMeta {
  gid: number = 0
  token: string = ''
  title: string = ''
  title_jpn: string = ''
  category: string = ''
  thumb: string = ''
  uploader: string = ''
  posted: string = ''
  filecount: string = ''
  filesize: number = 0
  expunged: boolean = false
  rating: string = ''
  torrentcount: string = ''
  tags: string[] = []
  error: string = ''
}

/** Shape of the /api.php gdata JSON response. */
class GDataResponse {
  gmetadata: GMeta[] = []
}

/**
 * Parses the EH /api.php `method=gdata` batch-metadata response (eros_fe getMoreGalleryInfo) into
 * EhGallery models. This is the canonical metadata enrich (source #2 in EhGallery's doc): a sparse
 * seed (a gid/token from a URL paste or deep link, lacking fileCount) is enriched from here before the
 * heavier /g/{gid}/{token} detail parse. Titles are HTML-entity escaped just like the page titles, so
 * they go through HtmlSelectorUtils.htmlUnescape. Mirror in scripts/test_gallery_data_parser_contract.mjs.
 */
export class EhGalleryDataParser {
  static parse(body: string): EhGallery[] {
    const out: EhGallery[] = []
    let raw: Object
    try {
      raw = JSON.parse(body) as Object
    } catch (e) {
      throw new Error('gdata: invalid JSON')
    }
    // JSON.parse('null') returns null WITHOUT throwing; guard the receiver before reading .gmetadata
    // so a null/non-object body surfaces as the clean error, not a raw TypeError null-deref.
    if (raw === null || typeof raw !== 'object') {
      throw new Error('gdata: invalid JSON')
    }
    const obj: GDataResponse = raw as GDataResponse
    const list: GMeta[] = Array.isArray(obj.gmetadata) ? obj.gmetadata : []
    list.forEach((m: GMeta) => {
      const g: EhGallery | null = EhGalleryDataParser.parseOne(m)
      if (g !== null) {
        out.push(g)
      }
    })
    return out
  }

  private static parseOne(m: GMeta): EhGallery | null {
    // A bad gid/token comes back as `{gid, error}` with no metadata — skip it.
    const err: string = typeof m.error === 'string' ? m.error : ''
    if (err.length > 0) {
      return null
    }
    // gid is a JSON number; token a string. Normalise gid to the string the rest of the app uses.
    let gid: string = ''
    if (typeof m.gid === 'number') {
      gid = `${m.gid}`
    } else if (typeof m.gid === 'string') {
      gid = m.gid
    }
    const token: string = typeof m.token === 'string' ? m.token : ''
    if (gid.length === 0 || token.length === 0) {
      return null
    }
    const g: EhGallery = new EhGallery(gid, token)
    g.englishTitle = HtmlSelectorUtils.htmlUnescape(typeof m.title === 'string' ? m.title : '')
    g.japaneseTitle = HtmlSelectorUtils.htmlUnescape(typeof m.title_jpn === 'string' ? m.title_jpn : '')
    g.category = typeof m.category === 'string' ? m.category : ''
    g.thumbUrl = typeof m.thumb === 'string' ? m.thumb : ''
    g.uploader = typeof m.uploader === 'string' ? m.uploader : ''
    g.posted = typeof m.posted === 'string' ? m.posted : ''
    g.fileCount = typeof m.filecount === 'string' ? m.filecount : ''
    g.fileSize = typeof m.filesize === 'number' ? m.filesize : 0
    g.expunged = typeof m.expunged === 'boolean' ? m.expunged : false
    g.torrentCount = typeof m.torrentcount === 'string' ? m.torrentcount : ''
    // rating arrives as a string ("2.92"); parse to a number, guard NaN (eros_fe falls back to ratingFallBack).
    const ratingStr: string = typeof m.rating === 'string' ? m.rating : ''
    const ratingNum: number = ratingStr.length > 0 ? Number.parseFloat(ratingStr) : 0
    if (!Number.isNaN(ratingNum) && ratingNum > 0) {
      g.rating = ratingNum
      g.ratingFallBack = ratingNum
    }
    // tags: ["namespace:tag", ...] → simpleTags (label only) + language/translated from a `language:` tag
    // (find over all tags — more robust than eros_fe's tags[0], matching the list parser's approach).
    const tags: string[] = Array.isArray(m.tags) ? m.tags : []
    const simple: SimpleTag[] = []
    tags.forEach((nsTag: string) => {
      if (typeof nsTag === 'string') {
        const idx: number = nsTag.indexOf(':')
        const text: string = idx >= 0 ? nsTag.substring(idx + 1) : nsTag
        simple.push(new SimpleTag(text, ''))
      }
    })
    g.simpleTags = simple
    const langTag: string | undefined = tags.find(
      (nsTag: string) =>
        typeof nsTag === 'string' &&
        nsTag.startsWith('language:') &&
        EhConstants.languageAbbr(nsTag.substring(LANG_PREFIX_LEN)).length > 0,
    )
    if (langTag !== undefined) {
      const name: string = langTag.substring(LANG_PREFIX_LEN)
      g.language = name
      g.translated = EhConstants.languageAbbr(name)
    }
    return g
  }
}
