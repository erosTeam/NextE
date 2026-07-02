import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'

const LOCAL_DATA_DB_NAME: string = 'NextE.db'
export const LOCAL_DATA_SCHEMA_VERSION: number = 21

const LOCAL_DATA_STORE_CONFIG: relationalStore.StoreConfig = {
  name: LOCAL_DATA_DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S3,
  autoCleanDirtyData: true,
}

const SQL_CREATE_SCHEMA_META_TABLE: string =
  'CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)'
const SQL_UPSERT_SCHEMA_VERSION: string =
  'INSERT OR REPLACE INTO schema_meta (key, value) VALUES (\'schema_version\', \'21\')'
const SQL_CREATE_TAG_TRANSLATIONS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS tag_translations (' +
    'namespace TEXT NOT NULL, ' +
    'key TEXT NOT NULL, ' +
    'name TEXT, ' +
    'intro TEXT, ' +
    'links TEXT, ' +
    'last_use_time INTEGER NOT NULL DEFAULT 0, ' +
    'PRIMARY KEY(namespace, key)' +
  ')'
const SQL_CREATE_TAG_TRANSLATIONS_KEY_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_tag_translations_key ON tag_translations (key)'
const SQL_CREATE_TAG_TRANSLATIONS_NAME_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_tag_translations_name ON tag_translations (name)'
const SQL_CREATE_TAG_TRANSLATIONS_LAST_USE_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_tag_translations_last_use ON tag_translations (last_use_time DESC)'
const SQL_CREATE_TAG_TRANSLATION_META_TABLE: string =
  'CREATE TABLE IF NOT EXISTS tag_translation_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)'
const SQL_CREATE_EH_PAGE_CACHE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS eh_page_cache (' +
    'kind TEXT NOT NULL, ' +
    'cache_key TEXT NOT NULL, ' +
    'payload TEXT NOT NULL, ' +
    'cached_at INTEGER NOT NULL, ' +
    'expires_at INTEGER NOT NULL, ' +
    'accessed_at INTEGER NOT NULL, ' +
    'PRIMARY KEY(kind, cache_key)' +
  ')'
const SQL_CREATE_EH_PAGE_CACHE_EXPIRES_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_eh_page_cache_expires ON eh_page_cache (expires_at)'
const SQL_CREATE_EH_PAGE_CACHE_ACCESS_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_eh_page_cache_access ON eh_page_cache (kind, accessed_at DESC)'
const SQL_CREATE_COMMENT_TRANSLATION_CACHE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS comment_translation_cache (' +
    'text_hash TEXT NOT NULL, ' +
    'target_lang TEXT NOT NULL, ' +
    'translated TEXT NOT NULL, ' +
    'cached_at INTEGER NOT NULL, ' +
    'expires_at INTEGER NOT NULL, ' +
    'PRIMARY KEY(text_hash, target_lang)' +
  ')'
const SQL_CREATE_COMMENT_TRANSLATION_CACHE_EXPIRES_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_comment_translation_cache_expires ON comment_translation_cache (expires_at)'
// Future cloud-syncable durable user data table. Columns intentionally omit NOT NULL, matching the
// HarmonyOS cloud-sync constraint used by V2Next synced tables.
const SQL_CREATE_GALLERY_READ_PROGRESS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS gallery_read_progress (' +
    'scope_key TEXT, ' +
    'gid TEXT, ' +
    'page_index INTEGER, ' +
    'column_mode TEXT, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, gid)' +
  ')'
const SQL_CREATE_GALLERY_READ_PROGRESS_UPDATED_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_gallery_read_progress_updated_at ON gallery_read_progress (updated_at DESC)'
const SQL_ADD_GALLERY_READ_PROGRESS_COLUMN_MODE: string =
  'ALTER TABLE gallery_read_progress ADD COLUMN column_mode TEXT'
const SQL_CREATE_VIEWED_HISTORY_TABLE: string =
  'CREATE TABLE IF NOT EXISTS viewed_history (' +
    'scope_key TEXT, ' +
    'gid TEXT, ' +
    'token TEXT, ' +
    'title TEXT, ' +
    'title_jp TEXT, ' +
    'thumb_url TEXT, ' +
    'category TEXT, ' +
    'uploader TEXT, ' +
    'rating REAL, ' +
    'file_count TEXT, ' +
    'viewed_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, gid)' +
  ')'
const SQL_CREATE_VIEWED_HISTORY_VIEWED_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_viewed_history_viewed_at ON viewed_history (viewed_at DESC)'
const SQL_CREATE_LOCAL_FAVORITES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS local_favorites (' +
    'scope_key TEXT, ' +
    'gid TEXT, ' +
    'token TEXT, ' +
    'url TEXT, ' +
    'thumb_url TEXT, ' +
    'thumb_url_l TEXT, ' +
    'img_width INTEGER, ' +
    'img_height INTEGER, ' +
    'english_title TEXT, ' +
    'japanese_title TEXT, ' +
    'category TEXT, ' +
    'uploader TEXT, ' +
    'post_time TEXT, ' +
    'file_count TEXT, ' +
    'rating REAL, ' +
    'rating_fallback REAL, ' +
    'color_rating TEXT, ' +
    'fav_note TEXT, ' +
    'fav_title TEXT, ' +
    'expunged INTEGER, ' +
    'last_view_time INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, gid)' +
  ')'
const SQL_CREATE_LOCAL_FAVORITES_LAST_VIEW_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_local_favorites_last_view ON local_favorites (last_view_time DESC)'
const SQL_CREATE_SEARCH_HISTORY_TABLE: string =
  'CREATE TABLE IF NOT EXISTS search_history (' +
    'scope_key TEXT, ' +
    'query_text TEXT, ' +
    'position_index INTEGER, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, query_text)' +
  ')'
const SQL_CREATE_SEARCH_HISTORY_POSITION_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_search_history_position ON search_history (position_index ASC)'
const SQL_CREATE_LOCAL_BLOCK_SETTINGS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS local_block_settings (' +
    'scope_key TEXT PRIMARY KEY, ' +
    'filter_comments_by_score INTEGER, ' +
    'score_filtering_threshold INTEGER, ' +
    'comment_display_mode TEXT, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0' +
  ')'
const SQL_CREATE_LOCAL_BLOCK_RULES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS local_block_rules (' +
    'scope_key TEXT, ' +
    'rule_id TEXT, ' +
    'position_index INTEGER, ' +
    'block_type TEXT, ' +
    'rule_text TEXT, ' +
    'enabled INTEGER, ' +
    'enable_regex INTEGER, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, rule_id)' +
  ')'
const SQL_CREATE_LOCAL_BLOCK_RULES_POSITION_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_local_block_rules_position ON local_block_rules (position_index ASC)'
const SQL_CREATE_IMAGE_BLOCK_SUBSCRIPTIONS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS image_block_subscriptions (' +
    'scope_key TEXT, ' +
    'feed_id TEXT, ' +
    'title TEXT, ' +
    'url TEXT, ' +
    'algorithm TEXT, ' +
    'default_threshold INTEGER, ' +
    'updated_at INTEGER, ' +
    'synced_at INTEGER, ' +
    'sha256 TEXT, ' +
    'rule_count INTEGER, ' +
    'enabled INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, feed_id)' +
  ')'
const SQL_CREATE_IMAGE_BLOCK_RULES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS image_block_rules (' +
    'scope_key TEXT, ' +
    'rule_id TEXT, ' +
    'hash TEXT, ' +
    'threshold INTEGER, ' +
    'label TEXT, ' +
    'scope TEXT, ' +
    'feed_id TEXT, ' +
    'source_type TEXT, ' +
    'source_url TEXT, ' +
    'source_page INTEGER, ' +
    'preview_path TEXT, ' +
    'enabled INTEGER, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, rule_id)' +
  ')'
const SQL_CREATE_IMAGE_BLOCK_RULES_HASH_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_image_block_rules_hash ON image_block_rules (hash)'
const SQL_CREATE_IMAGE_BLOCK_RULES_FEED_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_image_block_rules_feed ON image_block_rules (feed_id, enabled)'
const SQL_CREATE_IMAGE_BLOCK_USER_RULES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS image_block_user_rules (' +
    'rule_id TEXT, ' +
    'scope_key TEXT, ' +
    'hash TEXT, ' +
    'threshold INTEGER, ' +
    'label TEXT, ' +
    'scope TEXT, ' +
    'feed_id TEXT, ' +
    'source_type TEXT, ' +
    'source_url TEXT, ' +
    'source_page INTEGER, ' +
    'preview_path TEXT, ' +
    'enabled INTEGER, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(rule_id, scope_key)' +
  ')'
const IMAGE_BLOCK_USER_RULE_COLUMNS: string[] = [
  'rule_id',
  'scope_key',
  'hash',
  'threshold',
  'label',
  'scope',
  'feed_id',
  'source_type',
  'source_url',
  'source_page',
  'preview_path',
  'enabled',
  'updated_at',
  'deleted_at',
]
const SQL_DROP_IMAGE_BLOCK_USER_RULES_V18_TABLE: string =
  'DROP TABLE IF EXISTS image_block_user_rules_v18'
const SQL_CREATE_IMAGE_BLOCK_USER_RULES_V18_TABLE: string =
  'CREATE TABLE image_block_user_rules_v18 (' +
    'rule_id TEXT, ' +
    'scope_key TEXT, ' +
    'hash TEXT, ' +
    'threshold INTEGER, ' +
    'label TEXT, ' +
    'scope TEXT, ' +
    'feed_id TEXT, ' +
    'source_type TEXT, ' +
    'source_url TEXT, ' +
    'source_page INTEGER, ' +
    'preview_path TEXT, ' +
    'enabled INTEGER, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(rule_id, scope_key)' +
  ')'
const SQL_DROP_IMAGE_BLOCK_USER_RULES_TABLE: string =
  'DROP TABLE image_block_user_rules'
const SQL_RENAME_IMAGE_BLOCK_USER_RULES_V18_TABLE: string =
  'ALTER TABLE image_block_user_rules_v18 RENAME TO image_block_user_rules'
const SQL_CREATE_IMAGE_BLOCK_USER_RULES_HASH_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_image_block_user_rules_hash ON image_block_user_rules (hash)'
const SQL_ADD_IMAGE_BLOCK_RULES_SOURCE_URL: string =
  'ALTER TABLE image_block_rules ADD COLUMN source_url TEXT'
const SQL_ADD_IMAGE_BLOCK_RULES_SOURCE_PAGE: string =
  'ALTER TABLE image_block_rules ADD COLUMN source_page INTEGER'
const SQL_ADD_IMAGE_BLOCK_RULES_PREVIEW_PATH: string =
  'ALTER TABLE image_block_rules ADD COLUMN preview_path TEXT'
const SQL_MIGRATE_IMAGE_BLOCK_WHITELIST_TO_RULES: string =
  'INSERT INTO image_block_rules ' +
  '(scope_key, rule_id, hash, threshold, label, scope, feed_id, source_type, source_url, source_page, preview_path, enabled, updated_at, deleted_at) ' +
  'SELECT scope_key, \'allow:\' || hash, hash, 0, \'allow\', \'whole\', \'\', \'allow\', \'\', 0, ' +
  'COALESCE(preview_path, \'\'), 1, COALESCE(updated_at, 0), COALESCE(deleted_at, 0) ' +
  'FROM image_block_whitelist WHERE hash IS NOT NULL AND hash <> \'\' ' +
  'ON CONFLICT(scope_key, rule_id) DO UPDATE SET ' +
  'preview_path = CASE WHEN excluded.preview_path <> \'\' THEN excluded.preview_path ELSE image_block_rules.preview_path END, ' +
  'updated_at = excluded.updated_at, deleted_at = excluded.deleted_at'
const SQL_MIGRATE_IMAGE_BLOCK_OVERRIDE_ENABLED_TO_RULES: string =
  'UPDATE image_block_rules SET enabled = COALESCE((' +
  'SELECT enabled_override FROM image_block_rule_overrides o ' +
  'WHERE o.scope_key = image_block_rules.scope_key AND o.rule_id = image_block_rules.rule_id ' +
  'AND COALESCE(o.deleted_at, 0) = 0 AND COALESCE(o.enabled_override, -1) >= 0' +
  '), enabled), updated_at = MAX(updated_at, COALESCE((' +
  'SELECT updated_at FROM image_block_rule_overrides o ' +
  'WHERE o.scope_key = image_block_rules.scope_key AND o.rule_id = image_block_rules.rule_id ' +
  'AND COALESCE(o.deleted_at, 0) = 0 AND COALESCE(o.enabled_override, -1) >= 0' +
  '), updated_at)) WHERE EXISTS (' +
  'SELECT 1 FROM image_block_rule_overrides o WHERE o.scope_key = image_block_rules.scope_key ' +
  'AND o.rule_id = image_block_rules.rule_id AND COALESCE(o.deleted_at, 0) = 0 ' +
  'AND COALESCE(o.enabled_override, -1) >= 0)'
const SQL_MIGRATE_IMAGE_BLOCK_OVERRIDE_THRESHOLD_TO_RULES: string =
  'UPDATE image_block_rules SET threshold = COALESCE((' +
  'SELECT threshold_override FROM image_block_rule_overrides o ' +
  'WHERE o.scope_key = image_block_rules.scope_key AND o.rule_id = image_block_rules.rule_id ' +
  'AND COALESCE(o.deleted_at, 0) = 0 AND COALESCE(o.threshold_override, -1) >= 0' +
  '), threshold), updated_at = MAX(updated_at, COALESCE((' +
  'SELECT updated_at FROM image_block_rule_overrides o ' +
  'WHERE o.scope_key = image_block_rules.scope_key AND o.rule_id = image_block_rules.rule_id ' +
  'AND COALESCE(o.deleted_at, 0) = 0 AND COALESCE(o.threshold_override, -1) >= 0' +
  '), updated_at)) WHERE EXISTS (' +
  'SELECT 1 FROM image_block_rule_overrides o WHERE o.scope_key = image_block_rules.scope_key ' +
  'AND o.rule_id = image_block_rules.rule_id AND COALESCE(o.deleted_at, 0) = 0 ' +
  'AND COALESCE(o.threshold_override, -1) >= 0)'
const SQL_DROP_IMAGE_BLOCK_WHITELIST_TABLE: string = 'DROP TABLE IF EXISTS image_block_whitelist'
const SQL_DROP_IMAGE_BLOCK_RULE_OVERRIDES_TABLE: string = 'DROP TABLE IF EXISTS image_block_rule_overrides'
const SQL_CREATE_IMAGE_BLOCK_HASH_CACHE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS image_block_hash_cache (' +
    'scope_key TEXT, ' +
    'file_path TEXT, ' +
    'bytes INTEGER, ' +
    'hash TEXT, ' +
    'algorithm TEXT, ' +
    'hashed_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, file_path)' +
  ')'
const SQL_CREATE_IMAGE_BLOCK_HASH_CACHE_HASH_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_image_block_hash_cache_hash ON image_block_hash_cache (hash)'
const SQL_CREATE_CUSTOM_PROFILES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS custom_profiles (' +
    'scope_key TEXT, ' +
    'profile_uuid TEXT, ' +
    'position_index INTEGER, ' +
    'name TEXT, ' +
    'list_type TEXT, ' +
    'search_text TEXT, ' +
    'selected_cats INTEGER, ' +
    'advanced_enabled INTEGER, ' +
    'min_rating INTEGER, ' +
    'pages_from INTEGER, ' +
    'pages_to INTEGER, ' +
    'require_torrent INTEGER, ' +
    'show_expunged INTEGER, ' +
    'disable_language_filter INTEGER, ' +
    'disable_uploader_filter INTEGER, ' +
    'disable_tag_filter INTEGER, ' +
    'favcat TEXT, ' +
    'toplist_tl INTEGER, ' +
    'display_mode TEXT, ' +
    'hidden INTEGER, ' +
    'builtin INTEGER, ' +
    'last_edit_time INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, profile_uuid)' +
  ')'
const SQL_DROP_CUSTOM_PROFILES_V8_TABLE: string =
  'DROP TABLE IF EXISTS custom_profiles_v8'
const SQL_CREATE_CUSTOM_PROFILES_V8_TABLE: string =
  'CREATE TABLE custom_profiles_v8 (' +
    'scope_key TEXT, ' +
    'profile_uuid TEXT, ' +
    'position_index INTEGER, ' +
    'name TEXT, ' +
    'list_type TEXT, ' +
    'search_text TEXT, ' +
    'selected_cats INTEGER, ' +
    'advanced_enabled INTEGER, ' +
    'min_rating INTEGER, ' +
    'pages_from INTEGER, ' +
    'pages_to INTEGER, ' +
    'require_torrent INTEGER, ' +
    'show_expunged INTEGER, ' +
    'disable_language_filter INTEGER, ' +
    'disable_uploader_filter INTEGER, ' +
    'disable_tag_filter INTEGER, ' +
    'favcat TEXT, ' +
    'toplist_tl INTEGER, ' +
    'display_mode TEXT, ' +
    'hidden INTEGER, ' +
    'builtin INTEGER, ' +
    'last_edit_time INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, profile_uuid)' +
  ')'
const SQL_COPY_CUSTOM_PROFILES_UUID_TO_PROFILE_UUID: string =
  'INSERT OR REPLACE INTO custom_profiles_v8 ' +
  '(scope_key, profile_uuid, position_index, name, list_type, search_text, selected_cats, ' +
  'advanced_enabled, min_rating, pages_from, pages_to, require_torrent, show_expunged, ' +
  'disable_language_filter, disable_uploader_filter, disable_tag_filter, favcat, toplist_tl, ' +
  'display_mode, hidden, builtin, last_edit_time, deleted_at) ' +
  'SELECT scope_key, uuid, position_index, name, list_type, search_text, selected_cats, ' +
  'advanced_enabled, min_rating, pages_from, pages_to, require_torrent, show_expunged, ' +
  'disable_language_filter, disable_uploader_filter, disable_tag_filter, favcat, toplist_tl, ' +
  'display_mode, hidden, builtin, last_edit_time, deleted_at FROM custom_profiles'
const SQL_DROP_CUSTOM_PROFILES_TABLE: string =
  'DROP TABLE custom_profiles'
const SQL_RENAME_CUSTOM_PROFILES_V8_TABLE: string =
  'ALTER TABLE custom_profiles_v8 RENAME TO custom_profiles'
const SQL_CREATE_CUSTOM_PROFILES_POSITION_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_custom_profiles_position ON custom_profiles (position_index ASC)'
const SQL_CREATE_CUSTOM_PROFILE_SELECTION_TABLE: string =
  'CREATE TABLE IF NOT EXISTS custom_profile_selection (' +
    'scope_key TEXT PRIMARY KEY, ' +
    'selected_uuid TEXT, ' +
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0' +
  ')'
const SQL_CREATE_DOWNLOAD_GALLERY_TASKS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS download_gallery_tasks (' +
    'scope_key TEXT NOT NULL, ' +
    'gid TEXT NOT NULL, ' +
    'token TEXT NOT NULL, ' +
    'title TEXT NOT NULL, ' +
    'title_jp TEXT NOT NULL, ' +
    'thumb_url TEXT NOT NULL, ' +
    'img_width INTEGER NOT NULL DEFAULT 0, ' +
    'img_height INTEGER NOT NULL DEFAULT 0, ' +
    'page_count INTEGER NOT NULL, ' +
    'category TEXT NOT NULL, ' +
    'uploader TEXT NOT NULL, ' +
    'upgrade_from_gid TEXT NOT NULL DEFAULT \'\', ' +
    'queued_at INTEGER NOT NULL, ' +
    'prepared_at INTEGER NOT NULL, ' +
    'first_page_count INTEGER NOT NULL, ' +
    'preview_page_count INTEGER NOT NULL, ' +
    'prepare_error TEXT NOT NULL, ' +
    'prefer_original INTEGER NOT NULL DEFAULT 0, ' +
    'status TEXT NOT NULL, ' +
    'PRIMARY KEY(scope_key, gid, token, prefer_original)' +
  ')'
const SQL_CREATE_DOWNLOAD_GALLERY_TASKS_V15_TABLE: string =
  'CREATE TABLE IF NOT EXISTS download_gallery_tasks_v15 (' +
    'scope_key TEXT NOT NULL, ' +
    'gid TEXT NOT NULL, ' +
    'token TEXT NOT NULL, ' +
    'title TEXT NOT NULL, ' +
    'title_jp TEXT NOT NULL, ' +
    'thumb_url TEXT NOT NULL, ' +
    'img_width INTEGER NOT NULL DEFAULT 0, ' +
    'img_height INTEGER NOT NULL DEFAULT 0, ' +
    'page_count INTEGER NOT NULL, ' +
    'category TEXT NOT NULL, ' +
    'uploader TEXT NOT NULL, ' +
    'upgrade_from_gid TEXT NOT NULL DEFAULT \'\', ' +
    'queued_at INTEGER NOT NULL, ' +
    'prepared_at INTEGER NOT NULL, ' +
    'first_page_count INTEGER NOT NULL, ' +
    'preview_page_count INTEGER NOT NULL, ' +
    'prepare_error TEXT NOT NULL, ' +
    'prefer_original INTEGER NOT NULL DEFAULT 0, ' +
    'status TEXT NOT NULL, ' +
    'PRIMARY KEY(scope_key, gid, token, prefer_original)' +
  ')'
const SQL_COPY_DOWNLOAD_GALLERY_TASKS_TO_V15: string =
  'INSERT OR REPLACE INTO download_gallery_tasks_v15 ' +
    '(scope_key, gid, token, title, title_jp, thumb_url, img_width, img_height, page_count, category, uploader, upgrade_from_gid, queued_at, ' +
    'prepared_at, first_page_count, preview_page_count, prepare_error, prefer_original, status) ' +
  'SELECT scope_key, gid, token, title, title_jp, thumb_url, img_width, img_height, page_count, category, uploader, upgrade_from_gid, queued_at, ' +
    'prepared_at, first_page_count, preview_page_count, prepare_error, prefer_original, status FROM download_gallery_tasks'
const SQL_DROP_DOWNLOAD_GALLERY_TASKS_TABLE: string =
  'DROP TABLE download_gallery_tasks'
const SQL_RENAME_DOWNLOAD_GALLERY_TASKS_V15_TABLE: string =
  'ALTER TABLE download_gallery_tasks_v15 RENAME TO download_gallery_tasks'
const SQL_ADD_DOWNLOAD_GALLERY_TASKS_PREFER_ORIGINAL: string =
  'ALTER TABLE download_gallery_tasks ADD COLUMN prefer_original INTEGER NOT NULL DEFAULT 0'
const SQL_ADD_DOWNLOAD_GALLERY_TASKS_UPGRADE_FROM_GID: string =
  'ALTER TABLE download_gallery_tasks ADD COLUMN upgrade_from_gid TEXT NOT NULL DEFAULT \'\''
const SQL_ADD_DOWNLOAD_GALLERY_TASKS_IMG_WIDTH: string =
  'ALTER TABLE download_gallery_tasks ADD COLUMN img_width INTEGER NOT NULL DEFAULT 0'
const SQL_ADD_DOWNLOAD_GALLERY_TASKS_IMG_HEIGHT: string =
  'ALTER TABLE download_gallery_tasks ADD COLUMN img_height INTEGER NOT NULL DEFAULT 0'
const SQL_CREATE_DOWNLOAD_GALLERY_TASKS_QUEUED_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_download_gallery_tasks_queued ON download_gallery_tasks (queued_at DESC)'
const SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS download_gallery_seeds (' +
    'scope_key TEXT NOT NULL, ' +
    'gid TEXT NOT NULL, ' +
    'token TEXT NOT NULL, ' +
    'image_page_url TEXT NOT NULL, ' +
    'position_index INTEGER NOT NULL, ' +
    'page INTEGER NOT NULL, ' +
    'imgkey TEXT NOT NULL, ' +
    'thumb_url TEXT NOT NULL, ' +
    'image_url TEXT NOT NULL, ' +
    'origin_image_url TEXT NOT NULL, ' +
    'show_key TEXT NOT NULL, ' +
    'reload_key TEXT NOT NULL, ' +
    'file_path TEXT NOT NULL, ' +
    'bytes_written INTEGER NOT NULL, ' +
    'downloaded_at INTEGER NOT NULL, ' +
    'download_error TEXT NOT NULL, ' +
    'prefer_original INTEGER NOT NULL DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, gid, token, prefer_original, image_page_url)' +
  ')'
const SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_V15_TABLE: string =
  'CREATE TABLE IF NOT EXISTS download_gallery_seeds_v15 (' +
    'scope_key TEXT NOT NULL, ' +
    'gid TEXT NOT NULL, ' +
    'token TEXT NOT NULL, ' +
    'prefer_original INTEGER NOT NULL DEFAULT 0, ' +
    'image_page_url TEXT NOT NULL, ' +
    'position_index INTEGER NOT NULL, ' +
    'page INTEGER NOT NULL, ' +
    'imgkey TEXT NOT NULL, ' +
    'thumb_url TEXT NOT NULL, ' +
    'image_url TEXT NOT NULL, ' +
    'origin_image_url TEXT NOT NULL, ' +
    'show_key TEXT NOT NULL, ' +
    'reload_key TEXT NOT NULL, ' +
    'file_path TEXT NOT NULL, ' +
    'bytes_written INTEGER NOT NULL, ' +
    'downloaded_at INTEGER NOT NULL, ' +
    'download_error TEXT NOT NULL, ' +
    'PRIMARY KEY(scope_key, gid, token, prefer_original, image_page_url)' +
  ')'
const SQL_COPY_DOWNLOAD_GALLERY_SEEDS_TO_V15: string =
  'INSERT OR REPLACE INTO download_gallery_seeds_v15 ' +
    '(scope_key, gid, token, prefer_original, image_page_url, position_index, page, imgkey, thumb_url, image_url, ' +
    'origin_image_url, show_key, reload_key, file_path, bytes_written, downloaded_at, download_error) ' +
  'SELECT s.scope_key, s.gid, s.token, COALESCE(t.prefer_original, 0), s.image_page_url, s.position_index, s.page, ' +
    's.imgkey, s.thumb_url, s.image_url, s.origin_image_url, s.show_key, s.reload_key, s.file_path, s.bytes_written, ' +
    's.downloaded_at, s.download_error FROM download_gallery_seeds s ' +
  'LEFT JOIN download_gallery_tasks t ON t.scope_key = s.scope_key AND t.gid = s.gid AND t.token = s.token'
const SQL_DROP_DOWNLOAD_GALLERY_SEEDS_TABLE: string =
  'DROP TABLE download_gallery_seeds'
const SQL_RENAME_DOWNLOAD_GALLERY_SEEDS_V15_TABLE: string =
  'ALTER TABLE download_gallery_seeds_v15 RENAME TO download_gallery_seeds'
const SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_POSITION_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_download_gallery_seeds_position ' +
    'ON download_gallery_seeds (scope_key, gid, token, prefer_original, position_index ASC)'
const SQL_CREATE_DOWNLOAD_ARCHIVER_TASKS_TABLE: string =
  'CREATE TABLE IF NOT EXISTS download_archiver_tasks (' +
    'scope_key TEXT NOT NULL, ' +
    'tag TEXT NOT NULL, ' +
    'gid TEXT NOT NULL, ' +
    'token TEXT NOT NULL DEFAULT \'\', ' +
    'title TEXT NOT NULL, ' +
    'thumb_url TEXT NOT NULL DEFAULT \'\', ' +
    'img_width INTEGER NOT NULL DEFAULT 0, ' +
    'img_height INTEGER NOT NULL DEFAULT 0, ' +
    'dltype TEXT NOT NULL, ' +
    'resolution TEXT NOT NULL, ' +
    'parse_source TEXT NOT NULL DEFAULT \'official\', ' +
    'url TEXT NOT NULL, ' +
    'file_name TEXT NOT NULL, ' +
    'file_path TEXT NOT NULL, ' +
    'queued_at INTEGER NOT NULL, ' +
    'downloaded_at INTEGER NOT NULL, ' +
    'bytes_written INTEGER NOT NULL, ' +
    'bytes_total INTEGER NOT NULL, ' +
    'progress INTEGER NOT NULL, ' +
    'error TEXT NOT NULL, ' +
    'status TEXT NOT NULL, ' +
    'PRIMARY KEY(scope_key, tag)' +
  ')'
const SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_TOKEN: string =
  'ALTER TABLE download_archiver_tasks ADD COLUMN token TEXT NOT NULL DEFAULT \'\''
const SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_THUMB_URL: string =
  'ALTER TABLE download_archiver_tasks ADD COLUMN thumb_url TEXT NOT NULL DEFAULT \'\''
const SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_IMG_WIDTH: string =
  'ALTER TABLE download_archiver_tasks ADD COLUMN img_width INTEGER NOT NULL DEFAULT 0'
const SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_IMG_HEIGHT: string =
  'ALTER TABLE download_archiver_tasks ADD COLUMN img_height INTEGER NOT NULL DEFAULT 0'
const SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_PARSE_SOURCE: string =
  'ALTER TABLE download_archiver_tasks ADD COLUMN parse_source TEXT NOT NULL DEFAULT \'official\''
const SQL_CREATE_DOWNLOAD_ARCHIVER_TASKS_QUEUED_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_download_archiver_tasks_queued ON download_archiver_tasks (queued_at DESC)'

export class LocalDataStore {
  static async open(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    const store: relationalStore.RdbStore =
      await relationalStore.getRdbStore(context, LOCAL_DATA_STORE_CONFIG)
    await store.executeSql(SQL_CREATE_SCHEMA_META_TABLE)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_TABLE)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_KEY_INDEX)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_NAME_INDEX)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_LAST_USE_INDEX)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATION_META_TABLE)
    await store.executeSql(SQL_CREATE_EH_PAGE_CACHE_TABLE)
    await store.executeSql(SQL_CREATE_EH_PAGE_CACHE_EXPIRES_INDEX)
    await store.executeSql(SQL_CREATE_EH_PAGE_CACHE_ACCESS_INDEX)
    await store.executeSql(SQL_CREATE_COMMENT_TRANSLATION_CACHE_TABLE)
    await store.executeSql(SQL_CREATE_COMMENT_TRANSLATION_CACHE_EXPIRES_INDEX)
    await store.executeSql(SQL_CREATE_GALLERY_READ_PROGRESS_TABLE)
    await LocalDataStore.migrateGalleryReadProgressColumnMode(store)
    await store.executeSql(SQL_CREATE_GALLERY_READ_PROGRESS_UPDATED_INDEX)
    await store.executeSql(SQL_CREATE_VIEWED_HISTORY_TABLE)
    await store.executeSql(SQL_CREATE_VIEWED_HISTORY_VIEWED_INDEX)
    await store.executeSql(SQL_CREATE_LOCAL_FAVORITES_TABLE)
    await store.executeSql(SQL_CREATE_LOCAL_FAVORITES_LAST_VIEW_INDEX)
    await store.executeSql(SQL_CREATE_SEARCH_HISTORY_TABLE)
    await store.executeSql(SQL_CREATE_SEARCH_HISTORY_POSITION_INDEX)
    await store.executeSql(SQL_CREATE_LOCAL_BLOCK_SETTINGS_TABLE)
    await store.executeSql(SQL_CREATE_LOCAL_BLOCK_RULES_TABLE)
    await store.executeSql(SQL_CREATE_LOCAL_BLOCK_RULES_POSITION_INDEX)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_SUBSCRIPTIONS_TABLE)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_RULES_TABLE)
    await LocalDataStore.migrateImageBlockRuleSourceMetadata(store)
    await LocalDataStore.migrateImageBlockLegacyTables(store)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_RULES_HASH_INDEX)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_RULES_FEED_INDEX)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_USER_RULES_TABLE)
    await LocalDataStore.migrateImageBlockUserRuleColumnOrder(store)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_USER_RULES_HASH_INDEX)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_HASH_CACHE_TABLE)
    await store.executeSql(SQL_CREATE_IMAGE_BLOCK_HASH_CACHE_HASH_INDEX)
    await LocalDataStore.migrateCustomProfilesUuidColumn(store)
    await store.executeSql(SQL_CREATE_CUSTOM_PROFILES_TABLE)
    await store.executeSql(SQL_CREATE_CUSTOM_PROFILES_POSITION_INDEX)
    await store.executeSql(SQL_CREATE_CUSTOM_PROFILE_SELECTION_TABLE)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_TASKS_TABLE)
    await LocalDataStore.migrateDownloadGalleryPreferOriginal(store)
    await LocalDataStore.migrateDownloadGalleryUpgradeFromGid(store)
    await LocalDataStore.migrateDownloadGalleryCoverDimensions(store)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_TABLE)
    await LocalDataStore.migrateDownloadGalleryTaskQualityKey(store)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_TASKS_QUEUED_INDEX)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_POSITION_INDEX)
    await store.executeSql(SQL_CREATE_DOWNLOAD_ARCHIVER_TASKS_TABLE)
    await LocalDataStore.migrateDownloadArchiverToken(store)
    await LocalDataStore.migrateDownloadArchiverThumbUrl(store)
    await LocalDataStore.migrateDownloadArchiverCoverDimensions(store)
    await LocalDataStore.migrateDownloadArchiverParseSource(store)
    await store.executeSql(SQL_CREATE_DOWNLOAD_ARCHIVER_TASKS_QUEUED_INDEX)
    await store.executeSql(SQL_UPSERT_SCHEMA_VERSION)
    if (store.version !== LOCAL_DATA_SCHEMA_VERSION) {
      store.version = LOCAL_DATA_SCHEMA_VERSION
    }
    return store
  }

  private static async migrateCustomProfilesUuidColumn(store: relationalStore.RdbStore): Promise<void> {
    const hasOldUuid: boolean = await LocalDataStore.hasColumn(store, 'custom_profiles', 'uuid')
    const hasProfileUuid: boolean = await LocalDataStore.hasColumn(store, 'custom_profiles', 'profile_uuid')
    if (!hasOldUuid || hasProfileUuid) {
      return
    }
    store.beginTransaction()
    try {
      await store.executeSql(SQL_DROP_CUSTOM_PROFILES_V8_TABLE)
      await store.executeSql(SQL_CREATE_CUSTOM_PROFILES_V8_TABLE)
      await store.executeSql(SQL_COPY_CUSTOM_PROFILES_UUID_TO_PROFILE_UUID)
      await store.executeSql(SQL_DROP_CUSTOM_PROFILES_TABLE)
      await store.executeSql(SQL_RENAME_CUSTOM_PROFILES_V8_TABLE)
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to migrate custom profiles')
    }
  }

  private static async migrateGalleryReadProgressColumnMode(store: relationalStore.RdbStore): Promise<void> {
    const hasColumnMode: boolean = await LocalDataStore.hasColumn(
      store,
      'gallery_read_progress',
      'column_mode',
    )
    if (hasColumnMode) {
      return
    }
    await store.executeSql(SQL_ADD_GALLERY_READ_PROGRESS_COLUMN_MODE)
  }

  private static async migrateDownloadGalleryPreferOriginal(store: relationalStore.RdbStore): Promise<void> {
    const hasPreferOriginal: boolean = await LocalDataStore.hasColumn(
      store,
      'download_gallery_tasks',
      'prefer_original',
    )
    if (hasPreferOriginal) {
      return
    }
    await store.executeSql(SQL_ADD_DOWNLOAD_GALLERY_TASKS_PREFER_ORIGINAL)
  }

  private static async migrateImageBlockRuleSourceMetadata(store: relationalStore.RdbStore): Promise<void> {
    const hasSourceUrl: boolean = await LocalDataStore.hasColumn(store, 'image_block_rules', 'source_url')
    if (!hasSourceUrl) {
      await store.executeSql(SQL_ADD_IMAGE_BLOCK_RULES_SOURCE_URL)
    }
    const hasSourcePage: boolean = await LocalDataStore.hasColumn(store, 'image_block_rules', 'source_page')
    if (!hasSourcePage) {
      await store.executeSql(SQL_ADD_IMAGE_BLOCK_RULES_SOURCE_PAGE)
    }
    const hasRulePreview: boolean = await LocalDataStore.hasColumn(store, 'image_block_rules', 'preview_path')
    if (!hasRulePreview) {
      await store.executeSql(SQL_ADD_IMAGE_BLOCK_RULES_PREVIEW_PATH)
    }
  }

  private static async migrateImageBlockLegacyTables(store: relationalStore.RdbStore): Promise<void> {
    const hasWhitelist: boolean = await LocalDataStore.hasTable(store, 'image_block_whitelist')
    const hasOverrides: boolean = await LocalDataStore.hasTable(store, 'image_block_rule_overrides')
    if (!hasWhitelist && !hasOverrides) {
      return
    }
    store.beginTransaction()
    try {
      if (hasWhitelist) {
        const hasPreview: boolean = await LocalDataStore.hasColumn(store, 'image_block_whitelist', 'preview_path')
        if (!hasPreview) {
          await store.executeSql('ALTER TABLE image_block_whitelist ADD COLUMN preview_path TEXT')
        }
        await store.executeSql(SQL_MIGRATE_IMAGE_BLOCK_WHITELIST_TO_RULES)
        await store.executeSql(SQL_DROP_IMAGE_BLOCK_WHITELIST_TABLE)
      }
      if (hasOverrides) {
        const hasEnabledOverride: boolean = await LocalDataStore.hasColumn(
          store,
          'image_block_rule_overrides',
          'enabled_override',
        )
        if (hasEnabledOverride) {
          await store.executeSql(SQL_MIGRATE_IMAGE_BLOCK_OVERRIDE_ENABLED_TO_RULES)
        }
        const hasThresholdOverride: boolean = await LocalDataStore.hasColumn(
          store,
          'image_block_rule_overrides',
          'threshold_override',
        )
        if (hasThresholdOverride) {
          await store.executeSql(SQL_MIGRATE_IMAGE_BLOCK_OVERRIDE_THRESHOLD_TO_RULES)
        }
        await store.executeSql(SQL_DROP_IMAGE_BLOCK_RULE_OVERRIDES_TABLE)
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to migrate image block rules')
    }
  }

  private static async migrateImageBlockUserRuleColumnOrder(store: relationalStore.RdbStore): Promise<void> {
    const columns: string[] = await LocalDataStore.tableColumns(store, 'image_block_user_rules')
    if (LocalDataStore.sameColumns(columns, IMAGE_BLOCK_USER_RULE_COLUMNS)) {
      return
    }
    const selectColumns: string[] = IMAGE_BLOCK_USER_RULE_COLUMNS.map((column: string): string => {
      if (columns.includes(column)) {
        return column
      }
      return LocalDataStore.defaultImageBlockUserRuleColumn(column) + ' AS ' + column
    })
    store.beginTransaction()
    try {
      await store.executeSql(SQL_DROP_IMAGE_BLOCK_USER_RULES_V18_TABLE)
      await store.executeSql(SQL_CREATE_IMAGE_BLOCK_USER_RULES_V18_TABLE)
      await store.executeSql(
        'INSERT INTO image_block_user_rules_v18 (' +
        IMAGE_BLOCK_USER_RULE_COLUMNS.join(', ') +
        ') SELECT ' +
        selectColumns.join(', ') +
        ' FROM image_block_user_rules',
      )
      await store.executeSql(SQL_DROP_IMAGE_BLOCK_USER_RULES_TABLE)
      await store.executeSql(SQL_RENAME_IMAGE_BLOCK_USER_RULES_V18_TABLE)
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to migrate image block user rules')
    }
  }

  private static sameColumns(columns: string[], expected: string[]): boolean {
    if (columns.length !== expected.length) {
      return false
    }
    for (let index: number = 0; index < expected.length; index++) {
      if (columns[index] !== expected[index]) {
        return false
      }
    }
    return true
  }

  private static defaultImageBlockUserRuleColumn(column: string): string {
    if (column === 'threshold' || column === 'source_page' || column === 'enabled' ||
      column === 'updated_at' || column === 'deleted_at') {
      return '0'
    }
    return '\'\''
  }

  private static async migrateDownloadGalleryUpgradeFromGid(store: relationalStore.RdbStore): Promise<void> {
    const hasUpgradeFromGid: boolean = await LocalDataStore.hasColumn(
      store,
      'download_gallery_tasks',
      'upgrade_from_gid',
    )
    if (hasUpgradeFromGid) {
      return
    }
    await store.executeSql(SQL_ADD_DOWNLOAD_GALLERY_TASKS_UPGRADE_FROM_GID)
  }

  private static async migrateDownloadGalleryCoverDimensions(store: relationalStore.RdbStore): Promise<void> {
    const hasImgWidth: boolean = await LocalDataStore.hasColumn(
      store,
      'download_gallery_tasks',
      'img_width',
    )
    if (!hasImgWidth) {
      await store.executeSql(SQL_ADD_DOWNLOAD_GALLERY_TASKS_IMG_WIDTH)
    }
    const hasImgHeight: boolean = await LocalDataStore.hasColumn(
      store,
      'download_gallery_tasks',
      'img_height',
    )
    if (!hasImgHeight) {
      await store.executeSql(SQL_ADD_DOWNLOAD_GALLERY_TASKS_IMG_HEIGHT)
    }
  }

  private static async migrateDownloadGalleryTaskQualityKey(store: relationalStore.RdbStore): Promise<void> {
    const tasksUsePreferOriginalKey: boolean = await LocalDataStore.hasPrimaryKeyColumn(
      store,
      'download_gallery_tasks',
      'prefer_original',
    )
    const seedsUsePreferOriginalKey: boolean = await LocalDataStore.hasPrimaryKeyColumn(
      store,
      'download_gallery_seeds',
      'prefer_original',
    )
    if (tasksUsePreferOriginalKey && seedsUsePreferOriginalKey) {
      return
    }
    store.beginTransaction()
    try {
      await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_TASKS_V15_TABLE)
      await store.executeSql(SQL_COPY_DOWNLOAD_GALLERY_TASKS_TO_V15)
      await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_V15_TABLE)
      await store.executeSql(SQL_COPY_DOWNLOAD_GALLERY_SEEDS_TO_V15)
      await store.executeSql(SQL_DROP_DOWNLOAD_GALLERY_SEEDS_TABLE)
      await store.executeSql(SQL_DROP_DOWNLOAD_GALLERY_TASKS_TABLE)
      await store.executeSql(SQL_RENAME_DOWNLOAD_GALLERY_TASKS_V15_TABLE)
      await store.executeSql(SQL_RENAME_DOWNLOAD_GALLERY_SEEDS_V15_TABLE)
      store.commit()
    } catch (error) {
      store.rollBack()
      const e: Error = error as Error
      throw new Error(e.message || 'Failed to migrate download gallery quality key')
    }
  }

  private static async hasPrimaryKeyColumn(
    store: relationalStore.RdbStore,
    tableName: string,
    columnName: string,
  ): Promise<boolean> {
    const rs: relationalStore.ResultSet = await store.querySql('PRAGMA table_info(' + tableName + ')')
    try {
      while (rs.goToNextRow()) {
        const nameIndex: number = rs.getColumnIndex('name')
        const pkIndex: number = rs.getColumnIndex('pk')
        if (!rs.isColumnNull(nameIndex) && rs.getString(nameIndex) === columnName &&
          !rs.isColumnNull(pkIndex) && rs.getDouble(pkIndex) > 0) {
          return true
        }
      }
    } finally {
      rs.close()
    }
    return false
  }

  private static async migrateDownloadArchiverToken(store: relationalStore.RdbStore): Promise<void> {
    const hasToken: boolean = await LocalDataStore.hasColumn(
      store,
      'download_archiver_tasks',
      'token',
    )
    if (hasToken) {
      return
    }
    await store.executeSql(SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_TOKEN)
  }

  private static async migrateDownloadArchiverThumbUrl(store: relationalStore.RdbStore): Promise<void> {
    const hasThumbUrl: boolean = await LocalDataStore.hasColumn(
      store,
      'download_archiver_tasks',
      'thumb_url',
    )
    if (hasThumbUrl) {
      return
    }
    await store.executeSql(SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_THUMB_URL)
  }

  private static async migrateDownloadArchiverCoverDimensions(store: relationalStore.RdbStore): Promise<void> {
    const hasImgWidth: boolean = await LocalDataStore.hasColumn(
      store,
      'download_archiver_tasks',
      'img_width',
    )
    if (!hasImgWidth) {
      await store.executeSql(SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_IMG_WIDTH)
    }
    const hasImgHeight: boolean = await LocalDataStore.hasColumn(
      store,
      'download_archiver_tasks',
      'img_height',
    )
    if (!hasImgHeight) {
      await store.executeSql(SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_IMG_HEIGHT)
    }
  }

  private static async migrateDownloadArchiverParseSource(store: relationalStore.RdbStore): Promise<void> {
    const hasParseSource: boolean = await LocalDataStore.hasColumn(
      store,
      'download_archiver_tasks',
      'parse_source',
    )
    if (hasParseSource) {
      return
    }
    await store.executeSql(SQL_ADD_DOWNLOAD_ARCHIVER_TASKS_PARSE_SOURCE)
  }

  private static async hasColumn(
    store: relationalStore.RdbStore,
    tableName: string,
    columnName: string,
  ): Promise<boolean> {
    const rs: relationalStore.ResultSet = await store.querySql('PRAGMA table_info(' + tableName + ')')
    try {
      while (rs.goToNextRow()) {
        const index: number = rs.getColumnIndex('name')
        if (!rs.isColumnNull(index) && rs.getString(index) === columnName) {
          return true
        }
      }
    } finally {
      rs.close()
    }
    return false
  }

  private static async tableColumns(
    store: relationalStore.RdbStore,
    tableName: string,
  ): Promise<string[]> {
    const columns: string[] = []
    const rs: relationalStore.ResultSet = await store.querySql('PRAGMA table_info(' + tableName + ')')
    try {
      while (rs.goToNextRow()) {
        const index: number = rs.getColumnIndex('name')
        if (!rs.isColumnNull(index)) {
          columns.push(rs.getString(index))
        }
      }
    } finally {
      rs.close()
    }
    return columns
  }

  private static async hasTable(
    store: relationalStore.RdbStore,
    tableName: string,
  ): Promise<boolean> {
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT name FROM sqlite_master WHERE type = \'table\' AND name = ?',
      [tableName],
    )
    try {
      return rs.goToNextRow()
    } finally {
      rs.close()
    }
  }
}
