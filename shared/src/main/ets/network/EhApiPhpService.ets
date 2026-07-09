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

/** POST body for /api.php method=taggallery (eros_fe Api.tagGallery). */
class TagGalleryRequest {
  method: string = 'taggallery'
  apikey: string = ''
  apiuid: number = 0
  gid: number = 0
  token: string = ''
  tags: string = ''
  vote: number = 0
}

class TagGalleryResponse {
  error: string = ''
  tagpane: string = ''
}

export class TagGalleryResult {
  tagKey: string = ''
  vote: number = 0
}

/** POST body for /api.php method=setusertag (eros_fe Api.setUserTag). */
class SetUserTagRequest {
  method: string = 'setusertag'
  apikey: string = ''
  apiuid: number = 0
  tagid: number = 0
  tagwatch: number = 0
  taghide: number = 0
  tagcolor: string = ''
  tagweight: string = ''
}

class SetUserTagResponse {
  error: string = ''
}

export class SetUserTagResult {
  tagId: string = ''
  watched: boolean = false
  hidden: boolean = false
  color: string = ''
  weight: string = ''
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

  private static ratingClassFrom(value: string): string {
    const v: string = value.trim()
    if (v.indexOf('irr') >= 0) {
      return 'irr'
    }
    if (v.indexOf('irg') >= 0) {
      return 'irg'
    }
    if (v.indexOf('irb') >= 0) {
      return 'irb'
    }
    if (v.indexOf('iry') >= 0) {
      return 'iry'
    }
    return ''
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
    result.colorRating = typeof obj.rating_cls === 'string' ? EhApiPhpService.ratingClassFrom(obj.rating_cls) : ''
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
    if (result.commentId.length === 0 || (result.commentVote !== 1 && result.commentVote !== -1 && result.commentVote !== 0)) {
      throw new Error('votecomment: missing vote result')
    }
    return result
  }

  static async tagGallery(
    base: string,
    apikey: string,
    apiuid: string,
    gid: string,
    token: string,
    tagKey: string,
    vote: number,
    prevVote: number,
  ): Promise<TagGalleryResult> {
    const apiuidNum: number = Number.parseInt(apiuid, 10)
    const gidNum: number = Number.parseInt(gid, 10)
    const normalizedTag: string = tagKey.trim()
    if (
      apikey.length === 0 ||
      token.length === 0 ||
      normalizedTag.length === 0 ||
      Number.isNaN(apiuidNum) ||
      Number.isNaN(gidNum) ||
      (vote !== 1 && vote !== -1)
    ) {
      throw new Error('tagGallery: missing API key')
    }
    const req: TagGalleryRequest = new TagGalleryRequest()
    req.apikey = apikey
    req.apiuid = apiuidNum
    req.gid = gidNum
    req.token = token
    req.tags = normalizedTag
    req.vote = vote
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`taggallery HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (e) {
      throw new Error('taggallery: invalid JSON')
    }
    if (raw === null || typeof raw !== 'object') {
      throw new Error('taggallery: invalid JSON')
    }
    const obj: TagGalleryResponse = raw as TagGalleryResponse
    if (obj.error !== undefined && obj.error.length > 0) {
      throw new Error(obj.error)
    }
    const result: TagGalleryResult = new TagGalleryResult()
    result.tagKey = normalizedTag
    // Trust EH's own resulting state from the returned tagpane (sending the opposite vote withdraws to
    // 0, etc.), not the value we sent — so the UI reflects the truth after toggle/withdraw/switch.
    const pane: string = typeof obj.tagpane === 'string' ? obj.tagpane : ''
    result.vote = EhApiPhpService.parseTagVote(pane, normalizedTag, prevVote)
    return result
  }

  /**
   * Submit one FE-compatible comma-separated gallery-tag draft. Unlike tag voting, the result can
   * contain several new tags, so callers reload the gallery rather than inferring a single vote.
   */
  static async addGalleryTags(
    base: string,
    apikey: string,
    apiuid: string,
    gid: string,
    token: string,
    tags: string,
  ): Promise<void> {
    const apiuidNum: number = Number.parseInt(apiuid, 10)
    const gidNum: number = Number.parseInt(gid, 10)
    const normalizedTags: string = tags.trim()
    if (
      apikey.length === 0 ||
      token.length === 0 ||
      normalizedTags.length === 0 ||
      Number.isNaN(apiuidNum) ||
      Number.isNaN(gidNum)
    ) {
      throw new Error('addGalleryTags: missing API key')
    }
    const req: TagGalleryRequest = new TagGalleryRequest()
    req.apikey = apikey
    req.apiuid = apiuidNum
    req.gid = gidNum
    req.token = token
    req.tags = normalizedTags
    req.vote = 1
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`taggallery HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (e) {
      throw new Error('taggallery: invalid JSON')
    }
    if (raw === null || typeof raw !== 'object') {
      throw new Error('taggallery: invalid JSON')
    }
    const obj: TagGalleryResponse = raw as TagGalleryResponse
    if (obj.error !== undefined && obj.error.length > 0) {
      throw new Error(obj.error)
    }
  }

  // The resulting vote for `tagKey` parsed from a taggallery tagpane: <a id="ta_<key>" class="tup|tdn|">
  // (spaces in the key become underscores in the id). Falls back to the prior vote if the tag is not in
  // the pane (never the SENT value — that turned a withdraw into a phantom downvote).
  private static parseTagVote(tagpane: string, tagKey: string, fallback: number): number {
    if (tagpane.length === 0) {
      return fallback
    }
    const at: number = tagpane.indexOf(`id="ta_${tagKey.split(' ').join('_')}"`)
    if (at < 0) {
      return fallback
    }
    const m: RegExpMatchArray | null = tagpane.substring(at, at + 220).match(/class="([a-z]*)"/)
    const cls: string = m !== null ? m[1] : ''
    if (cls === 'tup') {
      return 1
    }
    if (cls === 'tdn') {
      return -1
    }
    return 0
  }

  static async setUserTag(
    base: string,
    apikey: string,
    apiuid: string,
    tagId: string,
    watched: boolean,
    hidden: boolean,
    color: string,
    weight: string,
  ): Promise<SetUserTagResult> {
    const apiuidNum: number = Number.parseInt(apiuid, 10)
    const tagIdNum: number = Number.parseInt(tagId, 10)
    const normalizedColor: string = color.trim()
    const normalizedWeight: string = weight.trim()
    if (apikey.length === 0 || Number.isNaN(apiuidNum) || Number.isNaN(tagIdNum)) {
      throw new Error('setUserTag: missing API key')
    }
    const req: SetUserTagRequest = new SetUserTagRequest()
    req.apikey = apikey
    req.apiuid = apiuidNum
    req.tagid = tagIdNum
    req.tagwatch = watched ? 1 : 0
    req.taghide = hidden ? 1 : 0
    req.tagcolor = normalizedColor
    req.tagweight = normalizedWeight
    const resp: EhTextResponse = await EhHttpClient.getInstance().postJson(
      `${base}/api.php`,
      JSON.stringify(req),
    )
    if (resp.statusCode !== 200) {
      throw new Error(`setusertag HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (e) {
      throw new Error('setusertag: invalid JSON')
    }
    if (raw === null || typeof raw !== 'object') {
      throw new Error('setusertag: invalid JSON')
    }
    const obj: SetUserTagResponse = raw as SetUserTagResponse
    if (obj.error !== undefined && obj.error.length > 0) {
      throw new Error(obj.error)
    }
    const result: SetUserTagResult = new SetUserTagResult()
    result.tagId = tagId
    result.watched = watched
    result.hidden = hidden
    result.color = normalizedColor
    result.weight = normalizedWeight
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
