import { common } from '@kit.AbilityKit'
import { CustomProfilesSettings } from '../settings/CustomProfilesSettings'
import { GalleryReadProgressSettings } from '../settings/GalleryReadProgressSettings'
import { LocalBlockSettings } from '../settings/LocalBlockSettings'
import { LocalFavSettings } from '../settings/LocalFavSettings'
import { SearchHistorySettings } from '../settings/SearchHistorySettings'
import { ViewedHistorySettings } from '../settings/ViewedHistorySettings'
import {
  SYNC_APP_ID,
  SYNC_MAGIC,
  SYNC_MIN_SUPPORTED_SCHEMA_VERSION,
  SYNC_SCHEMA_VERSION,
  SyncDatasetSelection,
  SyncDatasets,
  SyncEnvelopeV1,
} from './SyncTypes'
import { SyncLocalDataAdapter } from './SyncLocalDataAdapter'

export class SyncService {
  static async exportRaw(
    context: common.UIAbilityContext,
    deviceId: string = '',
    selection: SyncDatasetSelection = new SyncDatasetSelection(),
  ): Promise<string> {
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
    if (!Array.isArray(data.customProfiles)) {
      data.customProfiles = []
    }
    if (!Array.isArray(data.customProfileSelection)) {
      data.customProfileSelection = []
    }
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
      await GalleryReadProgressSettings.restore(context)
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
    if (selection.customProfiles) {
      await CustomProfilesSettings.restore(context)
    }
  }
}
