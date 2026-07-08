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

const doc = read('docs/plans/active/sync-design.md')
ok('sync design keeps Huawei Cloud visible by default with public-build override',
  /Huawei Cloud sync is compiled into the app/.test(doc) &&
    /defaults to visible/.test(doc) &&
    /NEXTE_HUAWEI_CLOUD_SYNC=0 scripts\/build_hvigor_signed\.sh/.test(doc) &&
    /manual WebDAV provider|WebDAV provider/.test(doc))
ok('sync design lists durable syncable tables',
  /gallery_read_progress/.test(doc) &&
    /image_block_subscriptions/.test(doc) &&
    /image_block_rules/.test(doc) &&
    /custom_profile_selection/.test(doc) &&
    /local_block_rules/.test(doc))
ok('sync design records Huawei Cloud image-block resolution and stale-metadata caveat',
  /tables\[\]\.name = snake_case local table/.test(doc) &&
    /setDistributedTables/.test(doc) &&
    /GalleryReadProgress/.test(doc) &&
    /Analysis sql and trigger failed -1003/.test(doc) &&
    /tables\[\]\.alias = PascalCase AGC data type/.test(doc) &&
    /route CloudKit requests to the PascalCase record type/.test(doc) &&
    /normal: 13, deleted: 39/.test(doc) &&
    /lost primary key\[1\]/.test(doc) &&
    /Cloud data do not contain expected primary field value/.test(doc) &&
    /image_block_user_rules:up=0\/0,down=0\/52,fail=52/.test(doc) &&
    /current AGC development data type `ImageBlockUserRules`/.test(doc) &&
    /AGC reports it as production-effective and refuses\s+deletion/.test(doc) &&
    /the client must not reference it again/.test(doc) &&
    /Do not rename the client to another\s+versioned image-block data type/.test(doc) &&
    /Do not add a new `CustomProfilesV2`/.test(doc) &&
    /No image-block first-upload\s+exception remains/.test(doc) &&
    /must not run cleanDirtyData/.test(doc) &&
    /must not run\s+native-first/.test(doc) &&
    /Do not set both `name` and `alias` to snake_case/.test(doc))
ok('sync design excludes cache, downloads, and secrets',
  /tag_translations/.test(doc) &&
    /image_block_hash_cache/.test(doc) &&
    /download_gallery_tasks/.test(doc) &&
    /cookie jars, account secrets, LLM API keys, WebDAV passwords/.test(doc))
ok('sync design requires ON CONFLICT and tombstones',
  /INSERT \.\.\. ON CONFLICT DO UPDATE/.test(doc) &&
    /deleted_at` tombstones/.test(doc))
ok('sync design preserves disabled WebDAV datasets',
  /Dataset Selection/.test(doc) &&
    /All groups default to enabled/.test(doc) &&
    /skips MKCOL\/GET\/\s*merge\/PUT/.test(doc))
ok('sync design requires WebDAV multi-file layout',
  /WebDAV File Layout/.test(doc) &&
    /manifest\.json/.test(doc) &&
    /read-progress\/00\.json \.\.\. 3f\.json/.test(doc) &&
    /search-history\/00\.json \.\.\. 3f\.json/.test(doc) &&
    /image-block\/00\.json \.\.\. 3f\.json/.test(doc) &&
    /stable hash buckets/.test(doc) &&
    /generatedAt` is derived from the newest record timestamp/.test(doc) &&
    /64 buckets/.test(doc) &&
    /PUTs only changed shards/.test(doc) &&
    /must not write a single all-data `nexte-sync-v1\.json`/.test(doc) &&
    /legacy\/transition input only/.test(doc))

const repos = [
  'shared/src/main/ets/storage/SearchHistoryRepository.ets',
  'shared/src/main/ets/storage/ReadProgressRepository.ets',
  'shared/src/main/ets/storage/ViewedHistoryRepository.ets',
  'shared/src/main/ets/storage/LocalFavoriteRepository.ets',
  'shared/src/main/ets/storage/LocalBlockRepository.ets',
  'shared/src/main/ets/storage/CustomProfilesRepository.ets',
  'shared/src/main/ets/storage/ImageBlockRepository.ets',
]

for (const file of repos) {
  const src = read(file)
  ok(`${file} avoids INSERT OR REPLACE`, !/INSERT OR REPLACE/i.test(src))
  ok(`${file} uses conflict upsert`, /ON CONFLICT/i.test(src))
}

const types = read('shared/src/main/ets/sync/SyncTypes.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
const imageBlockRepo = read('shared/src/main/ets/storage/ImageBlockRepository.ets')
ok('sync envelope has explicit datasets',
  /class SyncDatasets/.test(types) &&
    /readProgress: SyncReadProgressRecord\[\]/.test(types) &&
    /imageBlockSubscriptions: SyncImageBlockSubscriptionRecord\[\]/.test(types) &&
    /imageBlockRules: SyncImageBlockRuleRecord\[\]/.test(types) &&
    /customProfileSelection: SyncCustomProfileSelectionRecord\[\]/.test(types))
ok('sync types expose dataset selection toggles',
  /class SyncDatasetSelection/.test(types) &&
    /readProgress: boolean = true/.test(types) &&
    /imageBlock: boolean = true/.test(types) &&
    /customProfiles: boolean = true/.test(types))
ok('sync types do not include cache/download/secrets datasets',
  !/tagTranslation|ehPageCache|commentTranslation|downloadGallery|imageBlockHashCache|cookie|apiKey/i.test(types))

const service = read('shared/src/main/ets/sync/SyncService.ets')
ok('sync service merges remote raw through local adapter',
  /mergeRemoteRaw/.test(service) &&
    /SyncLocalDataAdapter\.mergeEnvelopes/.test(service) &&
    /SyncLocalDataAdapter\.applyEnvelope/.test(service))
ok('sync service preserves disabled remote datasets on write-back',
  /selectDatasets/.test(service) &&
    /mergeSelectedIntoRemote/.test(service) &&
    /config\.selection|selection: SyncDatasetSelection/.test(read('shared/src/main/ets/sync/WebDavSyncService.ets')))
ok('sync service refreshes live state after applying remote data',
  /refreshSelectedState/.test(service) &&
    /SearchHistorySettings\.restore/.test(service) &&
    /GalleryReadProgressSettings\.restore/.test(service) &&
    /CustomProfilesSettings\.restore/.test(service))
ok('sync service normalizes remote JSON records before RDB apply',
  /safeString\(r\.scopeKey\)/.test(service) &&
    /safeNumber\(r\.updatedAt\)/.test(service) &&
    /safeBoolean\(r\.enabled\)/.test(service) &&
    /return ''/.test(service) &&
    /return 0/.test(service))

const webdav = read('shared/src/main/ets/sync/WebDavSyncService.ets')
const webdavScheduler = read('shared/src/main/ets/sync/WebDavSyncScheduler.ets')
const syncScheduler = read('shared/src/main/ets/sync/SyncScheduler.ets')
ok('WebDAV provider uses manifest plus hashed dataset shards',
    /SYNC_WEBDAV_MANIFEST_FILE/.test(webdav) &&
    /SYNC_WEBDAV_ROOT_DIR/.test(webdav) &&
    /'datasets\/' \+ datasetId \+ '\/' \+ shardId \+ '\.json'/.test(webdav) &&
    /SHARD_COUNT: number = 64/.test(webdav) &&
    /shardId\(key: string\)/.test(webdav))
ok('WebDAV provider writes only changed shards',
  /hashText/.test(webdav) &&
    /previousShardHash/.test(webdav) &&
    /continue/.test(webdav) &&
    /writeChangedShards/.test(webdav) &&
    /stableGeneratedAt/.test(webdav) &&
    !/shardEnvelope\.generatedAt\s*=\s*new Date\(\)\.toISOString\(\)/.test(webdav))
ok('WebDAV provider builds shards off UI thread with a single bucket pass',
  /taskpool\.execute<\[string, string\], string>\(buildWebDavShardsTask/.test(webdav) &&
    /collectShardBuckets/.test(webdav) &&
    /bucketForKey/.test(webdav) &&
    /hashText/.test(webdav) &&
    !/private static filterShard/.test(webdav) &&
    !/private static collectShardIds/.test(webdav))
ok('WebDAV provider skips disabled dataset directories',
  /ensureCollections\(rootUrl: string, config: WebDavSyncConfig\)/.test(webdav) &&
    /datasetEnabled\(config\.selection, DATASET_IDS\[i\]\)/.test(webdav) &&
    /continue[\s\S]*makeCollection\(rootUrl \+ 'datasets\/' \+ DATASET_IDS\[i\]/.test(webdav))
ok('WebDAV provider treats single file as legacy input only',
  /legacyFileUrl/.test(webdav) &&
    /SYNC_FILE_NAME/.test(webdav) &&
    !/writeRemote\([^)]*legacyFileUrl/.test(webdav) &&
    !/writeRemote\([^)]*SYNC_FILE_NAME/.test(webdav))
ok('WebDAV basic auth uses UTF-8 encoder',
  /new util\.TextEncoder\(\)\.encodeInto/.test(webdav) &&
    /new util\.Base64Helper\(\)\.encodeToStringSync/.test(webdav))
ok('WebDAV provider has automatic scheduled sync',
  /requestAfterLocalWrite/.test(webdavScheduler) &&
    /requestAfterForeground/.test(webdavScheduler) &&
    /WebDavSyncService\.syncNow/.test(webdavScheduler) &&
    /SyncSettings\.markRun\(context, SYNC_STATUS_OK\)/.test(webdavScheduler) &&
    /SyncSettings\.markRun\(context, SYNC_STATUS_FAILED, error\.message\)/.test(webdavScheduler) &&
    /webdav_scheduled_start/.test(webdavScheduler))
ok('provider-neutral scheduler dispatches local writes and foreground to WebDAV and Huawei Cloud',
  /HuaweiCloudSyncScheduler\.requestAfterLocalWrite\(context, reason\)/.test(syncScheduler) &&
    /WebDavSyncScheduler\.requestAfterLocalWrite\(context, reason\)/.test(syncScheduler) &&
    /HuaweiCloudSyncScheduler\.requestAfterForeground\(context, reason\)/.test(syncScheduler) &&
    /WebDavSyncScheduler\.requestAfterForeground\(context, reason\)/.test(syncScheduler))

const syncSettings = read('shared/src/main/ets/settings/SyncSettings.ets')
const syncState = read('shared/src/main/ets/state/SyncSettingsState.ets')
const storageKeys = read('shared/src/main/ets/constants/StorageKeys.ets')
ok('sync settings persist WebDAV config locally',
  /SYNC_WEBDAV_URL/.test(syncSettings) &&
    /SYNC_WEBDAV_USERNAME/.test(syncSettings) &&
    /SYNC_WEBDAV_ENABLED/.test(syncSettings) &&
    /SYNC_WEBDAV_PASSWORD/.test(syncSettings) &&
    /SYNC_LAST_DETAIL/.test(storageKeys) &&
    /lastDetail/.test(syncState) &&
    /detail: string = ''/.test(syncSettings) &&
    /SYNC_DATASET_READ_PROGRESS/.test(syncSettings) &&
    /static selection/.test(syncSettings) &&
    /never exported/.test(syncSettings))
ok('image block WebDAV sync shares the block-rules dataset switch',
  /selection\.localBlock = snapshot\.datasetLocalBlock/.test(syncSettings) &&
    /selection\.imageBlock = snapshot\.datasetLocalBlock/.test(syncSettings))
ok('sync settings persist Huawei Cloud local status separately',
  /SYNC_HUAWEI_CLOUD_ENABLED/.test(syncSettings) &&
    /markHuaweiCloudRun/.test(syncSettings) &&
    /SYNC_HUAWEI_CLOUD_LAST_DETAIL/.test(syncSettings) &&
    /huaweiCloudLastDetail/.test(read('shared/src/main/ets/state/SyncSettingsState.ets')) &&
    /huaweiCloudLastCloudDisabled/.test(syncSettings))
ok('sync run status updates avoid full settings rewrites',
  /saveRunStatus/.test(syncSettings) &&
    /saveHuaweiCloudRunStatus/.test(syncSettings) &&
    /store\.putSync\(StorageKeys\.SYNC_LAST_RUN_AT/.test(syncSettings) &&
    /store\.putSync\(StorageKeys\.SYNC_HUAWEI_CLOUD_LAST_RUN_AT/.test(syncSettings) &&
    /await store\.flush\(\)/.test(syncSettings) &&
    !/markRun[\s\S]{0,450}SyncSettings\.save\(context, snapshot\)/.test(syncSettings) &&
    !/markHuaweiCloudRun[\s\S]{0,650}SyncSettings\.save\(context, snapshot\)/.test(syncSettings))

const cloudBuildFlag = read('shared/src/main/ets/sync/HuaweiCloudSyncBuildFlag.ets')
const huaweiCloud = read('shared/src/main/ets/sync/HuaweiCloudSyncService.ets')
const cloudFeatures = read('shared/src/main/ets/sync/CloudSyncFeatures.ets')
const localStore = read('shared/src/main/ets/storage/LocalDataStore.ets')
const moduleJson = read('entry/src/main/module.json5')
const signedBuild = read('scripts/build_hvigor_signed.sh')
const cloudSchema = JSON.parse(read('entry/src/main/resources/rawfile/arkdata/cloud/cloud_schema.json'))
ok('Huawei Cloud sync defaults on and can be disabled by signed build env',
  /HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = true/.test(cloudBuildFlag) &&
    /NEXTE_HUAWEI_CLOUD_SYNC/.test(signedBuild) &&
    /HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = false/.test(signedBuild))
ok('Huawei Cloud sync service is guarded and uses RDB cloud sync APIs',
  /HUAWEI_CLOUD_SYNC_BUILD_ENABLED/.test(huaweiCloud) &&
    /available\(\): boolean/.test(huaweiCloud) &&
    /DISTRIBUTED_DATASYNC/.test(huaweiCloud) &&
    /setDistributedTables/.test(huaweiCloud) &&
    /DISTRIBUTED_CLOUD/.test(huaweiCloud) &&
    /cloudSync/.test(huaweiCloud) &&
    /SYNC_MODE_TIME_FIRST/.test(huaweiCloud))
ok('Huawei Cloud sync constrains manual runs to selected tables',
  /mode: relationalStore\.SyncMode = relationalStore\.SyncMode\.SYNC_MODE_TIME_FIRST/.test(huaweiCloud) &&
    /\.cloudSync\(\s*mode,\s*tables,\s*\(progress: relationalStore\.ProgressDetails\) =>/.test(huaweiCloud) &&
    /waitCloudSyncFinish\([\s\S]*store,[\s\S]*tables,[\s\S]*context/.test(huaweiCloud))
ok('Huawei Cloud sync keeps app-managed image reset/upload repair outside normal system sync',
  /IMAGE_BLOCK_USER_RULES_TABLE: string = 'image_block_user_rules'/.test(huaweiCloud) &&
    !/cleanDirtyData\(IMAGE_BLOCK_USER_RULES_TABLE\)/.test(huaweiCloud) &&
    !/huawei_cloud_image_block_clean_dirty/.test(huaweiCloud) &&
    !/imageBlockCloudSuspended/.test(huaweiCloud) &&
    !/shouldUploadImageBlockBeforePull/.test(huaweiCloud) &&
    !/huawei_cloud_image_block_native_first/.test(huaweiCloud) &&
    !/SYNC_MODE_NATIVE_FIRST/.test(huaweiCloud) &&
    !/huawei_cloud_image_block_suspended/.test(huaweiCloud) &&
    !/treatImageBlockPartialAsSuccess/.test(huaweiCloud) &&
    !/huawei_cloud_image_block_degraded/.test(huaweiCloud) &&
    !/huawei_cloud_image_block_native_repair/.test(huaweiCloud) &&
    !/shouldRepairImageBlockFromLocal/.test(huaweiCloud) &&
    !/CloudSyncTableResetRepository|huawei_cloud_rebuild_table|huawei_cloud_reseed_table/.test(huaweiCloud) &&
    /Normal Huawei Cloud sync should stay system-owned/.test(doc) &&
    /No image-block first-upload\s+exception/.test(doc) &&
    /must not run cleanDirtyData/.test(doc) &&
    /must not run\s+native-first/.test(doc))
const localStoreVersionMatch = localStore.match(/LOCAL_DATA_SCHEMA_VERSION: number = (\d+)/)
ok('Huawei Cloud schema version is separate from local RDB migration version',
  !!localStoreVersionMatch &&
    Number(localStoreVersionMatch[1]) >= 20 &&
    cloudSchema.version === 17 &&
    cloudSchema.databases[0].version === cloudSchema.version)
ok('Huawei Cloud has no image-block cloud touch completion path',
    /Image-block cloud touch markers are retired/.test(doc) &&
    !/image_block_user_rules_cloud_touch/.test(syncAdapter) &&
    !/imageBlockTableSucceeded/.test(huaweiCloud) &&
    !/image_block_cloud_table_result/.test(huaweiCloud))
ok('Huawei Cloud sync marks tables before local image-block preparation',
  huaweiCloud.indexOf('await store.setDistributedTables') >= 0 &&
    huaweiCloud.indexOf('await store.setDistributedTables') <
      huaweiCloud.indexOf('await SyncLocalDataAdapter.prepareHuaweiCloudTables') &&
    /const config: relationalStore\.DistributedConfig = \{ autoSync: false \}/.test(huaweiCloud) &&
    !/autoSync: true/.test(huaweiCloud))
ok('Huawei Cloud prepares image-block legacy user rules only on cloud table marking',
  /static async tryEnableStartup[\s\S]*if \(!snapshot\.huaweiCloudEnabled\)[\s\S]*await HuaweiCloudSyncService\.markDistributedTables/.test(huaweiCloud) &&
    /prepareHuaweiCloudTables\(context, selection\)/.test(huaweiCloud) &&
    !/prepareHuaweiCloudTables\(context, selection, true\)/.test(huaweiCloud))
ok('Huawei Cloud sync uses the durable RDB cloud table subset',
  /gallery_read_progress/.test(cloudFeatures) &&
    /viewed_history/.test(cloudFeatures) &&
    /local_favorites/.test(cloudFeatures) &&
    /search_history/.test(cloudFeatures) &&
    /local_block_settings/.test(cloudFeatures) &&
    /local_block_rules/.test(cloudFeatures) &&
    /image_block_user_rules/.test(cloudFeatures) &&
    !/image_block_subscriptions/.test(cloudFeatures) &&
    !/'image_block_rules'/.test(cloudFeatures) &&
    /custom_profiles/.test(cloudFeatures) &&
    /custom_profile_selection/.test(cloudFeatures) &&
    !/tag_translations|eh_page_cache|comment_translation_cache|download_gallery_tasks|download_archiver_tasks/.test(cloudFeatures))
const cloudAliasByName = new Map(cloudSchema.databases[0].tables.map((table) => [table.name, table.alias]))
ok('Huawei Cloud schema keeps local table names but aliases AGC data type names',
  cloudAliasByName.get('gallery_read_progress') === 'GalleryReadProgress' &&
    cloudAliasByName.get('viewed_history') === 'ViewedHistory' &&
    cloudAliasByName.get('local_favorites') === 'LocalFavorites' &&
    cloudAliasByName.get('search_history') === 'SearchHistory' &&
    cloudAliasByName.get('local_block_settings') === 'LocalBlockSettings' &&
    cloudAliasByName.get('local_block_rules') === 'LocalBlockRules' &&
    cloudAliasByName.get('image_block_user_rules') === 'ImageBlockUserRules' &&
    !cloudAliasByName.has('image_block_subscriptions') &&
    !cloudAliasByName.has('image_block_rules') &&
    cloudAliasByName.get('custom_profiles') === 'CustomProfiles' &&
    cloudAliasByName.get('custom_profile_selection') === 'CustomProfileSelection')
ok('image block sync uses image_block_user_rules as the user-rule source table',
  /COALESCE\(source_type, \\\'\\\'\) <> \\\'subscription\\\'/.test(syncAdapter) &&
    /FROM image_block_user_rules/.test(syncAdapter) &&
    /image_block_user_rules/.test(cloudFeatures) &&
    !/image_block_subscriptions/.test(cloudFeatures) &&
    /ON CONFLICT\(rule_id, scope_key\)/.test(syncAdapter) &&
    /prepareHuaweiCloudTables/.test(syncAdapter) &&
    /_selection: SyncDatasetSelection/.test(syncAdapter) &&
    !/_selection\.imageBlock/.test(syncAdapter) &&
    !/image_block_user_rules_cloud_touch/.test(syncAdapter) &&
    !/image_block_cloud_touch/.test(syncAdapter) &&
    !/markImageBlockCloudTouchComplete/.test(syncAdapter) &&
    !/completeImageBlockTouchIfNeeded/.test(huaweiCloud) &&
    !/UPDATE image_block_user_rules SET updated_at = \? WHERE/.test(syncAdapter) &&
    !/updated_at \+ 1/.test(syncAdapter) &&
    !/prepareHuaweiCloudTables\(context, selection, true\)/.test(huaweiCloud) &&
    !/SQL_REPAIR_IMAGE_BLOCK_ACTIVE_USER_RULE_TOMBSTONES/.test(syncAdapter) &&
    !/dedupeImageBlockUserRules/.test(syncAdapter) &&
    !/image_block_cloud_dedupe/.test(syncAdapter) &&
    /SQL_SYNC_IMAGE_BLOCK_SUBSCRIPTION_DISABLES_FROM_MAIN/.test(syncAdapter) &&
    /SQL_UPSERT_USER_RULE/.test(imageBlockRepo) &&
    /FROM image_block_user_rules/.test(imageBlockRepo) &&
    !/syncOneUserRuleFromMain/.test(imageBlockRepo) &&
    !/SyncLocalDataAdapter\.prepareHuaweiCloudTables/.test(imageBlockRepo) &&
    /applyHuaweiCloudTables/.test(syncAdapter) &&
    /previewPath: string = ''/.test(types) &&
    /preview_path/.test(syncAdapter) &&
    /r\.previewPath = ''/.test(syncAdapter) &&
    !/r\.previewPath = SyncLocalDataAdapter\.stringColumn\(rs, 'preview_path'\)/.test(syncAdapter))
ok('Huawei Cloud sync permission is declared for private builds',
  /ohos\.permission\.DISTRIBUTED_DATASYNC/.test(moduleJson))

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
ok('sync settings restore during settings bootstrap',
  /import \{ SyncSettings \}/.test(bootstrap) &&
    /await SyncSettings\.restore\(context\)/.test(bootstrap))
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
ok('app lifecycle schedules provider-neutral sync after startup and foreground',
  /SyncScheduler\.rememberContext\(this\.context\)/.test(entryAbility) &&
    /HuaweiCloudSyncService\.tryEnableStartup\(this\.context\)/.test(entryAbility) &&
    !/SyncLocalDataAdapter\.prepareHuaweiCloudTables/.test(entryAbility) &&
    /SyncScheduler\.requestAfterForeground\(this\.context, 'startup'\)/.test(entryAbility) &&
    /SyncScheduler\.requestAfterForeground\(this\.context, 'foreground'\)/.test(entryAbility))

for (const file of [
  'shared/src/main/ets/settings/SearchHistorySettings.ets',
  'shared/src/main/ets/settings/GalleryReadProgressSettings.ets',
  'shared/src/main/ets/settings/ViewedHistorySettings.ets',
  'shared/src/main/ets/settings/LocalFavSettings.ets',
  'shared/src/main/ets/settings/LocalBlockSettings.ets',
  'shared/src/main/ets/settings/CustomProfilesSettings.ets',
]) {
  const src = read(file)
  ok(`${file} schedules all sync providers after local durable writes`,
    /SyncScheduler/.test(src) &&
      /requestAfterLocalWrite/.test(src) &&
      !/HuaweiCloudSyncScheduler/.test(src))
}

const settingsIndex = read('feature/settings/src/main/ets/Index.ets')
const entryIndex = read('entry/src/main/ets/pages/Index.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const cacheSettingsPage = read('feature/settings/src/main/ets/pages/CacheSettingsPage.ets')
ok('sync settings page is reachable from storage settings navigation',
  /SyncSettingsPage/.test(settingsIndex) &&
    /name === 'SyncSettings'/.test(entryIndex) &&
    /pushPathByName\('SyncSettings'/.test(cacheSettingsPage) &&
    !/pushPathByName\('SyncSettings'/.test(settingsPage))

const syncPage = read('feature/settings/src/main/ets/pages/SyncSettingsPage.ets')
const webdavPage = read('feature/settings/src/main/ets/pages/WebDavSyncSettingsPage.ets')
ok('sync overview keeps provider entries and routes WebDAV to a child page',
  /pushPathByName\('WebDavSyncSettings'/.test(syncPage) &&
    /sync_webdav/.test(syncPage) &&
    /sync_huawei_cloud/.test(syncPage) &&
    /WebDavSyncSettingsPage/.test(settingsIndex) &&
    /name === 'WebDavSyncSettings'/.test(entryIndex))
ok('WebDAV sync child page has visible running state and provider switch',
  /LoadingProgress/.test(webdavPage) &&
    /sync_status_running/.test(webdavPage) &&
    /this\.syncing = true/.test(webdavPage) &&
    /this\.syncing = false/.test(webdavPage) &&
    /this\.settings\.lastDetail/.test(webdavPage) &&
    /SyncSettings\.markRun\(this\.ctx\(\), SYNC_STATUS_FAILED, error\.message\)/.test(webdavPage) &&
    /sync_webdav_hint/.test(webdavPage) &&
    /hasSwitch: true/.test(webdavPage))
ok('Huawei Cloud provider UI is hidden when provider availability is disabled',
  /HuaweiCloudSyncService\.available\(\)/.test(syncPage) &&
    /sync_huawei_cloud/.test(syncPage) &&
    /sync_huawei_cloud_now/.test(syncPage) &&
    /HUAWEI_CLOUD_DEEP_LINK/.test(syncPage) &&
    /sync_huawei_cloud_open_space/.test(syncPage) &&
    /HuaweiCloudSyncService\.ensurePermission/.test(syncPage) &&
    /HuaweiCloudSyncService\.cloudSyncNow/.test(syncPage))
ok('sync overview exposes provider-neutral dataset switches',
  /DatasetRow/.test(syncPage) &&
    /sync_dataset_read_progress/.test(syncPage) &&
    /sync_dataset_custom_profiles/.test(syncPage) &&
    /hasSwitch: true/.test(syncPage))

const backup = read('shared/src/main/ets/backup/BackupService.ets')
ok('WebDAV password is not exported by backup service',
  !/SYNC_WEBDAV_PASSWORD|sync\.webdav\.password/.test(backup))

const webdavLocalTest = read('scripts/test_webdav_local_server_contract.mjs')
ok('local WebDAV server smoke covers sharded WebDAV layout',
  /createServer/.test(webdavLocalTest) &&
    /MKCOL/.test(webdavLocalTest) &&
    /manifest\.json/.test(webdavLocalTest) &&
    /datasets\/search-history\/0a\.json/.test(webdavLocalTest) &&
    /datasets\/viewed-history\/2f\.json/.test(webdavLocalTest) &&
    /legacy single-file path is not written/.test(webdavLocalTest) &&
    /server enforces Basic auth/.test(webdavLocalTest))

const syncStringKeys = [
  'settings_sync',
  'settings_sync_hint',
  'sync_webdav',
  'sync_webdav_hint',
  'sync_provider_disabled',
  'sync_webdav_url',
  'sync_webdav_url_hint',
  'sync_webdav_username',
  'sync_webdav_username_hint',
  'sync_webdav_password',
  'sync_webdav_password_hint',
  'sync_webdav_url_required',
  'sync_webdav_now',
  'sync_huawei_cloud',
  'sync_huawei_cloud_hint',
  'sync_huawei_cloud_now',
  'sync_huawei_cloud_enabled',
  'sync_huawei_cloud_permission_denied',
  'sync_huawei_cloud_disabled_status',
  'sync_huawei_cloud_open_space',
  'sync_huawei_cloud_open_space_hint',
  'sync_huawei_cloud_open_failed',
  'sync_now',
  'sync_now_done',
  'sync_now_failed',
  'sync_status_running',
  'sync_status_never',
  'sync_status_success',
  'sync_status_failed',
  'sync_dataset_read_progress',
  'sync_dataset_read_progress_hint',
  'sync_dataset_viewed_history',
  'sync_dataset_viewed_history_hint',
  'sync_dataset_local_favorites',
  'sync_dataset_local_favorites_hint',
  'sync_dataset_search_history',
  'sync_dataset_search_history_hint',
  'sync_dataset_local_block',
  'sync_dataset_local_block_hint',
  'sync_dataset_custom_profiles',
  'sync_dataset_custom_profiles_hint',
]
for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = JSON.parse(read(`entry/src/main/resources/${locale}/element/string.json`)).string
  const names = new Set(strings.map((item) => item.name))
  ok(`sync i18n keys exist in ${locale}`, syncStringKeys.every((key) => names.has(key)))
}

if (failures > 0) {
  console.error(`✗ sync design contract: ${failures} failure(s)`)
  process.exit(1)
}
console.log('✓ sync design contract passed')
