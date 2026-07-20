import { util } from '@kit.ArkTS'
import { ComicPageDocument, ComicTranslationState } from '../model/ComicTranslation'
import { CacheStat } from './CacheStat'
import { ComicPageAnalysisRequest, ComicPageAnalyzer } from './ComicPageAnalyzer'
import { ComicPageAnalysisParser } from './ComicPageAnalysisParser'

const DEFAULT_MEMORY_REPOSITORY_LIMIT: number = 64
const MAX_COMIC_IDENTITY_CHARS: number = 160
const MAX_COMIC_PROJECT_ID_CHARS: number = 160
const MAX_COMIC_IMAGE_EDGE: number = 100000
const MAX_COMIC_REPOSITORY_PREVIOUS_PAGES: number = 32

export function boundedComicPreviousPageLimit(limit: number): number {
  if (!Number.isFinite(limit) || limit <= 0) {
    return 0
  }
  return Math.min(MAX_COMIC_REPOSITORY_PREVIOUS_PAGES, Math.floor(limit))
}

export class ComicTranslationRequestIdentity {
  projectId: string = ''
  pageIndex: number = -1
  imageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  providerId: string = ''
  modelId: string = ''
  analysisPromptVersion: string = ''
  sourceLanguage: string = ''
  targetLanguage: string = ''
  analysisRevision: number = 0
  translationRevision: number = 0
  imagePreparationProfileId: string = ''
  glossaryRevision: number = 0
  styleGuideRevision: number = 0
  contextRevision: number = 0
  contextFingerprint: string = ''

  static from(
    request: ComicPageAnalysisRequest,
    analyzer: ComicPageAnalyzer,
  ): ComicTranslationRequestIdentity {
    ComicPageAnalysisParser.validateRequest(request)
    const providerId: string = analyzer.providerId()
    const modelId: string = analyzer.modelId()
    const analysisPromptVersion: string = analyzer.analysisPromptVersion()
    ComicPageAnalysisParser.validateAnalyzerIdentity(
      providerId,
      modelId,
      analysisPromptVersion,
    )
    const identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
    identity.projectId = request.projectId
    identity.pageIndex = request.pageIndex
    identity.imageHash = request.imageHash
    identity.imageWidth = request.sourceWidth
    identity.imageHeight = request.sourceHeight
    identity.providerId = providerId
    identity.modelId = modelId
    identity.analysisPromptVersion = analysisPromptVersion
    identity.sourceLanguage = request.context.sourceLanguage
    identity.targetLanguage = request.context.targetLanguage
    identity.analysisRevision = request.requestedAnalysisRevision
    identity.translationRevision = request.requestedTranslationRevision
    identity.imagePreparationProfileId = request.imagePreparationProfile.profileId
    identity.glossaryRevision = request.context.glossaryRevision
    identity.styleGuideRevision = request.context.styleGuideRevision
    identity.contextRevision = request.context.contextRevision
    identity.contextFingerprint = analyzer.contextFingerprint(request)
    identity.assertValid()
    return identity
  }

  copy(): ComicTranslationRequestIdentity {
    const identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
    identity.projectId = this.projectId
    identity.pageIndex = this.pageIndex
    identity.imageHash = this.imageHash
    identity.imageWidth = this.imageWidth
    identity.imageHeight = this.imageHeight
    identity.providerId = this.providerId
    identity.modelId = this.modelId
    identity.analysisPromptVersion = this.analysisPromptVersion
    identity.sourceLanguage = this.sourceLanguage
    identity.targetLanguage = this.targetLanguage
    identity.analysisRevision = this.analysisRevision
    identity.translationRevision = this.translationRevision
    identity.imagePreparationProfileId = this.imagePreparationProfileId
    identity.glossaryRevision = this.glossaryRevision
    identity.styleGuideRevision = this.styleGuideRevision
    identity.contextRevision = this.contextRevision
    identity.contextFingerprint = this.contextFingerprint
    return identity
  }

  cacheKey(): string {
    this.assertValid()
    return JSON.stringify([
      this.uncheckedScopeKey(),
      `${this.pageIndex}`,
      this.imageHash,
      `${this.imageWidth}`,
      `${this.imageHeight}`,
      `${this.contextRevision}`,
      this.contextFingerprint,
    ])
  }

  scopeKey(): string {
    this.assertValid()
    return this.uncheckedScopeKey()
  }

  assertValid(): void {
    if (!ComicTranslationRequestIdentity.validIdentifier(this.projectId, MAX_COMIC_PROJECT_ID_CHARS) ||
      !ComicTranslationRequestIdentity.nonNegativeSafeInteger(this.pageIndex) ||
      !/^[a-f0-9]{64}$/.test(this.imageHash) ||
      !ComicTranslationRequestIdentity.positiveImageEdge(this.imageWidth) ||
      !ComicTranslationRequestIdentity.positiveImageEdge(this.imageHeight) ||
      !ComicTranslationRequestIdentity.validIdentifier(this.providerId, MAX_COMIC_IDENTITY_CHARS) ||
      !ComicTranslationRequestIdentity.validIdentifier(this.modelId, MAX_COMIC_IDENTITY_CHARS) ||
      !ComicTranslationRequestIdentity.validIdentifier(
        this.analysisPromptVersion,
        MAX_COMIC_IDENTITY_CHARS,
      ) ||
      !ComicTranslationRequestIdentity.validIdentifier(this.sourceLanguage, MAX_COMIC_IDENTITY_CHARS) ||
      !ComicTranslationRequestIdentity.validIdentifier(this.targetLanguage, MAX_COMIC_IDENTITY_CHARS) ||
      !ComicTranslationRequestIdentity.positiveSafeInteger(this.analysisRevision) ||
      !ComicTranslationRequestIdentity.positiveSafeInteger(this.translationRevision) ||
      !ComicTranslationRequestIdentity.validIdentifier(
        this.imagePreparationProfileId,
        MAX_COMIC_IDENTITY_CHARS,
      ) ||
      !ComicTranslationRequestIdentity.nonNegativeSafeInteger(this.glossaryRevision) ||
      !ComicTranslationRequestIdentity.nonNegativeSafeInteger(this.styleGuideRevision) ||
      !ComicTranslationRequestIdentity.nonNegativeSafeInteger(this.contextRevision) ||
      !/^[a-f0-9]{64}$/.test(this.contextFingerprint)) {
      throw new Error('Comic translation request identity is invalid')
    }
  }

  private uncheckedScopeKey(): string {
    return JSON.stringify([
      this.projectId,
      this.providerId,
      this.modelId,
      this.analysisPromptVersion,
      this.sourceLanguage,
      this.targetLanguage,
      `${this.analysisRevision}`,
      `${this.translationRevision}`,
      this.imagePreparationProfileId,
      `${this.glossaryRevision}`,
      `${this.styleGuideRevision}`,
    ])
  }

  matchesDocument(document: ComicPageDocument): boolean {
    return document.projectId === this.projectId &&
      document.pageIndex === this.pageIndex &&
      document.imageHash === this.imageHash &&
      document.imageWidth === this.imageWidth &&
      document.imageHeight === this.imageHeight &&
      this.matchesDocumentRevisions(document) &&
      document.imagePreparationProfile.profileId === this.imagePreparationProfileId
  }

  matchesDocumentRevisions(document: ComicPageDocument): boolean {
    if (document.analysisRevision !== this.analysisRevision) {
      return false
    }
    if (document.translationRevision === this.translationRevision) {
      return true
    }
    return document.translationRevision === 0 && document.hasText === false &&
      document.blocks.length === 0 &&
      document.translationState === ComicTranslationState.MISSING
  }

  private static validIdentifier(value: string, maxChars: number): boolean {
    return value.length > 0 && value.length <= maxChars && value === value.trim()
  }

  private static nonNegativeSafeInteger(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  private static positiveSafeInteger(value: number): boolean {
    return value > 0 && ComicTranslationRequestIdentity.nonNegativeSafeInteger(value)
  }

  private static positiveImageEdge(value: number): boolean {
    return value > 0 && value <= MAX_COMIC_IMAGE_EDGE &&
      ComicTranslationRequestIdentity.nonNegativeSafeInteger(value)
  }

}

export interface ComicTranslationRepository {
  load(identity: ComicTranslationRequestIdentity): Promise<ComicPageDocument | null>

  save(identity: ComicTranslationRequestIdentity, document: ComicPageDocument): Promise<void>

  loadPrevious(
    identity: ComicTranslationRequestIdentity,
    limit: number,
  ): Promise<ComicPageDocument[]>

  stat(): Promise<CacheStat>

  clear(): Promise<void>
}

class ComicTranslationMemoryRecord {
  identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
  document: ComicPageDocument = new ComicPageDocument()
  sequence: number = 0
}

/** Process-local generated-document cache. It deliberately carries no backup or sync semantics. */
export class InMemoryComicTranslationRepository implements ComicTranslationRepository {
  private records: Map<string, ComicTranslationMemoryRecord> = new Map()
  private sequence: number = 0
  private readonly maxRecords: number

  constructor(maxRecords: number = DEFAULT_MEMORY_REPOSITORY_LIMIT) {
    this.maxRecords = Math.max(1, maxRecords)
  }

  async load(identity: ComicTranslationRequestIdentity): Promise<ComicPageDocument | null> {
    identity.assertValid()
    const record: ComicTranslationMemoryRecord | undefined = this.records.get(identity.cacheKey())
    return record === undefined ? null : record.document.copy()
  }

  async save(
    identity: ComicTranslationRequestIdentity,
    document: ComicPageDocument,
  ): Promise<void> {
    identity.assertValid()
    if (!identity.matchesDocument(document)) {
      throw new Error('Comic translation repository document identity mismatch')
    }
    const record: ComicTranslationMemoryRecord = new ComicTranslationMemoryRecord()
    record.identity = identity.copy()
    record.document = document.copy()
    this.sequence++
    record.sequence = this.sequence
    this.records.set(identity.cacheKey(), record)
    this.trim()
  }

  async loadPrevious(
    identity: ComicTranslationRequestIdentity,
    limit: number,
  ): Promise<ComicPageDocument[]> {
    identity.assertValid()
    const boundedLimit: number = boundedComicPreviousPageLimit(limit)
    if (boundedLimit === 0 || identity.pageIndex <= 0) {
      return []
    }
    const latestByPage: Map<number, ComicTranslationMemoryRecord> = new Map()
    this.records.forEach((record: ComicTranslationMemoryRecord) => {
      if (record.identity.scopeKey() !== identity.scopeKey() ||
        record.identity.pageIndex < 0 || record.identity.pageIndex >= identity.pageIndex) {
        return
      }
      const existing: ComicTranslationMemoryRecord | undefined =
        latestByPage.get(record.identity.pageIndex)
      if (existing === undefined || existing.sequence < record.sequence) {
        latestByPage.set(record.identity.pageIndex, record)
      }
    })
    const pageIndexes: number[] = []
    latestByPage.forEach((_record: ComicTranslationMemoryRecord, pageIndex: number) => {
      pageIndexes.push(pageIndex)
    })
    pageIndexes.sort((left: number, right: number): number => right - left)
    const selected: ComicPageDocument[] = []
    const count: number = Math.min(boundedLimit, pageIndexes.length)
    for (let index: number = count - 1; index >= 0; index--) {
      const record: ComicTranslationMemoryRecord | undefined = latestByPage.get(pageIndexes[index])
      if (record !== undefined) {
        selected.push(record.document.copy())
      }
    }
    return selected
  }

  async stat(): Promise<CacheStat> {
    const result: CacheStat = new CacheStat()
    this.records.forEach((record: ComicTranslationMemoryRecord): void => {
      result.count++
      result.bytes += new util.TextEncoder().encodeInto(JSON.stringify(record.document)).length
    })
    return result
  }

  async clear(): Promise<void> {
    this.records.clear()
  }

  private trim(): void {
    while (this.records.size > this.maxRecords) {
      let oldestKey: string = ''
      let oldestSequence: number = Number.MAX_SAFE_INTEGER
      this.records.forEach((record: ComicTranslationMemoryRecord, key: string) => {
        if (record.sequence < oldestSequence) {
          oldestSequence = record.sequence
          oldestKey = key
        }
      })
      if (oldestKey.length === 0) {
        return
      }
      this.records.delete(oldestKey)
    }
  }
}
