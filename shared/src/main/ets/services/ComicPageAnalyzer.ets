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

export class ComicPageAnalysisContext {
  sourceLanguage: string = ''
  targetLanguage: string = ''
  rollingSummary: string = ''
  styleGuide: string = ''
  glossaryRevision: number = 0
  styleGuideRevision: number = 0
  contextRevision: number = 0
  glossary: ComicGlossaryTerm[] = []
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

  capabilities(): ComicPageAnalyzerCapabilities

  analyze(request: ComicPageAnalysisRequest): Promise<ComicPageAnalysisResult>
}
