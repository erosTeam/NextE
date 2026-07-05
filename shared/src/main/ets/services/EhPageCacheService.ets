import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGallery, EhGalleryVersion } from '../model/EhGallery'
import {
  EhGalleryComment,
  EhGalleryCommentLink,
  EhGalleryCommentTextSpan,
} from '../model/EhGalleryComment'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { Favcat } from '../model/Favcat'
import { GalleryList } from '../model/GalleryList'
import { SimpleTag } from '../model/SimpleTag'
import { CacheStat } from './CacheStat'
import { TagGroup } from '../model/TagGroup'
import { GalleryDetailResult } from '../network/EhApiService'
import { EhCookieStore } from '../network/EhCookieStore'
import { LocalDataStore } from '../storage/LocalDataStore'

const CACHE_KIND_GALLERY_LIST: string = 'gallery_list'
const CACHE_KIND_GALLERY_DETAIL: string = 'gallery_detail'
const LIST_TTL_MS: number = 30 * 60 * 1000
const DETAIL_TTL_MS: number = 6 * 60 * 60 * 1000
const MAX_LIST_ROWS_PER_CACHE: number = 50
const MAX_CACHE_ROWS_PER_KIND: number = 128

const SQL_SELECT_CACHE: string =
  'SELECT payload FROM eh_page_cache WHERE kind = ? AND cache_key = ? AND expires_at > ? LIMIT 1'
const SQL_UPSERT_CACHE: string =
  'INSERT OR REPLACE INTO eh_page_cache ' +
  '(kind, cache_key, payload, cached_at, expires_at, accessed_at) VALUES (?, ?, ?, ?, ?, ?)'
const SQL_TOUCH_CACHE: string =
  'UPDATE eh_page_cache SET accessed_at = ? WHERE kind = ? AND cache_key = ?'
const SQL_DELETE_EXPIRED_CACHE: string = 'DELETE FROM eh_page_cache WHERE expires_at <= ?'
const SQL_PRUNE_KIND_CACHE: string =
  'DELETE FROM eh_page_cache WHERE kind = ? AND cache_key NOT IN (' +
  'SELECT cache_key FROM eh_page_cache WHERE kind = ? ORDER BY accessed_at DESC LIMIT ?' +
  ')'

export class EhPageCacheService {
  private static preloadedGalleryLists: Map<string, GalleryList> = new Map<string, GalleryList>()

  // Count + total payload bytes of the unexpired page cache (gallery list + detail), for the cache page.
  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = new CacheStat()
    try {
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT COUNT(*) AS c, COALESCE(SUM(LENGTH(payload)), 0) AS b FROM eh_page_cache WHERE expires_at > ?',
        [Date.now()],
      )
      try {
        if (rs.goToFirstRow()) {
          out.count = rs.getDouble(rs.getColumnIndex('c'))
          out.bytes = rs.getDouble(rs.getColumnIndex('b'))
        }
      } finally {
        rs.close()
      }
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'stat_failed', (error as Error).message)
    }
    return out
  }

  static async clearAll(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      await store.executeSql('DELETE FROM eh_page_cache')
      EhPageCacheService.preloadedGalleryLists.clear()
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'clear_failed', (error as Error).message)
    }
  }

  static homeListKey(isEx: boolean, source: string, toplistTl: number): string {
    const sourceKey: string = source.length > 0 ? source : 'front'
    return EhPageCacheService.scopedKey(
      isEx,
      `home:${EhPageCacheService.encode(sourceKey)}:tl:${toplistTl}`,
    )
  }

  /** Per-custom-profile home list cache key (uuid-scoped so two gallery-type profiles with different
   * searches don't collide on the old source-based key). */
  static homeProfileKey(isEx: boolean, uuid: string): string {
    return EhPageCacheService.scopedKey(isEx, `home:profile:${EhPageCacheService.encode(uuid)}`)
  }

  static favoritesListKey(isEx: boolean, favcat: string, order: string): string {
    const favcatKey: string = favcat.length > 0 ? favcat : 'a'
    const orderKey: string = order.length > 0 ? order : 'default'
    return EhPageCacheService.scopedKey(
      isEx,
      `favorites:${EhPageCacheService.encode(favcatKey)}:order:${EhPageCacheService.encode(orderKey)}`,
    )
  }

  static galleryDetailKey(isEx: boolean, gid: string, token: string): string {
    return EhPageCacheService.scopedKey(
      isEx,
      `detail:${EhPageCacheService.encode(gid)}:${EhPageCacheService.encode(token)}`,
    )
  }

  static async loadGalleryList(
    context: common.UIAbilityContext,
    cacheKey: string,
  ): Promise<GalleryList | null> {
    const payload: string = await EhPageCacheService.loadPayload(
      context,
      CACHE_KIND_GALLERY_LIST,
      cacheKey,
    )
    if (payload.length === 0) {
      return null
    }
    try {
      const raw: GalleryList = JSON.parse(payload) as GalleryList
      return EhPageCacheService.reviveGalleryList(raw)
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'gallery_list_decode_failed', (error as Error).message)
      return null
    }
  }

  static async preloadGalleryList(
    context: common.UIAbilityContext,
    cacheKey: string,
  ): Promise<void> {
    const cached: GalleryList | null = await EhPageCacheService.loadGalleryList(context, cacheKey)
    if (cached !== null) {
      EhPageCacheService.preloadedGalleryLists.set(cacheKey, cached)
      DiagnosticLogger.info('page-cache', 'preload_list_hit', `rows=${cached.gallerys.length}`)
    }
  }

  static takePreloadedGalleryList(cacheKey: string): GalleryList | null {
    const cached: GalleryList | undefined = EhPageCacheService.preloadedGalleryLists.get(cacheKey)
    if (cached === undefined) {
      return null
    }
    EhPageCacheService.preloadedGalleryLists.delete(cacheKey)
    DiagnosticLogger.info('page-cache', 'preload_list_take', `rows=${cached.gallerys.length}`)
    return cached.copy()
  }

  static async saveGalleryList(
    context: common.UIAbilityContext,
    cacheKey: string,
    list: GalleryList,
  ): Promise<void> {
    const snapshot: GalleryList = list.copy()
    if (snapshot.gallerys.length > MAX_LIST_ROWS_PER_CACHE) {
      snapshot.gallerys = snapshot.gallerys.slice(0, MAX_LIST_ROWS_PER_CACHE)
    }
    await EhPageCacheService.savePayload(
      context,
      CACHE_KIND_GALLERY_LIST,
      cacheKey,
      JSON.stringify(snapshot),
      LIST_TTL_MS,
    )
  }

  static async loadGalleryDetail(
    context: common.UIAbilityContext,
    cacheKey: string,
  ): Promise<GalleryDetailResult | null> {
    const payload: string = await EhPageCacheService.loadPayload(
      context,
      CACHE_KIND_GALLERY_DETAIL,
      cacheKey,
    )
    if (payload.length === 0) {
      return null
    }
    try {
      const raw: GalleryDetailResult = JSON.parse(payload) as GalleryDetailResult
      return EhPageCacheService.reviveGalleryDetail(raw)
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'gallery_detail_decode_failed', (error as Error).message)
      return null
    }
  }

  static async saveGalleryDetail(
    context: common.UIAbilityContext,
    cacheKey: string,
    detail: GalleryDetailResult,
  ): Promise<void> {
    const snapshot: GalleryDetailResult = new GalleryDetailResult(
      detail.gallery.copy(),
      detail.images.map((image: EhGalleryImage) => image.copy()),
      EhPageCacheService.copyComments(detail.comments),
      detail.previewPageCount,
    )
    await EhPageCacheService.savePayload(
      context,
      CACHE_KIND_GALLERY_DETAIL,
      cacheKey,
      JSON.stringify(snapshot),
      DETAIL_TTL_MS,
    )
  }

  private static scopedKey(isEx: boolean, body: string): string {
    const site: string = isEx ? 'exhentai' : 'e-hentai'
    return `${site}:member:${EhPageCacheService.accountKey()}:${body}`
  }

  private static accountKey(): string {
    const memberId: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
    return memberId.length > 0 ? EhPageCacheService.encode(memberId) : 'anon'
  }

  private static encode(value: string): string {
    return encodeURIComponent(value)
  }

  private static async loadPayload(
    context: common.UIAbilityContext,
    kind: string,
    cacheKey: string,
  ): Promise<string> {
    try {
      const now: number = Date.now()
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const args: relationalStore.ValueType[] = [kind, cacheKey, now]
      const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_CACHE, args)
      try {
        if (!resultSet.goToFirstRow()) {
          DiagnosticLogger.info('page-cache', 'load_miss', kind)
          return ''
        }
        const payloadIndex: number = resultSet.getColumnIndex('payload')
        const payload: string = resultSet.isColumnNull(payloadIndex)
          ? ''
          : resultSet.getString(payloadIndex)
        await store.executeSql(SQL_TOUCH_CACHE, [now, kind, cacheKey])
        DiagnosticLogger.info('page-cache', 'load_hit', `${kind} bytes=${payload.length}`)
        return payload
      } finally {
        resultSet.close()
      }
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'load_failed', (error as Error).message)
      return ''
    }
  }

  private static async savePayload(
    context: common.UIAbilityContext,
    kind: string,
    cacheKey: string,
    payload: string,
    ttlMs: number,
  ): Promise<void> {
    try {
      const now: number = Date.now()
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const args: relationalStore.ValueType[] = [kind, cacheKey, payload, now, now + ttlMs, now]
      await store.executeSql(SQL_UPSERT_CACHE, args)
      await store.executeSql(SQL_DELETE_EXPIRED_CACHE, [now])
      await store.executeSql(SQL_PRUNE_KIND_CACHE, [kind, kind, MAX_CACHE_ROWS_PER_KIND])
      DiagnosticLogger.info('page-cache', 'save_ok', `${kind} bytes=${payload.length}`)
    } catch (error) {
      DiagnosticLogger.warn('page-cache', 'save_failed', (error as Error).message)
    }
  }

  private static reviveGalleryList(raw: GalleryList): GalleryList {
    const out: GalleryList = new GalleryList()
    out.nextGid = EhPageCacheService.safeString(raw.nextGid)
    out.prevGid = EhPageCacheService.safeString(raw.prevGid)
    out.maxPage = EhPageCacheService.safeNumber(raw.maxPage)
    out.nextPage = EhPageCacheService.safeNumber(raw.nextPage, -1)
    out.prevPage = EhPageCacheService.safeNumber(raw.prevPage, -1)
    out.favOrder = EhPageCacheService.safeString(raw.favOrder)
    out.gallerys = EhPageCacheService.reviveGalleries(raw.gallerys)
    out.favList = EhPageCacheService.reviveFavcats(raw.favList)
    return out
  }

  private static reviveGalleryDetail(raw: GalleryDetailResult): GalleryDetailResult {
    return new GalleryDetailResult(
      EhPageCacheService.reviveGallery(raw.gallery),
      EhPageCacheService.reviveImages(raw.images),
      EhPageCacheService.reviveComments(raw.comments),
      EhPageCacheService.safeNumber(raw.previewPageCount, 1),
    )
  }

  private static reviveGalleries(raw: EhGallery[]): EhGallery[] {
    const rows: EhGallery[] = []
    if (raw === undefined || raw === null) {
      return rows
    }
    raw.forEach((g: EhGallery) => rows.push(EhPageCacheService.reviveGallery(g)))
    return rows
  }

  private static reviveGallery(raw: EhGallery): EhGallery {
    if (raw === undefined || raw === null) {
      return new EhGallery()
    }
    const g: EhGallery = new EhGallery(
      EhPageCacheService.safeString(raw.gid),
      EhPageCacheService.safeString(raw.token),
    )
    g.url = EhPageCacheService.safeString(raw.url)
    g.thumbUrl = EhPageCacheService.safeString(raw.thumbUrl)
    g.thumbUrlL = EhPageCacheService.safeString(raw.thumbUrlL)
    g.imgWidth = EhPageCacheService.safeNumber(raw.imgWidth)
    g.imgHeight = EhPageCacheService.safeNumber(raw.imgHeight)
    g.englishTitle = EhPageCacheService.safeString(raw.englishTitle)
    g.japaneseTitle = EhPageCacheService.safeString(raw.japaneseTitle)
    g.category = EhPageCacheService.safeString(raw.category)
    g.uploader = EhPageCacheService.safeString(raw.uploader)
    g.posted = EhPageCacheService.safeString(raw.posted)
    g.postTime = EhPageCacheService.safeString(raw.postTime)
    g.language = EhPageCacheService.safeString(raw.language)
    g.fileCount = EhPageCacheService.safeString(raw.fileCount)
    g.fileSize = EhPageCacheService.safeNumber(raw.fileSize)
    g.fileSizeText = EhPageCacheService.safeString(raw.fileSizeText)
    g.expunged = EhPageCacheService.safeBoolean(raw.expunged)
    g.rating = EhPageCacheService.safeNumber(raw.rating)
    g.ratingFallBack = EhPageCacheService.safeNumber(raw.ratingFallBack)
    g.ratingCount = EhPageCacheService.safeString(raw.ratingCount)
    g.numberOfReviews = EhPageCacheService.safeString(raw.numberOfReviews)
    g.colorRating = EhPageCacheService.safeString(raw.colorRating)
    g.isRated = EhPageCacheService.safeBoolean(raw.isRated)
    g.favcat = EhPageCacheService.safeString(raw.favcat)
    g.favTitle = EhPageCacheService.safeString(raw.favTitle)
    g.favNote = EhPageCacheService.safeString(raw.favNote)
    g.favoritedCount = EhPageCacheService.safeString(raw.favoritedCount)
    g.simpleTags = EhPageCacheService.reviveSimpleTags(raw.simpleTags)
    g.tagGroups = EhPageCacheService.reviveTagGroups(raw.tagGroups)
    g.translated = EhPageCacheService.safeString(raw.translated)
    g.torrentCount = EhPageCacheService.safeString(raw.torrentCount)
    g.archiverLink = EhPageCacheService.safeString(raw.archiverLink)
    g.visible = EhPageCacheService.safeString(raw.visible)
    g.parentTitle = EhPageCacheService.safeString(raw.parentTitle)
    g.parentUrl = EhPageCacheService.safeString(raw.parentUrl)
    g.parentGid = EhPageCacheService.safeString(raw.parentGid)
    g.parentToken = EhPageCacheService.safeString(raw.parentToken)
    g.newerVersions = EhPageCacheService.reviveGalleryVersions(raw.newerVersions)
    g.apiuid = EhPageCacheService.safeString(raw.apiuid)
    g.apikey = EhPageCacheService.safeString(raw.apikey)
    g.showKey = EhPageCacheService.safeString(raw.showKey)
    g.pageOfList = EhPageCacheService.safeNumber(raw.pageOfList)
    g.lastViewTime = EhPageCacheService.safeNumber(raw.lastViewTime)
    return g
  }

  private static reviveSimpleTags(raw: SimpleTag[]): SimpleTag[] {
    const tags: SimpleTag[] = []
    if (raw === undefined || raw === null) {
      return tags
    }
    raw.forEach((t: SimpleTag) => {
      const siteLabel: string = EhPageCacheService.safeString(t.siteLabel)
      const namespace: string = EhPageCacheService.safeString(t.namespace)
      const tag: SimpleTag = new SimpleTag(
        EhPageCacheService.safeString(t.text),
        siteLabel.length > 0
          ? EhPageCacheService.safeString(t.translat)
          : EhPageCacheService.stripLegacyGeneratedPrefix(
              namespace,
              EhPageCacheService.safeString(t.translat),
            ),
        namespace,
      )
      tag.siteLabel = siteLabel
      tag.color = EhPageCacheService.safeString(t.color)
      tag.backgroundColor = EhPageCacheService.safeString(t.backgroundColor)
      tag.vote = EhPageCacheService.safeNumber(t.vote)
      tags.push(tag)
    })
    return tags
  }

  private static stripLegacyGeneratedPrefix(namespace: string, translated: string): string {
    const prefix: string = `${EhConstants.compactNamespace(namespace)}:`
    if (prefix.length > 1 && translated.startsWith(prefix)) {
      return translated.substring(prefix.length)
    }
    return translated
  }

  private static reviveTagGroups(raw: TagGroup[]): TagGroup[] {
    const groups: TagGroup[] = []
    if (raw === undefined || raw === null) {
      return groups
    }
    raw.forEach((g: TagGroup) => {
      groups.push(
        new TagGroup(
          EhPageCacheService.safeString(g.namespace),
          EhPageCacheService.reviveSimpleTags(g.tags),
        ),
      )
    })
    return groups
  }

  private static reviveGalleryVersions(raw: EhGalleryVersion[]): EhGalleryVersion[] {
    const versions: EhGalleryVersion[] = []
    if (raw === undefined || raw === null) {
      return versions
    }
    raw.forEach((item: EhGalleryVersion) => {
      const gid: string = EhPageCacheService.safeString(item.gid)
      const token: string = EhPageCacheService.safeString(item.token)
      if (gid.length === 0 || token.length === 0) {
        return
      }
      const version: EhGalleryVersion = new EhGalleryVersion()
      version.gid = gid
      version.token = token
      version.title = EhPageCacheService.safeString(item.title)
      version.posted = EhPageCacheService.safeString(item.posted)
      versions.push(version)
    })
    return versions
  }

  private static reviveFavcats(raw: Favcat[]): Favcat[] {
    const favcats: Favcat[] = []
    if (raw === undefined || raw === null) {
      return favcats
    }
    raw.forEach((f: Favcat) => {
      favcats.push(
        new Favcat(
          EhPageCacheService.safeString(f.favId),
          EhPageCacheService.safeString(f.favTitle),
          EhPageCacheService.safeNumber(f.totNum),
          EhPageCacheService.safeBoolean(f.isPlaceholder),
        ),
      )
    })
    return favcats
  }

  private static reviveImages(raw: EhGalleryImage[]): EhGalleryImage[] {
    const images: EhGalleryImage[] = []
    if (raw === undefined || raw === null) {
      return images
    }
    raw.forEach((image: EhGalleryImage) => {
      const next: EhGalleryImage = new EhGalleryImage(EhPageCacheService.safeNumber(image.page))
      next.imgkey = EhPageCacheService.safeString(image.imgkey)
      next.sUrl = EhPageCacheService.safeString(image.sUrl)
      next.thumbUrl = EhPageCacheService.safeString(image.thumbUrl)
      next.thumbWidth = EhPageCacheService.safeNumber(image.thumbWidth)
      next.thumbHeight = EhPageCacheService.safeNumber(image.thumbHeight)
      next.thumbOffsetX = EhPageCacheService.safeNumber(image.thumbOffsetX)
      next.spriteWidth = EhPageCacheService.safeNumber(image.spriteWidth)
      next.spriteHeight = EhPageCacheService.safeNumber(image.spriteHeight)
      next.imageUrl = EhPageCacheService.safeString(image.imageUrl)
      next.originImageUrl = EhPageCacheService.safeString(image.originImageUrl)
      next.showKey = EhPageCacheService.safeString(image.showKey)
      next.reloadKey = EhPageCacheService.safeString(image.reloadKey)
      images.push(next)
    })
    return images
  }

  private static reviveComments(raw: EhGalleryComment[]): EhGalleryComment[] {
    const comments: EhGalleryComment[] = []
    if (raw === undefined || raw === null) {
      return comments
    }
    raw.forEach((c: EhGalleryComment) => {
      const comment: EhGalleryComment = new EhGalleryComment()
      comment.commentId = EhPageCacheService.safeString(c.commentId)
      comment.memberId = EhPageCacheService.safeString(c.memberId)
      comment.author = EhPageCacheService.safeString(c.author)
      comment.postedTime = EhPageCacheService.safeString(c.postedTime)
      comment.contentText = EhPageCacheService.safeString(c.contentText)
      comment.contentLinks = EhPageCacheService.copyCommentLinks(c.contentLinks)
      comment.contentSpans = EhPageCacheService.copyCommentSpans(c.contentSpans)
      comment.score = EhPageCacheService.safeString(c.score)
      comment.vote = EhPageCacheService.safeNumber(c.vote)
      comment.canEdit = EhPageCacheService.safeBoolean(c.canEdit)
      comment.canVote = EhPageCacheService.safeBoolean(c.canVote)
      comment.scoreDetails = EhPageCacheService.copyStringArray(c.scoreDetails)
      comment.isUploader = EhPageCacheService.safeBoolean(c.isUploader)
      comment.translationText = EhPageCacheService.safeString(c.translationText)
      comment.translationSpans = EhPageCacheService.copyCommentSpans(c.translationSpans)
      comment.translationShown = EhPageCacheService.safeBoolean(c.translationShown)
      comment.translationLoading = EhPageCacheService.safeBoolean(c.translationLoading)
      comment.translationAutoStarted = EhPageCacheService.safeBoolean(c.translationAutoStarted)
      comments.push(comment)
    })
    return comments
  }

  private static copyComments(comments: EhGalleryComment[]): EhGalleryComment[] {
    return EhPageCacheService.reviveComments(comments)
  }

  private static copyCommentLinks(raw: EhGalleryCommentLink[]): EhGalleryCommentLink[] {
    const out: EhGalleryCommentLink[] = []
    if (raw === undefined || raw === null) {
      return out
    }
    raw.forEach((value: EhGalleryCommentLink) => {
      const link: EhGalleryCommentLink = new EhGalleryCommentLink()
      link.start = EhPageCacheService.safeNumber(value.start)
      link.end = EhPageCacheService.safeNumber(value.end)
      link.url = EhPageCacheService.safeString(value.url)
      out.push(link)
    })
    return out
  }

  private static copyCommentSpans(raw: EhGalleryCommentTextSpan[]): EhGalleryCommentTextSpan[] {
    const out: EhGalleryCommentTextSpan[] = []
    if (raw === undefined || raw === null) {
      return out
    }
    raw.forEach((value: EhGalleryCommentTextSpan) => {
      const span: EhGalleryCommentTextSpan = new EhGalleryCommentTextSpan()
      span.start = EhPageCacheService.safeNumber(value.start)
      span.end = EhPageCacheService.safeNumber(value.end)
      span.url = EhPageCacheService.safeString(value.url)
      span.bold = EhPageCacheService.safeBoolean(value.bold)
      span.italic = EhPageCacheService.safeBoolean(value.italic)
      span.underline = EhPageCacheService.safeBoolean(value.underline)
      span.strike = EhPageCacheService.safeBoolean(value.strike)
      span.color = EhPageCacheService.safeString(value.color)
      out.push(span)
    })
    return out
  }

  private static copyStringArray(raw: string[]): string[] {
    const out: string[] = []
    if (raw === undefined || raw === null) {
      return out
    }
    raw.forEach((value: string) => out.push(EhPageCacheService.safeString(value)))
    return out
  }

  private static safeString(value: string | null | undefined): string {
    return typeof value === 'string' ? value : ''
  }

  private static safeNumber(value: number | null | undefined, fallback: number = 0): number {
    return typeof value === 'number' ? value : fallback
  }

  private static safeBoolean(value: boolean | null | undefined): boolean {
    return typeof value === 'boolean' ? value : false
  }
}
