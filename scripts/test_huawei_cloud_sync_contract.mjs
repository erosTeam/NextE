#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (name, value) => {
  if (value) {
    console.log(`✓ ${name}`)
  } else {
    failures += 1
    console.error(`✗ ${name}`)
  }
}
const inOrder = (text, needles) => {
  let cursor = -1
  for (const needle of needles) {
    const next = text.indexOf(needle, cursor + 1)
    if (next < 0) {
      return false
    }
    cursor = next
  }
  return true
}

const expectedCloudTables = [
  'gallery_read_progress',
  'viewed_history',
  'local_favorites',
  'search_history',
  'local_block_settings',
  'local_block_rules',
  'image_block_user_rules',
  'custom_profiles',
  'custom_profile_selection',
]
const expectedLocalTables = expectedCloudTables.concat(['image_block_subscriptions'])
const expectedCloudAliases = new Map([
  ['gallery_read_progress', 'GalleryReadProgress'],
  ['viewed_history', 'ViewedHistory'],
  ['local_favorites', 'LocalFavorites'],
  ['search_history', 'SearchHistory'],
  ['local_block_settings', 'LocalBlockSettings'],
  ['local_block_rules', 'LocalBlockRules'],
  ['image_block_user_rules', 'ImageBlockUserRules'],
  ['custom_profiles', 'CustomProfiles'],
  ['custom_profile_selection', 'CustomProfileSelection'],
])
const forbiddenTables = [
  'tag_translations',
  'tag_translation_meta',
  'eh_page_cache',
  'comment_translation_cache',
  'download_gallery_tasks',
  'download_gallery_seeds',
  'download_archiver_tasks',
  'schema_meta',
]

const buildFlag = read('shared/src/main/ets/sync/HuaweiCloudSyncBuildFlag.ets')
const appJson = read('AppScope/app.json5')
ok('Huawei cloud build flag defaults on for local development',
  /HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = true/.test(buildFlag) &&
    /Local development defaults/.test(buildFlag))
ok('Huawei cloud structured-data app capability defaults on for local development',
  /"cloudStructuredDataSyncEnabled": true/.test(appJson))

const signedBuild = read('scripts/build_hvigor_signed.sh')
ok('signed build can temporarily disable Huawei cloud sync for public builds',
  /NEXTE_HUAWEI_CLOUD_SYNC/.test(signedBuild) &&
    /HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = false/.test(signedBuild) &&
    /"cloudStructuredDataSyncEnabled": false/.test(signedBuild) &&
    /trap restore_build_flags EXIT/.test(signedBuild))

const githubBuild = read('.github/workflows/build.yml')
ok('GitHub Actions unsigned build disables Huawei cloud sync for public artifacts',
  /NEXTE_HUAWEI_CLOUD_SYNC:\s*'0'/.test(githubBuild) &&
    /Disable Huawei Cloud sync for public CI builds/.test(githubBuild) &&
    /HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = false/.test(githubBuild) &&
    /"cloudStructuredDataSyncEnabled": false/.test(githubBuild))

const service = read('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')
const scheduler = read('shared/src/main/ets/sync/HuaweiCloudSyncScheduler.ets')
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
const syncScheduler = read('shared/src/main/ets/sync/SyncScheduler.ets')
ok('Huawei cloud service checks availability before permission or sync',
  /available\(\): boolean/.test(service) &&
    /if \(!HuaweiCloudSyncService\.available\(\)\)/.test(service) &&
    /ensurePermission/.test(service) &&
    /cloudSyncNow/.test(service))
ok('Huawei cloud sync flushes selected reader progress before the provider reads RDB',
  /if \(selection\.readProgress\) \{\s*await GalleryReadProgressSettings\.flushForSync\(context\)/.test(service) &&
    /GalleryReadProgressSettings/.test(service))
ok('Huawei cloud service uses official RDB cloud sync entry points',
  /ohos\.permission\.DISTRIBUTED_DATASYNC/.test(service) &&
    /requestPermissionsFromUser/.test(service) &&
    /setDistributedTables/.test(service) &&
    /relationalStore\.DistributedType\.DISTRIBUTED_CLOUD/.test(service) &&
    /relationalStore\.SyncMode\.SYNC_MODE_TIME_FIRST/.test(service) &&
    /cloudSync/.test(service))
ok('Huawei cloud enables system auto sync uniformly for selected tables and disables deselected tables',
  /const configured: boolean = await HuaweiCloudSyncService\.configureAutomaticSync\([\s\S]*if \(!configured\)[\s\S]*if \(tables\.includes\(IMAGE_BLOCK_USER_RULES_TABLE\)\)[\s\S]*await SyncLocalDataAdapter\.prepareHuaweiCloudTables/.test(service) &&
    /const disabledConfig: relationalStore\.DistributedConfig = \{ autoSync: false \}/.test(service) &&
    /const enabledConfig: relationalStore\.DistributedConfig = \{ autoSync: true \}/.test(service) &&
    /HUAWEI_CLOUD_SYNC_TABLES/.test(service) &&
    !/setHistoryAutoSync/.test(service))
ok('manual Huawei cloud sync constrains each run to the selected table subset',
  /mode: relationalStore\.SyncMode = relationalStore\.SyncMode\.SYNC_MODE_TIME_FIRST/.test(service) &&
    /\.cloudSync\(\s*mode,\s*tables,\s*\(progress: relationalStore\.ProgressDetails\) =>/.test(service) &&
    /waitCloudSyncFinish\([\s\S]*store,[\s\S]*tables,[\s\S]*context/.test(service))
ok('Huawei cloud detail notifications refresh selected state without an app repair loop',
  /SUBSCRIBE_TYPE_CLOUD_DETAILS/.test(service) &&
    /SyncServiceBridge\.refresh\(context, SyncSettings\.selection/.test(service) &&
    /cloudListenerStore: relationalStore\.RdbStore \| null/.test(service) &&
    /HuaweiCloudSyncService\.cloudListenerStore = store/.test(service) &&
    !/SYNC_MODE_CLOUD_FIRST|reconcileViewedHistoryFromCloud|viewedHistoryCorrections/.test(service) &&
    !/viewedHistoryCorrections/.test(read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')))
ok('normal Huawei cloud sync stays system-owned for image-block user rules',
  /IMAGE_BLOCK_USER_RULES_TABLE: string = 'image_block_user_rules'/.test(service) &&
    !/cleanDirtyData\(IMAGE_BLOCK_USER_RULES_TABLE\)/.test(service) &&
    !/huawei_cloud_image_block_clean_dirty/.test(service) &&
    !/shouldUploadImageBlockBeforePull/.test(service) &&
    !/huawei_cloud_image_block_native_first/.test(service) &&
    !/SYNC_MODE_NATIVE_FIRST/.test(service) &&
    !/huawei_cloud_image_block_native_repair/.test(service) &&
    !/shouldRepairImageBlockFromLocal/.test(service) &&
    !/shouldRetryNativeFirst/.test(service) &&
    !/CloudSyncTableResetRepository/.test(service) &&
    !/huawei_cloud_rebuild_table/.test(service) &&
    !/huawei_cloud_reseed_table/.test(service))
ok('Huawei cloud schema does not add versioned CustomProfiles reset aliases',
  !/CustomProfilesV\d+/.test(read('entry/src/main/resources/rawfile/arkdata/cloud/cloud_schema.json')) &&
    !/CustomProfileSelectionV\d+/.test(read('entry/src/main/resources/rawfile/arkdata/cloud/cloud_schema.json')) &&
    !/CustomProfilesV\d+/.test(service) &&
    !/CustomProfileSelectionV\d+/.test(service))
ok('manual Huawei cloud sync allows enough time for first full upload',
  /CLOUD_SYNC_TIMEOUT_MS: number = 240000/.test(service))
ok('manual Huawei cloud sync exposes table-level failure detail',
  /lastRunDetailMessage\(\): string/.test(service) &&
    /progressDetailMessage/.test(service) &&
    /huawei_cloud_sync_done[\s\S]*detail=/.test(service) &&
    /huaweiCloudLastDetail/.test(read('shared/src/main/ets/state/SyncSettingsState.ets')) &&
    /SYNC_HUAWEI_CLOUD_LAST_DETAIL/.test(read('shared/src/main/ets/settings/SyncSettings.ets')))
ok('Huawei cloud image-block schema failures are reported without a fallback run',
  /IMAGE_BLOCK_USER_RULES_TABLE: string = 'image_block_user_rules'/.test(service) &&
    !/IMAGE_BLOCK_SCHEMA_PENDING_DETAIL/.test(service) &&
    !/imageBlockCloudSuspended/.test(service) &&
    !/tablesForCloudRun/.test(service) &&
    !/huawei_cloud_image_block_suspended/.test(service) &&
    !/shouldRetryWithoutImageBlock/.test(service) &&
    !/withoutImageBlockTable/.test(service) &&
    !/huawei_cloud_image_block_degraded/.test(service) &&
    !/huawei_cloud_sync_partial/.test(service) &&
    !/treatImageBlockPartialAsSuccess/.test(service) &&
    !/return treatImageBlockPartialAsSuccess/.test(service))
ok('Huawei cloud scheduled sync coalesces local writes uniformly for every selected table',
  /LOCAL_WRITE_DEBOUNCE_MS: number = 15000/.test(scheduler) &&
    /FOREGROUND_DEBOUNCE_MS: number = 3000/.test(scheduler) &&
    /MIN_ATTEMPT_INTERVAL_MS: number = 45000/.test(scheduler) &&
    /requestAfterLocalWrite/.test(scheduler) &&
    /requestAfterForeground/.test(scheduler) &&
    /SyncSettings\.current\(\)\.huaweiCloudEnabled/.test(scheduler) &&
    !/viewed_history|ViewedHistory|history/.test(scheduler))
ok('Huawei cloud scheduled sync retries failed runs without waiting for another foreground event',
  /failureCount = Math\.min\(HuaweiCloudSyncScheduler\.failureCount \+ 1, 4\)/.test(scheduler) &&
    /retryReason: string = reason\.startsWith\('retry:'\)/.test(scheduler) &&
    /scheduleTimer\(\s*HuaweiCloudSyncScheduler\.retryDelayMs\(\),\s*retryReason/.test(scheduler))
ok('EntryAbility binds scheduled uploads while startup also enables native cloud delivery',
    /HuaweiCloudSyncScheduler\.bindExecutor/.test(entryAbility) &&
    /HuaweiCloudSyncService\.runScheduledSync\(context, reason\)/.test(entryAbility) &&
    /HuaweiCloudSyncService\.tryEnableStartup\(this\.context\)/.test(entryAbility) &&
    !/SyncLocalDataAdapter\.prepareHuaweiCloudTables/.test(entryAbility) &&
    /SyncScheduler\.requestAfterForeground\(this\.context, 'startup'\)/.test(entryAbility) &&
    /onForeground\(\): void \{[\s\S]*SyncScheduler\.requestAfterForeground\(this\.context, 'foreground'\)/.test(entryAbility) &&
    /HuaweiCloudSyncScheduler\.requestAfterForeground\(context, reason\)/.test(syncScheduler) &&
    /WebDavSyncScheduler\.requestAfterForeground\(context, reason\)/.test(syncScheduler))

const localWriteFiles = [
  ['shared/src/main/ets/settings/GalleryReadProgressSettings.ets', 'read_progress'],
  ['shared/src/main/ets/settings/ViewedHistorySettings.ets', 'viewed_history'],
  ['shared/src/main/ets/settings/LocalFavSettings.ets', 'local_favorites'],
  ['shared/src/main/ets/settings/SearchHistorySettings.ets', 'search_history'],
  ['shared/src/main/ets/settings/LocalBlockSettings.ets', 'local_block'],
  ['shared/src/main/ets/settings/CustomProfilesSettings.ets', 'custom_profiles'],
]
for (const [file, reason] of localWriteFiles) {
  const src = read(file)
  ok(`${file} requests provider-neutral sync after local writes`,
    /SyncScheduler/.test(src) &&
      src.includes(`requestAfterLocalWrite(context, '${reason}`))
}

const moduleJson = read('entry/src/main/module.json5')
ok('distributed data sync permission has required user-grant metadata',
  /ohos\.permission\.DISTRIBUTED_DATASYNC/.test(moduleJson) &&
    /reason": "\$string:perm_distributed_datasync_reason"/.test(moduleJson) &&
    /"abilities": \["EntryAbility"\]/.test(moduleJson) &&
    /"when": "inuse"/.test(moduleJson))

const features = read('shared/src/main/ets/sync/CloudSyncFeatures.ets')
for (const table of expectedCloudTables) {
  ok(`cloud feature mapping includes ${table}`, features.includes(`'${table}'`))
}
ok('Huawei cloud image block table selection skips subscription metadata',
  !features.includes(`'image_block_subscriptions'`) &&
    features.includes(`'image_block_user_rules'`))
for (const table of forbiddenTables) {
  ok(`cloud feature mapping excludes ${table}`, !features.includes(table))
}

const schema = JSON.parse(read('entry/src/main/resources/rawfile/arkdata/cloud/cloud_schema.json'))
const expectedCloudSchemaVersion = 18
const appVersionCode = Number(appJson.match(/"versionCode":\s*(\d+)/)?.[1] ?? 0)
ok('cloud schema is for NextE bundle and database',
  schema.bundleName === 'com.erosteam.nexte' &&
    schema.metaVersion === 65537 &&
    schema.e2eeEnable === false &&
    schema.databases.length === 1 &&
    schema.databases[0].name === 'NextE' &&
    schema.databases[0].bundleName === 'com.erosteam.nexte' &&
    schema.databases[0].version === schema.version &&
    schema.databases[0].autoSyncType === 0)
ok('cloud schema declares the coordinated AGC migration target',
  schema.version === expectedCloudSchemaVersion &&
    schema.databases[0].version === expectedCloudSchemaVersion)
ok('app versionCode is bumped with Huawei cloud schema version',
  appVersionCode >= expectedCloudSchemaVersion)

const schemaTables = schema.databases[0].tables.map((table) => table.name)
ok('cloud schema table set exactly matches syncable durable tables',
  expectedCloudTables.every((table) => schemaTables.includes(table)) &&
    schemaTables.every((table) => expectedCloudTables.includes(table)))
ok('Huawei cloud schema does not expose image block subscription metadata',
  !schemaTables.includes('image_block_subscriptions') &&
    schemaTables.includes('image_block_user_rules'))
for (const table of forbiddenTables) {
  ok(`cloud schema excludes ${table}`, !schemaTables.includes(table))
}

for (const table of schema.databases[0].tables) {
  ok(`${table.name} cloud alias matches AGC data type name`,
    expectedCloudAliases.get(table.name) === table.alias)
  ok(`${table.name} has at least one duplicate-check primary key`,
    table.fields.some((field) => field.primary === true && field.dupCheckCol === true))
  ok(`${table.name} cloud fields are nullable`,
    table.fields.every((field) => field.nullable === true))
}
const customProfileSchema = schema.databases[0].tables.find((table) => table.name === 'custom_profiles')
ok('custom profiles cloud schema avoids AGC reserved uuid field name',
  !!customProfileSchema &&
    customProfileSchema.fields.some((field) =>
      field.colName === 'profile_uuid' && field.primary === true && field.dupCheckCol === true) &&
    !customProfileSchema.fields.some((field) => field.colName === 'uuid'))
const imageBlockUserRuleSchema = schema.databases[0].tables.find((table) => table.name === 'image_block_user_rules')
const imageBlockUserRuleFieldOrder = imageBlockUserRuleSchema
  ? imageBlockUserRuleSchema.fields.map((field) => field.colName)
  : []
ok('image block user rule cloud schema matches AGC device duplicate-key order',
  imageBlockUserRuleFieldOrder.join(',') === [
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
  ].join(','))
const readProgressSchema = schema.databases[0].tables.find((table) => table.name === 'gallery_read_progress')
ok('gallery read progress cloud schema includes per-gallery double-page pairing',
  !!readProgressSchema &&
    readProgressSchema.fields.some((field) =>
      field.colName === 'column_mode' &&
      field.type === 3 &&
      field.primary === false &&
      field.nullable === true &&
      field.dupCheckCol === false))
const viewedHistorySchema = schema.databases[0].tables.find((table) => table.name === 'viewed_history')
const viewedHistoryFieldOrder = viewedHistorySchema
  ? viewedHistorySchema.fields.map((field) => field.colName)
  : []
ok('viewed history cloud schema carries one canonical list snapshot in physical-table order',
  viewedHistoryFieldOrder.join(',') === [
    'scope_key',
    'gid',
    'token',
    'title',
    'title_jp',
    'thumb_url',
    'category',
    'uploader',
    'rating',
    'file_count',
    'viewed_at',
    'deleted_at',
    'post_time',
    'rating_fallback',
    'color_rating',
    'translated',
    'expunged',
  ].join(','))

const localStore = read('shared/src/main/ets/storage/LocalDataStore.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const imageBlockRepo = read('shared/src/main/ets/storage/ImageBlockRepository.ets')
const readProgressRepo = read('shared/src/main/ets/storage/ReadProgressRepository.ets')
const localStoreVersionMatch = localStore.match(/LOCAL_DATA_SCHEMA_VERSION: number = (\d+)/)
ok('local RDB schema version keeps image-block column-order migration',
  !!localStoreVersionMatch &&
    Number(localStoreVersionMatch[1]) >= 20 &&
    localStore.includes(`schema_version\\', \\'${localStoreVersionMatch[1]}\\'`))
for (const table of expectedLocalTables) {
  ok(`local store creates ${table}`, localStore.includes(`CREATE TABLE IF NOT EXISTS ${table} (`))
}
const imageBlockUserRuleCreateStart = localStore.indexOf('const SQL_CREATE_IMAGE_BLOCK_USER_RULES_TABLE')
const imageBlockUserRuleCreateEnd = localStore.indexOf('const SQL_CREATE_IMAGE_BLOCK_USER_RULES_HASH_INDEX')
const imageBlockUserRuleCreateSql = imageBlockUserRuleCreateStart >= 0 && imageBlockUserRuleCreateEnd > imageBlockUserRuleCreateStart
  ? localStore.slice(imageBlockUserRuleCreateStart, imageBlockUserRuleCreateEnd)
  : ''
const imageBlockUserRuleColumnOrder = [
  'rule_id TEXT',
  'scope_key TEXT',
  'hash TEXT',
  'threshold INTEGER',
  'label TEXT',
  'scope TEXT',
  'feed_id TEXT',
  'source_type TEXT',
  'source_url TEXT',
  'source_page INTEGER',
  'preview_path TEXT',
  'enabled INTEGER',
  'updated_at INTEGER',
  'deleted_at INTEGER DEFAULT 0',
]
ok('local image block user rule physical column order matches cloud schema',
  inOrder(imageBlockUserRuleCreateSql, imageBlockUserRuleColumnOrder) &&
    /PRIMARY KEY\(rule_id, scope_key\)/.test(imageBlockUserRuleCreateSql))
const viewedHistoryCreateStart = localStore.indexOf('const SQL_CREATE_VIEWED_HISTORY_TABLE')
const viewedHistoryCreateEnd = localStore.indexOf('const SQL_ADD_VIEWED_HISTORY_POST_TIME')
const viewedHistoryCreateSql = viewedHistoryCreateStart >= 0 && viewedHistoryCreateEnd > viewedHistoryCreateStart
  ? localStore.slice(viewedHistoryCreateStart, viewedHistoryCreateEnd)
  : ''
ok('local viewed history physical column order matches cloud schema and upgrades v23 in place',
  inOrder(viewedHistoryCreateSql, [
    'scope_key TEXT',
    'gid TEXT',
    'token TEXT',
    'title TEXT',
    'title_jp TEXT',
    'thumb_url TEXT',
    'category TEXT',
    'uploader TEXT',
    'rating REAL',
    'file_count TEXT',
    'viewed_at INTEGER',
    'deleted_at INTEGER DEFAULT 0',
    'post_time TEXT',
    'rating_fallback REAL',
    'color_rating TEXT',
    'translated TEXT',
    'expunged INTEGER',
  ]) &&
    /migrateViewedHistorySnapshotColumns/.test(localStore) &&
    /ALTER TABLE viewed_history ADD COLUMN post_time TEXT/.test(localStore) &&
    !/viewed_history_metadata/.test(localStore))
ok('local image block user rule SQL matches AGC端侧去重主键 order',
  !/image_block_user_rules_cloud_order_tmp/.test(localStore) &&
    /ON CONFLICT\(rule_id, scope_key\)/.test(syncAdapter) &&
    /ON CONFLICT\(rule_id, scope_key\)/.test(imageBlockRepo) &&
    /INSERT INTO image_block_user_rules [\s\S]*source_url, source_page, preview_path, enabled, updated_at, deleted_at/.test(syncAdapter) &&
    /INSERT INTO image_block_user_rules [\s\S]*source_url, source_page, preview_path, enabled, updated_at, deleted_at/.test(imageBlockRepo))
ok('custom profiles local RDB uses profile_uuid and migrates old uuid column',
  /profile_uuid TEXT/.test(localStore) &&
    /PRIMARY KEY\(scope_key, profile_uuid\)/.test(localStore) &&
    /migrateCustomProfilesUuidColumn/.test(localStore) &&
    /SQL_COPY_CUSTOM_PROFILES_UUID_TO_PROFILE_UUID/.test(localStore) &&
    !/['"]uuid TEXT, /.test(localStore))
ok('custom profile sync canonicalizes seeded search tabs before uuid-based merge',
  /normalizeCustomProfileRecord\(r\)/.test(syncAdapter) &&
    /canonicalStarterUuid\(r\)/.test(syncAdapter) &&
    /STARTER_CHINESE_UUID/.test(syncAdapter) &&
    /STARTER_ANTHOLOGY_UUID/.test(syncAdapter) &&
    /r\.searchText === 'language:chinese'/.test(syncAdapter) &&
    /r\.searchText === 'other:anthology'/.test(syncAdapter))
ok('read progress repository has no Huawei cloud table rebuild hook',
  !/cleanDirtyAndRebuildForCloud|CloudSyncTableResetRepository|rebuildTablesForCloud/.test(readProgressRepo))
ok('image block sync uses image_block_user_rules as the user-rule source table',
  syncAdapter.includes('COALESCE(source_type, \\\'\\\') <> \\\'subscription\\\'') &&
    /FROM image_block_user_rules/.test(syncAdapter) &&
    /image_block_user_rules/.test(features) &&
    !features.includes(`'image_block_subscriptions'`) &&
    /prepareHuaweiCloudTables/.test(syncAdapter) &&
    /_selection: SyncDatasetSelection/.test(syncAdapter) &&
    !/_selection\.imageBlock/.test(syncAdapter) &&
    !/image_block_user_rules_cloud_touch/.test(syncAdapter) &&
    !/image_block_cloud_touch/.test(syncAdapter) &&
    !/markImageBlockCloudTouchComplete/.test(syncAdapter) &&
    !/completeImageBlockTouchIfNeeded/.test(service) &&
    !/UPDATE image_block_user_rules SET updated_at = \? WHERE/.test(syncAdapter) &&
    !/updated_at \+ 1/.test(syncAdapter) &&
    !/prepareHuaweiCloudTables\(context, selection, true\)/.test(service) &&
    !/typeof\(enabled\) <> \\'text\\'/.test(syncAdapter) &&
    !/typeof\(deleted_at\) <> \\'text\\'/.test(syncAdapter) &&
    !/SQL_REPAIR_IMAGE_BLOCK_ACTIVE_USER_RULE_TOMBSTONES/.test(syncAdapter) &&
    !/SQL_DELETE_IMAGE_BLOCK_MAIN_USER_RULES_AFTER_SYNC/.test(syncAdapter) &&
    !/dedupeImageBlockUserRules/.test(syncAdapter) &&
    !/image_block_cloud_dedupe/.test(syncAdapter) &&
    /SQL_SYNC_IMAGE_BLOCK_SUBSCRIPTION_DISABLES_FROM_MAIN/.test(syncAdapter) &&
    /SQL_UPSERT_USER_RULE/.test(imageBlockRepo) &&
    /FROM image_block_user_rules/.test(imageBlockRepo) &&
    !/syncOneUserRuleFromMain/.test(imageBlockRepo) &&
    !/SyncLocalDataAdapter\.prepareHuaweiCloudTables/.test(imageBlockRepo) &&
    /applyHuaweiCloudTables/.test(syncAdapter) &&
    /preview_path/.test(syncAdapter) &&
    /r\.previewPath = ''/.test(syncAdapter) &&
    !/r\.previewPath = SyncLocalDataAdapter\.stringColumn\(rs, 'preview_path'\)/.test(syncAdapter))
ok('image block cloud sync has no app-managed touch completion path',
  !/imageBlockTableSucceeded/.test(service) &&
    !/image_block_cloud_table_result/.test(service) &&
    !/completeImageBlockTouchIfTableSucceeded/.test(service) &&
    !/completeImageBlockTouchIfNeeded/.test(service) &&
    !/huawei_cloud_image_block_degraded/.test(service) &&
    !/treatImageBlockPartialAsSuccess/.test(service))

if (failures > 0) {
  console.error(`✗ Huawei cloud sync contract: ${failures} failure(s)`)
  process.exit(1)
}
console.log('✓ Huawei cloud sync contract passed')
