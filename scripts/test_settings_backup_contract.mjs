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
    /customProfiles: BackupCustomProfilesSection/.test(types))

const deny = read('shared/src/main/ets/backup/BackupSecretDenylist.ets')
ok('denylist marks cookie/apikey + auth.accounts as secret',
  /static isSecret\(key: string\): boolean/.test(deny) &&
    /'cookie'/.test(deny) &&
    /'apikey'/.test(deny) &&
    /'auth\.accounts'/.test(deny))

const adapter = read('shared/src/main/ets/backup/BackupPreferencesAdapter.ets')
ok('adapter splits store by secret + re-checks denylist on restore + reapplies via bootstrap',
  /exportPreferences\(/.test(adapter) &&
    /exportSecrets\(/.test(adapter) &&
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
ok('plaintext Preferences restore also skips migrated local-data blobs',
  /!allowSecret && BackupPreferencesAdapter\.isPlaintextExcluded\(key\)/.test(adapter))

const svc = read('shared/src/main/ets/backup/BackupService.ets')
ok('service seals into the encrypted container only when includeSecrets',
  /if \(options\.includeSecrets\)[\s\S]*BackupCrypto\.seal\(JSON\.stringify\(envelope\), options\.password\)/.test(svc))
ok('service exports and restores localData section',
  /BackupLocalDataAdapter\.exportSection\(context\)/.test(svc) &&
    /sections: BackupSectionName\[\] = \['preferences', 'localData'\]/.test(svc) &&
    /BackupLocalDataAdapter\.restoreSection\(context, envelope\.data\.localData\)/.test(svc))
ok('a plaintext file declaring a secrets section is rejected',
  /!fromEncrypted && envelope\.sections\.indexOf\('secrets'\) >= 0/.test(svc) &&
    /code: 'malformed'/.test(svc))
ok('an encrypted file without a password surfaces password_required; wrong password -> bad_password',
  /encrypted: true,\s*code: 'password_required'/.test(svc) &&
    /code: 'bad_password'/.test(svc))
ok('checksum is verified on parse',
  /BackupChecksum\.verifyEnvelope\(envelope\)/.test(svc) && /code: 'bad_checksum'/.test(svc))

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
ok('sheets use $$ two-way binding on their own hosts',
  /\$\$this\.exportSheetShown/.test(page) && /\$\$this\.importPwdSheetShown/.test(page))

ok('backup UI is inlined on cache/storage settings page',
  /backup_export/.test(page) && /backup_import/.test(page) && /BackupFilePickerCoordinator/.test(page))

for (const locale of ['base', 'zh_CN', 'en_US', 'ja_JP']) {
  const s = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of ['settings_backup', 'backup_export', 'backup_import', 'backup_include_secrets',
    'backup_password', 'backup_password_mismatch', 'backup_bad_password', 'backup_restore_confirm_title']) {
    ok(`${locale} has ${key}`, new RegExp(`"name": "${key}"`).test(s))
  }
}

if (failures === 0) {
  console.log('✓ settings backup contract passed')
  process.exit(0)
}
console.error(`✗ settings backup contract: ${failures} failure(s)`)
process.exit(1)
