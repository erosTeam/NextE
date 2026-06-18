/**
 * Centralized preference / AppStorageV2 key strings.
 *
 * Convention (from V2Next): persisted preference keys are plain dotted names; the
 * matching AppStorageV2 mirror key is 'v2:<holderName>' and lives next to its holder.
 * Keeping every key here prevents silent typos and key collisions across settings.
 */
export class StorageKeys {
  // preferences store name
  static readonly STORE_SETTINGS: string = 'nexte_settings'

  // settings keys
  static readonly SITE_MODE_EX: string = 'site.modeEx' // boolean: 表站(false)/里站(true)
  static readonly LIST_MODE: string = 'layout.listMode' // list/simpleList/grid/waterfall
  static readonly LIST_ITEM_FIXED_HEIGHT: string = 'layout.fixedHeightOfListItems' // boolean: fixed(true)/adaptive list rows
  static readonly ITEM_WIDTH: string = 'layout.itemWidth'
  static readonly HIDE_GALLERY_THUMBNAILS: string = 'layout.hideGalleryThumbnails' // boolean: hide detail inline previews
  static readonly HORIZONTAL_THUMBNAILS: string = 'layout.horizontalThumbnails' // boolean: horizontal vs grid preview
  static readonly THEME_MODE: string = 'theme.mode' // system/light/dark
  static readonly LANGUAGE: string = 'app.language' // system/zh-CN/en-US/ja-JP
  static readonly SEARCH_HISTORY: string = 'search.history' // JSON array of recent query strings
  static readonly SEARCH_FILTER: string = 'search.filter' // JSON snapshot of advanced-search filters
  static readonly VIEWED_HISTORY: string = 'viewed.history' // JSON [ViewedGallery] recently-viewed, newest first
  static readonly READING_DIRECTION: string = 'reading.direction' // ltr/rtl/vertical
  static readonly READING_PROGRESS: string = 'reading.progress' // JSON [{g,i,t}] per-gallery lastIndex
  static readonly READING_DOUBLE_PAGE: string = 'reading.doublePage'
  static readonly READING_VOLUME_KEY: string = 'reading.volumeKeyTurn'
  static readonly READING_AUTO_PAGE_SEC: string = 'reading.autoPageSeconds'
  static readonly DOWNLOAD_DIR: string = 'download.dir'
  static readonly DOWNLOAD_CONCURRENCY: string = 'download.concurrency'
  static readonly DOWNLOAD_ORIGINAL: string = 'download.original'
  static readonly DOWNLOAD_GALLERY_QUEUE: string = 'download.galleryQueue'

  // sensitive auth bundle (redacted in logs, never committed)
  static readonly COOKIE_JAR: string = 'auth.cookieJar'
}
