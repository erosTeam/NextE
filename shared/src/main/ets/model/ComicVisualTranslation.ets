import { ComicPageDocument } from './ComicTranslation'

export const COMIC_VISUAL_TRANSLATION_SCHEMA_VERSION: number = 1

export enum ComicVisualTranslationRoute {
  STAGED = 'staged',
  WHOLE_PAGE_RENDER = 'whole_page_render',
}

export class ComicBackendTemplate {
  backendId: string = ''
  profileId: string = ''
  protocolRevision: number = 0
  contentHash: string = ''
  mimeType: string = ''
  payload: Uint8Array = new Uint8Array(0)

  copy(): ComicBackendTemplate {
    const value: ComicBackendTemplate = new ComicBackendTemplate()
    value.backendId = this.backendId
    value.profileId = this.profileId
    value.protocolRevision = this.protocolRevision
    value.contentHash = this.contentHash
    value.mimeType = this.mimeType
    value.payload = new Uint8Array(this.payload)
    return value
  }
}

export class ComicBlockTranslation {
  blockId: string = ''
  translatedText: string = ''

  copy(): ComicBlockTranslation {
    const value: ComicBlockTranslation = new ComicBlockTranslation()
    value.blockId = this.blockId
    value.translatedText = this.translatedText
    return value
  }
}

export class ComicTranslationBatch {
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  targetLanguage: string = ''
  sourceProfileId: string = ''
  sourceRevision: number = 0
  modelId: string = ''
  promptVersion: string = ''
  contextFingerprint: string = ''
  glossaryRevision: number = 0
  translationRevision: number = 0
  blocks: ComicBlockTranslation[] = []

  copy(): ComicTranslationBatch {
    const value: ComicTranslationBatch = new ComicTranslationBatch()
    value.projectId = this.projectId
    value.pageIndex = this.pageIndex
    value.sourceImageHash = this.sourceImageHash
    value.targetLanguage = this.targetLanguage
    value.sourceProfileId = this.sourceProfileId
    value.sourceRevision = this.sourceRevision
    value.modelId = this.modelId
    value.promptVersion = this.promptVersion
    value.contextFingerprint = this.contextFingerprint
    value.glossaryRevision = this.glossaryRevision
    value.translationRevision = this.translationRevision
    for (let index: number = 0; index < this.blocks.length; index++) {
      value.blocks.push(this.blocks[index].copy())
    }
    return value
  }
}

export class ComicRenderProfile {
  profileId: string = ''
  sourceTreatmentProfileId: string = ''
  layoutProfileId: string = ''
  targetMimeType: string = 'image/png'
  revision: number = 0

  copy(): ComicRenderProfile {
    const value: ComicRenderProfile = new ComicRenderProfile()
    value.profileId = this.profileId
    value.sourceTreatmentProfileId = this.sourceTreatmentProfileId
    value.layoutProfileId = this.layoutProfileId
    value.targetMimeType = this.targetMimeType
    value.revision = this.revision
    return value
  }
}

export class ComicRenderedPageIdentity {
  schemaVersion: number = COMIC_VISUAL_TRANSLATION_SCHEMA_VERSION
  route: ComicVisualTranslationRoute = ComicVisualTranslationRoute.STAGED
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  sourceWidth: number = 0
  sourceHeight: number = 0
  targetLanguage: string = ''
  regionBackendId: string = ''
  regionProfileId: string = ''
  regionRevision: number = 0
  documentRevision: number = 0
  translationSourceProfileId: string = ''
  translationSourceRevision: number = 0
  translationModelId: string = ''
  translationPromptVersion: string = ''
  translationContextFingerprint: string = ''
  glossaryRevision: number = 0
  translationRevision: number = 0
  sourceTreatmentProfileId: string = ''
  layoutProfileId: string = ''
  renderBackendId: string = ''
  renderProfileId: string = ''
  renderTargetMimeType: string = 'image/png'
  renderRevision: number = 0

  copy(): ComicRenderedPageIdentity {
    const value: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
    value.schemaVersion = this.schemaVersion
    value.route = this.route
    value.projectId = this.projectId
    value.pageIndex = this.pageIndex
    value.sourceImageHash = this.sourceImageHash
    value.sourceWidth = this.sourceWidth
    value.sourceHeight = this.sourceHeight
    value.targetLanguage = this.targetLanguage
    value.regionBackendId = this.regionBackendId
    value.regionProfileId = this.regionProfileId
    value.regionRevision = this.regionRevision
    value.documentRevision = this.documentRevision
    value.translationSourceProfileId = this.translationSourceProfileId
    value.translationSourceRevision = this.translationSourceRevision
    value.translationModelId = this.translationModelId
    value.translationPromptVersion = this.translationPromptVersion
    value.translationContextFingerprint = this.translationContextFingerprint
    value.glossaryRevision = this.glossaryRevision
    value.translationRevision = this.translationRevision
    value.sourceTreatmentProfileId = this.sourceTreatmentProfileId
    value.layoutProfileId = this.layoutProfileId
    value.renderBackendId = this.renderBackendId
    value.renderProfileId = this.renderProfileId
    value.renderTargetMimeType = this.renderTargetMimeType
    value.renderRevision = this.renderRevision
    return value
  }

  cacheKey(): string {
    this.assertValid()
    return JSON.stringify([
      `${this.schemaVersion}`,
      this.route,
      this.projectId,
      `${this.pageIndex}`,
      this.sourceImageHash,
      `${this.sourceWidth}`,
      `${this.sourceHeight}`,
      this.targetLanguage,
      this.regionBackendId,
      this.regionProfileId,
      `${this.regionRevision}`,
      `${this.documentRevision}`,
      this.translationSourceProfileId,
      `${this.translationSourceRevision}`,
      this.translationModelId,
      this.translationPromptVersion,
      this.translationContextFingerprint,
      `${this.glossaryRevision}`,
      `${this.translationRevision}`,
      this.sourceTreatmentProfileId,
      this.layoutProfileId,
      this.renderBackendId,
      this.renderProfileId,
      this.renderTargetMimeType,
      `${this.renderRevision}`,
    ])
  }

  assertValid(): void {
    if (this.schemaVersion !== COMIC_VISUAL_TRANSLATION_SCHEMA_VERSION ||
      (this.route !== ComicVisualTranslationRoute.STAGED &&
        this.route !== ComicVisualTranslationRoute.WHOLE_PAGE_RENDER) ||
      !ComicRenderedPageIdentity.identifier(this.projectId) ||
      !ComicRenderedPageIdentity.nonNegativeInteger(this.pageIndex) ||
      !ComicRenderedPageIdentity.hash(this.sourceImageHash) ||
      !ComicRenderedPageIdentity.imageEdge(this.sourceWidth) ||
      !ComicRenderedPageIdentity.imageEdge(this.sourceHeight) ||
      !ComicRenderedPageIdentity.identifier(this.targetLanguage) ||
      !ComicRenderedPageIdentity.identifier(this.translationSourceProfileId) ||
      !ComicRenderedPageIdentity.positiveInteger(this.translationSourceRevision) ||
      !ComicRenderedPageIdentity.identifier(this.translationModelId) ||
      !ComicRenderedPageIdentity.identifier(this.translationPromptVersion) ||
      !ComicRenderedPageIdentity.hash(this.translationContextFingerprint) ||
      !ComicRenderedPageIdentity.nonNegativeInteger(this.glossaryRevision) ||
      !ComicRenderedPageIdentity.positiveInteger(this.translationRevision) ||
      !ComicRenderedPageIdentity.identifier(this.sourceTreatmentProfileId) ||
      !ComicRenderedPageIdentity.identifier(this.layoutProfileId) ||
      !ComicRenderedPageIdentity.identifier(this.renderBackendId) ||
      !ComicRenderedPageIdentity.identifier(this.renderProfileId) ||
      !ComicRenderedPageIdentity.imageMime(this.renderTargetMimeType) ||
      !ComicRenderedPageIdentity.positiveInteger(this.renderRevision)) {
      throw new Error('Comic rendered page identity is invalid')
    }
    if (this.route === ComicVisualTranslationRoute.STAGED) {
      if (!ComicRenderedPageIdentity.identifier(this.regionBackendId) ||
        !ComicRenderedPageIdentity.identifier(this.regionProfileId) ||
        !ComicRenderedPageIdentity.positiveInteger(this.regionRevision) ||
        !ComicRenderedPageIdentity.positiveInteger(this.documentRevision)) {
        throw new Error('Comic staged render identity is invalid')
      }
      return
    }
    if (this.regionBackendId.length > 0 || this.regionProfileId.length > 0 ||
      this.regionRevision !== 0 || this.documentRevision !== 0) {
      throw new Error('Comic whole-page render identity carries staged fields')
    }
  }

  private static identifier(value: string): boolean {
    return value.length > 0 && value.length <= 160 && value === value.trim()
  }

  private static hash(value: string): boolean {
    return /^[a-f0-9]{64}$/.test(value)
  }

  private static nonNegativeInteger(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  private static positiveInteger(value: number): boolean {
    return value > 0 && ComicRenderedPageIdentity.nonNegativeInteger(value)
  }

  private static imageEdge(value: number): boolean {
    return value > 0 && value <= 100000 && ComicRenderedPageIdentity.nonNegativeInteger(value)
  }

  private static imageMime(value: string): boolean {
    return value === 'image/png' || value === 'image/jpeg' || value === 'image/webp'
  }
}

export class ComicRenderedPage {
  identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  artifactHash: string = ''
  mimeType: string = ''
  width: number = 0
  height: number = 0
  byteLength: number = 0
  localFilePath: string = ''
  createdAt: number = 0
  lastAccessAt: number = 0

  copy(): ComicRenderedPage {
    const value: ComicRenderedPage = new ComicRenderedPage()
    value.identity = this.identity.copy()
    value.artifactHash = this.artifactHash
    value.mimeType = this.mimeType
    value.width = this.width
    value.height = this.height
    value.byteLength = this.byteLength
    value.localFilePath = this.localFilePath
    value.createdAt = this.createdAt
    value.lastAccessAt = this.lastAccessAt
    return value
  }
}

export class ComicRegionAnalysisResult {
  backendId: string = ''
  profileId: string = ''
  regionRevision: number = 0
  document: ComicPageDocument = new ComicPageDocument()
  adapterTemplate: ComicBackendTemplate = new ComicBackendTemplate()

  copy(): ComicRegionAnalysisResult {
    const value: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
    value.backendId = this.backendId
    value.profileId = this.profileId
    value.regionRevision = this.regionRevision
    value.document = this.document.copy()
    value.adapterTemplate = this.adapterTemplate.copy()
    return value
  }
}
