#!/usr/bin/env node
// Contract for the custom home sub-tab profile model + persistence (Phase 1).
// .ets can't run in node, so this asserts the SOURCE invariants that matter: every CustomProfile field
// is carried by copy()/serialize()/parse() (the classic ArkTS "added a field, forgot to copy it" bug),
// the deserialize clamps + legacy migration + builtin seeds exist, and the storage keys are declared.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const repo = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(repo, p), 'utf8')

const problems = []
const must = (cond, msg) => {
  if (!cond) problems.push(msg)
}

const model = read('shared/src/main/ets/model/CustomProfile.ets')
const settings = read('shared/src/main/ets/settings/CustomProfilesSettings.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const zhStrings = read('entry/src/main/resources/zh_CN/element/string.json')

// --- 1. extract the declared fields from the CustomProfile class body ---
const classMatch = model.match(/export class CustomProfile \{([\s\S]*?)\n\}/)
must(!!classMatch, 'CustomProfile class block not found')
const fields = []
if (classMatch) {
  const re = /^ {2}([a-zA-Z][a-zA-Z0-9]*): /gm
  let m
  while ((m = re.exec(classMatch[1])) !== null) {
    fields.push(m[1])
  }
}
const EXPECTED = [
  'uuid', 'name', 'listType', 'searchText', 'selectedCats', 'advancedEnabled', 'minRating',
  'pagesFrom', 'pagesTo', 'requireTorrent', 'showExpunged', 'disableLanguageFilter',
  'disableUploaderFilter', 'disableTagFilter', 'favcat', 'toplistTl', 'displayMode', 'hidden',
  'builtin', 'lastEditTime',
]
EXPECTED.forEach((f) => must(fields.includes(f), `CustomProfile missing field: ${f}`))
must(
  fields.length === EXPECTED.length,
  `CustomProfile field count ${fields.length} != expected ${EXPECTED.length} (update this contract if intentional)`,
)

// --- 2. copy() must assign every field ---
fields.forEach((f) => must(model.includes(`c.${f} = this.${f}`), `copy() does not carry field: ${f}`))

// --- 3. methods + exported consts ---
must(/fCats\(\): number/.test(model), 'CustomProfile.fCats() missing')
must(/requiresLogin\(\): boolean/.test(model), 'CustomProfile.requiresLogin() missing')
must(/contentRevision\(\): string/.test(model), 'CustomProfile.contentRevision() missing')
must(
  model.includes('PROFILE_TYPE_POPULAR') &&
    model.includes('PROFILE_TYPE_TOPLIST') &&
    model.includes('PROFILE_TYPE_FAVORITE') &&
    model.includes('this.searchText') &&
    model.includes('this.disableTagFilter'),
  'contentRevision() must separate real request fields by profile type',
)
;[
  'PROFILE_TYPE_GALLERY', 'PROFILE_TYPE_POPULAR', 'PROFILE_TYPE_WATCHED', 'PROFILE_TYPE_TOPLIST',
  'PROFILE_TYPE_FAVORITE', 'PROFILE_DISPLAY_GLOBAL', 'BUILTIN_DEFAULT_UUID', 'BUILTIN_POPULAR_UUID',
  'BUILTIN_WATCHED_UUID', 'STARTER_CHINESE_UUID', 'STARTER_ANTHOLOGY_UUID',
].forEach((c) => must(model.includes(`export const ${c}`), `CustomProfile export const missing: ${c}`))

// --- 4. settings serialize()/parse() must carry every field (drift guard) ---
fields.forEach((f) => must(settings.includes(`s.${f} = p.${f}`), `serialize() does not carry field: ${f}`))
fields.forEach((f) => must(settings.includes(`p.${f} =`), `parse() does not restore field: ${f}`))

// --- 5. clamps, migration, seeds ---
must(settings.includes('isValidProfileType'), 'parse() must clamp listType via isValidProfileType')
must(/TOPLIST_PERIODS: number\[\] = \[11, 12, 13, 15\]/.test(settings), 'toplist period clamp domain [11,12,13,15] missing')
must(settings.includes('clampDisplayMode'), 'displayMode clamp missing')
must(settings.includes('clampFavcat'), 'favcat clamp missing')
must(settings.includes('StorageKeys.HOME_SOURCE'), 'migration must read legacy StorageKeys.HOME_SOURCE')
must(settings.includes('CustomProfilesRepository.loadProfiles(context)'), 'restore must read custom profiles from RDB')
must(settings.includes('CustomProfilesRepository.replaceAll('), 'persistAll must write custom profiles to RDB')
must(settings.includes('CustomProfilesRepository.saveSelected('), 'selected profile must persist through RDB')
must(!settings.includes('store.putSync(StorageKeys.HOME_CUSTOM_PROFILES,'), 'custom profiles must not write the big JSON list to Preferences')
must(settings.includes('migrateLegacyPreferences') &&
  settings.includes("store.getSync(StorageKeys.HOME_CUSTOM_PROFILES, '')") &&
  settings.includes('store.deleteSync(StorageKeys.HOME_CUSTOM_PROFILES)'),
  'legacy custom profile Preferences rows must migrate once')
const customProfilesRepository = read('shared/src/main/ets/storage/CustomProfilesRepository.ets')
must(
  customProfilesRepository.includes('static async hasPersistedState') &&
    customProfilesRepository.includes('SQL_HAS_PERSISTED_PROFILES') &&
    customProfilesRepository.includes('SQL_HAS_PERSISTED_SELECTION') &&
    settings.includes('const revision: number = CustomProfilesSettings.mutationRevision') &&
    settings.includes('await CustomProfilesRepository.hasPersistedState(context)') &&
    settings.includes('custom_profiles_migrate_failed') &&
    settings.includes('Keep the only legacy copy intact'),
  'legacy custom-profile migration must preserve newer RDB state and retain the only legacy copy on failure',
)
must(
  /"name": "tab_seed_chinese",\s*"value": "中文"/.test(zhStrings),
  'zh_CN starter Chinese custom profile label must be 中文',
)
must(settings.includes('migrateStarterNames(profiles)') &&
  settings.includes('ensureBuiltins(migratedProfiles)') &&
  settings.includes("p.searchText === 'language:chinese' && p.name === '汉化'") &&
  settings.includes("c.name = AppStrings.get('tab_seed_chinese')") &&
  settings.includes('return changed ? out : profiles') &&
  settings.includes('if (migratedProfiles !== profiles || builtinProfiles !== migratedProfiles || normalized.changed)'),
  'legacy 汉化 starter name and missing builtins must migrate and persist only changed restore output')
{
  const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
  const repo = read('shared/src/main/ets/storage/CustomProfilesRepository.ets')
  must(store.includes('CREATE TABLE IF NOT EXISTS custom_profiles') &&
    store.includes('CREATE TABLE IF NOT EXISTS custom_profile_selection') &&
    store.includes('profile_uuid TEXT') &&
    store.includes('PRIMARY KEY(scope_key, profile_uuid)') &&
    !/['"]uuid TEXT, /.test(store) &&
    store.includes('position_index INTEGER'),
    'custom profiles RDB tables missing')
  must(repo.includes('profile_uuid AS uuid') &&
    repo.includes('ORDER BY position_index ASC, profile_uuid ASC') &&
    repo.includes('UPDATE custom_profiles SET deleted_at = ?') &&
    repo.includes('ON CONFLICT(scope_key, profile_uuid) DO UPDATE') &&
    repo.includes('static async saveChanges') &&
    repo.includes('SQL_TOMBSTONE_PROFILE') &&
    repo.includes('nextProfileClock'),
    'custom profiles repository must map DB profile_uuid to model uuid, preserve order, target ordinary writes, and tombstone scoped rows')
  const localProfileUpsertStart = repo.indexOf('const SQL_UPSERT_PROFILE')
  const localProfileUpsertEnd = repo.indexOf('const SQL_REPLACE_PROFILE')
  const localProfileUpsert = localProfileUpsertStart >= 0 && localProfileUpsertEnd > localProfileUpsertStart
    ? repo.slice(localProfileUpsertStart, localProfileUpsertEnd)
    : ''
  must(
    localProfileUpsert.includes('last_edit_time = excluded.last_edit_time, deleted_at = 0 WHERE') &&
      localProfileUpsert.includes('COALESCE(excluded.deleted_at, 0) > COALESCE(excluded.last_edit_time, 0)') &&
      localProfileUpsert.includes('COALESCE(custom_profiles.deleted_at, 0) > COALESCE(custom_profiles.last_edit_time, 0)'),
    'custom profile local writes must not overwrite a newer profile row',
  )
  must(
    repo.includes('SET deleted_at = CASE WHEN COALESCE(last_edit_time, 0) >= ?') &&
      repo.includes('THEN COALESCE(last_edit_time, 0) + 1 ELSE ? END') &&
      repo.includes('[tombstoneTime, tombstoneTime, SCOPE_GLOBAL]'),
    'authoritative profile replacement must tombstone every missing row past its own LWW clock',
  )
  must(
    repo.includes('selectionChanged: boolean = false') &&
      repo.includes('if (selectionChanged) {\n        await CustomProfilesRepository.saveSelectedWithStore(store, selectedUuid)') &&
      settings.includes('const selectionChanged: boolean = state.selectedUuid === uuid') &&
      settings.includes("const selectionChanged: boolean = hidden && state.selectedUuid === uuid"),
    'ordinary profile writes must persist selection only when the selected tab actually changes',
  )
  must(repo.includes('SQL_SELECT_SELECTED_STATE') &&
    repo.includes('previous.deletedAt === 0 && previous.selectedUuid === selectedUuid') &&
    repo.includes('Math.max(Date.now(), latest + 1)') &&
    repo.includes('WHERE excluded.updated_at >=') &&
    repo.includes('custom_profile_selection.deleted_at'),
    'custom profile selection must avoid unrelated timestamp churn and advance past observed LWW clocks')
  const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
  const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
  must(backupTypes.includes('customProfiles: BackupCustomProfilesSection') &&
    backupAdapter.includes('CustomProfilesSettings.exportForBackupSnapshot(context)') &&
    backupAdapter.includes('CustomProfilesSettings.restoreBackup(context, profiles, section.customProfiles.selectedUuid)'),
    'backup localData must include custom profiles')
}
{
  const syncAdapter = read('shared/src/main/ets/sync/SyncLocalDataAdapter.ets')
  must(/SQL_APPLY_CUSTOM_PROFILE[\s\S]*?WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) > COALESCE\(excluded\.last_edit_time, 0\)[\s\S]*?custom_profiles\.deleted_at/.test(syncAdapter),
    'custom profile sync apply must not overwrite a newer local profile')
  must(/SQL_APPLY_CUSTOM_PROFILE_SELECTION[\s\S]*?WHERE CASE WHEN COALESCE\(excluded\.deleted_at, 0\) > COALESCE\(excluded\.updated_at, 0\)[\s\S]*?custom_profile_selection\.deleted_at/.test(syncAdapter),
    'custom profile selection sync apply must not overwrite a newer local selection')
}
must(
  settings.includes('persistChanged') &&
    settings.includes('changedUuids') &&
    settings.includes('nextEditTime') &&
    settings.includes('CustomProfilesRepository.saveChanges'),
  'ordinary profile mutations must advance only their affected LWW rows',
)
;['BUILTIN_DEFAULT_UUID', 'BUILTIN_POPULAR_UUID', 'BUILTIN_WATCHED_UUID'].forEach((u) =>
  must(settings.includes(u), `seedDefaults() missing builtin uuid: ${u}`),
)
must(
  settings.includes('private static ensureBuiltins') &&
    settings.includes('addMissingBuiltin(') &&
    settings.includes('normalizeBuiltin(') &&
    settings.includes('builtinListType(') &&
    settings.includes('BUILTIN_WATCHED_UUID') &&
    settings.includes("AppStrings.get('home_source_watched')") &&
    settings.includes('PROFILE_TYPE_WATCHED'),
  'restore must repair old/synced profile rows that are missing the built-in watched/subscription tab',
)
must(
  settings.includes('normalizeStarterProfiles(builtinProfiles, selected)') &&
    settings.includes('canonicalStarterUuid(p)') &&
    settings.includes("p.searchText === 'language:chinese'") &&
    settings.includes("p.searchText === 'other:anthology'") &&
    settings.includes('STARTER_CHINESE_UUID') &&
    settings.includes('STARTER_ANTHOLOGY_UUID') &&
    settings.includes('out[selectedIndex].hidden') &&
    settings.includes('firstVisibleUuid(out)'),
  'restore must canonicalize starter tab UUIDs, dedupe synced seed duplicates, and clamp selected tab to a visible profile',
)

// --- 6. storage keys declared ---
must(/HOME_CUSTOM_PROFILES: string = 'subtab\.customProfiles'/.test(keys), 'StorageKeys.HOME_CUSTOM_PROFILES missing')
must(
  /HOME_CUSTOM_PROFILES_SELECTED: string = 'subtab\.customProfilesSelected'/.test(keys),
  'StorageKeys.HOME_CUSTOM_PROFILES_SELECTED missing',
)

if (problems.length > 0) {
  console.error(`✗ custom-profiles contract: ${problems.length} problem(s)`)
  problems.forEach((p) => console.error('  - ' + p))
  process.exit(1)
}
console.log(
  `✓ custom-profiles contract: copy/serialize/parse all carry ${fields.length} fields; clamps + legacy migration + builtin seeds + storage keys present`,
)
