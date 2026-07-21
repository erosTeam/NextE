/**
 * Centralized preference / AppStorageV2 key strings.
 *
 * Convention (from V2Next): persisted preference keys are plain dotted names; the
 * matching AppStorageV2 mirror key uses the v2_ prefix and lives next to its holder.
 * Keeping every key here prevents silent typos and key collisions across settings.
 */
export class StorageKeys {
  // preferences store name
  static readonly STORE_SETTINGS: string = 'nexte_settings'

  // settings keys
  static readonly SITE_MODE_EX: string = 'site.modeEx' // boolean: 表站(false)/里站(true)
  static readonly LIST_MODE: string = 'layout.listMode' // list/simpleList/grid/waterfall/waterfallCompact/coverWall
  static readonly LIST_ITEM_FIXED_HEIGHT: string = 'layout.fixedHeightOfListItems' // boolean: fixed(true)/adaptive list rows
  // Per-mode column min-width (vp) overrides from pinch-zoom / slider. 0 = use base constant.
  static readonly GRID_COLUMN_WIDTH: string = 'layout.gridColumnWidth'
  static readonly WATERFALL_COLUMN_WIDTH: string = 'layout.waterfallColumnWidth'
  static readonly WATERFALL_COMPACT_COLUMN_WIDTH: string = 'layout.waterfallCompactColumnWidth'
  static readonly COVER_WALL_COLUMN_WIDTH: string = 'layout.coverWallColumnWidth'
  static readonly THUMBNAIL_COLUMN_WIDTH: string = 'layout.thumbnailColumnWidth'
  static readonly JAPANESE_TITLE_IN_GALLERY_PAGE: string = 'layout.japaneseTitleInGalleryPage'
  static readonly ITEM_WIDTH: string = 'layout.itemWidth'
  static readonly HIDE_GALLERY_THUMBNAILS: string = 'layout.hideGalleryThumbnails' // boolean: hide detail inline previews
  static readonly HORIZONTAL_THUMBNAILS: string = 'layout.horizontalThumbnails' // boolean: horizontal vs grid preview
  static readonly BLURRING_OF_COVER_BACKGROUND: string = 'layout.blurringOfCoverBackground' // boolean: blur off-aspect cover background (else color gradient)
  static readonly ACTION_ALIGNMENT_MODE: string = 'layout.actionAlignmentMode' // floating Read button: smartGrip/followOperation/fixedLeft/fixedRight
  static readonly READ_BUTTON_STYLE: string = 'layout.readButtonStyle' // filled/hds floating Read button style
  static readonly SCREEN_ORIENTATION: string = 'layout.screenOrientation' // unspecified/autoRotationUnspecified
  static readonly TABLET_LAYOUT_MODE: string = 'layout.tabletLayoutMode' // auto/off/landscapeOnly
  static readonly THEME_MODE: string = 'theme.mode' // system/light/dark
  static readonly THEME_COLOR: string = 'theme.color' // accent: system/blue/orange/red/purple/pink/green
  static readonly IMMERSIVE_MATERIAL_LEVEL: string = 'theme.immersiveMaterialLevel' // adaptive/exquisite/gentle/smooth
  static readonly LANGUAGE: string = 'app.language' // system/zh-CN/en-US/ja-JP
  static readonly SEARCH_HISTORY: string = 'search.history' // legacy Preferences key; RDB source of truth
  static readonly SEARCH_HISTORY_TRANSLATE: string = 'search.history.translate'
  static readonly SEARCH_FILTER: string = 'search.filter' // JSON snapshot of advanced-search filters
  static readonly FAVORITES_FAVCATS: string = 'favorites.favcats' // JSON [Favcat] selector snapshot
  static readonly LOCAL_FAVORITES: string = 'favorites.local' // legacy Preferences key; RDB source of truth
  static readonly VIEWED_HISTORY: string = 'viewed.history' // legacy Preferences key; RDB source of truth
  static readonly READING_DIRECTION: string = 'reading.direction' // ltr/rtl/topToBottom/vertical
  static readonly READING_PROGRESS: string = 'reading.progress' // legacy Preferences key; RDB source of truth
  static readonly READING_DOUBLE_PAGE: string = 'reading.doublePage'
  static readonly READING_SPREAD_LAYOUT: string = 'reading.spreadLayout'
  static readonly READING_VOLUME_KEY: string = 'reading.volumeKeyTurn'
  static readonly READING_AUTO_PAGE_SEC: string = 'reading.autoPageSeconds'
  static readonly READING_PRELOAD_PAGES: string = 'reading.preloadPages'
  static readonly READING_TAP_ZONE_LAYOUT: string = 'reading.tapZoneLayout'
  static readonly READING_TAP_ZONE_INVERT: string = 'reading.tapZoneInvert'
  static readonly READING_BACKGROUND_MODE: string = 'reading.backgroundMode'
  static readonly READING_IMAGE_SCALING_QUALITY: string = 'reading.imageScalingQuality'
  static readonly READING_SUPER_RESOLUTION_ENABLED: string = 'reading.superResolutionEnabled'
  static readonly READING_SUPER_RESOLUTION_MODEL: string = 'reading.superResolutionModel'
  static readonly READING_SUPER_RESOLUTION_MAX_HEIGHT: string = 'reading.superResolutionMaxHeight'
  static readonly READING_SHOW_PAGE_NUMBER: string = 'reading.showPageNumber'
  static readonly READING_FULLSCREEN: string = 'reading.fullscreen'
  static readonly READING_KEEP_SCREEN_ON: string = 'reading.keepScreenOn'
  static readonly READING_PAGE_TURN_ANIMATION: string = 'reading.pageTurnAnimation'
  static readonly READER_IMAGE_CACHE_LIMIT_MB: string = 'cache.readerImageLimitMb'
  static readonly DOWNLOAD_CONCURRENCY: string = 'download.concurrency'
  static readonly DOWNLOAD_REQUEST_INTERVAL_SECONDS: string = 'download.requestIntervalSeconds'
  static readonly DOWNLOAD_RETRY_COUNT: string = 'download.retryCount'
  static readonly DOWNLOAD_AUTO_RETRY_FAILED: string = 'download.autoRetryFailed'
  static readonly DOWNLOAD_SPEED_LIMIT_KBPS: string = 'download.speedLimitKbps'
  static readonly DOWNLOAD_NOTIFY_ON_COMPLETE: string = 'download.notifyOnComplete'
  static readonly DOWNLOAD_HIDE_FROM_MEDIA_LIBRARY: string = 'download.hideFromMediaLibrary'
  static readonly DOWNLOAD_ORIGINAL: string = 'download.original'
  static readonly DOWNLOAD_ARCHIVE_BOT_TYPE: string = 'download.archiveBot.type'
  static readonly DOWNLOAD_ARCHIVE_BOT_ADDRESS: string = 'download.archiveBot.address'
  static readonly DOWNLOAD_ARCHIVE_BOT_API_KEY: string = 'download.archiveBot.apiKey'
  static readonly DOWNLOAD_ARCHIVE_BOT_BALANCE_GP: string = 'download.archiveBot.balanceGp'
  static readonly DOWNLOAD_ARCHIVE_BOT_BALANCE_UPDATED_AT: string = 'download.archiveBot.balanceUpdatedAt'
  static readonly DOWNLOAD_GALLERY_QUEUE: string = 'download.galleryQueue' // legacy Preferences key; RDB source of truth
  static readonly SECURITY_RECENT_TASKS_PROTECTION: string = 'security.recentTasksProtection'
  static readonly SECURITY_AUTO_LOCK_SEC: string = 'security.autoLockSeconds'
  static readonly SECURITY_LAST_BACKGROUND_AT: string = 'security.lastBackgroundAt'
  static readonly HOME_SOURCE: string = 'subtab.homeSource'
  static readonly FAVORITES_FAVCAT: string = 'subtab.favoritesFavcat'
  static readonly TOPLIST_TL: string = 'subtab.toplistTl'
  static readonly WEB_LOGIN_BEAUTIFY_ENABLED: string = 'login.webBeautifyEnabled'
  // Custom home sub-tab profiles (JSON array) + the selected profile uuid.
  static readonly HOME_CUSTOM_PROFILES: string = 'subtab.customProfiles' // legacy Preferences key; RDB source of truth
  static readonly HOME_CUSTOM_PROFILES_SELECTED: string = 'subtab.customProfilesSelected' // legacy Preferences key; RDB source of truth
  static readonly TOPLIST_APPLY_HIDDEN_USER_TAGS: string = 'toplist.applyHiddenUserTags'
  static readonly CLIPBOARD_LINK_ENABLED: string = 'clipboardLink.enabled'
  static readonly CLIPBOARD_LINK_CHANGE_COUNT: string = 'clipboardLink.changeCount'
  static readonly APP_COLOR_FAVORITES: string = 'app.colorFavorites'
  static readonly HOME_TAB_AUTO_HIDE: string = 'home.tabAutoHide'
  static readonly TAG_TRANSLATION_ENABLED: string = 'tagTranslation.enabled'
  static readonly TAG_TRANSLATION_USE_CDN: string = 'tagTranslation.useCdn'
  static readonly TAG_TRANSLATION_UPDATE_MODE: string = 'tagTranslation.updateMode'
  static readonly TAG_TRANSLATION_INTRO_IMAGE_LEVEL: string = 'tagTranslation.introImageLevel'
  static readonly IMAGE_BLOCK_ENABLED: string = 'imageBlock.enabled'
  static readonly COMMENT_TRANSLATION_ENABLED: string = 'commentTranslation.enabled'
  static readonly COMMENT_TRANSLATION_AUTO: string = 'commentTranslation.auto'
  static readonly COMMENT_TRANSLATION_DISPLAY_MODE: string = 'commentTranslation.displayMode'
  static readonly COMMENT_TRANSLATION_GOOGLE_ONLY: string = 'commentTranslation.googleOnly'
  static readonly COMMENT_TRANSLATION_API_URL: string = 'commentTranslation.apiUrl'
  static readonly COMMENT_TRANSLATION_API_KEY: string = 'commentTranslation.apiKey'
  static readonly COMMENT_TRANSLATION_MODEL: string = 'commentTranslation.model'
  static readonly COMMENT_TRANSLATION_LLM_SOURCE_PROFILE: string = 'commentTranslation.llmSourceProfile'
  static readonly COMMENT_TRANSLATION_LLM_MODEL: string = 'commentTranslation.llmModel'
  static readonly COMIC_TRANSLATION_PROVIDER: string = 'comicTranslation.provider'
  static readonly COMIC_TRANSLATION_API_URL: string = 'comicTranslation.apiUrl'
  static readonly COMIC_TRANSLATION_API_KEY: string = 'comicTranslation.apiKey'
  static readonly COMIC_TRANSLATION_API_MODEL: string = 'comicTranslation.apiModel'
  static readonly COMIC_TRANSLATION_CODEX_MODEL: string = 'comicTranslation.codexModel'
  // Device-local rotating credential. Never sync or copy through backup, including encrypted backup.
  static readonly COMIC_TRANSLATION_CODEX_OAUTH_TOKEN: string = 'comicTranslation.codexOAuthToken'
  // Device-local stale-while-revalidate snapshot. Never sync or copy through backup.
  static readonly COMIC_TRANSLATION_CODEX_USAGE_CACHE: string = 'comicTranslation.codexUsageCache'
  static readonly COMIC_TRANSLATION_LLM_SOURCE_PROFILE: string = 'comicTranslation.llmSourceProfile'
  static readonly COMIC_TRANSLATION_LLM_MODEL: string = 'comicTranslation.llmModel'
  static readonly COMIC_TRANSLATION_VISUAL_ROUTE: string = 'comicTranslation.visualRoute'
  static readonly COMIC_TRANSLATION_TORII_MODEL: string = 'comicTranslation.torii.model'
  static readonly COMIC_TRANSLATION_TORII_BILLING_MODE: string =
    'comicTranslation.torii.billingMode'
  static readonly COMIC_TRANSLATION_TORII_BYOK_PROVIDER: string =
    'comicTranslation.torii.byokProvider'
  // Torii account and optional upstream BYOK secrets. Encrypted backup only; never sync.
  static readonly COMIC_TRANSLATION_TORII_CREDENTIAL: string =
    'comicTranslation.torii.credential'
  static readonly COMIC_TRANSLATION_RENDER_SERVICE_URL: string =
    'comicTranslation.renderService.url'
  // Sidecar login credentials; legacy session tokens remain readable. Encrypted backup only; never sync.
  static readonly COMIC_TRANSLATION_RENDER_SERVICE_CREDENTIAL: string =
    'comicTranslation.renderService.credential'
  static readonly LLM_SOURCE_PROFILES: string = 'llmSources.profiles'
  // Source-scoped API credentials. Included only in encrypted backup; never sync.
  static readonly LLM_SOURCE_API_KEYS: string = 'llmSources.apiKeys'
  // Source-scoped rotating Codex credentials. Strictly device-local.
  static readonly LLM_SOURCE_CODEX_OAUTH_TOKENS: string = 'llmSources.codexOAuthTokens'
  static readonly LLM_SOURCE_MODEL_CATALOG_CACHE: string = 'llmSources.modelCatalogCache'
  static readonly LLM_SOURCE_USAGE_CACHE: string = 'llmSources.usageCache'
  static readonly LLM_SOURCE_MIGRATION_VERSION: string = 'llmSources.migrationVersion'
  static readonly SYNC_WEBDAV_URL: string = 'sync.webdav.url'
  static readonly SYNC_WEBDAV_USERNAME: string = 'sync.webdav.username'
  static readonly SYNC_WEBDAV_ENABLED: string = 'sync.webdav.enabled'
  // Sensitive provider credential. Never sync; export only inside encrypted backup.
  static readonly SYNC_WEBDAV_PASSWORD: string = 'sync.webdav.password'
  static readonly SYNC_DATASET_READ_PROGRESS: string = 'sync.dataset.readProgress'
  static readonly SYNC_DATASET_VIEWED_HISTORY: string = 'sync.dataset.viewedHistory'
  static readonly SYNC_DATASET_LOCAL_FAVORITES: string = 'sync.dataset.localFavorites'
  static readonly SYNC_DATASET_SEARCH_HISTORY: string = 'sync.dataset.searchHistory'
  static readonly SYNC_DATASET_LOCAL_BLOCK: string = 'sync.dataset.localBlock'
  static readonly SYNC_DATASET_CUSTOM_PROFILES: string = 'sync.dataset.customProfiles'
  static readonly SYNC_LAST_RUN_AT: string = 'sync.lastRunAt'
  static readonly SYNC_LAST_STATUS: string = 'sync.lastStatus'
  static readonly SYNC_LAST_DETAIL: string = 'sync.lastDetail'
  static readonly SYNC_HUAWEI_CLOUD_ENABLED: string = 'sync.huaweiCloud.enabled'
  static readonly SYNC_HUAWEI_CLOUD_LAST_RUN_AT: string = 'sync.huaweiCloud.lastRunAt'
  static readonly SYNC_HUAWEI_CLOUD_LAST_STATUS: string = 'sync.huaweiCloud.lastStatus'
  static readonly SYNC_HUAWEI_CLOUD_LAST_DETAIL: string = 'sync.huaweiCloud.lastDetail'
  static readonly SYNC_HUAWEI_CLOUD_LAST_CLOUD_DISABLED: string = 'sync.huaweiCloud.lastCloudDisabled'
  static readonly SAFE_MODE_UNLOCKED: string = 'safeMode.unlocked'
  static readonly LOCAL_BLOCK_RULES: string = 'localBlock.rules' // legacy Preferences key; RDB source of truth
  static readonly DIAGNOSTICS_ENABLED: string = 'diagnostics.enabled'
  static readonly DIAGNOSTICS_MIN_LEVEL: string = 'diagnostics.minLevel'

  // sensitive auth bundle (redacted in logs, never committed)
  static readonly COOKIE_JAR: string = 'auth.cookieJar'
  static readonly AUTH_ACCOUNTS: string = 'auth.accounts'
  static readonly USER_PROFILE_PREFIX: string = 'auth.profile.'
}
