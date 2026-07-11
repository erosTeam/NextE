#!/usr/bin/env node
/**
 * Contract for the settings backup/restore (import/export) subsystem.
 *
 * Secrets (login cookie bundle, saved accounts, LLM API key) must NEVER appear in a plaintext export;
 * they travel only inside the AES-256-GCM encrypted container, gated by a password.
 * Run: node scripts/test_settings_backup_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const crypto = read('shared/src/main/ets/backup/BackupCrypto.ets')
ok('crypto is AES-256-GCM with PBKDF2-SHA256 (seal/open)',
  /static seal\(plaintext: string, password: string\)/.test(crypto) &&
    /static open\(/.test(crypto) &&
    /createCipher\('AES256\|GCM\|PKCS7'\)/.test(crypto) &&
    /createKdf\('PBKDF2\|SHA256'\)/.test(crypto))
ok('crypto splits the GCM auth tag off the ciphertext on open',
  /BACKUP_CIPHER_TAG_BYTES/.test(crypto) && /slice\(splitAt/.test(crypto))

const types = read('shared/src/main/ets/backup/BackupTypes.ets')
ok('envelope identity + KDF params defined',
  /BACKUP_MAGIC: string = 'NEXTE_BACKUP'/.test(types) &&
    /BACKUP_APP_ID: string = 'com\.erosteam\.nexte'/.test(types) &&
    /BACKUP_KDF_ITERATIONS: number = 210000/.test(types))
ok("'secrets' is encryption-only, localData is plaintext durable data",
  /BACKUP_SECTION_NAMES: BackupSectionName\[\] = \['preferences', 'localData'\]/.test(types) &&
    /BACKUP_ENCRYPTED_ONLY_SECTION_NAMES: BackupSectionName\[\] = \['secrets'\]/.test(types))
ok('localData section carries durable read progress outside Preferences',
  /BackupSectionName = 'preferences' \| 'localData' \| 'secrets'/.test(types) &&
    /interface BackupLocalDataSection/.test(types) &&
    /readProgress: BackupReadProgressEntry\[\]/.test(types) &&
    /viewedHistory: BackupViewedHistoryEntry\[\]/.test(types) &&
    /localFavorites: BackupLocalFavoriteEntry\[\]/.test(types) &&
    /searchHistory: string\[\]/.test(types) &&
    /localBlock: BackupLocalBlockSection/.test(types) &&
    /imageBlock: BackupImageBlockSection/.test(types) &&
    /interface BackupImageBlockRuleEntry/.test(types) &&
    /customProfiles: BackupCustomProfilesSection/.test(types))
ok('image block backup carries rule metadata, not preview image content',
  /imageBlockRules: number/.test(types) &&
    /interface BackupImageBlockRuleEntry/.test(types) &&
    !/previewPath/.test(types))

const deny = read('shared/src/main/ets/backup/BackupSecretDenylist.ets')
ok('denylist marks cookie/apikey + auth.accounts as secret',
  /static isSecret\(key: string\): boolean/.test(deny) &&
    /'cookie'/.test(deny) &&
    /'apikey'/.test(deny) &&
    /StorageKeys\.AUTH_ACCOUNTS/.test(deny))
ok('denylist keeps account-scoped user profile snapshots encrypted-only',
  /StorageKeys\.USER_PROFILE_PREFIX/.test(deny) &&
    /key\.startsWith\(StorageKeys\.USER_PROFILE_PREFIX\)/.test(deny))

const adapter = read('shared/src/main/ets/backup/BackupPreferencesAdapter.ets')
ok('adapter splits store by secret + re-checks denylist on restore + reapplies via bootstrap',
  /exportPreferences\(/.test(adapter) &&
    /exportSecrets\(/.test(adapter) &&
    /acceptsKey\(key: string, allowSecret: boolean\)/.test(adapter) &&
    /const secretKey: boolean = BackupSecretDenylist\.isSecret\(key\)/.test(adapter) &&
    /!allowSecret && secretKey/.test(adapter) &&
    /allowSecret && !secretKey/.test(adapter) &&
    /SettingsBootstrap\.loadAll\(context\)/.test(adapter))
ok('plaintext Preferences export skips cache snapshots and migrated legacy blobs',
  /PLAINTEXT_EXCLUDED_KEYS/.test(adapter) &&
    /StorageKeys\.FAVORITES_FAVCATS/.test(adapter) &&
    /StorageKeys\.DOWNLOAD_GALLERY_QUEUE/.test(adapter) &&
    /StorageKeys\.HOME_CUSTOM_PROFILES/.test(adapter) &&
    /!secret && BackupPreferencesAdapter\.isPlaintextExcluded\(key\)/.test(adapter))
ok('plaintext Preferences export and restore exclude account-scoped favcat cache snapshots',
  /key\.startsWith\(`\$\{StorageKeys\.FAVORITES_FAVCATS\}\.`\)/.test(adapter) &&
    /!secret && BackupPreferencesAdapter\.isPlaintextExcluded\(key\)/.test(adapter) &&
    /!allowSecret && BackupPreferencesAdapter\.isPlaintextExcluded\(key\)/.test(adapter))
ok('plaintext Preferences restore also skips migrated local-data blobs',
  /!allowSecret && BackupPreferencesAdapter\.isPlaintextExcluded\(key\)/.test(adapter))
ok('Preferences backup excludes volatile runtime state from plaintext and encrypted sections',
  /VOLATILE_EXCLUDED_KEYS/.test(adapter) &&
    /StorageKeys\.SYNC_LAST_RUN_AT/.test(adapter) &&
    /StorageKeys\.SYNC_LAST_STATUS/.test(adapter) &&
    /StorageKeys\.SYNC_LAST_DETAIL/.test(adapter) &&
    /StorageKeys\.SYNC_HUAWEI_CLOUD_LAST_RUN_AT/.test(adapter) &&
    /StorageKeys\.SYNC_HUAWEI_CLOUD_LAST_STATUS/.test(adapter) &&
    /StorageKeys\.SYNC_HUAWEI_CLOUD_LAST_DETAIL/.test(adapter) &&
    /StorageKeys\.SYNC_HUAWEI_CLOUD_LAST_CLOUD_DISABLED/.test(adapter) &&
    /StorageKeys\.SECURITY_LAST_BACKGROUND_AT/.test(adapter) &&
    /StorageKeys\.SAFE_MODE_UNLOCKED/.test(adapter) &&
    /StorageKeys\.DOWNLOAD_ARCHIVE_BOT_BALANCE_GP/.test(adapter) &&
    /StorageKeys\.DOWNLOAD_ARCHIVE_BOT_BALANCE_UPDATED_AT/.test(adapter) &&
    /BackupPreferencesAdapter\.isVolatileExcluded\(key\)[\s\S]*continue/.test(adapter))
ok('Preferences rollback replaces the backup scope and deletes import-added keys',
  /static async replace\(/.test(adapter) &&
    /store\.getAllSync\(\)/.test(adapter) &&
    /store\.deleteSync\(key\)/.test(adapter) &&
    /map\[key\] === undefined/.test(adapter) &&
    /BackupPreferencesAdapter\.acceptsKey\(key, allowSecret\)/.test(adapter))

const svc = read('shared/src/main/ets/backup/BackupService.ets')
ok('service seals into the encrypted container only when includeSecrets',
  /if \(options\.includeSecrets\)[\s\S]*BackupCrypto\.seal\(JSON\.stringify\(envelope\), options\.password\)/.test(svc))
ok('service exports and restores localData section',
  /BackupLocalDataAdapter\.exportSection\(context\)/.test(svc) &&
    /sections: BackupSectionName\[\] = \['preferences', 'localData'\]/.test(svc) &&
    /BackupLocalDataAdapter\.restoreSection\(context, envelope\.data\.localData\)/.test(svc) &&
    /imageBlockRules: localData\.imageBlock\.rules\.length/.test(svc))
ok('a plaintext file declaring a secrets section is rejected',
  /!fromEncrypted && envelope\.sections\.indexOf\('secrets'\) >= 0/.test(svc) &&
    /code: 'malformed'/.test(svc))
ok('an encrypted file without a password surfaces password_required; wrong password -> bad_password',
  /encrypted: true,\s*code: 'password_required'/.test(svc) &&
    /code: 'bad_password'/.test(svc))
ok('checksum is verified on parse',
  /BackupChecksum\.verifyEnvelope\(envelope\)/.test(svc) && /code: 'bad_checksum'/.test(svc))
ok('restore snapshots durable stores and rolls back on section failure',
  /const rollbackPreferences: SettingsMap = await BackupPreferencesAdapter\.exportPreferences\(context\)/.test(svc) &&
    /const rollbackLocalData: BackupLocalDataSection = await BackupLocalDataAdapter\.exportSection\(context\)/.test(svc) &&
    /const rollbackSecrets: SettingsMap = await BackupPreferencesAdapter\.exportSecrets\(context\)/.test(svc) &&
    /await BackupPreferencesAdapter\.replace\(context, rollbackPreferences, false\)/.test(svc) &&
    /await BackupLocalDataAdapter\.restoreSection\(context, rollbackLocalData\)/.test(svc) &&
    /await BackupPreferencesAdapter\.replace\(context, rollbackSecrets, true\)/.test(svc) &&
    /failedSections: \[failedSection\]/.test(svc))

ok('shared exports BackupService + types',
  /export \{ BackupService \}/.test(read('shared/src/main/ets/Index.ets')))

const page = read('feature/settings/src/main/ets/pages/CacheSettingsPage.ets')
ok('page has export + import, secrets require a password, restore confirms first',
  /openExport\(/.test(page) &&
    /startImport\(/.test(page) &&
    /this\.exportPwd !== this\.exportPwd2/.test(page) &&
    /backup_password_required/.test(page) &&
    /showAlertDialog/.test(page))
ok('encrypted import prompts for a password before restoring',
  /result\.encrypted === true/.test(page) && /importPwdSheetShown = true/.test(page))
ok('encrypted import password input is state-bound and cannot submit empty',
  /confirmEnabled: !this\.busy && this\.importPwd\.length > 0/.test(page) &&
    /PasswordField\(text: string, placeholder: ResourceStr/.test(page) &&
    /TextInput\(\{ text: text, placeholder: placeholder \}\)/.test(page))
ok('import diagnostics surface parser codes instead of a single generic failure',
  /importFailureText\(result: BackupParseResult\)/.test(page) &&
    /backup_import_too_large/.test(page) &&
    /backup_import_not_json/.test(page) &&
    /backup_import_foreign/.test(page) &&
    /backup_import_unsupported/.test(page) &&
    /backup_import_bad_checksum/.test(page) &&
    /backup_import_malformed/.test(page))
ok('restore confirmation previews backup section counts before applying',
  /BackupService\.preview\(envelope\)/.test(page) &&
    /restorePreviewMessage\(preview: BackupPreview\)/.test(page) &&
    /localDataCount\(preview: BackupPreview\)/.test(page) &&
    /backup_restore_preview_preferences/.test(page) &&
    /backup_restore_preview_local_data/.test(page))
ok('sheets use $$ two-way binding on their own hosts',
  /\$\$this\.exportSheetShown/.test(page) && /\$\$this\.importPwdSheetShown/.test(page))

ok('backup UI is inlined on cache/storage settings page',
  /backup_export/.test(page) && /backup_import/.test(page) && /BackupFilePickerCoordinator/.test(page))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const s = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of ['settings_backup', 'backup_export', 'backup_import', 'backup_include_secrets',
    'backup_password', 'backup_password_mismatch', 'backup_bad_password', 'backup_restore_confirm_title',
    'backup_import_not_json', 'backup_import_too_large', 'backup_import_foreign',
    'backup_import_unsupported', 'backup_import_bad_checksum', 'backup_import_malformed',
    'backup_restore_preview_version', 'backup_restore_preview_type',
    'backup_restore_preview_plain', 'backup_restore_preview_encrypted',
    'backup_restore_preview_preferences', 'backup_restore_preview_local_data',
    'backup_restore_preview_secrets']) {
    ok(`${locale} has ${key}`, new RegExp(`"name": "${key}"`).test(s))
  }
}

if (failures === 0) {
  console.log('✓ settings backup contract passed')
  process.exit(0)
}
console.error(`✗ settings backup contract: ${failures} failure(s)`)
process.exit(1)
