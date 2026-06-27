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
;[
  'PROFILE_TYPE_GALLERY', 'PROFILE_TYPE_POPULAR', 'PROFILE_TYPE_WATCHED', 'PROFILE_TYPE_TOPLIST',
  'PROFILE_TYPE_FAVORITE', 'PROFILE_DISPLAY_GLOBAL', 'BUILTIN_DEFAULT_UUID', 'BUILTIN_POPULAR_UUID',
  'BUILTIN_WATCHED_UUID',
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
must(settings.includes('CustomProfilesRepository.replaceAll(context, state.profiles, state.selectedUuid)'), 'persistAll must write custom profiles to RDB')
must(settings.includes('CustomProfilesRepository.saveSelected(context, uuid)'), 'selected profile must persist through RDB')
must(!settings.includes('store.putSync(StorageKeys.HOME_CUSTOM_PROFILES,'), 'custom profiles must not write the big JSON list to Preferences')
must(settings.includes('migrateLegacyPreferences') &&
  settings.includes("store.getSync(StorageKeys.HOME_CUSTOM_PROFILES, '')") &&
  settings.includes('store.deleteSync(StorageKeys.HOME_CUSTOM_PROFILES)'),
  'legacy custom profile Preferences rows must migrate once')
{
  const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
  const repo = read('shared/src/main/ets/storage/CustomProfilesRepository.ets')
  must(store.includes('CREATE TABLE IF NOT EXISTS custom_profiles') &&
    store.includes('CREATE TABLE IF NOT EXISTS custom_profile_selection') &&
    store.includes('position_index INTEGER'),
    'custom profiles RDB tables missing')
  must(repo.includes('ORDER BY position_index ASC, uuid ASC') &&
    repo.includes('UPDATE custom_profiles SET deleted_at = ?') &&
    repo.includes('ON CONFLICT(scope_key, uuid) DO UPDATE'),
    'custom profiles repository must preserve order and tombstone scoped rows')
  const backupTypes = read('shared/src/main/ets/backup/BackupTypes.ets')
  const backupAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
  must(backupTypes.includes('customProfiles: BackupCustomProfilesSection') &&
    backupAdapter.includes('CustomProfilesSettings.exportForBackup(context)') &&
    backupAdapter.includes('CustomProfilesSettings.restoreBackup(context, profiles, section.customProfiles.selectedUuid)'),
    'backup localData must include custom profiles')
}
;['BUILTIN_DEFAULT_UUID', 'BUILTIN_POPULAR_UUID', 'BUILTIN_WATCHED_UUID'].forEach((u) =>
  must(settings.includes(u), `seedDefaults() missing builtin uuid: ${u}`),
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
