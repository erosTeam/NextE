// Settings backup/restore envelope contract (ported from V2Next, simplified for NextE which keeps all
// settings in a single Preferences store). A plaintext envelope carries the non-secret 'preferences'
// section; the 'secrets' section (login cookie bundle, saved accounts, LLM API key) is encryption-only and
// may travel ONLY inside the encrypted container below — never in cleartext.
export const BACKUP_MAGIC: string = 'NEXTE_BACKUP'
export const BACKUP_APP_ID: string = 'com.erosteam.nexte'
export const BACKUP_SCHEMA_VERSION: number = 1
export const BACKUP_MIN_SUPPORTED_SCHEMA_VERSION: number = 1
export const BACKUP_FILE_SUFFIX: string = '.nexte-backup.json'
export const BACKUP_CHECKSUM_ALGORITHM: string = 'SHA-256'
export const MAX_BACKUP_BYTES: number = 10 * 1024 * 1024

export type BackupSectionName = 'preferences' | 'secrets'
// Plaintext-eligible sections. 'secrets' is intentionally excluded — it only rides inside the cipher.
export const BACKUP_SECTION_NAMES: BackupSectionName[] = ['preferences']
export const BACKUP_ENCRYPTED_ONLY_SECTION_NAMES: BackupSectionName[] = ['secrets']

// ── Encrypted container (AES-256-GCM + PBKDF2-SHA256), ported verbatim from V2Next ──
export const BACKUP_CIPHER_ALGORITHM: string = 'AES-256-GCM'
export const BACKUP_KDF_ALGORITHM: string = 'PBKDF2-SHA256'
export const BACKUP_KDF_ITERATIONS: number = 210000
export const BACKUP_KDF_KEY_SIZE: number = 32
export const BACKUP_CIPHER_SALT_BYTES: number = 16
export const BACKUP_CIPHER_IV_BYTES: number = 12
export const BACKUP_CIPHER_TAG_BYTES: number = 16

export type BackupSettingsValue = string | number | boolean

export interface BackupChecksumInfo {
  algorithm: string
  value: string
}

export interface BackupCounts {
  preferences: number
  secrets?: number
}

export interface BackupData {
  // Raw Preferences scalars (booleans/numbers, or JSON strings for composite settings).
  preferences?: Record<string, BackupSettingsValue>
  // The denylisted secret keys (auth.cookieJar / auth.accounts / commentTranslation.apiKey).
  secrets?: Record<string, BackupSettingsValue>
}

export interface BackupEnvelopeV1 {
  magic: string
  appId: string
  schemaVersion: number
  minSupportedSchemaVersion: number
  createdAt: string
  appVersion: string
  appVersionCode: number
  sections: BackupSectionName[]
  counts: BackupCounts
  data: BackupData
  checksum?: BackupChecksumInfo
}

export interface BackupCipherMeta {
  cipher: string
  kdf: string
  iterations: number
  keySize: number
  salt: string
  iv: string
}

export interface BackupEncryptedEnvelope {
  magic: string
  appId: string
  schemaVersion: number
  minSupportedSchemaVersion: number
  encrypted: boolean
  createdAt: string
  appVersion: string
  appVersionCode: number
  cipherMeta: BackupCipherMeta
  ciphertext: string
}

export interface BackupAppMetadata {
  appVersion: string
  appVersionCode: number
}

export interface BackupExportOptions {
  // When true the backup includes the 'secrets' section and MUST be sealed with a non-empty password.
  includeSecrets: boolean
  password: string
}

export interface BackupPreview {
  createdAt: string
  appVersion: string
  appVersionCode: number
  sections: BackupSectionName[]
  counts: BackupCounts
  hasSecrets: boolean
}

export interface BackupValidationResult {
  ok: boolean
  code: string
  message: string
}

export interface BackupParseResult {
  ok: boolean
  envelope?: BackupEnvelopeV1
  // Set when the raw file is a recognized encrypted NextE backup: ok=false, code='password_required';
  // the caller must prompt for a password and call the decrypt path.
  encrypted?: boolean
  code: string
  message: string
}

export interface BackupRestoreResult {
  ok: boolean
  restoredSections: BackupSectionName[]
  failedSections: BackupSectionName[]
  message: string
}
