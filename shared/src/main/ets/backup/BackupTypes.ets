// Settings/local-data backup/restore envelope contract. A plaintext envelope carries non-secret
// preferences + durable local data; the 'secrets' section is encryption-only and may travel ONLY inside
// the encrypted container below — never in cleartext.
export const BACKUP_MAGIC: string = 'NEXTE_BACKUP'
export const BACKUP_APP_ID: string = 'com.erosteam.nexte'
export const BACKUP_SCHEMA_VERSION: number = 1
export const BACKUP_MIN_SUPPORTED_SCHEMA_VERSION: number = 1
export const BACKUP_FILE_SUFFIX: string = '.nexte-backup.json'
export const BACKUP_CHECKSUM_ALGORITHM: string = 'SHA-256'
export const MAX_BACKUP_BYTES: number = 10 * 1024 * 1024

export type BackupSectionName = 'preferences' | 'localData' | 'secrets'
// Plaintext-eligible sections. 'secrets' is intentionally excluded — it only rides inside the cipher.
export const BACKUP_SECTION_NAMES: BackupSectionName[] = ['preferences', 'localData']
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
  localData?: BackupLocalDataCounts
  secrets?: number
}

export interface BackupLocalDataCounts {
  readProgress: number
  viewedHistory: number
  localFavorites: number
  searchHistory: number
  localBlockRules: number
  imageBlockRules: number
  customProfiles: number
}

export interface BackupReadProgressEntry {
  g: string
  i: number
  t: number
  c?: string
}

export interface BackupLocalDataSection {
  readProgress: BackupReadProgressEntry[]
  viewedHistory: BackupViewedHistoryEntry[]
  localFavorites: BackupLocalFavoriteEntry[]
  searchHistory: string[]
  localBlock: BackupLocalBlockSection
  imageBlock: BackupImageBlockSection
  customProfiles: BackupCustomProfilesSection
}

export interface BackupViewedHistoryEntry {
  gid: string
  token: string
  title: string
  titleJp: string
  thumbUrl: string
  category: string
  uploader: string
  rating: number
  fileCount: string
  time: number
  postTime?: string
  ratingFallBack?: number
  colorRating?: string
  translated?: string
  expunged?: boolean
}

export interface BackupLocalFavoriteEntry {
  gid: string
  token: string
  url: string
  thumbUrl: string
  thumbUrlL: string
  imgWidth: number
  imgHeight: number
  englishTitle: string
  japaneseTitle: string
  category: string
  uploader: string
  postTime: string
  fileCount: string
  rating: number
  ratingFallBack: number
  colorRating: string
  favNote: string
  favTitle: string
  expunged: boolean
  lastViewTime: number
}

export interface BackupLocalBlockRuleEntry {
  id: string
  blockType: string
  ruleText: string
  enabled: boolean
  enableRegex: boolean
}

export interface BackupLocalBlockSection {
  filterCommentsByScore: boolean
  scoreFilteringThreshold: number
  commentDisplayMode: string
  rules: BackupLocalBlockRuleEntry[]
}

export interface BackupImageBlockRuleEntry {
  id: string
  hash: string
  threshold: number
  label: string
  scope: string
  feedId: string
  sourceType: string
  sourceUrl: string
  sourcePage: number
  enabled: boolean
  updatedAt: number
}

export interface BackupImageBlockSection {
  rules: BackupImageBlockRuleEntry[]
}

export interface BackupCustomProfileEntry {
  uuid: string
  name: string
  listType: string
  searchText: string
  selectedCats: number
  advancedEnabled: boolean
  minRating: number
  pagesFrom: number
  pagesTo: number
  requireTorrent: boolean
  showExpunged: boolean
  disableLanguageFilter: boolean
  disableUploaderFilter: boolean
  disableTagFilter: boolean
  favcat: string
  toplistTl: number
  displayMode: string
  hidden: boolean
  builtin: boolean
  lastEditTime: number
}

export interface BackupCustomProfilesSection {
  selectedUuid: string
  profiles: BackupCustomProfileEntry[]
}

export interface BackupData {
  // Raw Preferences scalars (booleans/numbers, or JSON strings for composite settings).
  preferences?: Record<string, BackupSettingsValue>
  // Durable user-local records stored in RDB, kept out of disposable cache tables.
  localData?: BackupLocalDataSection
  // The denylisted secret keys (auth cookies/accounts, complete WebDAV configuration,
  // comment-translation API key, and future credential families).
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
