import { ComicPageDocument } from '../model/ComicTranslation'
import {
  ComicBackendTemplate,
  ComicRegionAnalysisResult,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicTranslationBatch,
} from '../model/ComicVisualTranslation'
import { ComicPageAnalysisContext } from './ComicPageAnalyzer'

export class ComicVisualPageSource {
  projectId: string = ''
  pageIndex: number = -1
  imageFilePath: string = ''
  imageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0

  copy(): ComicVisualPageSource {
    const value: ComicVisualPageSource = new ComicVisualPageSource()
    value.projectId = this.projectId
    value.pageIndex = this.pageIndex
    value.imageFilePath = this.imageFilePath
    value.imageHash = this.imageHash
    value.imageWidth = this.imageWidth
    value.imageHeight = this.imageHeight
    return value
  }
}

export class ComicRegionAnalysisRequest {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  requestedRegionRevision: number = 1
  requestedDocumentRevision: number = 1
}

export class ComicRegionRenderRequest {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  regionRevision: number = 0
  document: ComicPageDocument = new ComicPageDocument()
  translations: ComicTranslationBatch = new ComicTranslationBatch()
  adapterTemplate: ComicBackendTemplate = new ComicBackendTemplate()
  renderProfile: ComicRenderProfile = new ComicRenderProfile()
  identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
}

export class ComicTextTranslationRequest {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  document: ComicPageDocument = new ComicPageDocument()
  context: ComicPageAnalysisContext = new ComicPageAnalysisContext()
  requestedTranslationRevision: number = 1
}

export class ComicTextTranslationResult {
  batch: ComicTranslationBatch = new ComicTranslationBatch()
}

export class ComicWholePageRenderRequest {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  context: ComicPageAnalysisContext = new ComicPageAnalysisContext()
  identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
}

export interface ComicRegionRenderBackend {
  backendId(): string

  profileId(): string

  protocolRevision(): number

  analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult>

  render(request: ComicRegionRenderRequest): Promise<ComicRenderedPage>
}

export interface ComicTextTranslator {
  sourceProfileId(): string

  sourceRevision(): number

  modelId(): string

  promptVersion(): string

  contextFingerprint(request: ComicTextTranslationRequest): string

  translate(request: ComicTextTranslationRequest): Promise<ComicTextTranslationResult>
}

export interface ComicWholePageRenderBackend {
  sourceProfileId(): string

  sourceRevision(): number

  modelId(): string

  promptVersion(): string

  contextFingerprint(request: ComicWholePageRenderRequest): string

  render(request: ComicWholePageRenderRequest): Promise<ComicRenderedPage>
}
