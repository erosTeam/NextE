import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { http } from '@kit.NetworkKit'
import { BackupChecksum } from '../backup/BackupChecksum'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  SYNC_APP_ID,
  SYNC_FILE_NAME,
  SYNC_MAGIC,
  SYNC_MIN_SUPPORTED_SCHEMA_VERSION,
  SYNC_SCHEMA_VERSION,
  SYNC_WEBDAV_MANIFEST_FILE,
  SYNC_WEBDAV_ROOT_DIR,
  SyncDatasetSelection,
  SyncEnvelopeV1,
  SyncManifestDataset,
  SyncManifestShard,
  SyncManifestV1,
} from './SyncTypes'
import { SyncLocalDataAdapter } from './SyncLocalDataAdapter'
import { SyncService } from './SyncService'

const CONNECT_TIMEOUT_MS: number = 10000
const READ_TIMEOUT_MS: number = 20000
const SHARD_COUNT: number = 64

const DATASET_READ_PROGRESS: string = 'read-progress'
const DATASET_VIEWED_HISTORY: string = 'viewed-history'
const DATASET_LOCAL_FAVORITES: string = 'local-favorites'
const DATASET_SEARCH_HISTORY: string = 'search-history'
const DATASET_LOCAL_BLOCK: string = 'local-block'
const DATASET_IMAGE_BLOCK: string = 'image-block'
const DATASET_CUSTOM_PROFILES: string = 'custom-profiles'
const DATASET_IDS: string[] = [
  DATASET_READ_PROGRESS,
  DATASET_VIEWED_HISTORY,
  DATASET_LOCAL_FAVORITES,
  DATASET_SEARCH_HISTORY,
  DATASET_LOCAL_BLOCK,
  DATASET_IMAGE_BLOCK,
  DATASET_CUSTOM_PROFILES,
]

class WebDavBuiltShard {
  id: string = ''
  path: string = ''
  raw: string = ''
  sha256: string = ''
  recordCount: number = 0
  updatedAt: number = 0
}

export class WebDavSyncConfig {
  directoryUrl: string = ''
  username: string = ''
  password: string = ''
  selection: SyncDatasetSelection = new SyncDatasetSelection()
}

export class WebDavSyncService {
  static async syncNow(
    context: common.UIAbilityContext,
    config: WebDavSyncConfig,
    deviceId: string = '',
  ): Promise<void> {
    const rootUrl: string = WebDavSyncService.syncRootUrl(config.directoryUrl)
    await WebDavSyncService.ensureCollections(rootUrl, config)

    const manifest: SyncManifestV1 =
      WebDavSyncService.parseManifest(await WebDavSyncService.readRemoteOptional(rootUrl + SYNC_WEBDAV_MANIFEST_FILE, config))
    const legacyRaw: string =
      await WebDavSyncService.readRemoteOptional(WebDavSyncService.legacyFileUrl(config.directoryUrl), config)

    for (let i: number = 0; i < DATASET_IDS.length; i++) {
      const datasetId: string = DATASET_IDS[i]
      if (!WebDavSyncService.datasetEnabled(config.selection, datasetId)) {
        continue
      }
      DiagnosticLogger.info('sync', 'webdav_dataset_start', `dataset=${datasetId}`)
      const one: SyncDatasetSelection = WebDavSyncService.selectionForDataset(datasetId)
      let remote: SyncEnvelopeV1 = await WebDavSyncService.readDatasetEnvelope(rootUrl, manifest, datasetId, config)
      if (WebDavSyncService.datasetRecordCount(remote, datasetId) === 0 && legacyRaw.length > 0) {
        remote = WebDavSyncService.selectDataset(SyncService.parseRaw(legacyRaw), datasetId)
      }
      const merged: SyncEnvelopeV1 = await SyncService.mergeRemoteEnvelope(context, remote, deviceId, one)
      const shards: WebDavBuiltShard[] = await WebDavSyncService.buildShards(merged, datasetId)
      await WebDavSyncService.writeChangedShards(rootUrl, config, manifest, datasetId, shards)
      WebDavSyncService.replaceManifestDataset(manifest, datasetId, shards)
      DiagnosticLogger.info('sync', 'webdav_dataset_done', `dataset=${datasetId},shards=${shards.length}`)
    }

    manifest.generatedAt = new Date().toISOString()
    await WebDavSyncService.writeRemote(rootUrl + SYNC_WEBDAV_MANIFEST_FILE, config, JSON.stringify(manifest))
  }

  static async readRemote(url: string, config: WebDavSyncConfig): Promise<string> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: WebDavSyncService.headers(config),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      if (code === 404) {
        return ''
      }
      if (code < 200 || code >= 300) {
        throw new Error(`WebDAV GET failed: HTTP ${code}`)
      }
      return typeof resp.result === 'string' ? resp.result as string : ''
    } finally {
      req.destroy()
    }
  }

  static async writeRemote(url: string, config: WebDavSyncConfig, raw: string): Promise<void> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = WebDavSyncService.headers(config)
      header['Content-Type'] = 'application/json; charset=utf-8'
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.PUT,
        header: header,
        extraData: raw,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      if (code < 200 || code >= 300) {
        throw new Error(`WebDAV PUT failed: HTTP ${code}`)
      }
      DiagnosticLogger.info('sync', 'webdav_sync_uploaded', `url=${url} bytes=${raw.length}`)
    } finally {
      req.destroy()
    }
  }

  private static async readRemoteOptional(url: string, config: WebDavSyncConfig): Promise<string> {
    return WebDavSyncService.readRemote(url, config)
  }

  private static async ensureCollections(rootUrl: string, config: WebDavSyncConfig): Promise<void> {
    await WebDavSyncService.makeCollection(rootUrl, config)
    await WebDavSyncService.makeCollection(rootUrl + 'datasets/', config)
    for (let i: number = 0; i < DATASET_IDS.length; i++) {
      if (!WebDavSyncService.datasetEnabled(config.selection, DATASET_IDS[i])) {
        continue
      }
      await WebDavSyncService.makeCollection(rootUrl + 'datasets/' + DATASET_IDS[i] + '/', config)
    }
  }

  private static async makeCollection(url: string, config: WebDavSyncConfig): Promise<void> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: 'MKCOL' as http.RequestMethod,
        header: WebDavSyncService.headers(config),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      if (code === 405 || code === 409 || code === 301 || code === 302) {
        return
      }
      if (code < 200 || code >= 300) {
        throw new Error(`WebDAV MKCOL failed: HTTP ${code}`)
      }
    } finally {
      req.destroy()
    }
  }

  private static async readDatasetEnvelope(
    rootUrl: string,
    manifest: SyncManifestV1,
    datasetId: string,
    config: WebDavSyncConfig,
  ): Promise<SyncEnvelopeV1> {
    let out: SyncEnvelopeV1 = new SyncEnvelopeV1()
    const entry: SyncManifestDataset | null = WebDavSyncService.findManifestDataset(manifest, datasetId)
    if (entry === null) {
      return out
    }
    for (let i: number = 0; i < entry.shards.length; i++) {
      const shard: SyncManifestShard = entry.shards[i]
      const raw: string = await WebDavSyncService.readRemoteOptional(rootUrl + shard.path, config)
      if (raw.length === 0) {
        continue
      }
      out = SyncLocalDataAdapter.mergeEnvelopes(out, SyncService.parseRaw(raw))
    }
    return WebDavSyncService.selectDataset(out, datasetId)
  }

  private static async writeChangedShards(
    rootUrl: string,
    config: WebDavSyncConfig,
    manifest: SyncManifestV1,
    datasetId: string,
    shards: WebDavBuiltShard[],
  ): Promise<void> {
    const prev: SyncManifestDataset | null = WebDavSyncService.findManifestDataset(manifest, datasetId)
    for (let i: number = 0; i < shards.length; i++) {
      const shard: WebDavBuiltShard = shards[i]
      if (prev !== null && WebDavSyncService.previousShardHash(prev, shard.id) === shard.sha256) {
        continue
      }
      await WebDavSyncService.writeRemote(rootUrl + shard.path, config, shard.raw)
    }
  }

  private static async buildShards(envelope: SyncEnvelopeV1, datasetId: string): Promise<WebDavBuiltShard[]> {
    const ids: string[] = WebDavSyncService.collectShardIds(envelope, datasetId)
    const out: WebDavBuiltShard[] = []
    for (let i: number = 0; i < ids.length; i++) {
      const shardId: string = ids[i]
      const shardEnvelope: SyncEnvelopeV1 = WebDavSyncService.filterShard(envelope, datasetId, shardId)
      shardEnvelope.generatedAt = WebDavSyncService.stableGeneratedAt(shardEnvelope, datasetId)
      shardEnvelope.datasetId = datasetId
      shardEnvelope.shardId = shardId
      const raw: string = JSON.stringify(shardEnvelope)
      const shard: WebDavBuiltShard = new WebDavBuiltShard()
      shard.id = shardId
      shard.path = 'datasets/' + datasetId + '/' + shardId + '.json'
      shard.raw = raw
      shard.sha256 = await BackupChecksum.hashText(raw)
      shard.recordCount = WebDavSyncService.datasetRecordCount(shardEnvelope, datasetId)
      shard.updatedAt = WebDavSyncService.datasetUpdatedAt(shardEnvelope, datasetId)
      out.push(shard)
    }
    return out
  }

  private static collectShardIds(envelope: SyncEnvelopeV1, datasetId: string): string[] {
    const out: string[] = []
    if (datasetId === DATASET_READ_PROGRESS) {
      for (let i: number = 0; i < envelope.datasets.readProgress.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.readProgress[i].scopeKey + ':' + envelope.datasets.readProgress[i].gid)
      }
    } else if (datasetId === DATASET_VIEWED_HISTORY) {
      for (let i: number = 0; i < envelope.datasets.viewedHistory.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.viewedHistory[i].scopeKey + ':' + envelope.datasets.viewedHistory[i].gid)
      }
    } else if (datasetId === DATASET_LOCAL_FAVORITES) {
      for (let i: number = 0; i < envelope.datasets.localFavorites.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.localFavorites[i].scopeKey + ':' + envelope.datasets.localFavorites[i].gid)
      }
    } else if (datasetId === DATASET_SEARCH_HISTORY) {
      for (let i: number = 0; i < envelope.datasets.searchHistory.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.searchHistory[i].scopeKey + ':' + envelope.datasets.searchHistory[i].queryText)
      }
    } else if (datasetId === DATASET_LOCAL_BLOCK) {
      for (let i: number = 0; i < envelope.datasets.localBlockSettings.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.localBlockSettings[i].scopeKey)
      }
      for (let i: number = 0; i < envelope.datasets.localBlockRules.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.localBlockRules[i].scopeKey + ':' + envelope.datasets.localBlockRules[i].ruleId)
      }
    } else if (datasetId === DATASET_IMAGE_BLOCK) {
      for (let i: number = 0; i < envelope.datasets.imageBlockSubscriptions.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.imageBlockSubscriptions[i].scopeKey + ':' + envelope.datasets.imageBlockSubscriptions[i].feedId)
      }
      for (let i: number = 0; i < envelope.datasets.imageBlockRules.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.imageBlockRules[i].scopeKey + ':' + envelope.datasets.imageBlockRules[i].ruleId)
      }
    } else if (datasetId === DATASET_CUSTOM_PROFILES) {
      for (let i: number = 0; i < envelope.datasets.customProfiles.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.customProfiles[i].scopeKey + ':' + envelope.datasets.customProfiles[i].uuid)
      }
      for (let i: number = 0; i < envelope.datasets.customProfileSelection.length; i++) {
        WebDavSyncService.addShardId(out, envelope.datasets.customProfileSelection[i].scopeKey)
      }
    }
    return out
  }

  private static addShardId(out: string[], key: string): void {
    const id: string = WebDavSyncService.shardId(key)
    if (out.indexOf(id) < 0) {
      out.push(id)
    }
  }

  private static filterShard(envelope: SyncEnvelopeV1, datasetId: string, shardId: string): SyncEnvelopeV1 {
    const out: SyncEnvelopeV1 = new SyncEnvelopeV1()
    if (datasetId === DATASET_READ_PROGRESS) {
      for (let i: number = 0; i < envelope.datasets.readProgress.length; i++) {
        const r = envelope.datasets.readProgress[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.gid) === shardId) {
          out.datasets.readProgress.push(r)
        }
      }
    } else if (datasetId === DATASET_VIEWED_HISTORY) {
      for (let i: number = 0; i < envelope.datasets.viewedHistory.length; i++) {
        const r = envelope.datasets.viewedHistory[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.gid) === shardId) {
          out.datasets.viewedHistory.push(r)
        }
      }
    } else if (datasetId === DATASET_LOCAL_FAVORITES) {
      for (let i: number = 0; i < envelope.datasets.localFavorites.length; i++) {
        const r = envelope.datasets.localFavorites[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.gid) === shardId) {
          out.datasets.localFavorites.push(r)
        }
      }
    } else if (datasetId === DATASET_SEARCH_HISTORY) {
      for (let i: number = 0; i < envelope.datasets.searchHistory.length; i++) {
        const r = envelope.datasets.searchHistory[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.queryText) === shardId) {
          out.datasets.searchHistory.push(r)
        }
      }
    } else if (datasetId === DATASET_LOCAL_BLOCK) {
      for (let i: number = 0; i < envelope.datasets.localBlockSettings.length; i++) {
        const r = envelope.datasets.localBlockSettings[i]
        if (WebDavSyncService.shardId(r.scopeKey) === shardId) {
          out.datasets.localBlockSettings.push(r)
        }
      }
      for (let i: number = 0; i < envelope.datasets.localBlockRules.length; i++) {
        const r = envelope.datasets.localBlockRules[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.ruleId) === shardId) {
          out.datasets.localBlockRules.push(r)
        }
      }
    } else if (datasetId === DATASET_IMAGE_BLOCK) {
      for (let i: number = 0; i < envelope.datasets.imageBlockSubscriptions.length; i++) {
        const r = envelope.datasets.imageBlockSubscriptions[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.feedId) === shardId) {
          out.datasets.imageBlockSubscriptions.push(r)
        }
      }
      for (let i: number = 0; i < envelope.datasets.imageBlockRules.length; i++) {
        const r = envelope.datasets.imageBlockRules[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.ruleId) === shardId) {
          out.datasets.imageBlockRules.push(r)
        }
      }
    } else if (datasetId === DATASET_CUSTOM_PROFILES) {
      for (let i: number = 0; i < envelope.datasets.customProfiles.length; i++) {
        const r = envelope.datasets.customProfiles[i]
        if (WebDavSyncService.shardId(r.scopeKey + ':' + r.uuid) === shardId) {
          out.datasets.customProfiles.push(r)
        }
      }
      for (let i: number = 0; i < envelope.datasets.customProfileSelection.length; i++) {
        const r = envelope.datasets.customProfileSelection[i]
        if (WebDavSyncService.shardId(r.scopeKey) === shardId) {
          out.datasets.customProfileSelection.push(r)
        }
      }
    }
    return out
  }

  private static selectDataset(envelope: SyncEnvelopeV1, datasetId: string): SyncEnvelopeV1 {
    const out: SyncEnvelopeV1 = new SyncEnvelopeV1()
    if (datasetId === DATASET_READ_PROGRESS) {
      out.datasets.readProgress = envelope.datasets.readProgress
    } else if (datasetId === DATASET_VIEWED_HISTORY) {
      out.datasets.viewedHistory = envelope.datasets.viewedHistory
    } else if (datasetId === DATASET_LOCAL_FAVORITES) {
      out.datasets.localFavorites = envelope.datasets.localFavorites
    } else if (datasetId === DATASET_SEARCH_HISTORY) {
      out.datasets.searchHistory = envelope.datasets.searchHistory
    } else if (datasetId === DATASET_LOCAL_BLOCK) {
      out.datasets.localBlockSettings = envelope.datasets.localBlockSettings
      out.datasets.localBlockRules = envelope.datasets.localBlockRules
    } else if (datasetId === DATASET_IMAGE_BLOCK) {
      out.datasets.imageBlockSubscriptions = envelope.datasets.imageBlockSubscriptions
      out.datasets.imageBlockRules = envelope.datasets.imageBlockRules
    } else if (datasetId === DATASET_CUSTOM_PROFILES) {
      out.datasets.customProfiles = envelope.datasets.customProfiles
      out.datasets.customProfileSelection = envelope.datasets.customProfileSelection
    }
    return out
  }

  private static datasetRecordCount(envelope: SyncEnvelopeV1, datasetId: string): number {
    if (datasetId === DATASET_READ_PROGRESS) {
      return envelope.datasets.readProgress.length
    }
    if (datasetId === DATASET_VIEWED_HISTORY) {
      return envelope.datasets.viewedHistory.length
    }
    if (datasetId === DATASET_LOCAL_FAVORITES) {
      return envelope.datasets.localFavorites.length
    }
    if (datasetId === DATASET_SEARCH_HISTORY) {
      return envelope.datasets.searchHistory.length
    }
    if (datasetId === DATASET_LOCAL_BLOCK) {
      return envelope.datasets.localBlockSettings.length + envelope.datasets.localBlockRules.length
    }
    if (datasetId === DATASET_IMAGE_BLOCK) {
      return envelope.datasets.imageBlockSubscriptions.length + envelope.datasets.imageBlockRules.length
    }
    if (datasetId === DATASET_CUSTOM_PROFILES) {
      return envelope.datasets.customProfiles.length + envelope.datasets.customProfileSelection.length
    }
    return 0
  }

  private static datasetUpdatedAt(envelope: SyncEnvelopeV1, datasetId: string): number {
    let out: number = 0
    if (datasetId === DATASET_READ_PROGRESS) {
      for (let i: number = 0; i < envelope.datasets.readProgress.length; i++) {
        out = Math.max(out, envelope.datasets.readProgress[i].updatedAt, envelope.datasets.readProgress[i].deletedAt)
      }
    } else if (datasetId === DATASET_VIEWED_HISTORY) {
      for (let i: number = 0; i < envelope.datasets.viewedHistory.length; i++) {
        out = Math.max(out, envelope.datasets.viewedHistory[i].viewedAt, envelope.datasets.viewedHistory[i].deletedAt)
      }
    } else if (datasetId === DATASET_LOCAL_FAVORITES) {
      for (let i: number = 0; i < envelope.datasets.localFavorites.length; i++) {
        out = Math.max(out, envelope.datasets.localFavorites[i].lastViewTime, envelope.datasets.localFavorites[i].deletedAt)
      }
    } else if (datasetId === DATASET_SEARCH_HISTORY) {
      for (let i: number = 0; i < envelope.datasets.searchHistory.length; i++) {
        out = Math.max(out, envelope.datasets.searchHistory[i].updatedAt, envelope.datasets.searchHistory[i].deletedAt)
      }
    } else if (datasetId === DATASET_LOCAL_BLOCK) {
      for (let i: number = 0; i < envelope.datasets.localBlockSettings.length; i++) {
        out = Math.max(out, envelope.datasets.localBlockSettings[i].updatedAt, envelope.datasets.localBlockSettings[i].deletedAt)
      }
      for (let i: number = 0; i < envelope.datasets.localBlockRules.length; i++) {
        out = Math.max(out, envelope.datasets.localBlockRules[i].updatedAt, envelope.datasets.localBlockRules[i].deletedAt)
      }
    } else if (datasetId === DATASET_IMAGE_BLOCK) {
      for (let i: number = 0; i < envelope.datasets.imageBlockSubscriptions.length; i++) {
        out = Math.max(out, envelope.datasets.imageBlockSubscriptions[i].updatedAt, envelope.datasets.imageBlockSubscriptions[i].deletedAt)
      }
      for (let i: number = 0; i < envelope.datasets.imageBlockRules.length; i++) {
        out = Math.max(out, envelope.datasets.imageBlockRules[i].updatedAt, envelope.datasets.imageBlockRules[i].deletedAt)
      }
    } else if (datasetId === DATASET_CUSTOM_PROFILES) {
      for (let i: number = 0; i < envelope.datasets.customProfiles.length; i++) {
        out = Math.max(out, envelope.datasets.customProfiles[i].lastEditTime, envelope.datasets.customProfiles[i].deletedAt)
      }
      for (let i: number = 0; i < envelope.datasets.customProfileSelection.length; i++) {
        out = Math.max(out, envelope.datasets.customProfileSelection[i].updatedAt, envelope.datasets.customProfileSelection[i].deletedAt)
      }
    }
    return out
  }

  private static stableGeneratedAt(envelope: SyncEnvelopeV1, datasetId: string): string {
    const updatedAt: number = WebDavSyncService.datasetUpdatedAt(envelope, datasetId)
    if (updatedAt <= 0) {
      return ''
    }
    return new Date(updatedAt).toISOString()
  }

  private static replaceManifestDataset(
    manifest: SyncManifestV1,
    datasetId: string,
    shards: WebDavBuiltShard[],
  ): void {
    const next: SyncManifestDataset = new SyncManifestDataset()
    next.id = datasetId
    for (let i: number = 0; i < shards.length; i++) {
      const s: WebDavBuiltShard = shards[i]
      const m: SyncManifestShard = new SyncManifestShard()
      m.id = s.id
      m.path = s.path
      m.sha256 = s.sha256
      m.recordCount = s.recordCount
      m.updatedAt = s.updatedAt
      next.shards.push(m)
    }
    for (let i: number = 0; i < manifest.datasets.length; i++) {
      if (manifest.datasets[i].id === datasetId) {
        manifest.datasets[i] = next
        return
      }
    }
    manifest.datasets.push(next)
  }

  private static previousShardHash(dataset: SyncManifestDataset, shardId: string): string {
    for (let i: number = 0; i < dataset.shards.length; i++) {
      if (dataset.shards[i].id === shardId) {
        return dataset.shards[i].sha256
      }
    }
    return ''
  }

  private static findManifestDataset(manifest: SyncManifestV1, datasetId: string): SyncManifestDataset | null {
    for (let i: number = 0; i < manifest.datasets.length; i++) {
      if (manifest.datasets[i].id === datasetId) {
        return manifest.datasets[i]
      }
    }
    return null
  }

  private static parseManifest(raw: string): SyncManifestV1 {
    if (raw.trim().length === 0) {
      const empty: SyncManifestV1 = new SyncManifestV1()
      empty.generatedAt = new Date().toISOString()
      return empty
    }
    const parsed: SyncManifestV1 = JSON.parse(raw) as SyncManifestV1
    if (parsed.magic !== SYNC_MAGIC || parsed.appId !== SYNC_APP_ID) {
      throw new Error('Invalid NextE sync manifest')
    }
    if (parsed.schemaVersion !== SYNC_SCHEMA_VERSION ||
      parsed.minSupportedSchemaVersion > SYNC_SCHEMA_VERSION) {
      throw new Error('Unsupported NextE sync manifest schema')
    }
    if (!Array.isArray(parsed.datasets)) {
      parsed.datasets = []
    }
    for (let i: number = 0; i < parsed.datasets.length; i++) {
      if (!Array.isArray(parsed.datasets[i].shards)) {
        parsed.datasets[i].shards = []
      }
    }
    return parsed
  }

  private static selectionForDataset(datasetId: string): SyncDatasetSelection {
    const out: SyncDatasetSelection = new SyncDatasetSelection()
    out.readProgress = datasetId === DATASET_READ_PROGRESS
    out.viewedHistory = datasetId === DATASET_VIEWED_HISTORY
    out.localFavorites = datasetId === DATASET_LOCAL_FAVORITES
    out.searchHistory = datasetId === DATASET_SEARCH_HISTORY
    out.localBlock = datasetId === DATASET_LOCAL_BLOCK
    out.imageBlock = datasetId === DATASET_IMAGE_BLOCK
    out.customProfiles = datasetId === DATASET_CUSTOM_PROFILES
    return out
  }

  private static datasetEnabled(selection: SyncDatasetSelection, datasetId: string): boolean {
    if (datasetId === DATASET_READ_PROGRESS) {
      return selection.readProgress
    }
    if (datasetId === DATASET_VIEWED_HISTORY) {
      return selection.viewedHistory
    }
    if (datasetId === DATASET_LOCAL_FAVORITES) {
      return selection.localFavorites
    }
    if (datasetId === DATASET_SEARCH_HISTORY) {
      return selection.searchHistory
    }
    if (datasetId === DATASET_LOCAL_BLOCK) {
      return selection.localBlock
    }
    if (datasetId === DATASET_IMAGE_BLOCK) {
      return selection.imageBlock
    }
    if (datasetId === DATASET_CUSTOM_PROFILES) {
      return selection.customProfiles
    }
    return false
  }

  private static syncRootUrl(directoryUrl: string): string {
    const base: string = WebDavSyncService.baseDirectoryUrl(directoryUrl)
    return base + SYNC_WEBDAV_ROOT_DIR + '/'
  }

  private static legacyFileUrl(directoryUrl: string): string {
    return WebDavSyncService.baseDirectoryUrl(directoryUrl) + SYNC_FILE_NAME
  }

  private static baseDirectoryUrl(directoryUrl: string): string {
    const trimmed: string = directoryUrl.trim()
    if (trimmed.endsWith('/')) {
      return trimmed
    }
    return trimmed + '/'
  }

  private static shardId(key: string): string {
    let hash: number = 2166136261
    for (let i: number = 0; i < key.length; i++) {
      hash ^= key.charCodeAt(i)
      hash = Math.imul(hash, 16777619) >>> 0
    }
    return (hash % SHARD_COUNT).toString(16).padStart(2, '0')
  }

  private static headers(config: WebDavSyncConfig): Record<string, string> {
    const header: Record<string, string> = { 'Accept': 'application/json, text/plain, */*' }
    if (config.username.length > 0 || config.password.length > 0) {
      const bytes: Uint8Array = new util.TextEncoder().encodeInto(
        config.username + ':' + config.password,
      )
      header['Authorization'] = 'Basic ' + new util.Base64Helper().encodeToStringSync(bytes)
    }
    return header
  }
}
