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
  // Per-mode column min-width (vp) overrides from pinch-zoom / slider. 0 = use base constant.
  static readonly GRID_COLUMN_WIDTH: string = 'layout.gridColumnWidth'
  static readonly WATERFALL_COLUMN_WIDTH: string = 'layout.waterfallColumnWidth'
  static readonly COVER_WALL_COLUMN_WIDTH: string = 'layout.coverWallColumnWidth'
  static readonly JAPANESE_TITLE_IN_GALLERY_PAGE: string = 'layout.japaneseTitleInGalleryPage'
  static readonly ITEM_WIDTH: string = 'layout.itemWidth'
  static readonly HIDE_GALLERY_THUMBNAILS: string = 'layout.hideGalleryThumbnails' // boolean: hide detail inline previews
  static readonly HORIZONTAL_THUMBNAILS: string = 'layout.horizontalThumbnails' // boolean: horizontal vs grid preview
  static readonly BLURRING_OF_COVER_BACKGROUND: string = 'layout.blurringOfCoverBackground' // boolean: blur off-aspect cover background (else color gradient)
  static readonly ACTION_ALIGNMENT_MODE: string = 'layout.actionAlignmentMode' // floating Read button: smartGrip/followOperation/fixedLeft/fixedRight
  static readonly READ_BUTTON_STYLE: string = 'layout.readButtonStyle' // filled/hds floating Read button style
  static readonly THEME_MODE: string = 'theme.mode' // system/light/dark
  static readonly THEME_COLOR: string = 'theme.color' // accent: system/blue/orange/red/purple/pink/green
  static readonly IMMERSIVE_MATERIAL_LEVEL: string = 'theme.immersiveMaterialLevel' // adaptive/exquisite/gentle/smooth
  static readonly LANGUAGE: string = 'app.language' // system/zh-CN/en-US/ja-JP
  static readonly SEARCH_HISTORY: string = 'search.history' // JSON array of recent query strings
  static readonly SEARCH_FILTER: string = 'search.filter' // JSON snapshot of advanced-search filters
  static readonly FAVORITES_FAVCATS: string = 'favorites.favcats' // JSON [Favcat] selector snapshot
  static readonly LOCAL_FAVORITES: string = 'favorites.local' // JSON [EhGallery] local-only favorites
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
  static readonly SECURITY_AUTO_LOCK_SEC: string = 'security.autoLockSeconds'
  static readonly HOME_SOURCE: string = 'subtab.homeSource'
  static readonly FAVORITES_FAVCAT: string = 'subtab.favoritesFavcat'
  static readonly TOPLIST_TL: string = 'subtab.toplistTl'
  // Custom home sub-tab profiles (JSON array) + the selected profile uuid.
  static readonly HOME_CUSTOM_PROFILES: string = 'subtab.customProfiles'
  static readonly HOME_CUSTOM_PROFILES_SELECTED: string = 'subtab.customProfilesSelected'
  static readonly TOPLIST_APPLY_HIDDEN_USER_TAGS: string = 'toplist.applyHiddenUserTags'
  static readonly APP_COLOR_FAVORITES: string = 'app.colorFavorites'
  static readonly HOME_TAB_AUTO_HIDE: string = 'home.tabAutoHide'
  static readonly TAG_TRANSLATION_ENABLED: string = 'tagTranslation.enabled'
  static readonly TAG_TRANSLATION_USE_CDN: string = 'tagTranslation.useCdn'
  static readonly TAG_TRANSLATION_UPDATE_MODE: string = 'tagTranslation.updateMode'
  static readonly TAG_TRANSLATION_INTRO_IMAGE_LEVEL: string = 'tagTranslation.introImageLevel'
  static readonly COMMENT_TRANSLATION_ENABLED: string = 'commentTranslation.enabled'
  static readonly COMMENT_TRANSLATION_AUTO: string = 'commentTranslation.auto'
  static readonly COMMENT_TRANSLATION_DISPLAY_MODE: string = 'commentTranslation.displayMode'
  static readonly COMMENT_TRANSLATION_GOOGLE_ONLY: string = 'commentTranslation.googleOnly'
  static readonly COMMENT_TRANSLATION_API_URL: string = 'commentTranslation.apiUrl'
  static readonly COMMENT_TRANSLATION_API_KEY: string = 'commentTranslation.apiKey'
  static readonly COMMENT_TRANSLATION_MODEL: string = 'commentTranslation.model'
  static readonly LOCAL_BLOCK_RULES: string = 'localBlock.rules'
  static readonly DIAGNOSTICS_ENABLED: string = 'diagnostics.enabled'
  static readonly DIAGNOSTICS_MIN_LEVEL: string = 'diagnostics.minLevel'

  // sensitive auth bundle (redacted in logs, never committed)
  static readonly COOKIE_JAR: string = 'auth.cookieJar'
}
