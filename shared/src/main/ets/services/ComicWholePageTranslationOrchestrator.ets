import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import {
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicVisualTranslationRoute,
} from '../model/ComicVisualTranslation'
import { ComicPageAnalysisContext } from './ComicPageAnalyzer'
import {
  ComicRenderedPageRepository,
  ComicRenderedPageRepositoryContract,
} from './ComicRenderedPageRepository'
import {
  ComicVisualPageSource,
  ComicWholePageRenderBackend,
  ComicWholePageRenderRequest,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import { ComicVisualTranslationRunResult } from './ComicVisualTranslationOrchestrator'

export class ComicWholePageTranslationRequest {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  context: ComicPageAnalysisContext = new ComicPageAnalysisContext()
  renderProfile: ComicRenderProfile = new ComicRenderProfile()
  requestedTranslationRevision: number = 1
}

/** Whole-page providers join the product only at the validated rendered-artifact boundary. */
export class ComicWholePageTranslationOrchestrator {
  private readonly backend: ComicWholePageRenderBackend
  private readonly renderedRepository: ComicRenderedPageRepository
  private inFlight: Map<string, Promise<ComicVisualTranslationRunResult>> =
    new Map<string, Promise<ComicVisualTranslationRunResult>>()
  private cacheWritesEnabled: boolean = true

  constructor(
    backend: ComicWholePageRenderBackend,
    renderedRepository: ComicRenderedPageRepository,
  ) {
    this.backend = backend
    this.renderedRepository = renderedRepository
  }

  async run(
    sourceRequest: ComicWholePageTranslationRequest,
    forceRefresh: boolean = false,
  ): Promise<ComicVisualTranslationRunResult> {
    ComicWholePageTranslationOrchestrator.validateRequest(sourceRequest)
    const request: ComicWholePageTranslationRequest =
      ComicWholePageTranslationOrchestrator.copyRequest(sourceRequest)
    const renderRequest: ComicWholePageRenderRequest = new ComicWholePageRenderRequest()
    renderRequest.source = request.source.copy()
    renderRequest.context = request.context.copy()
    const contextFingerprint: string = this.backend.contextFingerprint(renderRequest)
    renderRequest.identity = this.identity(request, contextFingerprint)
    ComicVisualTranslationContract.validateWholePageRenderRequest(renderRequest)
    const lookupKey: string = ComicWholePageTranslationOrchestrator.digest(
      renderRequest.identity.cacheKey(),
    )
    if (!forceRefresh) {
      const cached: ComicRenderedPage | null = await this.renderedRepository.load(lookupKey)
      if (cached !== null && this.matchesPipeline(cached, renderRequest.identity)) {
        return ComicWholePageTranslationOrchestrator.result(cached, true)
      }
    }
    const existing: Promise<ComicVisualTranslationRunResult> | undefined =
      this.inFlight.get(lookupKey)
    if (existing !== undefined) {
      const shared: ComicVisualTranslationRunResult = await existing
      return ComicWholePageTranslationOrchestrator.result(
        shared.renderedPage,
        shared.cacheHit,
      )
    }
    const task: Promise<ComicVisualTranslationRunResult> = this.produce(
      renderRequest,
      lookupKey,
    )
    this.inFlight.set(lookupKey, task)
    try {
      const completed: ComicVisualTranslationRunResult = await task
      return ComicWholePageTranslationOrchestrator.result(
        completed.renderedPage,
        completed.cacheHit,
      )
    } finally {
      if (this.inFlight.get(lookupKey) === task) {
        this.inFlight.delete(lookupKey)
      }
    }
  }

  latestSuccessful(
    source: ComicVisualPageSource,
    targetLanguage: string,
  ): Promise<ComicRenderedPage | null> {
    return this.renderedRepository.loadLatest(source, targetLanguage)
  }

  invalidateCacheWrites(): void {
    this.cacheWritesEnabled = false
  }

  private async produce(
    request: ComicWholePageRenderRequest,
    lookupKey: string,
  ): Promise<ComicVisualTranslationRunResult> {
    const renderedPage: ComicRenderedPage = await this.backend.render(request)
    ComicVisualTranslationContract.validateRenderedPage(request.identity, renderedPage)
    if (this.cacheWritesEnabled) {
      await this.renderedRepository.save(lookupKey, renderedPage)
    } else {
      await this.renderedRepository.discardArtifact(renderedPage)
    }
    return ComicWholePageTranslationOrchestrator.result(renderedPage, false)
  }

  private identity(
    request: ComicWholePageTranslationRequest,
    contextFingerprint: string,
  ): ComicRenderedPageIdentity {
    const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
    identity.route = ComicVisualTranslationRoute.WHOLE_PAGE_RENDER
    identity.projectId = request.source.projectId
    identity.pageIndex = request.source.pageIndex
    identity.sourceImageHash = request.source.imageHash
    identity.sourceWidth = request.source.imageWidth
    identity.sourceHeight = request.source.imageHeight
    identity.targetLanguage = request.context.targetLanguage
    identity.translationSourceProfileId = this.backend.sourceProfileId()
    identity.translationSourceRevision = this.backend.sourceRevision()
    identity.translationModelId = this.backend.modelId()
    identity.translationPromptVersion = this.backend.promptVersion()
    identity.translationContextFingerprint = contextFingerprint
    identity.glossaryRevision = request.context.glossaryRevision
    identity.translationRevision = request.requestedTranslationRevision
    identity.sourceTreatmentProfileId = request.renderProfile.sourceTreatmentProfileId
    identity.layoutProfileId = request.renderProfile.layoutProfileId
    identity.renderBackendId = this.backend.sourceProfileId()
    identity.renderProfileId = request.renderProfile.profileId
    identity.renderTargetMimeType = request.renderProfile.targetMimeType
    identity.renderRevision = request.renderProfile.revision
    identity.assertValid()
    return identity
  }

  private matchesPipeline(
    page: ComicRenderedPage,
    expected: ComicRenderedPageIdentity,
  ): boolean {
    return ComicRenderedPageRepositoryContract.matchesScope(
      page,
      ComicWholePageTranslationOrchestrator.source(expected),
      expected.targetLanguage,
    ) && page.identity.route === ComicVisualTranslationRoute.WHOLE_PAGE_RENDER &&
      page.identity.cacheKey() === expected.cacheKey()
  }

  private static source(identity: ComicRenderedPageIdentity): ComicVisualPageSource {
    const source: ComicVisualPageSource = new ComicVisualPageSource()
    source.projectId = identity.projectId
    source.pageIndex = identity.pageIndex
    source.imageFilePath = 'cached-artifact-identity'
    source.imageHash = identity.sourceImageHash
    source.imageWidth = identity.sourceWidth
    source.imageHeight = identity.sourceHeight
    return source
  }

  private static validateRequest(request: ComicWholePageTranslationRequest): void {
    ComicVisualTranslationContract.validateSource(request.source)
    if (!ComicWholePageTranslationOrchestrator.positiveInteger(
      request.requestedTranslationRevision,
    ) || request.context.sourceLanguage.length <= 0 ||
      request.context.targetLanguage.length <= 0 ||
      request.renderProfile.profileId.length <= 0 ||
      request.renderProfile.sourceTreatmentProfileId.length <= 0 ||
      request.renderProfile.layoutProfileId.length <= 0 ||
      request.renderProfile.targetMimeType !== 'image/png' ||
      !ComicWholePageTranslationOrchestrator.positiveInteger(
        request.renderProfile.revision,
      )) {
      throw new Error('Comic whole-page translation request is invalid')
    }
  }

  private static copyRequest(
    source: ComicWholePageTranslationRequest,
  ): ComicWholePageTranslationRequest {
    const request: ComicWholePageTranslationRequest =
      new ComicWholePageTranslationRequest()
    request.source = source.source.copy()
    request.context = source.context.copy()
    request.renderProfile = source.renderProfile.copy()
    request.requestedTranslationRevision = source.requestedTranslationRevision
    return request
  }

  private static result(
    page: ComicRenderedPage,
    cacheHit: boolean,
  ): ComicVisualTranslationRunResult {
    const result: ComicVisualTranslationRunResult = new ComicVisualTranslationRunResult()
    result.renderedPage = page.copy()
    result.cacheHit = cacheHit
    return result
  }

  private static positiveInteger(value: number): boolean {
    return Number.isFinite(value) && value > 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  private static digest(value: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) })
    const bytes: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}
