import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  CommentTranslationService,
  CommentTranslationSettings,
  COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  TEXT_TRANSLATION_CONTENT_COMMENT,
  TEXT_TRANSLATION_CONTENT_GALLERY_TITLE,
} from 'shared'

async function translatePublicFixture(contentKind: string): Promise<void> {
  const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  const context: common.UIAbilityContext = ability.context as common.UIAbilityContext
  const original = CommentTranslationSettings.current()
  const fixture = CommentTranslationSettings.current()
  fixture.useGoogleOnly = true
  const startedAt: number = Date.now()
  const marker: string = startedAt.toString()
  const source: string = 'Hello world. Reference ' + marker + '.'
  let translated: string = ''
  let scope: string = ''
  try {
    CommentTranslationSettings.apply(fixture)
    scope = CommentTranslationService.bingCacheScope(
      CommentTranslationService.targetLanguage(), contentKind, true,
    )
    translated = await CommentTranslationService.translate(
      context, source, true, COMMENT_TRANSLATION_PRIORITY_INTERACTIVE, contentKind,
    )
    expect(translated.trim().length > 0).assertEqual(true)
    expect(translated.indexOf(marker) >= 0).assertEqual(true)
  } finally {
    CommentTranslationSettings.apply(original)
    if (translated.length > 0 && translated.indexOf(marker) >= 0) {
      const config: relationalStore.StoreConfig = {
        name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3, autoCleanDirtyData: true,
      }
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config)
      // Delete only this unique public fixture, never another translation or the user's cache.
      await store.executeSql(
        'DELETE FROM comment_translation_cache WHERE target_lang = ? AND translated = ? AND cached_at >= ?',
        [scope, translated, startedAt],
      )
    }
  }
}

export default function bingTranslationIntegrationTest(): void {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  if (parameters['-s bingTranslationIntegration'] !== 'true') {
    return
  }
  describe('BingTranslationIntegration', () => {
    it('translates public comment text through the production route and cleans its fixture', 0, async () => {
      await translatePublicFixture(TEXT_TRANSLATION_CONTENT_COMMENT)
    })
    it('translates public gallery-title text through the separate production cache scope', 0, async () => {
      await translatePublicFixture(TEXT_TRANSLATION_CONTENT_GALLERY_TITLE)
    })
  })
}
