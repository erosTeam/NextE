# Persistence Dataset Inventory

Status: active contract source.

Purpose: every persisted key and local table must have an owner-level decision before more backup or sync code is added.

Allowed `Backup` values:

- `plaintext`: included in normal app-data backup.
- `encrypted-only`: included only when the user creates an encrypted backup.
- `localData`: included through the backup local-data section.
- `excluded`: never exported by app-data backup.

Allowed `Sync` values:

- `excluded`: never synced.
- `WebDAV`: synced by the WebDAV provider.
- `HuaweiCloud`: synced by Huawei Cloud structured data.
- `WebDAV+HuaweiCloud`: synced by both providers.
- `metadata-only`: sync metadata, not primary user payload.
- `migration`: temporary migration table.

## StorageKeys

| Key | Class | Backup | Sync | Notes |
| --- | --- | --- | --- | --- |
| StorageKeys.STORE_SETTINGS | store | excluded | excluded | Preferences store name |
| StorageKeys.SITE_MODE_EX | setting | plaintext | excluded | EH site mode |
| StorageKeys.LIST_MODE | setting | plaintext | excluded | Gallery list layout |
| StorageKeys.LIST_ITEM_FIXED_HEIGHT | setting | plaintext | excluded | List-row height mode |
| StorageKeys.GRID_COLUMN_WIDTH | setting | plaintext | excluded | User layout override |
| StorageKeys.WATERFALL_COLUMN_WIDTH | setting | plaintext | excluded | User layout override |
| StorageKeys.WATERFALL_COMPACT_COLUMN_WIDTH | setting | plaintext | excluded | Compact waterfall user layout override |
| StorageKeys.COVER_WALL_COLUMN_WIDTH | setting | plaintext | excluded | User layout override |
| StorageKeys.THUMBNAIL_COLUMN_WIDTH | setting | plaintext | excluded | User layout override |
| StorageKeys.JAPANESE_TITLE_IN_GALLERY_PAGE | setting | plaintext | excluded | Title display preference |
| StorageKeys.ITEM_WIDTH | setting | plaintext | excluded | Legacy layout preference |
| StorageKeys.HIDE_GALLERY_THUMBNAILS | setting | plaintext | excluded | Detail preview visibility |
| StorageKeys.HORIZONTAL_THUMBNAILS | setting | plaintext | excluded | Detail preview layout |
| StorageKeys.BLURRING_OF_COVER_BACKGROUND | setting | plaintext | excluded | Cover background style |
| StorageKeys.ACTION_ALIGNMENT_MODE | setting | plaintext | excluded | Floating action placement |
| StorageKeys.READ_BUTTON_STYLE | setting | plaintext | excluded | Read button style |
| StorageKeys.SCREEN_ORIENTATION | setting | plaintext | excluded | Main-window orientation policy |
| StorageKeys.TABLET_LAYOUT_MODE | setting | plaintext | excluded | Adaptive tablet split-layout preference |
| StorageKeys.THEME_MODE | setting | plaintext | excluded | Theme mode |
| StorageKeys.THEME_COLOR | setting | plaintext | excluded | Theme accent |
| StorageKeys.IMMERSIVE_MATERIAL_LEVEL | setting | plaintext | excluded | Material preference |
| StorageKeys.LANGUAGE | setting | plaintext | excluded | App language |
| StorageKeys.SEARCH_HISTORY | legacy-local-data | excluded | excluded | RDB source is `search_history` |
| StorageKeys.SEARCH_HISTORY_TRANSLATE | setting | plaintext | excluded | Search-history translation preference |
| StorageKeys.SEARCH_FILTER | setting | plaintext | excluded | Advanced-search filter snapshot |
| StorageKeys.FAVORITES_FAVCATS | legacy-local-data | excluded | excluded | Favcat selector snapshot, not primary local data |
| StorageKeys.LOCAL_FAVORITES | legacy-local-data | excluded | excluded | RDB source is `local_favorites` |
| StorageKeys.VIEWED_HISTORY | legacy-local-data | excluded | excluded | RDB source is `viewed_history` |
| StorageKeys.READING_DIRECTION | setting | plaintext | excluded | Reader direction |
| StorageKeys.READING_PROGRESS | legacy-local-data | excluded | excluded | RDB source is `gallery_read_progress` |
| StorageKeys.READING_DOUBLE_PAGE | setting | plaintext | excluded | Reader spread mode |
| StorageKeys.READING_SPREAD_LAYOUT | setting | plaintext | excluded | Reader spread layout preference |
| StorageKeys.READING_VOLUME_KEY | setting | plaintext | excluded | Reader volume-key control |
| StorageKeys.READING_AUTO_PAGE_SEC | setting | plaintext | excluded | Reader auto page interval |
| StorageKeys.READING_PRELOAD_PAGES | setting | plaintext | excluded | Reader preload preference |
| StorageKeys.READING_TAP_ZONE_LAYOUT | setting | plaintext | excluded | Reader tap-zone layout |
| StorageKeys.READING_TAP_ZONE_INVERT | setting | plaintext | excluded | Reader tap-zone inversion |
| StorageKeys.READING_BACKGROUND_MODE | setting | plaintext | excluded | Reader background color mode |
| StorageKeys.READING_SHOW_PAGE_NUMBER | setting | plaintext | excluded | Reader page-number visibility |
| StorageKeys.READING_FULLSCREEN | setting | plaintext | excluded | Reader fullscreen preference |
| StorageKeys.READING_KEEP_SCREEN_ON | setting | plaintext | excluded | Reader keep-screen-on preference |
| StorageKeys.READING_PAGE_TURN_ANIMATION | setting | plaintext | excluded | Reader page-turn animation preference |
| StorageKeys.READING_IMAGE_SCALING_QUALITY | setting | plaintext | excluded | Reader image interpolation preference |
| StorageKeys.READING_SUPER_RESOLUTION_ENABLED | setting | plaintext | excluded | Reader super-resolution master switch |
| StorageKeys.READING_SUPER_RESOLUTION_MODEL | setting | plaintext | excluded | Selected local super-resolution model |
| StorageKeys.READING_SUPER_RESOLUTION_MAX_HEIGHT | setting | plaintext | excluded | Reader super-resolution input height limit |
| StorageKeys.READER_IMAGE_CACHE_LIMIT_MB | setting | plaintext | excluded | Local reader image-cache limit |
| StorageKeys.DOWNLOAD_CONCURRENCY | setting | plaintext | excluded | Download setting |
| StorageKeys.DOWNLOAD_REQUEST_INTERVAL_SECONDS | setting | plaintext | excluded | Download setting |
| StorageKeys.DOWNLOAD_RETRY_COUNT | setting | plaintext | excluded | Download setting |
| StorageKeys.DOWNLOAD_AUTO_RETRY_FAILED | setting | plaintext | excluded | Download setting |
| StorageKeys.DOWNLOAD_SPEED_LIMIT_KBPS | setting | plaintext | excluded | Download setting |
| StorageKeys.DOWNLOAD_NOTIFY_ON_COMPLETE | setting | plaintext | excluded | Download completion notification preference |
| StorageKeys.DOWNLOAD_HIDE_FROM_MEDIA_LIBRARY | setting | plaintext | excluded | Download media-library visibility preference |
| StorageKeys.DOWNLOAD_ORIGINAL | setting | plaintext | excluded | Download setting |
| StorageKeys.DOWNLOAD_ARCHIVE_BOT_TYPE | setting | plaintext | excluded | Archive bot setting |
| StorageKeys.DOWNLOAD_ARCHIVE_BOT_ADDRESS | setting | plaintext | excluded | Archive bot setting |
| StorageKeys.DOWNLOAD_ARCHIVE_BOT_API_KEY | secret | encrypted-only | excluded | Archive bot credential |
| StorageKeys.DOWNLOAD_ARCHIVE_BOT_BALANCE_GP | runtime | excluded | excluded | Cached balance |
| StorageKeys.DOWNLOAD_ARCHIVE_BOT_BALANCE_UPDATED_AT | runtime | excluded | excluded | Cached balance time |
| StorageKeys.DOWNLOAD_GALLERY_QUEUE | legacy-local-data | excluded | excluded | RDB source is download queue tables |
| StorageKeys.SECURITY_RECENT_TASKS_PROTECTION | setting | plaintext | excluded | Recent-task protection |
| StorageKeys.SECURITY_AUTO_LOCK_SEC | setting | plaintext | excluded | App lock timeout |
| StorageKeys.SECURITY_LAST_BACKGROUND_AT | runtime | excluded | excluded | App-lock runtime marker |
| StorageKeys.HOME_SOURCE | setting | plaintext | excluded | Home tab source |
| StorageKeys.FAVORITES_FAVCAT | setting | plaintext | excluded | Favorites tab choice |
| StorageKeys.TOPLIST_TL | setting | plaintext | excluded | Toplist period |
| StorageKeys.WEB_LOGIN_BEAUTIFY_ENABLED | setting | plaintext | excluded | Login WebView style |
| StorageKeys.HOME_CUSTOM_PROFILES | legacy-local-data | excluded | excluded | RDB source is `custom_profiles` |
| StorageKeys.HOME_CUSTOM_PROFILES_SELECTED | legacy-local-data | excluded | excluded | RDB source is `custom_profile_selection` |
| StorageKeys.TOPLIST_APPLY_HIDDEN_USER_TAGS | setting | plaintext | excluded | Toplist filtering |
| StorageKeys.CLIPBOARD_LINK_ENABLED | device-consent | excluded | excluded | Clipboard access opt-in is granted per device |
| StorageKeys.CLIPBOARD_LINK_CHANGE_COUNT | runtime | excluded | excluded | Device-local clipboard deduplication cursor |
| StorageKeys.APP_COLOR_FAVORITES | setting | plaintext | excluded | Theme color favorites |
| StorageKeys.HOME_TAB_AUTO_HIDE | setting | plaintext | excluded | Home tab behavior |
| StorageKeys.TAG_TRANSLATION_ENABLED | setting | plaintext | excluded | Tag translation setting |
| StorageKeys.TAG_TRANSLATION_USE_CDN | setting | plaintext | excluded | Tag translation setting |
| StorageKeys.TAG_TRANSLATION_UPDATE_MODE | setting | plaintext | excluded | Tag translation setting |
| StorageKeys.TAG_TRANSLATION_INTRO_IMAGE_LEVEL | setting | plaintext | excluded | Tag translation setting |
| StorageKeys.IMAGE_BLOCK_ENABLED | setting | plaintext | excluded | Image-block master switch |
| StorageKeys.COMMENT_TRANSLATION_ENABLED | setting | plaintext | excluded | Comment translation setting |
| StorageKeys.COMMENT_TRANSLATION_AUTO | setting | plaintext | excluded | Comment translation setting |
| StorageKeys.COMMENT_TRANSLATION_DISPLAY_MODE | setting | plaintext | excluded | Comment translation setting |
| StorageKeys.COMMENT_TRANSLATION_GOOGLE_ONLY | setting | plaintext | excluded | Comment translation setting |
| StorageKeys.COMMENT_TRANSLATION_API_URL | setting | plaintext | excluded | Comment translation endpoint |
| StorageKeys.COMMENT_TRANSLATION_API_KEY | secret | encrypted-only | excluded | Comment translation credential |
| StorageKeys.COMMENT_TRANSLATION_MODEL | setting | plaintext | excluded | Comment translation model |
| StorageKeys.COMMENT_TRANSLATION_LLM_SOURCE_PROFILE | setting | plaintext | excluded | Shared LLM source selected by comment translation; a missing referenced profile remains explicitly unconfigured |
| StorageKeys.COMMENT_TRANSLATION_LLM_MODEL | setting | plaintext | excluded | Comment translation model selected within its shared source |
| StorageKeys.COMIC_TRANSLATION_PROVIDER | setting | plaintext | excluded | Active manga-analysis provider |
| StorageKeys.COMIC_TRANSLATION_API_URL | setting | plaintext | excluded | Manga-analysis Responses endpoint |
| StorageKeys.COMIC_TRANSLATION_API_KEY | secret | encrypted-only | excluded | Manga-analysis API credential |
| StorageKeys.COMIC_TRANSLATION_API_MODEL | setting | plaintext | excluded | Manga-analysis API model |
| StorageKeys.COMIC_TRANSLATION_CODEX_MODEL | setting | plaintext | excluded | User-selected experimental Codex model |
| StorageKeys.COMIC_TRANSLATION_CODEX_OAUTH_TOKEN | device-credential | excluded | excluded | Rotating Codex OAuth pair; never copied between devices |
| StorageKeys.COMIC_TRANSLATION_CODEX_USAGE_CACHE | volatile-cache | excluded | excluded | Account-scoped 5H/7D snapshot; refreshed from Codex in background |
| StorageKeys.COMIC_TRANSLATION_LLM_SOURCE_PROFILE | setting | plaintext | excluded | Shared LLM source selected by manga translation; no implicit fallback after source deletion |
| StorageKeys.COMIC_TRANSLATION_LLM_MODEL | setting | plaintext | excluded | Manga translation model selected within its shared source |
| StorageKeys.COMIC_TRANSLATION_VISUAL_ROUTE | setting | plaintext | excluded | Explicit on-device or Torii whole-page visual route; defaults to on-device |
| StorageKeys.COMIC_TRANSLATION_TORII_MODEL | setting | plaintext | excluded | Model ID selected from the versioned official Torii catalog snapshot |
| StorageKeys.COMIC_TRANSLATION_TORII_FONT | setting | plaintext | excluded | Torii whole-page rendering font ID |
| StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BILLING_MODE | retired-tombstone | excluded | excluded | Legacy BYOK setting; deleted on load and never written |
| StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_PROVIDER | retired-tombstone | excluded | excluded | Legacy BYOK setting; deleted on load and never written |
| StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_SOURCE_PROFILE | retired-tombstone | excluded | excluded | Legacy BYOK setting; deleted on load and never written |
| StorageKeys.COMIC_TRANSLATION_TORII_LEGACY_BYOK_MODEL | retired-tombstone | excluded | excluded | Legacy BYOK setting; deleted on load and never written |
| StorageKeys.COMIC_TRANSLATION_TORII_CREDITS_CACHE | volatile-cache | excluded | excluded | API-key-scoped Torii balance snapshot; shown from cache and refreshed in background |
| StorageKeys.COMIC_TRANSLATION_TORII_CREDENTIAL | secret | encrypted-only | excluded | Torii account API key; disclosed to Torii only on the selected cloud route |
| StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_URL | setting | plaintext | excluded | User-configured manga rendering sidecar endpoint; public endpoints require HTTPS |
| StorageKeys.COMIC_TRANSLATION_RENDER_SERVICE_CREDENTIAL | secret | encrypted-only | excluded | Optional Authorization value for the manga rendering sidecar |
| StorageKeys.LLM_SOURCE_PROFILES | setting | plaintext | excluded | Provider-neutral reusable source metadata; contains no API key or OAuth token |
| StorageKeys.LLM_SOURCE_API_KEYS | secret | encrypted-only | excluded | Source-scoped API credentials keyed by stable source profile ID |
| StorageKeys.LLM_SOURCE_CODEX_OAUTH_TOKENS | device-credential | excluded | excluded | Source-scoped rotating Codex OAuth credentials; never copied between devices |
| StorageKeys.LLM_SOURCE_MODEL_CATALOG_CACHE | volatile-cache | excluded | excluded | Regenerable source/account-scoped model catalog snapshots |
| StorageKeys.LLM_SOURCE_USAGE_CACHE | volatile-cache | excluded | excluded | Regenerable source/account-scoped quota snapshots |
| StorageKeys.LLM_SOURCE_MIGRATION_VERSION | setting | plaintext | excluded | Idempotent legacy comment/manga provider migration marker |
| StorageKeys.SYNC_WEBDAV_URL | credential-group | encrypted-only | excluded | WebDAV endpoint; restored atomically with the credential group |
| StorageKeys.SYNC_WEBDAV_USERNAME | credential-group | encrypted-only | excluded | WebDAV username; restored atomically with the credential group |
| StorageKeys.SYNC_WEBDAV_ENABLED | credential-group | encrypted-only | excluded | WebDAV provider switch; restored atomically with the credential group |
| StorageKeys.SYNC_WEBDAV_PASSWORD | credential-group | encrypted-only | excluded | WebDAV password; restored atomically with the credential group |
| StorageKeys.SYNC_DATASET_READ_PROGRESS | setting | plaintext | excluded | Sync dataset switch |
| StorageKeys.SYNC_DATASET_VIEWED_HISTORY | setting | plaintext | excluded | Sync dataset switch |
| StorageKeys.SYNC_DATASET_LOCAL_FAVORITES | setting | plaintext | excluded | Sync dataset switch |
| StorageKeys.SYNC_DATASET_SEARCH_HISTORY | setting | plaintext | excluded | Sync dataset switch |
| StorageKeys.SYNC_DATASET_LOCAL_BLOCK | setting | plaintext | excluded | Sync dataset switch, also controls image-block sync |
| StorageKeys.SYNC_DATASET_CUSTOM_PROFILES | setting | plaintext | excluded | Sync dataset switch |
| StorageKeys.SYNC_LAST_RUN_AT | runtime | excluded | excluded | WebDAV last-run status |
| StorageKeys.SYNC_LAST_STATUS | runtime | excluded | excluded | WebDAV last-run status |
| StorageKeys.SYNC_LAST_DETAIL | runtime | excluded | excluded | WebDAV last-run detail |
| StorageKeys.SYNC_HUAWEI_CLOUD_ENABLED | setting | plaintext | excluded | Huawei Cloud provider switch |
| StorageKeys.SYNC_HUAWEI_CLOUD_LAST_RUN_AT | runtime | excluded | excluded | Huawei Cloud last-run status |
| StorageKeys.SYNC_HUAWEI_CLOUD_LAST_STATUS | runtime | excluded | excluded | Huawei Cloud last-run status |
| StorageKeys.SYNC_HUAWEI_CLOUD_LAST_DETAIL | runtime | excluded | excluded | Huawei Cloud last-run detail |
| StorageKeys.SYNC_HUAWEI_CLOUD_LAST_CLOUD_DISABLED | runtime | excluded | excluded | System cloud-switch marker |
| StorageKeys.SAFE_MODE_UNLOCKED | runtime | excluded | excluded | Session marker |
| StorageKeys.LOCAL_BLOCK_RULES | legacy-local-data | excluded | excluded | RDB source is local block tables |
| StorageKeys.DIAGNOSTICS_ENABLED | setting | plaintext | excluded | Diagnostics switch |
| StorageKeys.DIAGNOSTICS_MIN_LEVEL | setting | plaintext | excluded | Diagnostics level |
| StorageKeys.COOKIE_JAR | secret | encrypted-only | excluded | EH cookie jar |
| StorageKeys.AUTH_ACCOUNTS | secret | encrypted-only | excluded | Saved EH account bundles |
| StorageKeys.USER_PROFILE_PREFIX | secret-prefix | encrypted-only | excluded | Saved EH account profile prefix |

## LocalDataStore Tables

| Table | Class | Backup | Sync | Notes |
| --- | --- | --- | --- | --- |
| schema_meta | schema | excluded | excluded | Local schema marker |
| tag_translations | cache | excluded | excluded | Downloaded tag translation index |
| tag_translation_meta | cache | excluded | excluded | Tag translation metadata |
| eh_page_cache | cache | excluded | excluded | EH page payload cache |
| comment_translation_cache | cache | excluded | excluded | Comment translation cache |
| comic_translation_document_cache | cache | excluded | excluded | Bounded generated normalized page documents; no raw response, image, credential, or user edits |
| gallery_read_progress | local-data | localData | WebDAV+HuaweiCloud | Durable reader progress |
| viewed_history | local-data | localData | WebDAV+HuaweiCloud | Durable viewed history |
| local_favorites | local-data | localData | WebDAV+HuaweiCloud | Durable local favorites |
| search_history | local-data | localData | WebDAV+HuaweiCloud | Durable search history |
| local_block_settings | local-data | localData | WebDAV+HuaweiCloud | Local block settings |
| local_block_rules | local-data | localData | WebDAV+HuaweiCloud | Local block rules |
| image_block_subscriptions | metadata | excluded | WebDAV | Subscription metadata; not Huawei Cloud |
| image_block_rules | subscription-cache | excluded | excluded | Materialized subscription/community rules |
| image_block_user_rules | local-data | localData | WebDAV+HuaweiCloud | User rules and user overrides |
| image_block_hash_cache | cache | excluded | excluded | pHash cache |
| custom_profiles | local-data | localData | WebDAV+HuaweiCloud | Custom home profiles |
| custom_profile_selection | local-data | localData | WebDAV+HuaweiCloud | Selected custom profile |
| download_gallery_tasks | download | excluded | excluded | Download queue task state |
| download_gallery_seeds | download | excluded | excluded | Download queue image seeds |
| download_archiver_tasks | download | excluded | excluded | Archive bot task state |
| custom_profiles_v8 | migration-temp | excluded | migration | Temporary migration table |
| download_gallery_tasks_v15 | migration-temp | excluded | migration | Temporary migration table |
| download_gallery_seeds_v15 | migration-temp | excluded | migration | Temporary migration table |
| image_block_user_rules_v18 | migration-temp | excluded | migration | Temporary migration table |
