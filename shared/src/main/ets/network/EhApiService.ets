import { EhHttpClient, EhTextResponse } from './EhHttpClient'
import { EhError, EhErrorKind } from './EhError'
import { EhErrorClassifier } from './EhErrorClassifier'
import { EhConstants } from '../constants/EhConstants'
import { EhGalleryListParseTask } from '../parser/EhGalleryListParseTask'
import { EhFavcatListParser } from '../parser/EhFavcatListParser'
import { EhMytagsParser } from '../parser/EhMytagsParser'
import { EhUconfigParser } from '../parser/EhUconfigParser'
import { EhProfileSettings } from '../model/EhProfileSettings'
import { EhCommentParser } from '../parser/EhCommentParser'
import { EhGalleryDetailParser } from '../parser/EhGalleryDetailParser'
import { EhGalleryImageParser } from '../parser/EhGalleryImageParser'
import { EhGalleryTorrentParser } from '../parser/EhGalleryTorrentParser'
import { EhGalleryArchiverParser } from '../parser/EhGalleryArchiverParser'
import { HtmlSelectorUtils } from '../parser/HtmlSelectorUtils'
import { EhGalleryFavoriteParser, GalleryFavoriteInfo } from '../parser/EhGalleryFavoriteParser'
import { UserTagStore } from '../state/UserTagStore'
import { connectUserTagSignal, UserTagSignal } from '../state/UserTagSignal'
import { GalleryList } from '../model/GalleryList'
import { LocalBlockService } from '../services/LocalBlockService'
import { EhGallery } from '../model/EhGallery'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { EhMytags } from '../model/EhMytags'
import { EhGalleryComment } from '../model/EhGalleryComment'
import { EhGalleryTorrentList } from '../model/EhGalleryTorrent'
import { EhGalleryArchiverQuote, EhGalleryArchiverSubmitResult } from '../model/EhGalleryArchiver'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const ARCHIVER_PREPARE_RETRY_MS: number = 1000

/** Header + first preview page + comments parsed from a gallery detail fetch. */
export class GalleryDetailResult {
  gallery: EhGallery
  images: EhGalleryImage[]
  comments: EhGalleryComment[]
  previewPageCount: number

  constructor(
    gallery: EhGallery,
    images: EhGalleryImage[],
    comments: EhGalleryComment[] = [],
    previewPageCount: number = 1,
  ) {
    this.gallery = gallery
    this.images = images
    this.comments = comments
    this.previewPageCount = previewPageCount
  }
}

/** Options for a gallery-list request. */
export interface GalleryListQuery {
  isEx: boolean
  source: string // home source path: '' front page / 'popular' / 'watched' / 'toplist' (page-paged)
  next: string // nextGid cursor for forward paging; '' = first page
  tl: number // toplist period (11 all / 12 year / 13 month / 15 yesterday); 0 = not a toplist
  page: number // 0-based page number for page-paged sources (toplist); ignored by cursor sources
  fCats: number // f_cats bitmask (categories to exclude); 0 = all
  search: string
  advancedEnabled: boolean // gates advsearch=1 and all advanced params; f_cats/f_search are basic
  minRating: number // f_srdd minimum stars (2-5); 0 = off
  pagesFrom: number // f_spf page lower bound; 0 = off
  pagesTo: number // f_spt page upper bound; 0 = off
  requireTorrent: boolean // f_sto: only galleries with torrents
  showExpunged: boolean // f_sh: only expunged/removed galleries
  // eros_fe's three independent "ignore my default <X> filter" toggles (each its own EH param).
  disableLanguageFilter: boolean // f_sfl: ignore the account's default language filter
  disableUploaderFilter: boolean // f_sfu: ignore the account's default uploader filter
  disableTagFilter: boolean // f_sft: ignore the account's default tag filter
  applyToplistHiddenUserTags: boolean // local-only: hide Toplist rows carrying My Tags hidden tags
}

/** Options for a favorites request (favorites.php). */
export interface FavoritesQuery {
  isEx: boolean
  favcat: string // '' or 'a' = all slots; '0'-'9' = a specific favcat
  next: string // nextGid cursor; '' = first page
  page: number // 0-based page number for favorites ptt paging; -1 = use cursor/first page
  from: string // last visible gid paired with page paging; '' for first page/cursor fallback
  search: string // f_search within favorites; '' = none
  order: string // inline_set order: 'fs_f' (favorited time) / 'fs_p' (posted time); '' = EH default
}

/** POST body for gallerypopups.php?act=addfav. favcat='favdel' removes the remote favorite. */
export interface GalleryFavoriteUpdate {
  isEx: boolean
  gid: string
  token: string
  favcat: string
  favnote: string
}

/** POST body semantics for /g/{gid}/{token} comment writes. */
export interface GalleryCommentWrite {
  isEx: boolean
  gid: string
  token: string
  comment: string
  commentId: string
  isEdit: boolean
}

/** POST body semantics for deleting existing My Tags through /mytags. */
export interface MyTagsDeleteUpdate {
  isEx: boolean
  tagIds: string[]
  tagset: string
}

/** POST body semantics for adding one new My Tag through /mytags. */
export interface MyTagsAddUpdate {
  isEx: boolean
  tagName: string
  tagset: string
  color: string
  weight: string
  watched: boolean
  hidden: boolean
}

/** POST body semantics for creating / renaming / deleting a My Tags tagset through /mytags. */
export interface MyTagsTagsetUpdate {
  isEx: boolean
  action: string // 'create' / 'rename' / 'delete'
  tagset: string
  name: string
}

/**
 * Web-page API surface: builds EH list/search URLs, fetches via EhHttpClient, hands HTML
 * to the parsers. Mirrors V2Next's ApiService. M1 covers the anonymous table-site gallery
 * list; favorites/search/watched land in later milestones.
 */
export class EhApiService {
  private static instance: EhApiService

  static getInstance(): EhApiService {
    if (!EhApiService.instance) {
      EhApiService.instance = new EhApiService()
    }
    return EhApiService.instance
  }

  /**
   * GET + truthful failure classification. A transport throw (no HTTP response) becomes a Network
   * EhError; a response that is not a usable page for `page` ('list' / 'detail' / 'generic') becomes
   * the classified EhError (NotFound only for a captured 404, SadPanda/Login/Cloudflare/RateLimited/
   * ServerError/EmptyBody/ParseFailure otherwise). Replaces the old `throw new Error('... HTTP <n>')`
   * so a non-404 failure can never surface to the UI as a 404.
   */
  private async fetch(url: string, isEx: boolean, page: string): Promise<EhTextResponse> {
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().getText(url)
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, page)
    if (failure !== null) {
      throw failure
    }
    return resp
  }

  private formPair(name: string, value: string): string {
    return `${encodeURIComponent(name)}=${encodeURIComponent(value)}`
  }

  async getGalleryFavoriteInfo(
    isEx: boolean,
    gid: string,
    token: string,
  ): Promise<GalleryFavoriteInfo> {
    const base: string = EhConstants.baseUrl(isEx)
    const url: string =
      `${base}/gallerypopups.php?gid=${encodeURIComponent(gid)}` +
      `&t=${encodeURIComponent(token)}&act=addfav`
    const resp: EhTextResponse = await this.fetch(url, isEx, 'generic')
    return EhGalleryFavoriteParser.parse(resp.body)
  }

  async updateGalleryFavorite(update: GalleryFavoriteUpdate): Promise<void> {
    const base: string = EhConstants.baseUrl(update.isEx)
    const url: string =
      `${base}/gallerypopups.php?gid=${encodeURIComponent(update.gid)}` +
      `&t=${encodeURIComponent(update.token)}&act=addfav`
    const body: string = [
      this.formPair('favcat', update.favcat.length > 0 ? update.favcat : 'favdel'),
      this.formPair('update', '1'),
      this.formPair('favnote', update.favnote),
    ].join('&')
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, body)
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(
        url,
        update.isEx,
        resp,
        'generic',
      )
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `favorite unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(
      url,
      update.isEx,
      resp,
      'generic',
    )
    if (failure !== null) {
      throw failure
    }
  }

  async postGalleryComment(update: GalleryCommentWrite): Promise<void> {
    const comment: string = update.comment.trim()
    if (comment.length < 10) {
      throw new Error('comment too short')
    }
    if (update.gid.length === 0 || update.token.length === 0) {
      throw new Error('comment missing gallery')
    }
    const base: string = EhConstants.baseUrl(update.isEx)
    const url: string = `${base}/g/${encodeURIComponent(update.gid)}/${encodeURIComponent(update.token)}`
    const pairs: string[] = []
    if (update.isEdit) {
      if (update.commentId.length === 0) {
        throw new Error('comment missing edit id')
      }
      pairs.push(this.formPair('commenttext_edit', comment))
      pairs.push(this.formPair('edit_comment', update.commentId))
    } else {
      pairs.push(this.formPair('commenttext_new', comment))
    }
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, pairs.join('&'))
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(
        url,
        update.isEx,
        resp,
        'detail',
      )
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `comment unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(
      url,
      update.isEx,
      resp,
      'detail',
    )
    if (failure !== null) {
      throw failure
    }
  }

  /** Add one new usertag (eros_fe actionNewUserTag: usertag_action=add). */
  async addUserTag(update: MyTagsAddUpdate): Promise<void> {
    const tagName: string = update.tagName.trim()
    if (tagName.length === 0) {
      throw new Error('mytags add: missing tag')
    }
    const base: string = EhConstants.baseUrl(update.isEx)
    const params: string[] = []
    if (update.tagset.length > 0) {
      params.push(`tagset=${encodeURIComponent(update.tagset)}`)
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : ''
    const url: string = `${base}/mytags${suffix}`
    const pairs: string[] = [
      this.formPair('usertag_action', 'add'),
      this.formPair('tagname_new', tagName),
      this.formPair('tagcolor_new', update.color.trim()),
      this.formPair('tagweight_new', update.weight.trim().length > 0 ? update.weight.trim() : '10'),
      this.formPair('tagwatch_new', update.watched ? 'on' : ''),
      this.formPair('taghide_new', update.hidden ? 'on' : ''),
      this.formPair('usertag_target', '0'),
    ]
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, pairs.join('&'))
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(
        url,
        update.isEx,
        resp,
        'generic',
      )
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `mytags add unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(
      url,
      update.isEx,
      resp,
      'generic',
    )
    if (failure !== null) {
      throw failure
    }
  }

  /** Manage My Tags tagsets (eros_fe actionCreatTagSet / actionRenameTagSet / actionDeleteTagSet). */
  async updateMyTagsTagset(update: MyTagsTagsetUpdate): Promise<void> {
    const action: string = update.action.trim()
    if (action !== 'create' && action !== 'rename' && action !== 'delete') {
      throw new Error('mytags tagset: invalid action')
    }
    if ((action === 'rename' || action === 'delete') && update.tagset.length === 0) {
      throw new Error('mytags tagset: missing tagset')
    }
    const name: string = update.name.trim()
    if ((action === 'create' || action === 'rename') && name.length === 0) {
      throw new Error('mytags tagset: missing name')
    }
    const base: string = EhConstants.baseUrl(update.isEx)
    const params: string[] = []
    if ((action === 'rename' || action === 'delete') && update.tagset.length > 0) {
      params.push(`tagset=${encodeURIComponent(update.tagset)}`)
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : ''
    const url: string = `${base}/mytags${suffix}`
    const pairs: string[] = [this.formPair('tagset_action', action)]
    if (action === 'create' || action === 'rename') {
      pairs.push(this.formPair('tagset_name', name))
    }
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, pairs.join('&'))
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(
        url,
        update.isEx,
        resp,
        'generic',
      )
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `mytags tagset unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(
      url,
      update.isEx,
      resp,
      'generic',
    )
    if (failure !== null) {
      throw failure
    }
  }

  /** Delete one or more existing usertags (eros_fe actionDeleteUserTag: usertag_action=mass). */
  async deleteUserTags(update: MyTagsDeleteUpdate): Promise<void> {
    if (update.tagIds.length === 0) {
      throw new Error('mytags delete: missing tag')
    }
    const base: string = EhConstants.baseUrl(update.isEx)
    const params: string[] = []
    if (update.tagset.length > 0) {
      params.push(`tagset=${encodeURIComponent(update.tagset)}`)
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : ''
    const url: string = `${base}/mytags${suffix}`
    const pairs: string[] = [this.formPair('usertag_action', 'mass')]
    update.tagIds.forEach((tagId: string) => {
      if (tagId.length > 0) {
        pairs.push(this.formPair('modify_usertags[]', tagId))
      }
    })
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, pairs.join('&'))
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(
        url,
        update.isEx,
        resp,
        'generic',
      )
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `mytags delete unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(
      url,
      update.isEx,
      resp,
      'generic',
    )
    if (failure !== null) {
      throw failure
    }
  }

  /**
   * Fetch and parse one gallery-list page. `query.source` routes the path (eros_fe request.dart):
   * '' → front page `/`, 'watched' → `/watched` (login-only; same gltc layout + next cursor),
   * 'popular' → `/popular` (a fixed snapshot — no paging, no filters, so all params are skipped).
   */
  /** Remove galleries carrying any user-hidden tag (eros_fe TagController.needHide / fetch_list.dart).
   * Applied to the main + popular + search lists, and optionally Toplist; never watched (you want watched-tag hits);
   * a no-op until My Tags load, so logged-out / cold-start lists are unfiltered. */
  private filterHidden(list: GalleryList): GalleryList {
    const store: UserTagStore = UserTagStore.getInstance()
    if (store.hasAny()) {
      list.gallerys = list.gallerys.filter((g: EhGallery) => !store.anyHidden(g.simpleTags))
    }
    return list
  }

  private filterLocalBlocked(list: GalleryList): GalleryList {
    return LocalBlockService.filterGalleryList(list)
  }

  private registerInlineTagColors(list: GalleryList): GalleryList {
    const store: UserTagStore = UserTagStore.getInstance()
    let changed: boolean = false
    list.gallerys.forEach((g: EhGallery) => {
      changed = store.ingestInlineTags(g.simpleTags) || changed
    })
    if (changed) {
      const sig: UserTagSignal = connectUserTagSignal()
      sig.version = sig.version + 1
    }
    return list
  }

  async getGalleryList(query: GalleryListQuery): Promise<GalleryList> {
    const base: string = EhConstants.baseUrl(query.isEx)
    const isPopular: boolean = query.source === 'popular'
    let path: string = '/'
    if (query.source === 'popular') {
      path = '/popular'
    } else if (query.source === 'watched') {
      path = '/watched'
    }
    const params: string[] = []
    if (isPopular) {
      // /popular ignores filters and the next cursor — request the bare snapshot.
      const url: string = `${base}${path}`
      const resp = await this.fetch(url, query.isEx, 'list')
      return this.filterLocalBlocked(
        this.filterHidden(
          this.registerInlineTagColors(await EhGalleryListParseTask.parse(resp.body)),
        ),
      )
    }
    if (query.source === 'toplist') {
      // toplist.php is E-Hentai-ONLY (exhentai.org has no toplist → 404), so always use the e-hentai
      // host even in 里站 mode. Page-number paging (table.ptt), no cursor/filters (eros_fe toplist tab).
      const pageParam: string = query.page >= 0 ? `&p=${query.page}` : ''
      const url: string = `${EhConstants.baseUrl(false)}/toplist.php?tl=${query.tl}${pageParam}`
      // toplist.php is hard-pinned to the e-hentai host, so classify it as the table site (isEx=false).
      const resp = await this.fetch(url, false, 'list')
      const list: GalleryList = this.registerInlineTagColors(
        await EhGalleryListParseTask.parse(resp.body),
      )
      return this.filterLocalBlocked(
        query.applyToplistHiddenUserTags ? this.filterHidden(list) : list,
      )
    }
    if (query.fCats > 0) {
      params.push(`f_cats=${query.fCats}`)
    }
    if (query.search.length > 0) {
      params.push(`f_search=${encodeURIComponent(query.search)}`)
    }
    // EH only honours the advanced block (f_sr/f_sp/f_sto/f_sh/f_sf*) when advsearch=1 is also sent;
    // without it the server silently drops every advanced filter (eros_fe request.dart gates it the
    // same way). f_cats/f_search are basic params and work without it.
    const hasAdvanced: boolean =
      query.advancedEnabled &&
      (query.minRating >= 2 ||
        query.pagesFrom > 0 ||
        query.pagesTo > 0 ||
        query.requireTorrent ||
        query.showExpunged ||
        query.disableLanguageFilter ||
        query.disableUploaderFilter ||
        query.disableTagFilter)
    if (hasAdvanced) {
      params.push('advsearch=1')
    }
    if (query.advancedEnabled && query.minRating >= 2) {
      params.push('f_sr=on')
      params.push(`f_srdd=${query.minRating}`)
    }
    if (query.advancedEnabled && (query.pagesFrom > 0 || query.pagesTo > 0)) {
      params.push('f_sp=on')
      params.push(`f_spf=${query.pagesFrom > 0 ? query.pagesFrom : ''}`)
      params.push(`f_spt=${query.pagesTo > 0 ? query.pagesTo : ''}`)
    }
    if (query.advancedEnabled && query.requireTorrent) {
      params.push('f_sto=on')
    }
    if (query.advancedEnabled && query.showExpunged) {
      params.push('f_sh=on')
    }
    if (query.advancedEnabled && query.disableLanguageFilter) {
      params.push('f_sfl=on')
    }
    if (query.advancedEnabled && query.disableUploaderFilter) {
      params.push('f_sfu=on')
    }
    if (query.advancedEnabled && query.disableTagFilter) {
      params.push('f_sft=on')
    }
    if (query.next.length > 0) {
      params.push(`next=${query.next}`)
    }
    const queryStr: string = params.length > 0 ? `?${params.join('&')}` : ''
    const url: string = `${base}${path}${queryStr}`
    const resp = await this.fetch(url, query.isEx, 'list')
    const list: GalleryList = this.registerInlineTagColors(
      await EhGalleryListParseTask.parse(resp.body),
    )
    // Hide-filter the front page + search results (eros_fe gates on the tag filter), but NOT /watched —
    // a watched-tag list is exactly where you want those tags to show.
    if (query.source !== 'watched' && !query.disableTagFilter) {
      return this.filterLocalBlocked(this.filterHidden(list))
    }
    return this.filterLocalBlocked(list)
  }

  /** Fetch one favorites.php page: gallery rows (same gltc layout as the list) + the favcat
   * selector bar. Requires login (ipb_*); ExHentai favorites also need igneous. */
  async getFavoritesList(query: FavoritesQuery): Promise<GalleryList> {
    const base: string = EhConstants.baseUrl(query.isEx)
    // Match eros_fe: normal paging sends page/from or next only. inline_set is an exception retry
    // for display/order correction, not part of the ordinary page request.
    const firstPage: boolean = query.page < 0 && query.next.length === 0
    let body: string = await this.fetchFavoritesBody(base, query, '')
    // The gltc TABLE parser only understands the Minimal/Compact layout. If the account's favorites
    // display mode is Thumbnail (`<div class="itg gld">`, no `<table class="itg">`), the parse finds
    // zero rows — so force inline_set=dm_l (Minimal) once and re-fetch (eros_fe dm_l handling). The
    // guard (no itg table AND an itg div present) means a table-mode account never triggers the retry.
    if (body.indexOf('<table class="itg') < 0 && body.indexOf('class="itg gld') >= 0) {
      body = await this.fetchFavoritesBody(base, query, EhConstants.FAV_DISPLAY_LIST)
    }
    const activeOrder: string = this.favoriteOrderFromBody(body)
    if (
      firstPage &&
      query.order.length > 0 &&
      activeOrder.length > 0 &&
      activeOrder !== query.order
    ) {
      body = await this.fetchFavoritesBody(base, query, query.order)
      if (body.indexOf('<table class="itg') < 0 && body.indexOf('class="itg gld') >= 0) {
        body = await this.fetchFavoritesBody(base, query, EhConstants.FAV_DISPLAY_LIST)
      }
    }
    const list: GalleryList = this.registerInlineTagColors(await EhGalleryListParseTask.parse(body))
    list.favList = EhFavcatListParser.parse(body)
    // Active sort order from the inline_set dropdown (`<option value="f|p" selected>`).
    list.favOrder = this.favoriteOrderFromBody(body)
    return this.filterLocalBlocked(list)
  }

  private favoriteOrderFromBody(body: string): string {
    const orderM: RegExpMatchArray | null = body.match(/<option value="([fp])" selected/)
    return orderM !== null && orderM[1] !== undefined ? `fs_${orderM[1]}` : ''
  }

  /** Build the favorites.php URL and return the page body. Favorites uses page+from when the
   * searchnav exposes page numbers; otherwise it falls back to next cursor paging like normal lists. */
  private async fetchFavoritesBody(
    base: string,
    query: FavoritesQuery,
    inlineSet: string,
  ): Promise<string> {
    const params: string[] = []
    if (query.favcat.length > 0 && query.favcat !== 'a') {
      params.push(`favcat=${query.favcat}`)
    }
    if (query.search.length > 0) {
      params.push(`f_search=${encodeURIComponent(query.search)}`)
    }
    if (inlineSet.length > 0) {
      params.push(`inline_set=${inlineSet}`)
    }
    if (query.page >= 0) {
      params.push(`page=${query.page}`)
      if (query.from.length > 0) {
        params.push(`from=${encodeURIComponent(query.from)}`)
      }
    } else if (query.next.length > 0) {
      params.push(`next=${encodeURIComponent(query.next)}`)
    }
    const queryStr: string = params.length > 0 ? `?${params.join('&')}` : ''
    const url: string = `${base}/favorites.php${queryStr}`
    const resp = await this.fetch(url, query.isEx, 'list')
    return resp.body
  }

  /** Fetch the user's My Tags (watched/hidden/flagged tags + apiuid/apikey). Requires login.
   * `tagset` ('' = the default set) selects one of the user's tag sets via `?tagset=N`. */
  async getMyTags(isEx: boolean, tagset: string = ''): Promise<EhMytags> {
    const suffix: string = tagset.length > 0 ? `?tagset=${tagset}` : ''
    const url: string = `${EhConstants.baseUrl(isEx)}/mytags${suffix}`
    const resp = await this.fetch(url, isEx, 'generic')
    return EhMytagsParser.parse(resp.body)
  }

  /** Read the EH user config (uconfig.php) for the current site into the editable model. */
  async getUserConfig(isEx: boolean): Promise<EhProfileSettings> {
    const url: string = `${EhConstants.baseUrl(isEx)}/uconfig.php`
    const resp: EhTextResponse = await this.fetch(url, isEx, 'generic')
    return EhUconfigParser.parse(resp.body)
  }

  /**
   * Write the EH user config (POST uconfig.php). Non-idempotent: it overwrites the user's server-side
   * profile, so the caller must have the user's intent (a Save action), not auto-save.
   */
  async saveUserConfig(isEx: boolean, settings: EhProfileSettings): Promise<void> {
    const url: string = `${EhConstants.baseUrl(isEx)}/uconfig.php`
    const body: string = EhUconfigParser.buildPostBody(settings)
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, body)
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, 'generic')
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `uconfig unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, 'generic')
    if (failure !== null) {
      throw failure
    }
  }

  /**
   * Profile action on uconfig.php (eros_fe postEhProfile): action '' = select, 'create' / 'rename' /
   * 'delete' / 'default'. profileSet is the profile value; name is for create/rename. Returns the
   * re-parsed config for the resulting active profile.
   */
  async postProfileAction(
    isEx: boolean,
    action: string,
    profileSet: string,
    name: string,
  ): Promise<EhProfileSettings> {
    const url: string = `${EhConstants.baseUrl(isEx)}/uconfig.php`
    const pairs: string[] = [this.formPair('profile_action', action)]
    if (name.length > 0) {
      pairs.push(this.formPair('profile_name', name))
    }
    if (profileSet.length > 0) {
      pairs.push(this.formPair('profile_set', profileSet))
    }
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, pairs.join('&'))
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, 'generic')
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `profile unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, 'generic')
    if (failure !== null) {
      throw failure
    }
    return EhUconfigParser.parse(resp.body)
  }

  /** Fetch the torrent list for a gallery (eros_fe getTorrent / gallerytorrents.php). */
  async getGalleryTorrents(
    gid: string,
    token: string,
    isEx: boolean,
  ): Promise<EhGalleryTorrentList> {
    const url: string = `${EhConstants.baseUrl(isEx)}/gallerytorrents.php?gid=${gid}&t=${token}`
    const resp = await this.fetch(url, isEx, 'generic')
    return EhGalleryTorrentParser.parse(resp.body)
  }

  /** Fetch the gallery archiver quote/options page. Submit actions use the protected POST methods below. */
  async getGalleryArchiver(
    gid: string,
    token: string,
    archiverLink: string,
    isEx: boolean,
  ): Promise<EhGalleryArchiverQuote> {
    const url: string = this.archiverUrl(gid, token, archiverLink, isEx)
    const resp = await this.fetch(url, isEx, 'generic')
    return EhGalleryArchiverParser.parse(resp.body)
  }

  /** Submit a protected local archive request. Returns the generated archive URL; caller decides how to open it. */
  async submitGalleryArchiverLocal(
    gid: string,
    token: string,
    archiverLink: string,
    dltype: string,
    dlcheck: string,
    isEx: boolean,
  ): Promise<EhGalleryArchiverSubmitResult> {
    const url: string = this.archiverUrl(gid, token, archiverLink, isEx)
    const body: string = [
      this.formPair('dltype', dltype.trim()),
      this.formPair('dlcheck', dlcheck.trim()),
    ].join('&')
    let resp: EhTextResponse = await this.postArchiverForm(url, body, isEx)
    let result: EhGalleryArchiverSubmitResult = EhGalleryArchiverParser.parseLocalSubmit(resp.body)
    if (result.localDownloadUrl.length === 0) {
      await EhApiService.delay(ARCHIVER_PREPARE_RETRY_MS)
      resp = await this.postArchiverForm(url, body, isEx)
      result = EhGalleryArchiverParser.parseLocalSubmit(resp.body)
    }
    result.localDownloadUrl = this.absoluteArchiverUrl(result.localDownloadUrl, isEx)
    if (result.message.length === 0 && result.localDownloadUrl.length > 0) {
      result.message = result.localDownloadUrl
    }
    return result
  }

  /** Submit a protected H@H archive request. EH returns a status message, not a local download URL. */
  async submitGalleryArchiverHath(
    gid: string,
    token: string,
    archiverLink: string,
    resolution: string,
    isEx: boolean,
  ): Promise<EhGalleryArchiverSubmitResult> {
    const url: string = this.archiverUrl(gid, token, archiverLink, isEx)
    const body: string = this.formPair('hathdl_xres', resolution.trim())
    const resp: EhTextResponse = await this.postArchiverForm(url, body, isEx)
    return EhGalleryArchiverParser.parseHathSubmit(resp.body)
  }

  private archiverUrl(gid: string, token: string, archiverLink: string, isEx: boolean): string {
    const link: string = HtmlSelectorUtils.htmlUnescape(archiverLink.trim())
    if (link.indexOf('archiver.php') >= 0) {
      return this.normalizeArchiverUrl(link, isEx)
    }
    if (link.length === 0) {
      return `${EhConstants.baseUrl(isEx)}/archiver.php?gid=${encodeURIComponent(gid)}&token=${encodeURIComponent(token)}`
    }
    return (
      `${EhConstants.baseUrl(isEx)}/archiver.php?gid=${encodeURIComponent(gid)}` +
      `&token=${encodeURIComponent(token)}&or=${encodeURIComponent(link)}`
    )
  }

  private normalizeArchiverUrl(rawUrl: string, isEx: boolean): string {
    const base: string = EhConstants.baseUrl(isEx)
    const absoluteIdx: number = rawUrl.indexOf('/archiver.php')
    if (absoluteIdx >= 0) {
      return `${base}${rawUrl.substring(absoluteIdx)}`
    }
    const relativeNeedle: string = 'archiver.php'
    const relativeIdx: number = rawUrl.indexOf(relativeNeedle)
    if (relativeIdx >= 0) {
      return `${base}/${rawUrl.substring(relativeIdx)}`
    }
    return rawUrl
  }

  private async postArchiverForm(
    url: string,
    body: string,
    isEx: boolean,
  ): Promise<EhTextResponse> {
    let resp: EhTextResponse
    try {
      resp = await EhHttpClient.getInstance().postFormUrlEncoded(url, body)
    } catch (err) {
      throw EhErrorClassifier.network(err as Error, url)
    }
    if (resp.statusCode >= 400) {
      const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, 'generic')
      if (failure !== null) {
        throw failure
      }
      throw new EhError(EhErrorKind.HttpError, `archiver unclassified status=${resp.statusCode}`)
    }
    const failure: EhError | null = EhErrorClassifier.classifyResponse(url, isEx, resp, 'generic')
    if (failure !== null) {
      throw failure
    }
    return resp
  }

  private absoluteArchiverUrl(url: string, isEx: boolean): string {
    if (url.length === 0 || url.startsWith('http://') || url.startsWith('https://')) {
      return url
    }
    if (url.startsWith('/')) {
      return `${EhConstants.baseUrl(isEx)}${url}`
    }
    return `${EhConstants.baseUrl(isEx)}/${url}`
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }

  /** Fetch a gallery detail page; returns header (incl. tags/apikey) + first preview page. */
  async getGalleryDetail(gid: string, token: string, isEx: boolean): Promise<GalleryDetailResult> {
    const url: string = `${EhConstants.baseUrl(isEx)}/g/${gid}/${token}/`
    const resp = await this.fetch(url, isEx, 'detail')
    const gallery: EhGallery = EhGalleryDetailParser.parse(resp.body, gid, token)
    const images: EhGalleryImage[] = EhGalleryImageParser.parse(resp.body)
    const comments: EhGalleryComment[] = EhCommentParser.parse(resp.body)
    const previewPageCount: number = EhGalleryImageParser.parsePageCount(resp.body)
    DiagnosticLogger.info(
      'gallery',
      'detail_fetch_parsed',
      `gid=${gid} hasArchiver=${gallery.archiverLink.length > 0} torrents=${gallery.torrentCount} images=${images.length} comments=${comments.length}`,
    )
    return new GalleryDetailResult(gallery, images, comments, previewPageCount)
  }

  /** Fetch one preview page (?p=) of image-page links for the reader. */
  async getPreviewImages(
    gid: string,
    token: string,
    isEx: boolean,
    p: number,
  ): Promise<EhGalleryImage[]> {
    const url: string = `${EhConstants.baseUrl(isEx)}/g/${gid}/${token}/?p=${p}`
    const resp = await this.fetch(url, isEx, 'detail')
    return EhGalleryImageParser.parse(resp.body)
  }
}
