import { SimpleTag } from './SimpleTag'
import { TagGroup } from './TagGroup'

export class EhGalleryVersion {
  gid: string = ''
  token: string = ''
  title: string = ''
  posted: string = ''

  copy(): EhGalleryVersion {
    const v: EhGalleryVersion = new EhGalleryVersion()
    v.gid = this.gid
    v.token = this.token
    v.title = this.title
    v.posted = this.posted
    return v
  }
}

/**
 * Aggregate root for an EH gallery. It accumulates from up to three sources:
 *   1. the list-page parse (thumb, title, category, rating, uploader, favcat)
 *   2. the /api.php gdata batch (canonical metadata enrich)
 *   3. the /g/{gid}/{token} detail parse (tags, comments, images, apikey/apiuid, showKey)
 *
 * `merge(other)` folds a newer/richer source onto this one without dropping known fields
 * (non-empty wins). Hand-written field-by-field — ArkTS forbids destructuring/spread, so
 * porting eros_fe's GalleryProvider means an explicit field list + copy()/merge().
 * M1 carries the list-relevant fields; M2 adds tagGroups/comments/images.
 */
export class EhGallery {
  // identity
  gid: string = ''
  token: string = ''
  url: string = ''

  // thumbnail / cover
  thumbUrl: string = '' // imgUrl (list thumb)
  thumbUrlL: string = '' // imgUrlL (large)
  imgWidth: number = 0
  imgHeight: number = 0

  // titles
  englishTitle: string = ''
  japaneseTitle: string = ''

  // meta
  category: string = ''
  uploader: string = ''
  posted: string = '' // raw posted timestamp string from list
  postTime: string = '' // formatted post time
  language: string = ''
  fileCount: string = ''
  fileSize: number = 0
  fileSizeText: string = ''
  expunged: boolean = false

  // rating
  rating: number = 0 // resolved star rating 0..5
  ratingFallBack: number = 0 // rating before personal vote
  ratingCount: string = ''
  numberOfReviews: string = ''
  colorRating: string = '' // '' for community/default `ir`; `irr`/`irg`/`irb` for personal rating variants
  isRated: boolean = false

  // favorites
  favcat: string = '' // '0'..'9' or '' if not favorited
  favTitle: string = '' // favcat display name
  favNote: string = ''
  favoritedCount: string = ''

  // tags (list-level simple tags; detail-level grouped tags)
  simpleTags: SimpleTag[] = []
  tagGroups: TagGroup[] = []
  translated: string = ''

  // detail-page extras (read): torrent count + parent/newer-version links
  torrentCount: string = ''
  // EH archiver entry. Modern EH detail pages expose the full archiver.php?gid&token URL; older
  // pages may still only carry an `or` token. The network layer accepts either form.
  archiverLink: string = ''
  visible: string = ''
  parentTitle: string = ''
  parentUrl: string = ''
  parentGid: string = ''
  parentToken: string = ''
  newerVersions: EhGalleryVersion[] = []

  // api credentials scraped from detail HTML (needed for /api.php mutating calls)
  apiuid: string = ''
  apikey: string = ''
  showKey: string = ''

  // list bookkeeping
  pageOfList: number = 0
  lastViewTime: number = 0

  constructor(gid: string = '', token: string = '') {
    this.gid = gid
    this.token = token
  }

  /** Title to render: English primary, Japanese fallback (caller may invert per setting). */
  title(): string {
    return this.englishTitle.length > 0 ? this.englishTitle : this.japaneseTitle
  }

  fileCountNumber(): number {
    return EhGallery.parseFileCount(this.fileCount)
  }

  static parseFileCount(value: string): number {
    const normalized: string = value.replace(/[,，\s]/g, '')
    if (normalized.length === 0 || !/^[0-9]+$/.test(normalized)) {
      return 0
    }
    return Number.parseInt(normalized, 10)
  }

  displayTitle(japanesePrimary: boolean): string {
    if (japanesePrimary && this.japaneseTitle.length > 0) {
      return this.japaneseTitle
    }
    return this.title()
  }

  secondaryTitle(japanesePrimary: boolean): string {
    if (japanesePrimary) {
      return this.englishTitle.length > 0 && this.englishTitle !== this.displayTitle(true)
        ? this.englishTitle
        : ''
    }
    return this.japaneseTitle.length > 0 && this.japaneseTitle !== this.title()
      ? this.japaneseTitle
      : ''
  }

  /** LazyForEach identity must change when async tag translation fills display text. */
  renderKey(): string {
    let key: string = `${this.gid}:${this.translated}`
    for (let i = 0; i < this.simpleTags.length; i++) {
      const tag: SimpleTag = this.simpleTags[i]
      key = `${key}:${tag.namespace}:${tag.text}:${tag.siteLabel}:${tag.translat}`
    }
    for (let i = 0; i < this.tagGroups.length; i++) {
      const group: TagGroup = this.tagGroups[i]
      key = `${key}:${group.namespace}`
      for (let j = 0; j < group.tags.length; j++) {
        const tag: SimpleTag = group.tags[j]
        key = `${key}:${tag.text}:${tag.translat}`
      }
    }
    return `gallery_${EhGallery.safeKeyPart(this.gid)}_${EhGallery.keyHash(key)}`
  }

  private static safeKeyPart(value: string): string {
    const safe: string = value.replace(/[^A-Za-z0-9_]/g, '_')
    return safe.length > 0 ? safe : 'empty'
  }

  private static keyHash(value: string): string {
    let hash: number = 2166136261
    for (let i = 0; i < value.length; i++) {
      hash = hash ^ value.charCodeAt(i)
      hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0).toString(36)
  }

  /**
   * Cleaned title for a "similar" search (eros_fe `shortTitle`): strip [..]/(..)/{..} groups,
   * trim, and keep only the part before the first `|`. Used as `title:"<shortTitle>"`.
   */
  shortTitle(): string {
    let s: string = this.title()
    s = s.replace(/\[[^\]]*\]/g, '')
    s = s.replace(/\([^)]*\)/g, '')
    s = s.replace(/\{[^}]*\}/g, '')
    s = s.trim()
    const bar: number = s.indexOf('|')
    if (bar >= 0) {
      s = s.substring(0, bar)
    }
    return s.trim()
  }

  copy(): EhGallery {
    const g: EhGallery = new EhGallery(this.gid, this.token)
    g.url = this.url
    g.thumbUrl = this.thumbUrl
    g.thumbUrlL = this.thumbUrlL
    g.imgWidth = this.imgWidth
    g.imgHeight = this.imgHeight
    g.englishTitle = this.englishTitle
    g.japaneseTitle = this.japaneseTitle
    g.category = this.category
    g.uploader = this.uploader
    g.posted = this.posted
    g.postTime = this.postTime
    g.language = this.language
    g.fileCount = this.fileCount
    g.fileSize = this.fileSize
    g.fileSizeText = this.fileSizeText
    g.expunged = this.expunged
    g.rating = this.rating
    g.ratingFallBack = this.ratingFallBack
    g.ratingCount = this.ratingCount
    g.numberOfReviews = this.numberOfReviews
    g.colorRating = this.colorRating
    g.isRated = this.isRated
    g.favcat = this.favcat
    g.favTitle = this.favTitle
    g.favNote = this.favNote
    g.favoritedCount = this.favoritedCount
    g.simpleTags = this.simpleTags.map((t: SimpleTag) => t.copy())
    g.tagGroups = this.tagGroups.map((tg: TagGroup) => tg.copy())
    g.translated = this.translated
    g.torrentCount = this.torrentCount
    g.archiverLink = this.archiverLink
    g.visible = this.visible
    g.parentTitle = this.parentTitle
    g.parentUrl = this.parentUrl
    g.parentGid = this.parentGid
    g.parentToken = this.parentToken
    g.newerVersions = this.newerVersions.map((v: EhGalleryVersion) => v.copy())
    g.apiuid = this.apiuid
    g.apikey = this.apikey
    g.showKey = this.showKey
    g.pageOfList = this.pageOfList
    g.lastViewTime = this.lastViewTime
    return g
  }

  /** Fold a richer source onto a copy of this gallery; non-empty/non-zero values win. */
  merge(o: EhGallery): EhGallery {
    const g: EhGallery = this.copy()
    if (o.url.length > 0) g.url = o.url
    if (o.thumbUrl.length > 0) g.thumbUrl = o.thumbUrl
    if (o.thumbUrlL.length > 0) g.thumbUrlL = o.thumbUrlL
    if (o.imgWidth > 0) g.imgWidth = o.imgWidth
    if (o.imgHeight > 0) g.imgHeight = o.imgHeight
    if (o.englishTitle.length > 0) g.englishTitle = o.englishTitle
    if (o.japaneseTitle.length > 0) g.japaneseTitle = o.japaneseTitle
    if (o.category.length > 0) g.category = o.category
    if (o.uploader.length > 0) g.uploader = o.uploader
    if (o.posted.length > 0) g.posted = o.posted
    if (o.postTime.length > 0) g.postTime = o.postTime
    if (o.language.length > 0) g.language = o.language
    if (o.fileCount.length > 0) g.fileCount = o.fileCount
    if (o.fileSize > 0) g.fileSize = o.fileSize
    if (o.fileSizeText.length > 0) g.fileSizeText = o.fileSizeText
    if (o.expunged) g.expunged = o.expunged
    if (o.rating > 0) g.rating = o.rating
    if (o.ratingFallBack > 0) g.ratingFallBack = o.ratingFallBack
    if (o.ratingCount.length > 0) g.ratingCount = o.ratingCount
    if (o.numberOfReviews.length > 0) g.numberOfReviews = o.numberOfReviews
    if (o.colorRating.length > 0) g.colorRating = o.colorRating
    if (o.isRated) g.isRated = o.isRated
    if (o.favcat.length > 0) g.favcat = o.favcat
    if (o.favTitle.length > 0) g.favTitle = o.favTitle
    if (o.favNote.length > 0) g.favNote = o.favNote
    if (o.favoritedCount.length > 0) g.favoritedCount = o.favoritedCount
    if (o.simpleTags.length > 0) g.simpleTags = o.simpleTags.map((t: SimpleTag) => t.copy())
    if (o.tagGroups.length > 0) g.tagGroups = o.tagGroups.map((tg: TagGroup) => tg.copy())
    if (o.translated.length > 0) g.translated = o.translated
    if (o.torrentCount.length > 0) g.torrentCount = o.torrentCount
    if (o.archiverLink.length > 0) g.archiverLink = o.archiverLink
    if (o.visible.length > 0) g.visible = o.visible
    if (o.parentTitle.length > 0) g.parentTitle = o.parentTitle
    if (o.parentUrl.length > 0) g.parentUrl = o.parentUrl
    if (o.parentGid.length > 0) g.parentGid = o.parentGid
    if (o.parentToken.length > 0) g.parentToken = o.parentToken
    if (o.newerVersions.length > 0) g.newerVersions = o.newerVersions.map((v: EhGalleryVersion) => v.copy())
    if (o.apiuid.length > 0) g.apiuid = o.apiuid
    if (o.apikey.length > 0) g.apikey = o.apikey
    if (o.showKey.length > 0) g.showKey = o.showKey
    return g
  }
}
