import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  COMIC_TRANSLATION_SCHEMA_VERSION,
  ComicAnalysisState,
  ComicImagePreparationProfile,
  ComicPageDocument,
  ComicPoint,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicRenderState,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTextKind,
  ComicTranslationOrigin,
  ComicTranslationState,
} from '../model/ComicTranslation'
import { LocalDataStore } from '../storage/LocalDataStore'
import {
  ComicTranslationRepository,
  ComicTranslationRequestIdentity,
  InMemoryComicTranslationRepository,
} from './ComicTranslationRepository'

const MAX_PERSISTED_DOCUMENT_CHARS: number = 4 * 1024 * 1024
const MAX_PERSISTED_DOCUMENTS: number = 128
const MAX_PREVIOUS_SCAN_ROWS: number = 128
const MAX_TEXT_BLOCKS: number = 512
const MAX_POLYGON_POINTS: number = 64
const MAX_QUALITY_SIGNALS: number = 512
const MAX_TEXT_CHARS: number = 4096
const MAX_SUMMARY_CHARS: number = 4096
const MAX_MESSAGE_CHARS: number = 1024
const MAX_IDENTIFIER_CHARS: number = 512
const MAX_IMAGE_EDGE: number = 100000
const MAX_IMAGE_TILES: number = 4096

const SQL_SELECT_EXACT: string =
  'SELECT payload FROM comic_translation_document_cache WHERE cache_key = ? LIMIT 1'
const SQL_TOUCH_EXACT: string =
  'UPDATE comic_translation_document_cache SET accessed_at = ? WHERE cache_key = ?'
const SQL_SELECT_PREVIOUS: string =
  'SELECT cache_key, payload FROM comic_translation_document_cache ' +
  'WHERE scope_key = ? AND page_index < ? ' +
  'ORDER BY page_index DESC, accessed_at DESC LIMIT ?'
const SQL_UPSERT_DOCUMENT: string =
  'INSERT OR REPLACE INTO comic_translation_document_cache ' +
  '(cache_key, scope_key, project_id, page_index, payload, cached_at, accessed_at) ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?)'
const SQL_PRUNE_DOCUMENTS: string =
  'DELETE FROM comic_translation_document_cache WHERE cache_key NOT IN (' +
  'SELECT cache_key FROM comic_translation_document_cache ORDER BY accessed_at DESC LIMIT ?' +
  ')'
const SQL_DELETE_EXACT: string =
  'DELETE FROM comic_translation_document_cache WHERE cache_key = ?'
const SQL_DELETE_PROJECT: string =
  'DELETE FROM comic_translation_document_cache WHERE project_id = ?'
const SQL_DELETE_ALL: string = 'DELETE FROM comic_translation_document_cache'

/** Strict codec for the provider-neutral generated document stored in the local cache. */
export class ComicTranslationDocumentCodec {
  static encode(document: ComicPageDocument): string {
    const payload: string = JSON.stringify(document.copy())
    if (payload.length === 0 || payload.length > MAX_PERSISTED_DOCUMENT_CHARS) {
      throw new Error('Comic translation cache payload size is invalid')
    }
    return payload
  }

  static decode(payload: string): ComicPageDocument {
    if (payload.length === 0 || payload.length > MAX_PERSISTED_DOCUMENT_CHARS) {
      throw new Error('Comic translation cache payload size is invalid')
    }
    const raw: ComicPageDocument = JSON.parse(payload) as ComicPageDocument
    const document: ComicPageDocument = new ComicPageDocument()
    document.schemaVersion = ComicTranslationDocumentCodec.integer(raw.schemaVersion)
    if (document.schemaVersion !== COMIC_TRANSLATION_SCHEMA_VERSION) {
      throw new Error('Comic translation cache schema is unsupported')
    }
    document.projectId = ComicTranslationDocumentCodec.requiredString(
      raw.projectId,
      MAX_IDENTIFIER_CHARS,
    )
    document.pageIndex = ComicTranslationDocumentCodec.integer(raw.pageIndex, -1)
    if (document.pageIndex < 0) {
      throw new Error('Comic translation cache page is invalid')
    }
    document.imageHash = ComicTranslationDocumentCodec.requiredString(raw.imageHash, 64)
    if (!/^[a-f0-9]{64}$/.test(document.imageHash)) {
      throw new Error('Comic translation cache image identity is invalid')
    }
    document.imageWidth = ComicTranslationDocumentCodec.positiveEdge(raw.imageWidth)
    document.imageHeight = ComicTranslationDocumentCodec.positiveEdge(raw.imageHeight)
    document.imagePreparationProfile = ComicTranslationDocumentCodec.profile(
      raw.imagePreparationProfile,
    )
    document.analysisRevision = ComicTranslationDocumentCodec.nonNegativeInteger(
      raw.analysisRevision,
    )
    document.translationRevision = ComicTranslationDocumentCodec.nonNegativeInteger(
      raw.translationRevision,
    )
    document.renderRevision = ComicTranslationDocumentCodec.nonNegativeInteger(raw.renderRevision)
    document.analysisState = ComicTranslationDocumentCodec.analysisState(raw.analysisState)
    document.translationState = ComicTranslationDocumentCodec.translationState(raw.translationState)
    document.renderState = ComicTranslationDocumentCodec.renderState(raw.renderState)
    if (typeof raw.hasText !== 'boolean') {
      throw new Error('Comic translation cache text state is invalid')
    }
    document.hasText = raw.hasText
    document.pageSummary = ComicTranslationDocumentCodec.string(raw.pageSummary, MAX_SUMMARY_CHARS)
    document.lastErrorCode = ComicTranslationDocumentCodec.string(
      raw.lastErrorCode,
      MAX_IDENTIFIER_CHARS,
    )
    document.lastErrorMessage = ComicTranslationDocumentCodec.string(
      raw.lastErrorMessage,
      MAX_MESSAGE_CHARS,
    )

    if (!Array.isArray(raw.blocks) || raw.blocks.length > MAX_TEXT_BLOCKS ||
      (document.hasText && raw.blocks.length === 0) || (!document.hasText && raw.blocks.length > 0)) {
      throw new Error('Comic translation cache blocks are invalid')
    }
    const blockIds: Set<string> = new Set<string>()
    const readingOrders: Set<number> = new Set<number>()
    for (let index: number = 0; index < raw.blocks.length; index++) {
      const block: ComicTextBlock = ComicTranslationDocumentCodec.block(
        raw.blocks[index],
        document.imageWidth,
        document.imageHeight,
      )
      if (blockIds.has(block.blockId) || readingOrders.has(block.readingOrder)) {
        throw new Error('Comic translation cache block identity is invalid')
      }
      blockIds.add(block.blockId)
      readingOrders.add(block.readingOrder)
      document.blocks.push(block)
    }
    document.blocks.sort(
      (left: ComicTextBlock, right: ComicTextBlock): number => left.readingOrder - right.readingOrder,
    )

    if (!Array.isArray(raw.qualitySignals) || raw.qualitySignals.length > MAX_QUALITY_SIGNALS) {
      throw new Error('Comic translation cache quality signals are invalid')
    }
    for (let index: number = 0; index < raw.qualitySignals.length; index++) {
      const signal: ComicQualitySignal = ComicTranslationDocumentCodec.signal(raw.qualitySignals[index])
      if (signal.blockId.length > 0 && !blockIds.has(signal.blockId)) {
        throw new Error('Comic translation cache quality signal target is invalid')
      }
      document.qualitySignals.push(signal)
    }
    return document
  }

  private static profile(raw: ComicImagePreparationProfile): ComicImagePreparationProfile {
    if (raw === undefined || raw === null) {
      throw new Error('Comic translation cache image profile is missing')
    }
    const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
    profile.profileId = ComicTranslationDocumentCodec.requiredString(
      raw.profileId,
      MAX_IDENTIFIER_CHARS,
    )
    profile.mimeType = ComicTranslationDocumentCodec.requiredString(raw.mimeType, 160)
    profile.preparedWidth = ComicTranslationDocumentCodec.positiveEdge(raw.preparedWidth)
    profile.preparedHeight = ComicTranslationDocumentCodec.positiveEdge(raw.preparedHeight)
    profile.tileCount = ComicTranslationDocumentCodec.positiveInteger(raw.tileCount)
    if (profile.tileCount > MAX_IMAGE_TILES) {
      throw new Error('Comic translation cache image tile count is invalid')
    }
    return profile
  }

  private static block(raw: ComicTextBlock, imageWidth: number, imageHeight: number): ComicTextBlock {
    if (raw === undefined || raw === null) {
      throw new Error('Comic translation cache block is missing')
    }
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = ComicTranslationDocumentCodec.requiredString(raw.blockId, MAX_IDENTIFIER_CHARS)
    block.readingOrder = ComicTranslationDocumentCodec.nonNegativeInteger(raw.readingOrder)
    if (block.readingOrder >= MAX_TEXT_BLOCKS) {
      throw new Error('Comic translation cache reading order is invalid')
    }
    block.kind = ComicTranslationDocumentCodec.textKind(raw.kind)
    block.sourceText = ComicTranslationDocumentCodec.requiredString(raw.sourceText, MAX_TEXT_CHARS)
    block.normalizedSourceText = ComicTranslationDocumentCodec.string(
      raw.normalizedSourceText,
      MAX_TEXT_CHARS,
    )
    block.translatedText = ComicTranslationDocumentCodec.string(raw.translatedText, MAX_TEXT_CHARS)
    block.speakerId = ComicTranslationDocumentCodec.string(raw.speakerId, MAX_IDENTIFIER_CHARS)
    block.styleHint = ComicTranslationDocumentCodec.string(raw.styleHint, MAX_MESSAGE_CHARS)
    block.sourceOrigin = ComicTranslationDocumentCodec.sourceOrigin(raw.sourceOrigin)
    block.translationOrigin = ComicTranslationDocumentCodec.translationOrigin(raw.translationOrigin)
    block.providerConfidence = ComicTranslationDocumentCodec.confidence(raw.providerConfidence)
    block.sourceRevision = ComicTranslationDocumentCodec.nonNegativeInteger(raw.sourceRevision)
    block.translationRevision = ComicTranslationDocumentCodec.nonNegativeInteger(
      raw.translationRevision,
    )
    if (typeof raw.manualSource !== 'boolean' || typeof raw.manualTranslation !== 'boolean') {
      throw new Error('Comic translation cache manual state is invalid')
    }
    block.manualSource = raw.manualSource
    block.manualTranslation = raw.manualTranslation
    if (block.translatedText.length === 0 && block.translationOrigin !== ComicTranslationOrigin.NONE) {
      throw new Error('Comic translation cache translation origin is invalid')
    }
    if (block.translatedText.length > 0 && block.translationOrigin === ComicTranslationOrigin.NONE) {
      throw new Error('Comic translation cache translated block origin is missing')
    }
    if (!Array.isArray(raw.polygon) || raw.polygon.length > MAX_POLYGON_POINTS ||
      (raw.polygon.length > 0 && raw.polygon.length < 3)) {
      throw new Error('Comic translation cache polygon is invalid')
    }
    for (let index: number = 0; index < raw.polygon.length; index++) {
      const point: ComicPoint = raw.polygon[index]
      if (point === undefined || point === null || typeof point.x !== 'number' ||
        !Number.isFinite(point.x) || typeof point.y !== 'number' || !Number.isFinite(point.y) ||
        point.x < 0 || point.x > imageWidth || point.y < 0 || point.y > imageHeight) {
        throw new Error('Comic translation cache polygon point is invalid')
      }
      block.polygon.push(new ComicPoint(point.x, point.y))
    }
    return block
  }

  private static signal(raw: ComicQualitySignal): ComicQualitySignal {
    if (raw === undefined || raw === null) {
      throw new Error('Comic translation cache quality signal is missing')
    }
    const signal: ComicQualitySignal = new ComicQualitySignal()
    signal.code = ComicTranslationDocumentCodec.requiredString(raw.code, MAX_IDENTIFIER_CHARS)
    signal.severity = ComicTranslationDocumentCodec.severity(raw.severity)
    signal.blockId = ComicTranslationDocumentCodec.string(raw.blockId, MAX_IDENTIFIER_CHARS)
    signal.message = ComicTranslationDocumentCodec.string(raw.message, MAX_MESSAGE_CHARS)
    return signal
  }

  private static analysisState(value: ComicAnalysisState): ComicAnalysisState {
    if (value === ComicAnalysisState.MISSING || value === ComicAnalysisState.READY ||
      value === ComicAnalysisState.STALE || value === ComicAnalysisState.FAILED) {
      return value
    }
    throw new Error('Comic translation cache analysis state is invalid')
  }

  private static translationState(value: ComicTranslationState): ComicTranslationState {
    if (value === ComicTranslationState.MISSING || value === ComicTranslationState.PROVISIONAL ||
      value === ComicTranslationState.READY || value === ComicTranslationState.STALE ||
      value === ComicTranslationState.FAILED || value === ComicTranslationState.REVIEW_REQUIRED) {
      return value
    }
    throw new Error('Comic translation cache translation state is invalid')
  }

  private static renderState(value: ComicRenderState): ComicRenderState {
    if (value === ComicRenderState.UNAVAILABLE || value === ComicRenderState.READY ||
      value === ComicRenderState.STALE || value === ComicRenderState.FAILED) {
      return value
    }
    throw new Error('Comic translation cache render state is invalid')
  }

  private static textKind(value: ComicTextKind): ComicTextKind {
    if (value === ComicTextKind.DIALOGUE || value === ComicTextKind.NARRATION ||
      value === ComicTextKind.SFX || value === ComicTextKind.ANNOTATION || value === ComicTextKind.OTHER) {
      return value
    }
    throw new Error('Comic translation cache text kind is invalid')
  }

  private static sourceOrigin(value: ComicSourceOrigin): ComicSourceOrigin {
    if (value === ComicSourceOrigin.VISION || value === ComicSourceOrigin.OCR ||
      value === ComicSourceOrigin.MANUAL) {
      return value
    }
    throw new Error('Comic translation cache source origin is invalid')
  }

  private static translationOrigin(value: ComicTranslationOrigin): ComicTranslationOrigin {
    if (value === ComicTranslationOrigin.NONE || value === ComicTranslationOrigin.VISION ||
      value === ComicTranslationOrigin.TEXT || value === ComicTranslationOrigin.MANUAL) {
      return value
    }
    throw new Error('Comic translation cache translation origin is invalid')
  }

  private static severity(value: ComicQualitySeverity): ComicQualitySeverity {
    if (value === ComicQualitySeverity.INFO || value === ComicQualitySeverity.WARNING ||
      value === ComicQualitySeverity.ERROR) {
      return value
    }
    throw new Error('Comic translation cache quality severity is invalid')
  }

  private static confidence(value: number | null): number | null {
    if (value === null || value === undefined) {
      return null
    }
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
      throw new Error('Comic translation cache confidence is invalid')
    }
    return value
  }

  private static string(value: string, maxLength: number): string {
    if (typeof value !== 'string' || value.length > maxLength) {
      throw new Error('Comic translation cache text is invalid')
    }
    return value
  }

  private static requiredString(value: string, maxLength: number): string {
    const normalized: string = ComicTranslationDocumentCodec.string(value, maxLength)
    if (normalized.trim().length === 0) {
      throw new Error('Comic translation cache required text is missing')
    }
    return normalized
  }

  private static integer(value: number, fallback: number = 0): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || Math.floor(value) !== value ||
      value < -Number.MAX_SAFE_INTEGER || value > Number.MAX_SAFE_INTEGER) {
      return fallback
    }
    return value
  }

  private static nonNegativeInteger(value: number): number {
    const normalized: number = ComicTranslationDocumentCodec.integer(value, -1)
    if (normalized < 0) {
      throw new Error('Comic translation cache revision is invalid')
    }
    return normalized
  }

  private static positiveInteger(value: number): number {
    const normalized: number = ComicTranslationDocumentCodec.integer(value)
    if (normalized <= 0) {
      throw new Error('Comic translation cache positive integer is invalid')
    }
    return normalized
  }

  private static positiveEdge(value: number): number {
    const normalized: number = ComicTranslationDocumentCodec.positiveInteger(value)
    if (normalized > MAX_IMAGE_EDGE) {
      throw new Error('Comic translation cache image edge is invalid')
    }
    return normalized
  }
}

/** RDB implementation. Callers may wrap it when cache I/O must remain best-effort. */
export class RdbComicTranslationRepository implements ComicTranslationRepository {
  private readonly context: common.UIAbilityContext
  private readonly maxRecords: number

  constructor(context: common.UIAbilityContext, maxRecords: number = MAX_PERSISTED_DOCUMENTS) {
    this.context = context
    this.maxRecords = Math.max(1, Math.min(MAX_PERSISTED_DOCUMENTS, maxRecords))
  }

  async load(identity: ComicTranslationRequestIdentity): Promise<ComicPageDocument | null> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(this.context)
    const resultSet: relationalStore.ResultSet = await store.querySql(
      SQL_SELECT_EXACT,
      [identity.cacheKey()],
    )
    let payload: string = ''
    try {
      if (!resultSet.goToFirstRow()) {
        return null
      }
      payload = resultSet.getString(resultSet.getColumnIndex('payload'))
    } finally {
      resultSet.close()
    }
    let document: ComicPageDocument
    try {
      document = ComicTranslationDocumentCodec.decode(payload)
      if (!identity.matchesDocument(document)) {
        throw new Error('Comic translation cache document identity mismatch')
      }
    } catch (_error) {
      try {
        await store.executeSql(SQL_DELETE_EXACT, [identity.cacheKey()])
      } catch (_cleanupError) {
      }
      DiagnosticLogger.warn('comic-translation-cache', 'discard_invalid_exact', `bytes=${payload.length}`)
      return null
    }
    try {
      await store.executeSql(SQL_TOUCH_EXACT, [Date.now(), identity.cacheKey()])
    } catch (_error) {
      DiagnosticLogger.warn('comic-translation-cache', 'touch_failed', 'kept=1')
    }
    return document
  }

  async save(
    identity: ComicTranslationRequestIdentity,
    document: ComicPageDocument,
  ): Promise<void> {
    if (!identity.matchesDocument(document)) {
      throw new Error('Comic translation repository document identity mismatch')
    }
    const payload: string = ComicTranslationDocumentCodec.encode(document)
    const now: number = Date.now()
    const store: relationalStore.RdbStore = await LocalDataStore.open(this.context)
    store.beginTransaction()
    try {
      const args: relationalStore.ValueType[] = [
        identity.cacheKey(),
        identity.scopeKey(),
        identity.projectId,
        identity.pageIndex,
        payload,
        now,
        now,
      ]
      await store.executeSql(SQL_UPSERT_DOCUMENT, args)
      await store.executeSql(SQL_PRUNE_DOCUMENTS, [this.maxRecords])
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  async loadPrevious(
    identity: ComicTranslationRequestIdentity,
    limit: number,
  ): Promise<ComicPageDocument[]> {
    const boundedLimit: number = Math.max(0, Math.min(2, limit))
    if (boundedLimit === 0 || identity.pageIndex <= 0) {
      return []
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(this.context)
    const resultSet: relationalStore.ResultSet = await store.querySql(
      SQL_SELECT_PREVIOUS,
      [identity.scopeKey(), identity.pageIndex, MAX_PREVIOUS_SCAN_ROWS],
    )
    const latestByPage: Map<number, ComicPageDocument> = new Map<number, ComicPageDocument>()
    const corruptKeys: string[] = []
    try {
      while (resultSet.goToNextRow()) {
        const cacheKey: string = resultSet.getString(resultSet.getColumnIndex('cache_key'))
        const payload: string = resultSet.getString(resultSet.getColumnIndex('payload'))
        try {
          const document: ComicPageDocument = ComicTranslationDocumentCodec.decode(payload)
          if (document.projectId !== identity.projectId || document.pageIndex < 0 ||
            document.pageIndex >= identity.pageIndex ||
            !identity.matchesDocumentRevisions(document) ||
            document.imagePreparationProfile.profileId !== identity.imagePreparationProfileId) {
            throw new Error('Comic translation previous cache identity mismatch')
          }
          if (!latestByPage.has(document.pageIndex)) {
            latestByPage.set(document.pageIndex, document)
          }
        } catch (_error) {
          corruptKeys.push(cacheKey)
        }
      }
    } finally {
      resultSet.close()
    }
    for (let index: number = 0; index < corruptKeys.length; index++) {
      try {
        await store.executeSql(SQL_DELETE_EXACT, [corruptKeys[index]])
      } catch (_error) {
      }
    }
    if (corruptKeys.length > 0) {
      DiagnosticLogger.warn(
        'comic-translation-cache',
        'discard_invalid_previous',
        `rows=${corruptKeys.length}`,
      )
    }
    const pageIndexes: number[] = []
    latestByPage.forEach((_document: ComicPageDocument, pageIndex: number): void => {
      pageIndexes.push(pageIndex)
    })
    pageIndexes.sort((left: number, right: number): number => right - left)
    const selected: ComicPageDocument[] = []
    const count: number = Math.min(boundedLimit, pageIndexes.length)
    for (let index: number = count - 1; index >= 0; index--) {
      const document: ComicPageDocument | undefined = latestByPage.get(pageIndexes[index])
      if (document !== undefined) {
        selected.push(document.copy())
      }
    }
    return selected
  }

  async clear(): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(this.context)
    await store.executeSql(SQL_DELETE_ALL)
  }

  async removeProject(projectId: string): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(this.context)
    await store.executeSql(SQL_DELETE_PROJECT, [projectId])
  }
}

/** Memory-fronted cache whose durable layer is deliberately best-effort and regenerable. */
export class PersistentComicTranslationRepository implements ComicTranslationRepository {
  private readonly memory: InMemoryComicTranslationRepository
  private readonly durable: RdbComicTranslationRepository

  constructor(
    context: common.UIAbilityContext,
    memoryRecords: number = 64,
    durableRecords: number = MAX_PERSISTED_DOCUMENTS,
  ) {
    this.memory = new InMemoryComicTranslationRepository(memoryRecords)
    this.durable = new RdbComicTranslationRepository(context, durableRecords)
  }

  async load(identity: ComicTranslationRequestIdentity): Promise<ComicPageDocument | null> {
    const hot: ComicPageDocument | null = await this.memory.load(identity)
    if (hot !== null) {
      return hot
    }
    try {
      const persisted: ComicPageDocument | null = await this.durable.load(identity)
      if (persisted !== null) {
        await this.memory.save(identity, persisted)
      }
      return persisted
    } catch (_error) {
      DiagnosticLogger.warn('comic-translation-cache', 'load_failed', 'fallback=miss')
      return null
    }
  }

  async save(
    identity: ComicTranslationRequestIdentity,
    document: ComicPageDocument,
  ): Promise<void> {
    await this.memory.save(identity, document)
    try {
      await this.durable.save(identity, document)
      DiagnosticLogger.info(
        'comic-translation-cache',
        'save_ready',
        `page=${identity.pageIndex} blocks=${document.blocks.length}`,
      )
    } catch (_error) {
      DiagnosticLogger.warn('comic-translation-cache', 'save_failed', 'fallback=memory')
    }
  }

  async loadPrevious(
    identity: ComicTranslationRequestIdentity,
    limit: number,
  ): Promise<ComicPageDocument[]> {
    const boundedLimit: number = Math.max(0, Math.min(2, limit))
    if (boundedLimit === 0) {
      return []
    }
    const durableDocuments: ComicPageDocument[] = []
    try {
      const persisted: ComicPageDocument[] = await this.durable.loadPrevious(identity, boundedLimit)
      for (let index: number = 0; index < persisted.length; index++) {
        durableDocuments.push(persisted[index])
      }
    } catch (_error) {
      DiagnosticLogger.warn('comic-translation-cache', 'previous_load_failed', 'fallback=memory')
    }
    const hotDocuments: ComicPageDocument[] = await this.memory.loadPrevious(identity, boundedLimit)
    const latestByPage: Map<number, ComicPageDocument> = new Map<number, ComicPageDocument>()
    for (let index: number = 0; index < durableDocuments.length; index++) {
      latestByPage.set(durableDocuments[index].pageIndex, durableDocuments[index])
    }
    for (let index: number = 0; index < hotDocuments.length; index++) {
      latestByPage.set(hotDocuments[index].pageIndex, hotDocuments[index])
    }
    const indexes: number[] = []
    latestByPage.forEach((_document: ComicPageDocument, pageIndex: number): void => {
      indexes.push(pageIndex)
    })
    indexes.sort((left: number, right: number): number => right - left)
    const selected: ComicPageDocument[] = []
    const count: number = Math.min(boundedLimit, indexes.length)
    for (let index: number = count - 1; index >= 0; index--) {
      const document: ComicPageDocument | undefined = latestByPage.get(indexes[index])
      if (document !== undefined) {
        selected.push(document.copy())
      }
    }
    return selected
  }

  async clear(): Promise<void> {
    await this.memory.clear()
    await this.durable.clear()
  }

  async removeProject(projectId: string): Promise<void> {
    await this.durable.removeProject(projectId)
  }
}
