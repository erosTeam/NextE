import { common } from '@kit.AbilityKit'
import { CustomProfilesSettings } from '../settings/CustomProfilesSettings'
import { GalleryReadProgressSettings } from '../settings/GalleryReadProgressSettings'
import { LocalBlockSettings } from '../settings/LocalBlockSettings'
import { LocalFavSettings } from '../settings/LocalFavSettings'
import { SearchHistorySettings } from '../settings/SearchHistorySettings'
import { ViewedHistorySettings } from '../settings/ViewedHistorySettings'
import { publishImageBlockRulesChanged } from '../state/ImageBlockRuntimeState'
import {
  SYNC_APP_ID,
  SYNC_MAGIC,
  SYNC_MIN_SUPPORTED_SCHEMA_VERSION,
  SYNC_SCHEMA_VERSION,
  SyncCustomProfileRecord,
  SyncCustomProfileSelectionRecord,
  SyncDatasetSelection,
  SyncDatasets,
  SyncEnvelopeV1,
  SyncImageBlockRuleRecord,
  SyncImageBlockSubscriptionRecord,
  SyncLocalBlockRuleRecord,
  SyncLocalBlockSettingsRecord,
  SyncLocalFavoriteRecord,
  SyncReadProgressRecord,
  SyncSearchHistoryRecord,
  SyncViewedHistoryRecord,
} from './SyncTypes'
import { SyncLocalDataAdapter } from './SyncLocalDataAdapter'

export class SyncService {
  static async exportRaw(
    context: common.UIAbilityContext,
    deviceId: string = '',
    selection: SyncDatasetSelection = new SyncDatasetSelection(),
  ): Promise<string> {
    if (selection.viewedHistory) {
      await ViewedHistorySettings.flushForSync(context)
    }
    if (selection.localFavorites) {
      await LocalFavSettings.flushForSync(context)
    }
    if (selection.searchHistory) {
      await SearchHistorySettings.flushForSync(context)
    }
    if (selection.localBlock) {
      await LocalBlockSettings.flushForSync(context)
    }
    const envelope: SyncEnvelopeV1 = await SyncLocalDataAdapter.exportEnvelope(context, deviceId, selection)
    return JSON.stringify(envelope)
  }

  // Transport-neutral file sync core: merge a remote envelope with local RDB, apply the merged result
  // locally, and return the exact raw payload that the provider should write back.
  static async mergeRemoteRaw(
    context: common.UIAbilityContext,
    remoteRaw: string,
    deviceId: string = '',
    selection: SyncDatasetSelection = new SyncDatasetSelection(),
  ): Promise<string> {
    const remote: SyncEnvelopeV1 = SyncService.parseRaw(remoteRaw)
    const selectedMerged: SyncEnvelopeV1 =
      await SyncService.mergeRemoteEnvelope(context, remote, deviceId, selection)
    const writeBack: SyncEnvelopeV1 =
      SyncLocalDataAdapter.mergeSelectedIntoRemote(remote, selectedMerged, selection, deviceId)
    return JSON.stringify(writeBack)
  }

  static async mergeRemoteEnvelope(
    context: common.UIAbilityContext,
    remote: SyncEnvelopeV1,
    deviceId: string = '',
    selection: SyncDatasetSelection = new SyncDatasetSelection(),
  ): Promise<SyncEnvelopeV1> {
    if (selection.readProgress) {
      await GalleryReadProgressSettings.flushForSync(context)
    }
    if (selection.viewedHistory) {
      await ViewedHistorySettings.flushForSync(context)
    }
    if (selection.localFavorites) {
      await LocalFavSettings.flushForSync(context)
    }
    if (selection.searchHistory) {
      await SearchHistorySettings.flushForSync(context)
    }
    if (selection.localBlock) {
      await LocalBlockSettings.flushForSync(context)
    }
    const local: SyncEnvelopeV1 =
      await SyncLocalDataAdapter.exportEnvelope(context, deviceId, selection)
    const selectedRemote: SyncEnvelopeV1 = SyncService.selectDatasets(remote, selection)
    const selectedMerged: SyncEnvelopeV1 =
      SyncLocalDataAdapter.mergeEnvelopes(local, selectedRemote)
    selectedMerged.deviceId = deviceId
    await SyncLocalDataAdapter.applyEnvelope(context, selectedMerged)
    await SyncService.refreshSelectedState(context, selection)
    return selectedMerged
  }

  static async importRaw(context: common.UIAbilityContext, raw: string): Promise<void> {
    const envelope: SyncEnvelopeV1 = SyncService.parseRaw(raw)
    await ViewedHistorySettings.flushForSync(context)
    await LocalFavSettings.flushForSync(context)
    await SearchHistorySettings.flushForSync(context)
    await LocalBlockSettings.flushForSync(context)
    await SyncLocalDataAdapter.applyEnvelope(context, envelope)
  }

  static parseRaw(raw: string): SyncEnvelopeV1 {
    if (raw.trim().length === 0) {
      const empty: SyncEnvelopeV1 = new SyncEnvelopeV1()
      empty.generatedAt = new Date().toISOString()
      return empty
    }
    const parsed: SyncEnvelopeV1 = JSON.parse(raw) as SyncEnvelopeV1
    if (parsed.magic !== SYNC_MAGIC || parsed.appId !== SYNC_APP_ID) {
      throw new Error('Invalid NextE sync file')
    }
    if (
      parsed.schemaVersion !== SYNC_SCHEMA_VERSION ||
      parsed.minSupportedSchemaVersion > SYNC_SCHEMA_VERSION
    ) {
      throw new Error('Unsupported NextE sync schema')
    }
    if (parsed.datasets === null || parsed.datasets === undefined) {
      parsed.datasets = new SyncDatasets()
    }
    SyncService.normalizeDatasets(parsed)
    return parsed
  }

  private static normalizeDatasets(envelope: SyncEnvelopeV1): void {
    const data: SyncDatasets = envelope.datasets
    if (!Array.isArray(data.readProgress)) {
      data.readProgress = []
    }
    if (!Array.isArray(data.viewedHistory)) {
      data.viewedHistory = []
    }
    if (!Array.isArray(data.localFavorites)) {
      data.localFavorites = []
    }
    if (!Array.isArray(data.searchHistory)) {
      data.searchHistory = []
    }
    if (!Array.isArray(data.localBlockSettings)) {
      data.localBlockSettings = []
    }
    if (!Array.isArray(data.localBlockRules)) {
      data.localBlockRules = []
    }
    if (!Array.isArray(data.imageBlockSubscriptions)) {
      data.imageBlockSubscriptions = []
    }
    if (!Array.isArray(data.imageBlockRules)) {
      data.imageBlockRules = []
    }
    if (!Array.isArray(data.customProfiles)) {
      data.customProfiles = []
    }
    if (!Array.isArray(data.customProfileSelection)) {
      data.customProfileSelection = []
    }
    for (let i: number = 0; i < data.readProgress.length; i++) {
      const r: SyncReadProgressRecord = data.readProgress[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.gid = SyncService.safeString(r.gid)
      r.pageIndex = SyncService.safeNumber(r.pageIndex)
      r.columnMode = SyncService.safeString(r.columnMode)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.viewedHistory.length; i++) {
      const r: SyncViewedHistoryRecord = data.viewedHistory[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.gid = SyncService.safeString(r.gid)
      r.token = SyncService.safeString(r.token)
      r.title = SyncService.safeString(r.title)
      r.titleJp = SyncService.safeString(r.titleJp)
      r.thumbUrl = SyncService.safeString(r.thumbUrl)
      r.category = SyncService.safeString(r.category)
      r.uploader = SyncService.safeString(r.uploader)
      r.rating = SyncService.safeNumber(r.rating)
      r.fileCount = SyncService.safeString(r.fileCount)
      r.viewedAt = SyncService.safeNumber(r.viewedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.localFavorites.length; i++) {
      const r: SyncLocalFavoriteRecord = data.localFavorites[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.gid = SyncService.safeString(r.gid)
      r.token = SyncService.safeString(r.token)
      r.url = SyncService.safeString(r.url)
      r.thumbUrl = SyncService.safeString(r.thumbUrl)
      r.thumbUrlL = SyncService.safeString(r.thumbUrlL)
      r.imgWidth = SyncService.safeNumber(r.imgWidth)
      r.imgHeight = SyncService.safeNumber(r.imgHeight)
      r.englishTitle = SyncService.safeString(r.englishTitle)
      r.japaneseTitle = SyncService.safeString(r.japaneseTitle)
      r.category = SyncService.safeString(r.category)
      r.uploader = SyncService.safeString(r.uploader)
      r.postTime = SyncService.safeString(r.postTime)
      r.fileCount = SyncService.safeString(r.fileCount)
      r.rating = SyncService.safeNumber(r.rating)
      r.ratingFallback = SyncService.safeNumber(r.ratingFallback)
      r.colorRating = SyncService.safeString(r.colorRating)
      r.favNote = SyncService.safeString(r.favNote)
      r.favTitle = SyncService.safeString(r.favTitle)
      r.expunged = SyncService.safeBoolean(r.expunged)
      r.lastViewTime = SyncService.safeNumber(r.lastViewTime)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.searchHistory.length; i++) {
      const r: SyncSearchHistoryRecord = data.searchHistory[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.queryText = SyncService.safeString(r.queryText)
      r.positionIndex = SyncService.safeNumber(r.positionIndex)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.localBlockSettings.length; i++) {
      const r: SyncLocalBlockSettingsRecord = data.localBlockSettings[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.filterCommentsByScore = SyncService.safeBoolean(r.filterCommentsByScore)
      r.scoreFilteringThreshold = SyncService.safeNumber(r.scoreFilteringThreshold)
      r.commentDisplayMode = SyncService.safeString(r.commentDisplayMode)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.localBlockRules.length; i++) {
      const r: SyncLocalBlockRuleRecord = data.localBlockRules[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.ruleId = SyncService.safeString(r.ruleId)
      r.positionIndex = SyncService.safeNumber(r.positionIndex)
      r.blockType = SyncService.safeString(r.blockType)
      r.ruleText = SyncService.safeString(r.ruleText)
      r.enabled = SyncService.safeBoolean(r.enabled)
      r.enableRegex = SyncService.safeBoolean(r.enableRegex)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.imageBlockSubscriptions.length; i++) {
      const r: SyncImageBlockSubscriptionRecord = data.imageBlockSubscriptions[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.feedId = SyncService.safeString(r.feedId)
      r.title = SyncService.safeString(r.title)
      r.url = SyncService.safeString(r.url)
      r.algorithm = SyncService.safeString(r.algorithm)
      r.defaultThreshold = SyncService.safeNumber(r.defaultThreshold)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.syncedAt = SyncService.safeNumber(r.syncedAt)
      r.sha256 = SyncService.safeString(r.sha256)
      r.ruleCount = SyncService.safeNumber(r.ruleCount)
      r.enabled = SyncService.safeBoolean(r.enabled)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.imageBlockRules.length; i++) {
      const r: SyncImageBlockRuleRecord = data.imageBlockRules[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.ruleId = SyncService.safeString(r.ruleId)
      r.hash = SyncService.safeString(r.hash)
      r.threshold = SyncService.safeNumber(r.threshold)
      r.label = SyncService.safeString(r.label)
      r.scope = SyncService.safeString(r.scope)
      r.feedId = SyncService.safeString(r.feedId)
      r.sourceType = SyncService.safeString(r.sourceType)
      r.sourceUrl = SyncService.safeString(r.sourceUrl)
      r.sourcePage = SyncService.safeNumber(r.sourcePage)
      r.previewPath = SyncService.safeString(r.previewPath)
      r.enabled = SyncService.safeBoolean(r.enabled)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.customProfiles.length; i++) {
      const r: SyncCustomProfileRecord = data.customProfiles[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.uuid = SyncService.safeString(r.uuid)
      r.positionIndex = SyncService.safeNumber(r.positionIndex)
      r.name = SyncService.safeString(r.name)
      r.listType = SyncService.safeString(r.listType)
      r.searchText = SyncService.safeString(r.searchText)
      r.selectedCats = SyncService.safeNumber(r.selectedCats)
      r.advancedEnabled = SyncService.safeBoolean(r.advancedEnabled)
      r.minRating = SyncService.safeNumber(r.minRating)
      r.pagesFrom = SyncService.safeNumber(r.pagesFrom)
      r.pagesTo = SyncService.safeNumber(r.pagesTo)
      r.requireTorrent = SyncService.safeBoolean(r.requireTorrent)
      r.showExpunged = SyncService.safeBoolean(r.showExpunged)
      r.disableLanguageFilter = SyncService.safeBoolean(r.disableLanguageFilter)
      r.disableUploaderFilter = SyncService.safeBoolean(r.disableUploaderFilter)
      r.disableTagFilter = SyncService.safeBoolean(r.disableTagFilter)
      r.favcat = SyncService.safeString(r.favcat)
      r.toplistTl = SyncService.safeNumber(r.toplistTl)
      r.displayMode = SyncService.safeString(r.displayMode)
      r.hidden = SyncService.safeBoolean(r.hidden)
      r.builtin = SyncService.safeBoolean(r.builtin)
      r.lastEditTime = SyncService.safeNumber(r.lastEditTime)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
    for (let i: number = 0; i < data.customProfileSelection.length; i++) {
      const r: SyncCustomProfileSelectionRecord = data.customProfileSelection[i]
      r.scopeKey = SyncService.safeString(r.scopeKey)
      r.selectedUuid = SyncService.safeString(r.selectedUuid)
      r.updatedAt = SyncService.safeNumber(r.updatedAt)
      r.deletedAt = SyncService.safeNumber(r.deletedAt)
    }
  }

  private static safeString(value: Object): string {
    if (typeof value === 'string') {
      return value
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return `${value}`
    }
    return ''
  }

  private static safeNumber(value: Object): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? Math.floor(value) : 0
    }
    if (typeof value === 'string') {
      const parsed: number = Number.parseFloat(value)
      return Number.isFinite(parsed) ? Math.floor(parsed) : 0
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    return 0
  }

  private static safeBoolean(value: Object): boolean {
    if (typeof value === 'boolean') {
      return value
    }
    if (typeof value === 'number') {
      return value > 0
    }
    if (typeof value === 'string') {
      const normalized: string = value.toLowerCase()
      return normalized === 'true' || normalized === '1'
    }
    return false
  }

  private static selectDatasets(
    source: SyncEnvelopeV1,
    selection: SyncDatasetSelection,
  ): SyncEnvelopeV1 {
    const out: SyncEnvelopeV1 = new SyncEnvelopeV1()
    out.generatedAt = source.generatedAt
    out.deviceId = source.deviceId
    if (selection.readProgress) {
      out.datasets.readProgress = source.datasets.readProgress
    }
    if (selection.viewedHistory) {
      out.datasets.viewedHistory = source.datasets.viewedHistory
    }
    if (selection.localFavorites) {
      out.datasets.localFavorites = source.datasets.localFavorites
    }
    if (selection.searchHistory) {
      out.datasets.searchHistory = source.datasets.searchHistory
    }
    if (selection.localBlock) {
      out.datasets.localBlockSettings = source.datasets.localBlockSettings
      out.datasets.localBlockRules = source.datasets.localBlockRules
    }
    if (selection.imageBlock) {
      out.datasets.imageBlockSubscriptions = source.datasets.imageBlockSubscriptions
      out.datasets.imageBlockRules = source.datasets.imageBlockRules
    }
    if (selection.customProfiles) {
      out.datasets.customProfiles = source.datasets.customProfiles
      out.datasets.customProfileSelection = source.datasets.customProfileSelection
    }
    return out
  }

  static async refreshSelectedState(
    context: common.UIAbilityContext,
    selection: SyncDatasetSelection,
  ): Promise<void> {
    if (selection.readProgress) {
      await GalleryReadProgressSettings.refreshAfterSync(context)
    }
    if (selection.viewedHistory) {
      await ViewedHistorySettings.restore(context)
    }
    if (selection.localFavorites) {
      await LocalFavSettings.restore(context)
    }
    if (selection.searchHistory) {
      await SearchHistorySettings.restore(context)
    }
    if (selection.localBlock) {
      await LocalBlockSettings.restore(context)
    }
    if (selection.imageBlock) {
      publishImageBlockRulesChanged('sync')
    }
    if (selection.customProfiles) {
      await CustomProfilesSettings.restore(context)
    }
  }
}
