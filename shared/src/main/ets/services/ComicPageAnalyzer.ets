import {
  ComicGlossaryTerm,
  ComicImagePreparationProfile,
  ComicPageDocument,
} from '../model/ComicTranslation'

export class ComicPreviousPageContext {
  pageIndex: number = -1
  sourceText: string = ''
  translatedText: string = ''
  pageSummary: string = ''

  copy(): ComicPreviousPageContext {
    const page: ComicPreviousPageContext = new ComicPreviousPageContext()
    page.pageIndex = this.pageIndex
    page.sourceText = this.sourceText
    page.translatedText = this.translatedText
    page.pageSummary = this.pageSummary
    return page
  }
}

export const MAX_COMIC_TRANSLATION_MEMORY_ENTRIES: number = 64
export const MAX_COMIC_TRANSLATION_MEMORY_SOURCE_CHARS: number = 120
export const MAX_COMIC_TRANSLATION_MEMORY_TARGET_CHARS: number = 240
export const MAX_COMIC_TRANSLATION_MEMORY_OCCURRENCES: number = 32

/** Regenerable exact-match context derived from prior generated page documents. */
export class ComicTranslationMemoryEntry {
  sourceText: string = ''
  translatedText: string = ''
  firstSeenPageIndex: number = -1
  occurrenceCount: number = 0

  copy(): ComicTranslationMemoryEntry {
    const entry: ComicTranslationMemoryEntry = new ComicTranslationMemoryEntry()
    entry.sourceText = this.sourceText
    entry.translatedText = this.translatedText
    entry.firstSeenPageIndex = this.firstSeenPageIndex
    entry.occurrenceCount = this.occurrenceCount
    return entry
  }
}

export class ComicPageAnalysisContext {
  sourceLanguage: string = ''
  targetLanguage: string = ''
  rollingSummary: string = ''
  styleGuide: string = ''
  glossaryRevision: number = 0
  styleGuideRevision: number = 0
  contextRevision: number = 0
  glossary: ComicGlossaryTerm[] = []
  translationMemory: ComicTranslationMemoryEntry[] = []
  previousPages: ComicPreviousPageContext[] = []

  copy(): ComicPageAnalysisContext {
    const context: ComicPageAnalysisContext = new ComicPageAnalysisContext()
    context.sourceLanguage = this.sourceLanguage
    context.targetLanguage = this.targetLanguage
    context.rollingSummary = this.rollingSummary
    context.styleGuide = this.styleGuide
    context.glossaryRevision = this.glossaryRevision
    context.styleGuideRevision = this.styleGuideRevision
    context.contextRevision = this.contextRevision
    for (let index: number = 0; index < this.glossary.length; index++) {
      context.glossary.push(this.glossary[index].copy())
    }
    for (let index: number = 0; index < this.translationMemory.length; index++) {
      context.translationMemory.push(this.translationMemory[index].copy())
    }
    for (let index: number = 0; index < this.previousPages.length; index++) {
      context.previousPages.push(this.previousPages[index].copy())
    }
    return context
  }
}

export class ComicPageAnalysisRequest {
  projectId: string = ''
  pageIndex: number = -1
  imageFilePath: string = ''
  imageHash: string = ''
  sourceWidth: number = 0
  sourceHeight: number = 0
  requestedAnalysisRevision: number = 1
  requestedTranslationRevision: number = 1
  imagePreparationProfile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
  context: ComicPageAnalysisContext = new ComicPageAnalysisContext()
}

export class ComicPageAnalyzerCapabilities {
  transcript: boolean = false
  readingOrder: boolean = false
  geometry: boolean = false
  speakerAssociation: boolean = false
  mask: boolean = false
  contextAwareTranslation: boolean = false
}

export class ComicPageAnalysisResult {
  providerId: string = ''
  modelId: string = ''
  analysisPromptVersion: string = ''
  document: ComicPageDocument = new ComicPageDocument()
}

export interface ComicPageAnalyzer {
  providerId(): string

  modelId(): string

  analysisPromptVersion(): string

  contextFingerprint(request: ComicPageAnalysisRequest): string

  capabilities(): ComicPageAnalyzerCapabilities

  analyze(request: ComicPageAnalysisRequest): Promise<ComicPageAnalysisResult>
}
