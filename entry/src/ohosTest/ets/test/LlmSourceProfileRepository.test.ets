import { describe, expect, it } from '@ohos/hypium'
import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
  LlmConsumerBinding,
  LlmSourceProfile,
  LlmSourceProfileCodec,
  LlmSourceProfileContract,
  LlmSourceProfileRepository,
  LlmSourceSecretStore,
} from 'shared'

function apiSource(id: string, name: string = 'Fixture API'): LlmSourceProfile {
  const value: LlmSourceProfile = new LlmSourceProfile()
  value.sourceProfileId = id
  value.displayName = name
  value.sourceType = LLM_SOURCE_TYPE_OPENAI_COMPATIBLE
  value.baseUrl = 'https://api.fixture.example/v1'
  value.capabilities.responses = true
  value.capabilities.imageInput = true
  value.capabilities.modelCatalog = true
  return value
}

function codexSource(id: string): LlmSourceProfile {
  const value: LlmSourceProfile = new LlmSourceProfile()
  value.sourceProfileId = id
  value.displayName = 'Fixture Codex'
  value.sourceType = LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
  value.capabilities.responses = true
  value.capabilities.imageInput = true
  value.capabilities.modelCatalog = true
  value.capabilities.usage = true
  return value
}

function prepared(candidate: LlmSourceProfile, now: number): LlmSourceProfile {
  return LlmSourceProfileRepository.prepareForUpsert(null, candidate, now)
}

function binding(consumerId: string, sourceProfileId: string, modelId: string): LlmConsumerBinding {
  const value: LlmConsumerBinding = new LlmConsumerBinding()
  value.consumerId = consumerId
  value.sourceProfileId = sourceProfileId
  value.modelId = modelId
  return value
}

function rejected(action: () => void): boolean {
  try {
    action()
    return false
  } catch (_error) {
    return true
  }
}

export default function llmSourceProfileRepositoryTest(): void {
  describe('Shared LLM source profiles', () => {
    it('round-trips multiple source types with copy isolation', 0, () => {
      const first: LlmSourceProfile = prepared(apiSource('source-api'), 1000)
      const second: LlmSourceProfile = prepared(codexSource('source-codex'), 1001)
      const encoded: string = LlmSourceProfileCodec.encode([first, second])
      const decoded: LlmSourceProfile[] = LlmSourceProfileCodec.decode(encoded)
      decoded[0].displayName = 'Changed copy'
      decoded[0].capabilities.responses = false
      const decodedAgain: LlmSourceProfile[] = LlmSourceProfileCodec.decode(encoded)
      expect(decodedAgain.length).assertEqual(2)
      expect(decodedAgain[0].displayName).assertEqual('Fixture API')
      expect(decodedAgain[0].capabilities.responses).assertEqual(true)
      expect(decodedAgain[1].sourceType).assertEqual(LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL)
    })

    it('keeps revision stable for display edits and bumps request identity edits', 0, () => {
      const original: LlmSourceProfile = prepared(apiSource('source-stable'), 1000)
      const renamedCandidate: LlmSourceProfile = original.copy()
      renamedCandidate.displayName = 'Renamed source'
      const renamed: LlmSourceProfile = LlmSourceProfileRepository.prepareForUpsert(
        original,
        renamedCandidate,
        1001,
      )
      expect(renamed.sourceProfileId).assertEqual(original.sourceProfileId)
      expect(renamed.sourceRevision).assertEqual(original.sourceRevision)
      const movedCandidate: LlmSourceProfile = renamed.copy()
      movedCandidate.baseUrl = 'https://other.fixture.example/v1'
      const moved: LlmSourceProfile = LlmSourceProfileRepository.prepareForUpsert(
        renamed,
        movedCandidate,
        1002,
      )
      expect(moved.sourceRevision).assertEqual(original.sourceRevision + 1)
      expect(moved.createdAt).assertEqual(original.createdAt)
      expect(moved.updatedAt > renamed.updatedAt).assertEqual(true)
    })

    it('does not fall back when a referenced profile disappears', 0, () => {
      const selected: LlmSourceProfile = prepared(apiSource('source-selected'), 1000)
      const unrelated: LlmSourceProfile = prepared(apiSource('source-unrelated'), 1001)
      const selectedBinding: LlmConsumerBinding = binding(
        LLM_CONSUMER_COMMENT_TRANSLATION,
        selected.sourceProfileId,
        'fixture-comment-model',
      )
      expect(LlmSourceProfileRepository.resolve(
        [selected, unrelated],
        selectedBinding,
      )?.profile.sourceProfileId).assertEqual(selected.sourceProfileId)
      expect(LlmSourceProfileRepository.resolve([unrelated], selectedBinding)).assertNull()
      expect(selectedBinding.sourceProfileId).assertEqual(selected.sourceProfileId)
    })

    it('requires an all-or-empty consumer binding', 0, () => {
      const empty: LlmConsumerBinding = binding(LLM_CONSUMER_MANGA_TRANSLATION, '', '')
      LlmSourceProfileContract.validateBinding(empty)
      const missingModel: LlmConsumerBinding = binding(
        LLM_CONSUMER_MANGA_TRANSLATION,
        'source-api',
        '',
      )
      const missingSource: LlmConsumerBinding = binding(
        LLM_CONSUMER_MANGA_TRANSLATION,
        '',
        'fixture-model',
      )
      expect(rejected((): void => LlmSourceProfileContract.validateBinding(missingModel))).assertEqual(true)
      expect(rejected((): void => LlmSourceProfileContract.validateBinding(missingSource))).assertEqual(true)
    })

    it('rejects duplicate profiles, invalid URLs, and oversized stores', 0, () => {
      const first: LlmSourceProfile = prepared(apiSource('source-duplicate'), 1000)
      const duplicate: LlmSourceProfile = first.copy()
      duplicate.displayName = 'Duplicate'
      expect(rejected((): void => {
        LlmSourceProfileCodec.encode([first, duplicate])
      })).assertEqual(true)
      const invalidUrl: LlmSourceProfile = apiSource('source-url')
      invalidUrl.baseUrl = 'file:///fixture'
      expect(rejected((): void => {
        prepared(invalidUrl, 1000)
      })).assertEqual(true)
      expect(rejected((): void => {
        LlmSourceProfileCodec.decode('x'.repeat(256 * 1024 + 1))
      }))
        .assertEqual(true)
    })

    it('keeps source-scoped secret maps deterministic and bounded', 0, () => {
      const values: Record<string, string> = {
        'source-b': 'key-b',
        'source-a': 'key-a',
      }
      const encoded: string = LlmSourceSecretStore.encodeStringMap(values, 1024, 64)
      expect(encoded.indexOf('source-a') < encoded.indexOf('source-b')).assertEqual(true)
      const decoded: Record<string, string> = LlmSourceSecretStore.decodeStringMap(encoded, 1024, 64)
      decoded['source-a'] = 'changed'
      const decodedAgain: Record<string, string> = LlmSourceSecretStore.decodeStringMap(
        encoded,
        1024,
        64,
      )
      expect(decodedAgain['source-a']).assertEqual('key-a')
      expect(rejected((): void => {
        LlmSourceSecretStore.decodeStringMap(
          '{"source-a":"oversized"}',
          1024,
          4,
        )
      })).assertEqual(true)
    })

    it('reports every consumer before source deletion without changing bindings', 0, () => {
      const comment: LlmConsumerBinding = binding(
        LLM_CONSUMER_COMMENT_TRANSLATION,
        'source-shared',
        'comment-model',
      )
      const manga: LlmConsumerBinding = binding(
        LLM_CONSUMER_MANGA_TRANSLATION,
        'source-shared',
        'manga-model',
      )
      const consumers: string[] = LlmSourceProfileRepository.referencedConsumers(
        'source-shared',
        [comment, manga],
      )
      expect(consumers.length).assertEqual(2)
      expect(consumers[0]).assertEqual(LLM_CONSUMER_COMMENT_TRANSLATION)
      expect(consumers[1]).assertEqual(LLM_CONSUMER_MANGA_TRANSLATION)
    })
  })
}
