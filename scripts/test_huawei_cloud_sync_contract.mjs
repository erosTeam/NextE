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

const expectedTables = [
  'gallery_read_progress',
  'viewed_history',
  'local_favorites',
  'search_history',
  'local_block_settings',
  'local_block_rules',
  'custom_profiles',
  'custom_profile_selection',
]
const expectedCloudAliases = new Map([
  ['gallery_read_progress', 'GalleryReadProgress'],
  ['viewed_history', 'ViewedHistory'],
  ['local_favorites', 'LocalFavorites'],
  ['search_history', 'SearchHistory'],
  ['local_block_settings', 'LocalBlockSettings'],
  ['local_block_rules', 'LocalBlockRules'],
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
ok('Huawei cloud service checks availability before permission or sync',
  /available\(\): boolean/.test(service) &&
    /if \(!HuaweiCloudSyncService\.available\(\)\)/.test(service) &&
    /ensurePermission/.test(service) &&
    /cloudSyncNow/.test(service))
ok('Huawei cloud service uses official RDB cloud sync entry points',
  /ohos\.permission\.DISTRIBUTED_DATASYNC/.test(service) &&
    /requestPermissionsFromUser/.test(service) &&
    /setDistributedTables/.test(service) &&
    /relationalStore\.DistributedType\.DISTRIBUTED_CLOUD/.test(service) &&
    /relationalStore\.SyncMode\.SYNC_MODE_TIME_FIRST/.test(service) &&
    /cloudSync/.test(service))
ok('manual Huawei cloud sync follows Next2V whole marked-store cloudSync path',
  /cloudSync\(\s*relationalStore\.SyncMode\.SYNC_MODE_TIME_FIRST,\s*\(progress: relationalStore\.ProgressDetails\) =>/.test(service) &&
    !/\\.cloudSync\(\s*relationalStore\.SyncMode\.SYNC_MODE_TIME_FIRST,\s*tables,/.test(service))
ok('Huawei cloud scheduled sync coalesces writes and foreground events',
  /LOCAL_WRITE_DEBOUNCE_MS: number = 15000/.test(scheduler) &&
    /FOREGROUND_DEBOUNCE_MS: number = 3000/.test(scheduler) &&
    /MIN_ATTEMPT_INTERVAL_MS: number = 45000/.test(scheduler) &&
    /RETRY_BASE_MS: number = 60000/.test(scheduler) &&
    /requestAfterLocalWrite/.test(scheduler) &&
    /requestAfterForeground/.test(scheduler) &&
    /SyncSettings\.current\(\)\.huaweiCloudEnabled/.test(scheduler) &&
    /connectSyncSettings\(\)\.huaweiCloudSyncing/.test(scheduler))
ok('EntryAbility binds Huawei cloud scheduled sync and foreground startup kicks',
  /HuaweiCloudSyncScheduler\.bindExecutor/.test(entryAbility) &&
    /HuaweiCloudSyncService\.runScheduledSync\(context, reason\)/.test(entryAbility) &&
    /HuaweiCloudSyncScheduler\.requestAfterForeground\(this\.context, 'startup'\)/.test(entryAbility) &&
    /onForeground\(\): void \{[\s\S]*HuaweiCloudSyncScheduler\.requestAfterForeground\(this\.context, 'foreground'\)/.test(entryAbility))

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
  ok(`${file} requests Huawei cloud sync after local writes`,
    /HuaweiCloudSyncScheduler/.test(src) &&
      src.includes(`requestAfterLocalWrite(context, '${reason}`))
}

const moduleJson = read('entry/src/main/module.json5')
ok('distributed data sync permission has required user-grant metadata',
  /ohos\.permission\.DISTRIBUTED_DATASYNC/.test(moduleJson) &&
    /reason": "\$string:perm_distributed_datasync_reason"/.test(moduleJson) &&
    /"abilities": \["EntryAbility"\]/.test(moduleJson) &&
    /"when": "inuse"/.test(moduleJson))

const features = read('shared/src/main/ets/sync/CloudSyncFeatures.ets')
for (const table of expectedTables) {
  ok(`cloud feature mapping includes ${table}`, features.includes(`'${table}'`))
}
for (const table of forbiddenTables) {
  ok(`cloud feature mapping excludes ${table}`, !features.includes(table))
}

const schema = JSON.parse(read('entry/src/main/resources/rawfile/arkdata/cloud/cloud_schema.json'))
ok('cloud schema is for NextE bundle and database',
  schema.bundleName === 'com.erosteam.nexte' &&
    schema.metaVersion === 65537 &&
    schema.e2eeEnable === false &&
    schema.databases.length === 1 &&
    schema.databases[0].name === 'NextE' &&
    schema.databases[0].bundleName === 'com.erosteam.nexte' &&
    schema.databases[0].version === schema.version &&
    schema.databases[0].autoSyncType === 0)

const schemaTables = schema.databases[0].tables.map((table) => table.name)
ok('cloud schema table set exactly matches syncable durable tables',
  expectedTables.every((table) => schemaTables.includes(table)) &&
    schemaTables.every((table) => expectedTables.includes(table)))
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

const localStore = read('shared/src/main/ets/storage/LocalDataStore.ets')
const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
for (const table of expectedTables) {
  ok(`local store creates ${table}`, localStore.includes(`CREATE TABLE IF NOT EXISTS ${table} (`))
}
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

const syncPage = read('feature/settings/src/main/ets/pages/SyncSettingsPage.ets')
ok('Huawei cloud settings UI is gated by provider availability',
  /if \(HuaweiCloudSyncService\.available\(\)\)/.test(syncPage) &&
    /sync_huawei_cloud/.test(syncPage) &&
    /sync_huawei_cloud_now/.test(syncPage))

if (failures > 0) {
  console.error(`✗ Huawei cloud sync contract: ${failures} failure(s)`)
  process.exit(1)
}
console.log('✓ Huawei cloud sync contract passed')
