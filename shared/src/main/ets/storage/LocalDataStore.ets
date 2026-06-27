import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'

const LOCAL_DATA_DB_NAME: string = 'NextE.db'
export const LOCAL_DATA_SCHEMA_VERSION: number = 7

const LOCAL_DATA_STORE_CONFIG: relationalStore.StoreConfig = {
  name: LOCAL_DATA_DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S3,
}

const SQL_CREATE_SCHEMA_META_TABLE: string =
  'CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)'
const SQL_UPSERT_SCHEMA_VERSION: string =
  'INSERT OR REPLACE INTO schema_meta (key, value) VALUES (\'schema_version\', \'7\')'
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
    'updated_at INTEGER, ' +
    'deleted_at INTEGER DEFAULT 0, ' +
    'PRIMARY KEY(scope_key, gid)' +
  ')'
const SQL_CREATE_GALLERY_READ_PROGRESS_UPDATED_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_gallery_read_progress_updated_at ON gallery_read_progress (updated_at DESC)'
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
const SQL_CREATE_CUSTOM_PROFILES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS custom_profiles (' +
    'scope_key TEXT, ' +
    'uuid TEXT, ' +
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
    'PRIMARY KEY(scope_key, uuid)' +
  ')'
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
    'page_count INTEGER NOT NULL, ' +
    'category TEXT NOT NULL, ' +
    'uploader TEXT NOT NULL, ' +
    'queued_at INTEGER NOT NULL, ' +
    'prepared_at INTEGER NOT NULL, ' +
    'first_page_count INTEGER NOT NULL, ' +
    'preview_page_count INTEGER NOT NULL, ' +
    'prepare_error TEXT NOT NULL, ' +
    'status TEXT NOT NULL, ' +
    'PRIMARY KEY(scope_key, gid, token)' +
  ')'
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
    'PRIMARY KEY(scope_key, gid, token, image_page_url)' +
  ')'
const SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_POSITION_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_download_gallery_seeds_position ' +
    'ON download_gallery_seeds (scope_key, gid, token, position_index ASC)'

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
    await store.executeSql(SQL_CREATE_CUSTOM_PROFILES_TABLE)
    await store.executeSql(SQL_CREATE_CUSTOM_PROFILES_POSITION_INDEX)
    await store.executeSql(SQL_CREATE_CUSTOM_PROFILE_SELECTION_TABLE)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_TASKS_TABLE)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_TASKS_QUEUED_INDEX)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_TABLE)
    await store.executeSql(SQL_CREATE_DOWNLOAD_GALLERY_SEEDS_POSITION_INDEX)
    await store.executeSql(SQL_UPSERT_SCHEMA_VERSION)
    if (store.version !== LOCAL_DATA_SCHEMA_VERSION) {
      store.version = LOCAL_DATA_SCHEMA_VERSION
    }
    return store
  }
}
