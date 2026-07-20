import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { ComicPageDocument, ComicTranslationState } from '../model/ComicTranslation'
import { ComicPageAnalysisRequest, ComicPageAnalyzer } from './ComicPageAnalyzer'

const DEFAULT_MEMORY_REPOSITORY_LIMIT: number = 64

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
    const identity: ComicTranslationRequestIdentity = new ComicTranslationRequestIdentity()
    identity.projectId = request.projectId
    identity.pageIndex = request.pageIndex
    identity.imageHash = request.imageHash
    identity.imageWidth = request.sourceWidth
    identity.imageHeight = request.sourceHeight
    identity.providerId = analyzer.providerId()
    identity.modelId = analyzer.modelId()
    identity.analysisPromptVersion = analyzer.analysisPromptVersion()
    identity.sourceLanguage = request.context.sourceLanguage
    identity.targetLanguage = request.context.targetLanguage
    identity.analysisRevision = request.requestedAnalysisRevision
    identity.translationRevision = request.requestedTranslationRevision
    identity.imagePreparationProfileId = request.imagePreparationProfile.profileId
    identity.glossaryRevision = request.context.glossaryRevision
    identity.styleGuideRevision = request.context.styleGuideRevision
    identity.contextRevision = request.context.contextRevision
    identity.contextFingerprint = ComicTranslationRequestIdentity.contextFingerprint(request)
    identity.validate()
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
    return JSON.stringify([
      this.scopeKey(),
      `${this.pageIndex}`,
      this.imageHash,
      `${this.imageWidth}`,
      `${this.imageHeight}`,
      `${this.contextRevision}`,
      this.contextFingerprint,
    ])
  }

  scopeKey(): string {
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

  private validate(): void {
    if (this.projectId.trim().length === 0 || this.projectId.length > 512 || this.pageIndex < 0 ||
      !/^[a-f0-9]{64}$/.test(this.imageHash) || this.imageWidth <= 0 || this.imageHeight <= 0 ||
      this.providerId.trim().length === 0 || this.modelId.trim().length === 0 ||
      this.analysisPromptVersion.trim().length === 0 || this.sourceLanguage.trim().length === 0 ||
      this.targetLanguage.trim().length === 0 || this.analysisRevision <= 0 ||
      this.translationRevision <= 0 || this.imagePreparationProfileId.trim().length === 0 ||
      this.glossaryRevision < 0 || this.styleGuideRevision < 0 || this.contextRevision < 0) {
      throw new Error('Comic translation request identity is invalid')
    }
  }

  private static contextFingerprint(request: ComicPageAnalysisRequest): string {
    const values: string[] = [
      request.context.rollingSummary,
      request.context.styleGuide,
    ]
    for (let index: number = 0; index < request.context.glossary.length; index++) {
      const term = request.context.glossary[index]
      values.push(JSON.stringify([
        term.sourceTerm,
        JSON.stringify(term.aliases),
        term.targetTerm,
        term.status,
        term.provenance,
        `${term.firstSeenPageIndex}`,
        `${term.updatedRevision}`,
        term.notes,
      ]))
    }
    for (let index: number = 0; index < request.context.previousPages.length; index++) {
      const page = request.context.previousPages[index]
      values.push(JSON.stringify([
        `${page.pageIndex}`,
        page.sourceText,
        page.translatedText,
        page.pageSummary,
      ]))
    }
    const encoded: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(values))
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: encoded })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}

export interface ComicTranslationRepository {
  load(identity: ComicTranslationRequestIdentity): Promise<ComicPageDocument | null>

  save(identity: ComicTranslationRequestIdentity, document: ComicPageDocument): Promise<void>

  loadPrevious(
    identity: ComicTranslationRequestIdentity,
    limit: number,
  ): Promise<ComicPageDocument[]>

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
    const record: ComicTranslationMemoryRecord | undefined = this.records.get(identity.cacheKey())
    return record === undefined ? null : record.document.copy()
  }

  async save(
    identity: ComicTranslationRequestIdentity,
    document: ComicPageDocument,
  ): Promise<void> {
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
    const boundedLimit: number = Math.max(0, Math.min(2, limit))
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
