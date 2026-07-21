import { describe, expect, it } from '@ohos/hypium'
import { IndexRouteCoordinator } from '../../../main/ets/model/IndexRouteCoordinator'

export default function indexRouteCoordinatorTest(): void {
  describe('IndexRouteCoordinator', () => {
    it('maps shared LLM source destinations to registered builder families', 0, (done: Function) => {
      expect(IndexRouteCoordinator.family('LlmSourceManager')).assertEqual('llmSourceManager')
      expect(IndexRouteCoordinator.family('LlmSourceDetail')).assertEqual('llmSourceDetail')
      expect(IndexRouteCoordinator.family('ToriiWholePageLiveEvaluation'))
        .assertEqual('toriiWholePageLiveEvaluation')
      expect(IndexRouteCoordinator.family('MangaRenderingServiceSettings'))
        .assertEqual('mangaRenderingServiceSettings')
      done()
    })
  })
}
