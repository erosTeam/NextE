import { describe, expect, it } from '@ohos/hypium'
import {
  CacheStat,
  ComicRenderedPage,
  ComicRenderProfile,
  ComicVisualPageSource,
  ComicVisualTranslationRoute,
  ComicWholePageRenderBackend,
  ComicWholePageRenderRequest,
  ComicWholePageTranslationOrchestrator,
  ComicWholePageTranslationRequest,
  InMemoryComicRenderedPageRepository,
} from 'shared'

const WHOLE_PAGE_CONTEXT_A: string = 'a'.repeat(64)
const WHOLE_PAGE_CONTEXT_B: string = 'b'.repeat(64)

class FixtureWholePageBackend implements ComicWholePageRenderBackend {
  renderCalls: number = 0
  fingerprint: string = WHOLE_PAGE_CONTEXT_A
  invalidResult: boolean = false

  sourceProfileId(): string {
    return 'fixture-whole-page-provider'
  }

  sourceRevision(): number {
    return 1
  }

  modelId(): string {
    return 'fixture-whole-page-model'
  }

  promptVersion(): string {
    return 'fixture-whole-page-prompt-v1'
  }

  contextFingerprint(_request: ComicWholePageRenderRequest): string {
    return this.fingerprint
  }

  async render(request: ComicWholePageRenderRequest): Promise<ComicRenderedPage> {
    this.renderCalls++
    const now: number = Date.now()
    const page: ComicRenderedPage = new ComicRenderedPage()
    page.identity = request.identity.copy()
    if (this.invalidResult) {
      page.identity.translationModelId = 'wrong-model'
    }
    page.artifactHash = 'f'.repeat(64)
    page.mimeType = 'image/png'
    page.width = request.source.imageWidth
    page.height = request.source.imageHeight
    page.byteLength = 4096
    page.localFilePath = '/fixture/whole-page.png'
    page.createdAt = now
    page.lastAccessAt = now
    return page
  }
}

function wholePageRequest(): ComicWholePageTranslationRequest {
  const source: ComicVisualPageSource = new ComicVisualPageSource()
  source.projectId = 'whole-page-project'
  source.pageIndex = 0
  source.imageFilePath = '/fixture/source-page.png'
  source.imageHash = 'c'.repeat(64)
  source.imageWidth = 1024
  source.imageHeight = 1536

  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'whole-page-render-v1'
  profile.sourceTreatmentProfileId = 'provider-managed-treatment-v1'
  profile.layoutProfileId = 'provider-managed-layout-v1'
  profile.targetMimeType = 'image/png'
  profile.revision = 1

  const request: ComicWholePageTranslationRequest = new ComicWholePageTranslationRequest()
  request.source = source
  request.context.sourceLanguage = 'ja'
  request.context.targetLanguage = 'zh-CN'
  request.context.rollingSummary = '优是上一页出现的人名。'
  request.context.glossaryRevision = 2
  request.renderProfile = profile
  return request
}

export default function comicWholePageTranslationOrchestratorTest(): void {
  describe('ComicWholePageTranslationOrchestrator', () => {
    it('publishes only a whole-page identity and caches an exact result', 0,
      async (done: Function) => {
        const backend: FixtureWholePageBackend = new FixtureWholePageBackend()
        const orchestrator: ComicWholePageTranslationOrchestrator =
          new ComicWholePageTranslationOrchestrator(
            backend,
            new InMemoryComicRenderedPageRepository(),
          )
        const request: ComicWholePageTranslationRequest = wholePageRequest()
        const first = await orchestrator.run(request)
        const second = await orchestrator.run(request)
        expect(first.cacheHit).assertEqual(false)
        expect(second.cacheHit).assertEqual(true)
        expect(backend.renderCalls).assertEqual(1)
        expect(first.renderedPage.identity.route)
          .assertEqual(ComicVisualTranslationRoute.WHOLE_PAGE_RENDER)
        expect(first.renderedPage.identity.regionBackendId).assertEqual('')
        expect(first.renderedPage.identity.regionProfileId).assertEqual('')
        expect(first.renderedPage.identity.regionRevision).assertEqual(0)
        expect(first.renderedPage.identity.documentRevision).assertEqual(0)
        done()
      })

    it('uses context identity for cache separation and supports forced refresh', 0,
      async (done: Function) => {
        const backend: FixtureWholePageBackend = new FixtureWholePageBackend()
        const orchestrator: ComicWholePageTranslationOrchestrator =
          new ComicWholePageTranslationOrchestrator(
            backend,
            new InMemoryComicRenderedPageRepository(),
          )
        const request: ComicWholePageTranslationRequest = wholePageRequest()
        await orchestrator.run(request)
        backend.fingerprint = WHOLE_PAGE_CONTEXT_B
        await orchestrator.run(request)
        await orchestrator.run(request, true)
        expect(backend.renderCalls).assertEqual(3)
        done()
      })

    it('does not cache a provider result with a mismatched identity', 0,
      async (done: Function) => {
        const backend: FixtureWholePageBackend = new FixtureWholePageBackend()
        backend.invalidResult = true
        const repository: InMemoryComicRenderedPageRepository =
          new InMemoryComicRenderedPageRepository()
        const orchestrator: ComicWholePageTranslationOrchestrator =
          new ComicWholePageTranslationOrchestrator(backend, repository)
        let rejected: boolean = false
        try {
          await orchestrator.run(wholePageRequest())
        } catch (_error) {
          rejected = true
        }
        const stat: CacheStat = await repository.stat()
        expect(rejected).assertEqual(true)
        expect(stat.count).assertEqual(0)
        done()
      })
  })
}
