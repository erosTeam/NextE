import { EhHttpClient, EhTextResponse } from './EhHttpClient'
import { EhImagePageParser, ImagePageResult } from '../parser/EhImagePageParser'
import { EhGalleryDataParser } from '../parser/EhGalleryDataParser'
import { EhGallery } from '../model/EhGallery'
import { EhTagSuggestion } from '../model/EhTagSuggestion'

/** POST body for /api.php method=showpage (eros_fe reqMap). gid/page are ints; keys are strings. */
class ShowPageRequest {
  method: string = 'showpage'
  gid: number = 0
  page: number = 0
  imgkey: string = ''
  showkey: string = ''
}

/** POST body for /api.php method=gdata. gidlist is [[gid, token], ...] (both strings, as eros_fe sends). */
class GDataRequest {
  method: string = 'gdata'
  gidlist: string[][] = []
}

/** POST body for /api.php method=tagsuggest. */
class TagSuggestRequest {
  method: string = 'tagsuggest'
  text: string = ''
}

class TagSuggestEntry {
  ns: string = ''
  tn: string = ''
}

class TagSuggestResponse {
  tags: Record<string, TagSuggestEntry> = {}
}

// EH caps a gdata request at 25 galleries; larger batches are split (eros_fe splitList(_, 25)).
const GDATA_BATCH: number = 25

/**
 * EH /api.php (multiplexed JSON endpoint), separate from EhApiService (web pages). M-reader uses the
 * `showpage` method: once the gallery's showKey is known (scraped from the first /s/ HTML resolve),
 * every other page can resolve its full-image URL with a single POST instead of a full /s/ HTML GET
 * (eros_fe fetchImageInfoByApi). Throws on a non-200 or the response `error` so ImageResolveService
 * can fall back to the /s/ path.
 */
export class EhApiPhpService {
  static async showPage(
    base: string,
    gid: number,
    page: number,
    imgkey: string,
    showKey: string,
  ): Promise<ImagePageResult> {
    const req: ShowPageRequest = new ShowPageRequest()
    req.gid = gid
    req.page = page
    req.imgkey = imgkey
    req.showkey = showKey
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`showpage HTTP ${resp.statusCode}`)
    }
    return EhImagePageParser.parseShowPage(resp.body)
  }

  /**
   * Batch-fetch canonical gallery metadata via /api.php `method=gdata` (eros_fe getMoreGalleryInfo).
   * Builds [gid, token] pairs (skipping items missing either), splits into ≤25-gallery requests, and
   * merges all `gmetadata` results. Used to enrich a sparse seed (URL paste / deep link) before the
   * heavier detail page parse. Throws on a non-200 so the caller can fall back to the detail fetch.
   */
  static async galleryData(base: string, items: EhGallery[]): Promise<EhGallery[]> {
    const pairs: string[][] = []
    items.forEach((it: EhGallery) => {
      if (it.gid.length > 0 && it.token.length > 0) {
        pairs.push([it.gid, it.token])
      }
    })
    if (pairs.length === 0) {
      return []
    }
    const out: EhGallery[] = []
    for (let i: number = 0; i < pairs.length; i += GDATA_BATCH) {
      const group: string[][] = pairs.slice(i, i + GDATA_BATCH)
      const req: GDataRequest = new GDataRequest()
      req.gidlist = group
      const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
        `${base}/api.php`,
        JSON.stringify(req),
      )
      if (resp.statusCode !== 200) {
        throw new Error(`gdata HTTP ${resp.statusCode}`)
      }
      EhGalleryDataParser.parse(resp.body).forEach((g: EhGallery) => out.push(g))
    }
    return out
  }

  /**
   * Search matching EH tags for the last typed token (eros_fe Api.tagSuggest). The response is a map
   * keyed by opaque ids; each value carries namespace (`ns`) and tag name (`tn`).
   */
  static async tagSuggest(base: string, text: string): Promise<EhTagSuggestion[]> {
    const q: string = text.trim()
    if (q.length === 0) {
      return []
    }
    const req: TagSuggestRequest = new TagSuggestRequest()
    req.text = q
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`tagsuggest HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (e) {
      throw new Error('tagsuggest: invalid JSON')
    }
    if (raw === null || typeof raw !== 'object') {
      throw new Error('tagsuggest: invalid JSON')
    }
    const obj: TagSuggestResponse = raw as TagSuggestResponse
    const tags: Record<string, TagSuggestEntry> =
      obj.tags !== undefined && obj.tags !== null ? obj.tags : {}
    const out: EhTagSuggestion[] = []
    Object.keys(tags).forEach((key: string) => {
      const entry: TagSuggestEntry = tags[key] as TagSuggestEntry
      const ns: string = typeof entry.ns === 'string' ? entry.ns.trim() : ''
      const tn: string = typeof entry.tn === 'string' ? entry.tn.trim() : ''
      if (tn.length > 0) {
        out.push(new EhTagSuggestion(ns, tn))
      }
    })
    return out
  }
}
