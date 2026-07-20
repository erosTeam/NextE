export const COMIC_TRANSLATION_SCHEMA_VERSION: number = 1

export enum ComicAnalysisState {
  MISSING = 'missing',
  READY = 'ready',
  STALE = 'stale',
  FAILED = 'failed',
}

export enum ComicTranslationState {
  MISSING = 'missing',
  PROVISIONAL = 'provisional',
  READY = 'ready',
  STALE = 'stale',
  FAILED = 'failed',
  REVIEW_REQUIRED = 'review_required',
}

export enum ComicRenderState {
  UNAVAILABLE = 'unavailable',
  READY = 'ready',
  STALE = 'stale',
  FAILED = 'failed',
}

export enum ComicTextKind {
  DIALOGUE = 'dialogue',
  NARRATION = 'narration',
  SFX = 'sfx',
  ANNOTATION = 'annotation',
  OTHER = 'other',
}

export enum ComicSourceOrigin {
  VISION = 'vision',
  OCR = 'ocr',
  MANUAL = 'manual',
}

export enum ComicTranslationOrigin {
  NONE = 'none',
  VISION = 'vision',
  TEXT = 'text',
  MANUAL = 'manual',
}

export enum ComicQualitySeverity {
  INFO = 'info',
  WARNING = 'warning',
  ERROR = 'error',
}

export enum ComicGlossaryTermStatus {
  PROVISIONAL = 'provisional',
  LOCKED = 'locked',
}

export enum ComicGlossaryTermProvenance {
  MODEL = 'model',
  USER = 'user',
  IMPORTED = 'imported',
}

export class ComicImagePreparationProfile {
  profileId: string = ''
  mimeType: string = ''
  preparedWidth: number = 0
  preparedHeight: number = 0
  tileCount: number = 1

  copy(): ComicImagePreparationProfile {
    const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
    profile.profileId = this.profileId
    profile.mimeType = this.mimeType
    profile.preparedWidth = this.preparedWidth
    profile.preparedHeight = this.preparedHeight
    profile.tileCount = this.tileCount
    return profile
  }
}

export class ComicPoint {
  x: number = 0
  y: number = 0

  constructor(x: number = 0, y: number = 0) {
    this.x = x
    this.y = y
  }

  copy(): ComicPoint {
    return new ComicPoint(this.x, this.y)
  }
}

export class ComicQualitySignal {
  code: string = ''
  severity: ComicQualitySeverity = ComicQualitySeverity.INFO
  blockId: string = ''
  message: string = ''

  copy(): ComicQualitySignal {
    const signal: ComicQualitySignal = new ComicQualitySignal()
    signal.code = this.code
    signal.severity = this.severity
    signal.blockId = this.blockId
    signal.message = this.message
    return signal
  }
}

export class ComicTextBlock {
  blockId: string = ''
  readingOrder: number = 0
  kind: ComicTextKind = ComicTextKind.OTHER
  sourceText: string = ''
  normalizedSourceText: string = ''
  translatedText: string = ''
  polygon: ComicPoint[] = []
  speakerId: string = ''
  styleHint: string = ''
  sourceOrigin: ComicSourceOrigin = ComicSourceOrigin.VISION
  translationOrigin: ComicTranslationOrigin = ComicTranslationOrigin.NONE
  providerConfidence: number | null = null
  sourceRevision: number = 0
  translationRevision: number = 0
  manualSource: boolean = false
  manualTranslation: boolean = false

  copy(): ComicTextBlock {
    const block: ComicTextBlock = new ComicTextBlock()
    block.blockId = this.blockId
    block.readingOrder = this.readingOrder
    block.kind = this.kind
    block.sourceText = this.sourceText
    block.normalizedSourceText = this.normalizedSourceText
    block.translatedText = this.translatedText
    for (let index: number = 0; index < this.polygon.length; index++) {
      block.polygon.push(this.polygon[index].copy())
    }
    block.speakerId = this.speakerId
    block.styleHint = this.styleHint
    block.sourceOrigin = this.sourceOrigin
    block.translationOrigin = this.translationOrigin
    block.providerConfidence = this.providerConfidence
    block.sourceRevision = this.sourceRevision
    block.translationRevision = this.translationRevision
    block.manualSource = this.manualSource
    block.manualTranslation = this.manualTranslation
    return block
  }
}

export class ComicGlossaryTerm {
  sourceTerm: string = ''
  aliases: string[] = []
  targetTerm: string = ''
  status: ComicGlossaryTermStatus = ComicGlossaryTermStatus.PROVISIONAL
  provenance: ComicGlossaryTermProvenance = ComicGlossaryTermProvenance.MODEL
  firstSeenPageIndex: number = -1
  updatedRevision: number = 0
  notes: string = ''

  copy(): ComicGlossaryTerm {
    const term: ComicGlossaryTerm = new ComicGlossaryTerm()
    term.sourceTerm = this.sourceTerm
    for (let index: number = 0; index < this.aliases.length; index++) {
      term.aliases.push(this.aliases[index])
    }
    term.targetTerm = this.targetTerm
    term.status = this.status
    term.provenance = this.provenance
    term.firstSeenPageIndex = this.firstSeenPageIndex
    term.updatedRevision = this.updatedRevision
    term.notes = this.notes
    return term
  }
}

export class ComicPageDocument {
  schemaVersion: number = COMIC_TRANSLATION_SCHEMA_VERSION
  projectId: string = ''
  pageIndex: number = -1
  imageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  imagePreparationProfile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
  analysisRevision: number = 0
  translationRevision: number = 0
  renderRevision: number = 0
  analysisState: ComicAnalysisState = ComicAnalysisState.MISSING
  translationState: ComicTranslationState = ComicTranslationState.MISSING
  renderState: ComicRenderState = ComicRenderState.UNAVAILABLE
  hasText: boolean = false
  pageSummary: string = ''
  blocks: ComicTextBlock[] = []
  qualitySignals: ComicQualitySignal[] = []
  lastErrorCode: string = ''
  lastErrorMessage: string = ''

  copy(): ComicPageDocument {
    const document: ComicPageDocument = new ComicPageDocument()
    document.schemaVersion = this.schemaVersion
    document.projectId = this.projectId
    document.pageIndex = this.pageIndex
    document.imageHash = this.imageHash
    document.imageWidth = this.imageWidth
    document.imageHeight = this.imageHeight
    document.imagePreparationProfile = this.imagePreparationProfile.copy()
    document.analysisRevision = this.analysisRevision
    document.translationRevision = this.translationRevision
    document.renderRevision = this.renderRevision
    document.analysisState = this.analysisState
    document.translationState = this.translationState
    document.renderState = this.renderState
    document.hasText = this.hasText
    document.pageSummary = this.pageSummary
    for (let index: number = 0; index < this.blocks.length; index++) {
      document.blocks.push(this.blocks[index].copy())
    }
    for (let index: number = 0; index < this.qualitySignals.length; index++) {
      document.qualitySignals.push(this.qualitySignals[index].copy())
    }
    document.lastErrorCode = this.lastErrorCode
    document.lastErrorMessage = this.lastErrorMessage
    return document
  }
}

export class ComicTranslationProject {
  schemaVersion: number = COMIC_TRANSLATION_SCHEMA_VERSION
  projectId: string = ''
  galleryIdentity: string = ''
  sourceFingerprint: string = ''
  sourceLanguage: string = ''
  targetLanguage: string = ''
  glossaryRevision: number = 0
  styleGuideRevision: number = 0
  contextRevision: number = 0
  documentRevision: number = 0
  rollingSummary: string = ''
  styleGuide: string = ''
  glossary: ComicGlossaryTerm[] = []
  pages: ComicPageDocument[] = []

  copy(): ComicTranslationProject {
    const project: ComicTranslationProject = new ComicTranslationProject()
    project.schemaVersion = this.schemaVersion
    project.projectId = this.projectId
    project.galleryIdentity = this.galleryIdentity
    project.sourceFingerprint = this.sourceFingerprint
    project.sourceLanguage = this.sourceLanguage
    project.targetLanguage = this.targetLanguage
    project.glossaryRevision = this.glossaryRevision
    project.styleGuideRevision = this.styleGuideRevision
    project.contextRevision = this.contextRevision
    project.documentRevision = this.documentRevision
    project.rollingSummary = this.rollingSummary
    project.styleGuide = this.styleGuide
    for (let index: number = 0; index < this.glossary.length; index++) {
      project.glossary.push(this.glossary[index].copy())
    }
    for (let index: number = 0; index < this.pages.length; index++) {
      project.pages.push(this.pages[index].copy())
    }
    return project
  }
}
