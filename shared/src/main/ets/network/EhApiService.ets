import { EhHttpClient, EhTextResponse } from './EhHttpClient'
import { EhError } from './EhError'
import { EhErrorClassifier } from './EhErrorClassifier'
import { EhConstants } from '../constants/EhConstants'
import { EhGalleryListParser } from '../parser/EhGalleryListParser'
import { EhFavcatListParser } from '../parser/EhFavcatListParser'
import { EhMytagsParser } from '../parser/EhMytagsParser'
import { EhCommentParser } from '../parser/EhCommentParser'
import { EhGalleryDetailParser } from '../parser/EhGalleryDetailParser'
import { EhGalleryImageParser } from '../parser/EhGalleryImageParser'
import { EhGalleryTorrentParser } from '../parser/EhGalleryTorrentParser'
import { UserTagStore } from '../state/UserTagStore'
import { GalleryList } from '../model/GalleryList'
import { EhGallery } from '../model/EhGallery'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { EhMytags } from '../model/EhMytags'
import { EhGalleryComment } from '../model/EhGalleryComment'
import { EhGalleryTorrentList } from '../model/EhGalleryTorrent'

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
  minRating: number // f_srdd minimum stars (2-5); 0 = off
  pagesFrom: number // f_spf page lower bound; 0 = off
  pagesTo: number // f_spt page upper bound; 0 = off
  requireTorrent: boolean // f_sto: only galleries with torrents
  showExpunged: boolean // f_sh: include expunged/removed galleries
  // eros_fe's three independent "ignore my default <X> filter" toggles (each its own EH param).
  disableLanguageFilter: boolean // f_sfl: ignore the account's default language filter
  disableUploaderFilter: boolean // f_sfu: ignore the account's default uploader filter
  disableTagFilter: boolean // f_sft: ignore the account's default tag filter
}

/** Options for a favorites request (favorites.php). */
export interface FavoritesQuery {
  isEx: boolean
  favcat: string // '' or 'a' = all slots; '0'-'9' = a specific favcat
  next: string // nextGid cursor; '' = first page
  search: string // f_search within favorites; '' = none
  order: string // inline_set order: 'fs_f' (favorited time) / 'fs_p' (posted time); '' = EH default
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

  /**
   * Fetch and parse one gallery-list page. `query.source` routes the path (eros_fe request.dart):
   * '' → front page `/`, 'watched' → `/watched` (login-only; same gltc layout + next cursor),
   * 'popular' → `/popular` (a fixed snapshot — no paging, no filters, so all params are skipped).
   */
  /** Remove galleries carrying any user-hidden tag (eros_fe TagController.needHide / fetch_list.dart).
   * Applied to the main + popular + search lists, never watched (you want watched-tag hits) or toplist;
   * a no-op until My Tags load, so logged-out / cold-start lists are unfiltered. */
  private filterHidden(list: GalleryList): GalleryList {
    const store: UserTagStore = UserTagStore.getInstance()
    if (store.hasAny()) {
      list.gallerys = list.gallerys.filter((g: EhGallery) => !store.anyHidden(g.simpleTags))
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
      return this.filterHidden(EhGalleryListParser.parse(resp.body))
    }
    if (query.source === 'toplist') {
      // toplist.php is E-Hentai-ONLY (exhentai.org has no toplist → 404), so always use the e-hentai
      // host even in 里站 mode. Page-number paging (table.ptt), no cursor/filters (eros_fe toplist tab).
      const url: string = `${EhConstants.baseUrl(false)}/toplist.php?tl=${query.tl}&p=${query.page}`
      // toplist.php is hard-pinned to the e-hentai host, so classify it as the table site (isEx=false).
      const resp = await this.fetch(url, false, 'list')
      return EhGalleryListParser.parse(resp.body)
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
      query.minRating >= 2 ||
      query.pagesFrom > 0 ||
      query.pagesTo > 0 ||
      query.requireTorrent ||
      query.showExpunged ||
      query.disableLanguageFilter ||
      query.disableUploaderFilter ||
      query.disableTagFilter
    if (hasAdvanced) {
      params.push('advsearch=1')
    }
    if (query.minRating >= 2) {
      params.push('f_sr=on')
      params.push(`f_srdd=${query.minRating}`)
    }
    if (query.pagesFrom > 0 || query.pagesTo > 0) {
      params.push('f_sp=on')
      params.push(`f_spf=${query.pagesFrom > 0 ? query.pagesFrom : ''}`)
      params.push(`f_spt=${query.pagesTo > 0 ? query.pagesTo : ''}`)
    }
    if (query.requireTorrent) {
      params.push('f_sto=on')
    }
    if (query.showExpunged) {
      params.push('f_sh=on')
    }
    if (query.disableLanguageFilter) {
      params.push('f_sfl=on')
    }
    if (query.disableUploaderFilter) {
      params.push('f_sfu=on')
    }
    if (query.disableTagFilter) {
      params.push('f_sft=on')
    }
    if (query.next.length > 0) {
      params.push(`next=${query.next}`)
    }
    const queryStr: string = params.length > 0 ? `?${params.join('&')}` : ''
    const url: string = `${base}${path}${queryStr}`
    const resp = await this.fetch(url, query.isEx, 'list')
    // TODO(perf): move heavy parse to a TaskPool worker (pass HTML in, GalleryList out).
    const list: GalleryList = EhGalleryListParser.parse(resp.body)
    // Hide-filter the front page + search results (eros_fe gates on the tag filter), but NOT /watched —
    // a watched-tag list is exactly where you want those tags to show.
    if (query.source !== 'watched' && !query.disableTagFilter) {
      return this.filterHidden(list)
    }
    return list
  }

  /** Fetch one favorites.php page: gallery rows (same gltc layout as the list) + the favcat
   * selector bar. Requires login (ipb_*); ExHentai favorites also need igneous. */
  async getFavoritesList(query: FavoritesQuery): Promise<GalleryList> {
    const base: string = EhConstants.baseUrl(query.isEx)
    // First fetch carries the user's sort order (inline_set=fs_f|fs_p).
    let body: string = await this.fetchFavoritesBody(base, query, query.order)
    // The gltc TABLE parser only understands the Minimal/Compact layout. If the account's favorites
    // display mode is Thumbnail (`<div class="itg gld">`, no `<table class="itg">`), the parse finds
    // zero rows — so force inline_set=dm_l (Minimal) once and re-fetch (eros_fe dm_l handling). The
    // guard (no itg table AND an itg div present) means a table-mode account never triggers the retry.
    if (body.indexOf('<table class="itg') < 0 && body.indexOf('class="itg gld') >= 0) {
      body = await this.fetchFavoritesBody(base, query, EhConstants.FAV_DISPLAY_LIST)
    }
    const list: GalleryList = EhGalleryListParser.parse(body)
    list.favList = EhFavcatListParser.parse(body)
    // Active sort order from the inline_set dropdown (`<option value="f|p" selected>`).
    const orderM: RegExpMatchArray | null = body.match(/<option value="([fp])" selected/)
    list.favOrder = orderM !== null && orderM[1] !== undefined ? `fs_${orderM[1]}` : ''
    return list
  }

  /** Build the favorites.php URL (favcat/f_search/inline_set/next) and return the page body. The
   * inline_set value is either the sort order (fs_f|fs_p) or a display-mode override (dm_l). */
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
    if (query.next.length > 0) {
      params.push(`next=${query.next}`)
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

  /** Fetch the torrent list for a gallery (eros_fe getTorrent / gallerytorrents.php). */
  async getGalleryTorrents(gid: string, token: string, isEx: boolean): Promise<EhGalleryTorrentList> {
    const url: string = `${EhConstants.baseUrl(isEx)}/gallerytorrents.php?gid=${gid}&t=${token}`
    const resp = await this.fetch(url, isEx, 'generic')
    return EhGalleryTorrentParser.parse(resp.body)
  }

  /** Fetch a gallery detail page; returns header (incl. tags/apikey) + first preview page. */
  async getGalleryDetail(gid: string, token: string, isEx: boolean): Promise<GalleryDetailResult> {
    const url: string = `${EhConstants.baseUrl(isEx)}/g/${gid}/${token}/`
    const resp = await this.fetch(url, isEx, 'detail')
    const gallery: EhGallery = EhGalleryDetailParser.parse(resp.body, gid, token)
    const images: EhGalleryImage[] = EhGalleryImageParser.parse(resp.body)
    const comments: EhGalleryComment[] = EhCommentParser.parse(resp.body)
    const previewPageCount: number = EhGalleryImageParser.parsePageCount(resp.body)
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
