export const SYNC_MAGIC: string = 'NEXTE_SYNC'
export const SYNC_APP_ID: string = 'com.erosteam.nexte'
export const SYNC_SCHEMA_VERSION: number = 1
export const SYNC_MIN_SUPPORTED_SCHEMA_VERSION: number = 1
export const SYNC_FILE_NAME: string = 'nexte-sync-v1.json'
export const SYNC_WEBDAV_ROOT_DIR: string = 'nexte-sync-v1'
export const SYNC_WEBDAV_MANIFEST_FILE: string = 'manifest.json'

export class SyncReadProgressRecord {
  scopeKey: string = ''
  gid: string = ''
  pageIndex: number = 0
  columnMode: string = ''
  updatedAt: number = 0
  deletedAt: number = 0
}

export class SyncViewedHistoryRecord {
  scopeKey: string = ''
  gid: string = ''
  token: string = ''
  title: string = ''
  titleJp: string = ''
  thumbUrl: string = ''
  category: string = ''
  uploader: string = ''
  rating: number = 0
  fileCount: string = ''
  viewedAt: number = 0
  deletedAt: number = 0
  postTime: string = ''
  ratingFallback: number = 0
  colorRating: string = ''
  translated: string = ''
  expunged: boolean = false
}

export class SyncLocalFavoriteRecord {
  scopeKey: string = ''
  gid: string = ''
  token: string = ''
  url: string = ''
  thumbUrl: string = ''
  thumbUrlL: string = ''
  imgWidth: number = 0
  imgHeight: number = 0
  englishTitle: string = ''
  japaneseTitle: string = ''
  category: string = ''
  uploader: string = ''
  postTime: string = ''
  fileCount: string = ''
  rating: number = 0
  ratingFallback: number = 0
  colorRating: string = ''
  favNote: string = ''
  favTitle: string = ''
  expunged: boolean = false
  lastViewTime: number = 0
  deletedAt: number = 0
}

export class SyncSearchHistoryRecord {
  scopeKey: string = ''
  queryText: string = ''
  positionIndex: number = 0
  updatedAt: number = 0
  deletedAt: number = 0
}

export class SyncLocalBlockSettingsRecord {
  scopeKey: string = ''
  filterCommentsByScore: boolean = false
  scoreFilteringThreshold: number = -20
  commentDisplayMode: string = ''
  updatedAt: number = 0
  deletedAt: number = 0
}

export class SyncLocalBlockRuleRecord {
  scopeKey: string = ''
  ruleId: string = ''
  positionIndex: number = 0
  blockType: string = ''
  ruleText: string = ''
  enabled: boolean = true
  enableRegex: boolean = false
  updatedAt: number = 0
  deletedAt: number = 0
}

export class SyncImageBlockSubscriptionRecord {
  scopeKey: string = ''
  feedId: string = ''
  title: string = ''
  url: string = ''
  algorithm: string = ''
  defaultThreshold: number = 0
  updatedAt: number = 0
  syncedAt: number = 0
  sha256: string = ''
  ruleCount: number = 0
  enabled: boolean = true
  deletedAt: number = 0
}

export class SyncImageBlockRuleRecord {
  scopeKey: string = ''
  ruleId: string = ''
  hash: string = ''
  threshold: number = 0
  label: string = ''
  scope: string = ''
  feedId: string = ''
  sourceType: string = ''
  sourceUrl: string = ''
  sourcePage: number = 0
  previewPath: string = ''
  enabled: boolean = true
  updatedAt: number = 0
  deletedAt: number = 0
}

export class SyncCustomProfileRecord {
  scopeKey: string = ''
  uuid: string = ''
  positionIndex: number = 0
  name: string = ''
  listType: string = ''
  searchText: string = ''
  selectedCats: number = 0
  advancedEnabled: boolean = false
  minRating: number = 0
  pagesFrom: number = 0
  pagesTo: number = 0
  requireTorrent: boolean = false
  showExpunged: boolean = false
  disableLanguageFilter: boolean = false
  disableUploaderFilter: boolean = false
  disableTagFilter: boolean = false
  favcat: string = ''
  toplistTl: number = 0
  displayMode: string = ''
  hidden: boolean = false
  builtin: boolean = false
  lastEditTime: number = 0
  deletedAt: number = 0
}

export class SyncCustomProfileSelectionRecord {
  scopeKey: string = ''
  selectedUuid: string = ''
  updatedAt: number = 0
  deletedAt: number = 0
}

export class SyncDatasets {
  readProgress: SyncReadProgressRecord[] = []
  viewedHistory: SyncViewedHistoryRecord[] = []
  localFavorites: SyncLocalFavoriteRecord[] = []
  searchHistory: SyncSearchHistoryRecord[] = []
  localBlockSettings: SyncLocalBlockSettingsRecord[] = []
  localBlockRules: SyncLocalBlockRuleRecord[] = []
  imageBlockSubscriptions: SyncImageBlockSubscriptionRecord[] = []
  imageBlockRules: SyncImageBlockRuleRecord[] = []
  customProfiles: SyncCustomProfileRecord[] = []
  customProfileSelection: SyncCustomProfileSelectionRecord[] = []
}

export class SyncManifestShard {
  id: string = ''
  path: string = ''
  sha256: string = ''
  recordCount: number = 0
  updatedAt: number = 0
}

export class SyncManifestDataset {
  id: string = ''
  shards: SyncManifestShard[] = []
}

export class SyncManifestV1 {
  magic: string = SYNC_MAGIC
  appId: string = SYNC_APP_ID
  schemaVersion: number = SYNC_SCHEMA_VERSION
  minSupportedSchemaVersion: number = SYNC_MIN_SUPPORTED_SCHEMA_VERSION
  generatedAt: string = ''
  datasets: SyncManifestDataset[] = []
}

export class SyncDatasetSelection {
  readProgress: boolean = true
  viewedHistory: boolean = true
  localFavorites: boolean = true
  searchHistory: boolean = true
  localBlock: boolean = true
  imageBlock: boolean = true
  customProfiles: boolean = true
}

export class SyncEnvelopeV1 {
  magic: string = SYNC_MAGIC
  appId: string = SYNC_APP_ID
  schemaVersion: number = SYNC_SCHEMA_VERSION
  minSupportedSchemaVersion: number = SYNC_MIN_SUPPORTED_SCHEMA_VERSION
  generatedAt: string = ''
  deviceId: string = ''
  datasetId: string = ''
  shardId: string = ''
  datasets: SyncDatasets = new SyncDatasets()
}
