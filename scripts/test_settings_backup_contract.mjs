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
ok('crypto fixes schema-v1 KDF work instead of accepting container-selected cost or key size',
  /static isSupportedMeta\(meta: BackupCipherMeta\)[\s\S]*meta\.iterations === BACKUP_KDF_ITERATIONS[\s\S]*meta\.keySize === BACKUP_KDF_KEY_SIZE/.test(crypto) &&
    /if \(!BackupCrypto\.isSupportedMeta\(meta\)\)/.test(crypto) &&
    /iterations: BACKUP_KDF_ITERATIONS[\s\S]*keySize: BACKUP_KDF_KEY_SIZE/.test(crypto) &&
    !/meta\.keySize > 0/.test(crypto) && !/meta\.iterations > 0/.test(crypto))

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
ok('WebDAV configuration is an encrypted-only atomic credential group',
  /WEBDAV_CREDENTIAL_KEYS/.test(deny) &&
    /StorageKeys\.SYNC_WEBDAV_URL/.test(deny) &&
    /StorageKeys\.SYNC_WEBDAV_USERNAME/.test(deny) &&
    /StorageKeys\.SYNC_WEBDAV_ENABLED/.test(deny) &&
    /StorageKeys\.SYNC_WEBDAV_PASSWORD/.test(deny) &&
    /static isWebDavCredentialKey\(key: string\): boolean/.test(deny))
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
ok('backup restores WebDAV only as one complete encrypted credential group',
  /BackupSecretDenylist\.isWebDavCredentialKey\(key\)[\s\S]*continue/.test(adapter) &&
    /static async restoreWebDavCredentialGroup\(/.test(adapter) &&
    /static resolveWebDavCredentialGroup\([\s\S]*webDavCredentialValue\(plaintext, secrets/.test(adapter) &&
    /static resolveWebDavCredentialValues\([\s\S]*if \(!fromEncrypted\)[\s\S]*return null/.test(adapter) &&
    /typeof url !== 'string'[\s\S]*typeof username !== 'string'[\s\S]*typeof enabled !== 'boolean'[\s\S]*typeof password !== 'string'/.test(adapter) &&
    /store\.putSync\(StorageKeys\.SYNC_WEBDAV_URL, group\.url\)[\s\S]*store\.putSync\(StorageKeys\.SYNC_WEBDAV_PASSWORD, group\.password\)/.test(adapter))

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
ok('encrypted import validates byte size and fixed cipher metadata before decrypting',
  /static async decryptAndPreview\(raw: string, password: string\)[\s\S]*BackupService\.isTooLarge\(raw\)[\s\S]*JSON\.parse\(raw\)/.test(svc) &&
    /typeof container\.ciphertext !== 'string'[\s\S]*!BackupCrypto\.isSupportedMeta\(meta\)[\s\S]*BackupCrypto\.open\(container\.ciphertext, password, meta\)/.test(svc) &&
    /private static isTooLarge\(raw: string\): boolean/.test(svc))
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
ok('backup restore suppresses automatic remote sync and restores WebDAV atomically',
  /import \{ SyncScheduler \} from '\.\.\/sync\/SyncScheduler'/.test(svc) &&
    /SyncScheduler\.suspendAutomaticSync\(\)[\s\S]*BackupPreferencesAdapter\.restoreWebDavCredentialGroup\([\s\S]*SyncScheduler\.resumeAutomaticSync\(\)/.test(svc))

const syncScheduler = read('shared/src/main/ets/sync/SyncScheduler.ets')
const webDavScheduler = read('shared/src/main/ets/sync/WebDavSyncScheduler.ets')
const huaweiCloudScheduler = read('shared/src/main/ets/sync/HuaweiCloudSyncScheduler.ets')
const webDavCredentialGroupTest = read('entry/src/ohosTest/ets/test/BackupWebDavCredentialGroup.test.ets')
const webDavCredentialGroupTestList = read('entry/src/ohosTest/ets/test/List.test.ets')
ok('both automatic providers cancel queued work and reject restore-window scheduling',
  /suspendAutomaticSync\(\)[\s\S]*HuaweiCloudSyncScheduler\.suspendAutomaticSync\(\)[\s\S]*WebDavSyncScheduler\.suspendAutomaticSync\(\)/.test(syncScheduler) &&
    /automaticSyncSuppressionDepth/.test(webDavScheduler) &&
    /clearTimeout\(WebDavSyncScheduler\.timerId\)/.test(webDavScheduler) &&
    /automaticSyncSuppressed\(\)[\s\S]*webdav_schedule_suppressed/.test(webDavScheduler) &&
    /automaticSyncSuppressionDepth/.test(huaweiCloudScheduler) &&
    /clearTimeout\(HuaweiCloudSyncScheduler\.timerId\)/.test(huaweiCloudScheduler) &&
    /automaticSyncSuppressed\(\)[\s\S]*huawei_cloud_schedule_suppressed/.test(huaweiCloudScheduler))
ok('device test covers legacy/current encrypted groups and rejects plaintext/incomplete input',
  /resolveWebDavCredentialValues\([\s\S]*'legacy-password',[\s\S]*true/.test(webDavCredentialGroupTest) &&
    /resolveWebDavCredentialValues\([\s\S]*'current-password',[\s\S]*true/.test(webDavCredentialGroupTest) &&
    /resolveWebDavCredentialValues\([\s\S]*'legacy-password',[\s\S]*false/.test(webDavCredentialGroupTest) &&
    /backupWebDavCredentialGroupTest\(\)/.test(webDavCredentialGroupTestList))

const imageBlockRepository = read('shared/src/main/ets/storage/ImageBlockRepository.ets')
const localDataAdapter = read('shared/src/main/ets/backup/BackupLocalDataAdapter.ets')
const imageBlockMutationMethods = [
  'upsertLocalRule',
  'removeLocalRule',
  'setLocalRuleThreshold',
  'setLocalRuleEnabled',
  'replaceWhitelist',
  'upsertWhitelistHash',
  'ignoreRule',
  'setRuleEnabledOverride',
  'setRuleThresholdOverride',
  'removeWhitelistHash',
]
const imageBlockMutationBodiesUseLogicalTime = imageBlockMutationMethods.every((method) => {
  const start = imageBlockRepository.indexOf(`static async ${method}`)
  const next = imageBlockRepository.indexOf('\n  static async ', start + 1)
  const body = start >= 0 ? imageBlockRepository.slice(start, next >= 0 ? next : imageBlockRepository.length) : ''
  return body.includes('nextUserRuleMutationTime(store, Date.now())') && body.includes('store.beginTransaction()')
})
ok('image-block backup restore replaces the complete user-rule snapshot, including an empty backup',
  /SQL_TOMBSTONE_USER_RULES_FOR_BACKUP/.test(imageBlockRepository) &&
    /nextUserRuleMutationTime\(store, Date\.now\(\)\)/.test(imageBlockRepository) &&
    /await store\.executeSql\(SQL_TOMBSTONE_USER_RULES_FOR_BACKUP, \[restoredAt, restoredAt, SCOPE_GLOBAL\]\)/.test(imageBlockRepository) &&
    /const snapshotTime: number = Math\.max\(originalTime, restoredAt \+ restoredCount\)/.test(imageBlockRepository) &&
    imageBlockMutationBodiesUseLogicalTime &&
    /ImageBlockRepository\.requestSync\(context, 'image_block_rule_backup_restore'\)/.test(imageBlockRepository) &&
    !/if \(rules\.length <= 0\) \{\s*return/.test(imageBlockRepository) &&
    /publishImageBlockRulesChanged\('backup-restore'\)/.test(localDataAdapter))

ok('shared exports BackupService + types',
  /export \{ BackupService \}/.test(read('shared/src/main/ets/Index.ets')))

const page = read('feature/settings/src/main/ets/pages/CacheSettingsPage.ets')
const picker = read('feature/settings/src/main/ets/model/BackupFilePickerCoordinator.ets')
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
ok('picker rejects oversized files before allocating and preserves the size-specific import message',
  /const size: number = fileIo\.statSync\(file\.fd\)\.size[\s\S]*size > MAX_BACKUP_BYTES[\s\S]*throw new Error\('backup file is too large'\)[\s\S]*new ArrayBuffer\(size\)/.test(picker) &&
    /error\.message === 'backup file is too large'[\s\S]*backup_import_too_large/.test(page))
const backupCipherGuardTest = read('entry/src/ohosTest/ets/test/BackupCipherMetadataGuard.test.ets')
const testList = read('entry/src/ohosTest/ets/test/List.test.ets')
ok('device test exercises rejection of untrusted encrypted KDF metadata before decrypt',
  /BackupService\.decryptAndPreview\([\s\S]*encryptedContainer\(210001, 32\)[\s\S]*result\.code\)\.assertEqual\('malformed'\)/.test(backupCipherGuardTest) &&
    /backupCipherMetadataGuardTest\(\)/.test(testList))
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
