import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'

const LOCAL_DATA_DB_NAME: string = 'NextE.db'

const LOCAL_DATA_STORE_CONFIG: relationalStore.StoreConfig = {
  name: LOCAL_DATA_DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S3,
}

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

export class LocalDataStore {
  static async open(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    const store: relationalStore.RdbStore =
      await relationalStore.getRdbStore(context, LOCAL_DATA_STORE_CONFIG)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_TABLE)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_KEY_INDEX)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_NAME_INDEX)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATIONS_LAST_USE_INDEX)
    await store.executeSql(SQL_CREATE_TAG_TRANSLATION_META_TABLE)
    await store.executeSql(SQL_CREATE_EH_PAGE_CACHE_TABLE)
    await store.executeSql(SQL_CREATE_EH_PAGE_CACHE_EXPIRES_INDEX)
    await store.executeSql(SQL_CREATE_EH_PAGE_CACHE_ACCESS_INDEX)
    return store
  }
}
