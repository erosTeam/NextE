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

/** POST body for /api.php method=rategallery (eros_fe Api.setRating). */
class RateGalleryRequest {
  method: string = 'rategallery'
  apikey: string = ''
  apiuid: number = 0
  gid: number = 0
  token: string = ''
  rating: number = 0
}

class RateGalleryResponse {
  rating_usr: string | number = ''
  rating_avg: string | number = ''
  rating_cnt: string | number = ''
  rating_cls: string = ''
  error: string = ''
}

export class GalleryRatingResult {
  userRating: number = 0
  averageRating: number = 0
  ratingCount: string = ''
  colorRating: string = ''
}

/** POST body for /api.php method=votecomment (eros_fe Api.commitVote). */
class VoteCommentRequest {
  method: string = 'votecomment'
  apikey: string = ''
  apiuid: number = 0
  gid: number = 0
  token: string = ''
  comment_id: number = 0
  comment_vote: number = 0
}

class VoteCommentResponse {
  comment_id?: string | number
  comment_score?: string | number
  comment_vote?: string | number
  error: string = ''
}

export class CommentVoteResult {
  commentId: string = ''
  commentScore: number = 0
  commentVote: number = 0
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
  private static numberFrom(value: string | number): number {
    if (typeof value === 'number') {
      return Number.isNaN(value) ? 0 : value
    }
    const n: number = Number.parseFloat(value)
    return Number.isNaN(n) ? 0 : n
  }

  private static intFrom(value: string | number): number {
    if (typeof value === 'number') {
      return Number.isNaN(value) ? 0 : Math.floor(value)
    }
    const n: number = Number.parseInt(value, 10)
    return Number.isNaN(n) ? 0 : n
  }

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

  static async rateGallery(
    base: string,
    apikey: string,
    apiuid: string,
    gid: string,
    token: string,
    rating: number,
  ): Promise<GalleryRatingResult> {
    const apiuidNum: number = Number.parseInt(apiuid, 10)
    const gidNum: number = Number.parseInt(gid, 10)
    if (apikey.length === 0 || token.length === 0 || Number.isNaN(apiuidNum) || Number.isNaN(gidNum)) {
      throw new Error('rateGallery: missing API key')
    }
    const req: RateGalleryRequest = new RateGalleryRequest()
    req.apikey = apikey
    req.apiuid = apiuidNum
    req.gid = gidNum
    req.token = token
    req.rating = rating
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`rategallery HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (e) {
      throw new Error('rategallery: invalid JSON')
    }
    if (raw === null || typeof raw !== 'object') {
      throw new Error('rategallery: invalid JSON')
    }
    const obj: RateGalleryResponse = raw as RateGalleryResponse
    if (obj.error !== undefined && obj.error.length > 0) {
      throw new Error(obj.error)
    }
    const result: GalleryRatingResult = new GalleryRatingResult()
    result.userRating = EhApiPhpService.numberFrom(obj.rating_usr)
    result.averageRating = EhApiPhpService.numberFrom(obj.rating_avg)
    result.ratingCount = EhApiPhpService.intFrom(obj.rating_cnt).toString()
    result.colorRating = typeof obj.rating_cls === 'string' ? obj.rating_cls : ''
    if (result.userRating <= 0 || result.averageRating <= 0) {
      throw new Error('rategallery: missing rating result')
    }
    return result
  }

  static async voteComment(
    base: string,
    apikey: string,
    apiuid: string,
    gid: string,
    token: string,
    commentId: string,
    vote: number,
  ): Promise<CommentVoteResult> {
    const apiuidNum: number = Number.parseInt(apiuid, 10)
    const gidNum: number = Number.parseInt(gid, 10)
    const commentIdNum: number = Number.parseInt(commentId, 10)
    if (
      apikey.length === 0 ||
      token.length === 0 ||
      Number.isNaN(apiuidNum) ||
      Number.isNaN(gidNum) ||
      Number.isNaN(commentIdNum) ||
      (vote !== 1 && vote !== -1)
    ) {
      throw new Error('voteComment: missing API key')
    }
    const req: VoteCommentRequest = new VoteCommentRequest()
    req.apikey = apikey
    req.apiuid = apiuidNum
    req.gid = gidNum
    req.token = token
    req.comment_id = commentIdNum
    req.comment_vote = vote
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`votecomment HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (e) {
      throw new Error('votecomment: invalid JSON')
    }
    if (raw === null || typeof raw !== 'object') {
      throw new Error('votecomment: invalid JSON')
    }
    const obj: VoteCommentResponse = raw as VoteCommentResponse
    if (obj.error !== undefined && obj.error.length > 0) {
      throw new Error(obj.error)
    }
    if (obj.comment_id === undefined || obj.comment_score === undefined || obj.comment_vote === undefined) {
      throw new Error('votecomment: missing vote result')
    }
    const result: CommentVoteResult = new CommentVoteResult()
    result.commentId = EhApiPhpService.intFrom(obj.comment_id).toString()
    result.commentScore = EhApiPhpService.intFrom(obj.comment_score)
    result.commentVote = EhApiPhpService.intFrom(obj.comment_vote)
    if (result.commentId.length === 0 || (result.commentVote !== 1 && result.commentVote !== -1)) {
      throw new Error('votecomment: missing vote result')
    }
    return result
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
