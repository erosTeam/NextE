import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { textProcessing } from '@kit.NaturalLanguageKit'
import { BusinessError } from '@kit.BasicServicesKit'
import {
  CommentWordSegmentService,
  LocalBlockService,
  LocalBlockRule,
  LocalBlockSettings,
  connectLocalBlock,
  LOCAL_BLOCK_MEMBER_ID_PREFIX,
  LOCAL_BLOCK_COMMENT_ID_PREFIX,
} from 'shared'

interface IcuSegment {
  segment: string
}

interface IcuSegments {
  [Symbol.iterator](): Iterator<IcuSegment>
}

const JA_SAMPLE: string = 'このギャラリーは最高でした。絵がとても綺麗で、ストーリーも面白い。'

/**
 * Device-side check for the comment block feature's two platform-dependent parts, which a host build cannot
 * prove: the engine's ICU word segmenter (the tier that covers Japanese, which the platform segmenter's
 * documented languages do not include) and identity-rule matching.
 */
export default function commentBlockTrialTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] !== 'CommentBlockTrial') return
  describe('CommentBlockTrial', (): void => {
    it('segmentsJapaneseIntoRealWords', 0, async (): Promise<void> => {
      const words: string[] = await CommentWordSegmentService.segment(JA_SAMPLE)
      console.info(`[NEXTE_BLOCK_SEG] ja=${JSON.stringify(words)}`)
      expect(words.length > 0).assertTrue()
      expect(words.indexOf('ギャラリー') >= 0).assertTrue()
      expect(words.indexOf('ストーリー') >= 0).assertTrue()
      // A per-character fragment means some tier degraded to single-character output and polluted the panel.
      expect(words.indexOf('ギ') >= 0).assertFalse()
      expect(words.indexOf('白') >= 0).assertFalse()
    })

    it('attributesEachSegmentTier', 0, async (): Promise<void> => {
      const globalApi: ESObject = globalThis
      const intlApi: ESObject = globalApi.Intl
      const ctor: ESObject = intlApi.Segmenter
      const segmenter: ESObject = new ctor('ja', { granularity: 'word' })
      const icu: string[] = []
      const segments: IcuSegments = segmenter.segment(JA_SAMPLE) as IcuSegments
      for (const piece of segments) {
        icu.push(piece.segment)
      }
      let platform: string[] = []
      let platformError: string = ''
      try {
        const segments: textProcessing.WordSegment[] = await textProcessing.getWordSegment(JA_SAMPLE)
        for (let i = 0; i < segments.length; i++) {
          platform.push(segments[i].word)
        }
      } catch (error) {
        platformError = `${(error as BusinessError).code}`
      }
      console.info(`[NEXTE_BLOCK_TIER] icu=${JSON.stringify(icu)}`)
      console.info(`[NEXTE_BLOCK_TIER] platform=${JSON.stringify(platform)} error=${platformError}`)
      expect(icu.length > 0).assertTrue()
    })

    it('segmentsChineseAndEnglish', 0, async (): Promise<void> => {
      const zh: string[] = await CommentWordSegmentService.segment('这个画廊非常棒，画风很精美！推荐')
      const en: string[] = await CommentWordSegmentService.segment('Thanks for uploading! The art is amazing.')
      console.info(`[NEXTE_BLOCK_SEG] zh=${JSON.stringify(zh)} en=${JSON.stringify(en)}`)
      expect(zh.length > 0).assertTrue()
      expect(en.length > 0).assertTrue()
    })

    it('preservesSingleWordsAndLongCommentTail', 0, async (): Promise<void> => {
      const source: string = '梦之茗汉化组 画风很精美 这是完整评论内容 '.repeat(80) + '末尾验收标记987654'
      const words: string[] = await CommentWordSegmentService.segment(source)
      const original: string = source.replace(/[\s\p{P}\p{S}]/gu, '')
      const segmented: string = words.join('').replace(/[\s\p{P}\p{S}]/gu, '')
      expect(segmented).assertEqual(original)
      expect(words.length > 40).assertTrue()
      const ja: string[] = await CommentWordSegmentService.segment('これはとても綺麗な絵です')
      expect(ja.indexOf('絵') >= 0).assertTrue()
      console.info(`[NEXTE_BLOCK_COVERAGE] chars=${source.length} tokens=${words.length} tail=${words.slice(-8).join('/')}`)
    })

    it('identityRuleMatchingStaysExact', 0, (): void => {
      const byMember: LocalBlockRule = new LocalBlockRule()
      byMember.blockType = 'commentator'
      byMember.ruleText = `${LOCAL_BLOCK_MEMBER_ID_PREFIX}123`
      expect(LocalBlockService.isIdentityRule(byMember)).assertTrue()

      const byComment: LocalBlockRule = new LocalBlockRule()
      byComment.blockType = 'comment'
      byComment.ruleText = `${LOCAL_BLOCK_COMMENT_ID_PREFIX}456`
      expect(LocalBlockService.isIdentityRule(byComment)).assertTrue()

      const plain: LocalBlockRule = new LocalBlockRule()
      plain.blockType = 'comment'
      plain.ruleText = '广告'
      expect(LocalBlockService.isIdentityRule(plain)).assertFalse()
    })

    it('flatPhraseMatchesItsMultilineSource', 0, (): void => {
      const state = connectLocalBlock()
      const original: LocalBlockRule[] = state.rules
      try {
        const phrase: string = LocalBlockSettings.cleanText('电子版\r\n漫画\u2028Thanks again')
        expect(phrase).assertEqual('电子版 漫画 Thanks again')
        const rule: LocalBlockRule = new LocalBlockRule()
        rule.blockType = 'comment'
        rule.ruleText = phrase
        state.rules = [rule]
        expect(LocalBlockService.matchText('这是电子版\n漫画\nThanks again', 'comment')).assertTrue()
        expect(LocalBlockService.matchText('电子版和漫画', 'comment')).assertFalse()
      } finally {
        state.rules = original
      }
    })
  })
}
