import { describe, expect, it } from '@ohos/hypium'
import {
  COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH,
  COMIC_TRANSLATION_PROVIDER_OPENAI_API,
  CodexOAuthTokenCodec,
  CodexOAuthTokenSet,
  CodexUsageSnapshot,
  CodexUsageWindow,
  ComicTranslationCodexUsageService,
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LegacyCommentLlmSettings,
  LegacyMangaLlmSettings,
  LlmSourceMigrationInput,
  LlmSourceMigrationPlan,
  LlmSourceMigrationPlanner,
  LlmSourceProfile,
  LlmSourceProfileCodec,
} from 'shared'

function migrationInput(now: number = 1000): LlmSourceMigrationInput {
  const value: LlmSourceMigrationInput = new LlmSourceMigrationInput()
  value.now = now
  return value
}

function commentLegacy(
  apiUrl: string,
  apiKey: string,
  model: string,
): LegacyCommentLlmSettings {
  const value: LegacyCommentLlmSettings = new LegacyCommentLlmSettings()
  value.present = true
  value.apiUrl = apiUrl
  value.apiKey = apiKey
  value.model = model
  return value
}

function mangaApiLegacy(
  apiUrl: string,
  apiKey: string,
  model: string,
): LegacyMangaLlmSettings {
  const value: LegacyMangaLlmSettings = new LegacyMangaLlmSettings()
  value.provider = COMIC_TRANSLATION_PROVIDER_OPENAI_API
  value.apiPresent = true
  value.apiBaseUrl = apiUrl
  value.apiKey = apiKey
  value.apiModel = model
  return value
}

function selectedProfile(plan: LlmSourceMigrationPlan, sourceProfileId: string): LlmSourceProfile {
  for (let index: number = 0; index < plan.profiles.length; index++) {
    if (plan.profiles[index].sourceProfileId === sourceProfileId) {
      return plan.profiles[index]
    }
  }
  throw new Error('Fixture source profile is missing')
}

export default function llmSourceMigrationTest(): void {
  describe('Shared LLM source migration', () => {
    it('migrates comment-only settings with the legacy defaults', 0, () => {
      const input: LlmSourceMigrationInput = migrationInput()
      input.comment = commentLegacy('', 'fixture-comment-key', '')
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      expect(plan.profiles.length).assertEqual(1)
      expect(plan.commentBinding.consumerId).assertEqual(LLM_CONSUMER_COMMENT_TRANSLATION)
      expect(plan.commentBinding.modelId).assertEqual('gpt-4o-mini')
      expect(plan.mangaBinding.configured()).assertEqual(false)
      const profile: LlmSourceProfile = selectedProfile(
        plan,
        plan.commentBinding.sourceProfileId,
      )
      expect(profile.baseUrl).assertEqual('https://api.openai.com')
      expect(profile.capabilities.chatCompletions).assertEqual(true)
      expect(profile.capabilities.responses).assertEqual(false)
      expect(plan.apiKeys[profile.sourceProfileId]).assertEqual('fixture-comment-key')
    })

    it('migrates a manga API selection without creating a comment binding', 0, () => {
      const input: LlmSourceMigrationInput = migrationInput()
      input.manga = mangaApiLegacy(
        'https://manga.fixture.example/v1',
        'fixture-manga-key',
        'fixture-vision-model',
      )
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      expect(plan.profiles.length).assertEqual(1)
      expect(plan.commentBinding.configured()).assertEqual(false)
      expect(plan.mangaBinding.consumerId).assertEqual(LLM_CONSUMER_MANGA_TRANSLATION)
      expect(plan.mangaBinding.modelId).assertEqual('fixture-vision-model')
      const profile: LlmSourceProfile = selectedProfile(plan, plan.mangaBinding.sourceProfileId)
      expect(profile.baseUrl).assertEqual('https://manga.fixture.example')
      expect(profile.capabilities.responses).assertEqual(true)
      expect(profile.capabilities.imageInput).assertEqual(true)
    })

    it('deduplicates equivalent API roots while preserving consumer models', 0, () => {
      const input: LlmSourceMigrationInput = migrationInput()
      input.comment = commentLegacy(
        'https://shared.fixture.example',
        'fixture-shared-key',
        'fixture-text-model',
      )
      input.manga = mangaApiLegacy(
        'https://shared.fixture.example/v1/',
        'fixture-shared-key',
        'fixture-image-model',
      )
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      expect(plan.profiles.length).assertEqual(1)
      expect(plan.commentBinding.sourceProfileId).assertEqual(plan.mangaBinding.sourceProfileId)
      expect(plan.commentBinding.modelId).assertEqual('fixture-text-model')
      expect(plan.mangaBinding.modelId).assertEqual('fixture-image-model')
      expect(plan.profiles[0].capabilities.chatCompletions).assertEqual(true)
      expect(plan.profiles[0].capabilities.responses).assertEqual(true)
      expect(plan.profiles[0].sourceRevision).assertEqual(1)
    })

    it('keeps distinct API credentials as distinct reusable sources', 0, () => {
      const input: LlmSourceMigrationInput = migrationInput()
      input.comment = commentLegacy(
        'https://distinct.fixture.example/v1',
        'fixture-comment-key',
        'fixture-text-model',
      )
      input.manga = mangaApiLegacy(
        'https://distinct.fixture.example',
        'fixture-manga-key',
        'fixture-image-model',
      )
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      expect(plan.profiles.length).assertEqual(2)
      expect(plan.commentBinding.sourceProfileId === plan.mangaBinding.sourceProfileId)
        .assertEqual(false)
      expect(Object.keys(plan.apiKeys).length).assertEqual(2)
    })

    it('moves Codex login, selected model, account hash and valid usage cache together', 0, () => {
      const input: LlmSourceMigrationInput = migrationInput()
      input.manga.provider = COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      input.manga.codexPresent = true
      input.manga.codexModel = '5.6 LUNA'
      const tokens: CodexOAuthTokenSet = new CodexOAuthTokenSet()
      tokens.accessToken = 'fixture-access-token'
      tokens.refreshToken = 'fixture-refresh-token'
      tokens.idToken = 'fixture-id-token'
      tokens.accountId = 'fixture-account'
      tokens.expiresAt = 2000
      input.manga.codexTokenText = CodexOAuthTokenCodec.serialize(tokens)
      const usage: CodexUsageSnapshot = new CodexUsageSnapshot()
      usage.fiveHour = new CodexUsageWindow()
      usage.fiveHour.usedPercent = 25
      usage.fiveHour.windowSeconds = 18000
      usage.fiveHour.resetsAtMs = 3000
      usage.fetchedAtMs = 1500
      input.manga.codexUsageCacheText = ComicTranslationCodexUsageService.serializeCached(
        tokens.accountId,
        usage,
      )
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      expect(plan.profiles.length).assertEqual(1)
      expect(plan.mangaBinding.modelId).assertEqual('5.6 LUNA')
      const profile: LlmSourceProfile = selectedProfile(plan, plan.mangaBinding.sourceProfileId)
      expect(profile.sourceType).assertEqual(LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL)
      expect(profile.accountIdentityHash.length).assertEqual(64)
      expect(profile.accountIdentityHash === tokens.accountId).assertEqual(false)
      expect(plan.codexTokens[profile.sourceProfileId]).assertEqual(input.manga.codexTokenText)
      expect(plan.usageCaches[profile.sourceProfileId]).assertEqual(
        input.manga.codexUsageCacheText,
      )
    })

    it('skips a damaged legacy source without discarding another valid source', 0, () => {
      const input: LlmSourceMigrationInput = migrationInput()
      input.comment = commentLegacy('file:///invalid', 'fixture-comment-key', 'fixture-model')
      input.manga = mangaApiLegacy(
        'https://valid.fixture.example/v1',
        'fixture-manga-key',
        'fixture-image-model',
      )
      const plan: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(input)
      expect(plan.profiles.length).assertEqual(1)
      expect(plan.commentBinding.configured()).assertEqual(false)
      expect(plan.mangaBinding.configured()).assertEqual(true)
    })

    it('is stable on re-entry and never replaces an existing consumer binding', 0, () => {
      const firstInput: LlmSourceMigrationInput = migrationInput(1000)
      firstInput.comment = commentLegacy(
        'https://stable.fixture.example/v1',
        'fixture-stable-key',
        'fixture-model',
      )
      const first: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(firstInput)
      const secondInput: LlmSourceMigrationInput = migrationInput(2000)
      secondInput.profiles = first.profiles
      secondInput.apiKeys = first.apiKeys
      secondInput.codexTokens = first.codexTokens
      secondInput.usageCaches = first.usageCaches
      secondInput.commentBinding = first.commentBinding
      secondInput.mangaBinding = first.mangaBinding
      secondInput.comment = commentLegacy(
        'https://stable.fixture.example',
        'fixture-stable-key',
        'different-legacy-model',
      )
      const second: LlmSourceMigrationPlan = LlmSourceMigrationPlanner.plan(secondInput)
      expect(LlmSourceProfileCodec.encode(second.profiles)).assertEqual(
        LlmSourceProfileCodec.encode(first.profiles),
      )
      expect(second.commentBinding.sourceProfileId).assertEqual(first.commentBinding.sourceProfileId)
      expect(second.commentBinding.modelId).assertEqual(first.commentBinding.modelId)
      expect(second.profiles[0].updatedAt).assertEqual(first.profiles[0].updatedAt)
    })
  })
}
