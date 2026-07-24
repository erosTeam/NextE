import { application, common } from '@kit.AbilityKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  ComicPageDocument,
  ComicPoint,
  ComicPreviousPageContext,
  ComicResponsesHttpTransport,
  ComicResponsesTextTranslationProtocol,
  ComicTextBlock,
  ComicTextKind,
  ComicTextTranslationRequest,
  ComicVisualPageSource,
  OpenAiApiComicTextTranslator,
} from 'shared'

class TranslationOutputBlock {
  blockId: string = ''
  translatedText: string = ''
}

class TranslationOutputPayload {
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  targetLanguage: string = ''
  pageSummary: string = ''
  blocks: TranslationOutputBlock[] = []
}

class TranslationOutputText {
  type: string = 'output_text'
  text: string = ''
}

class TranslationOutputMessage {
  type: string = 'message'
  phase: string = 'final_answer'
  content: TranslationOutputText[] = []
}

class TranslationResponsesEnvelope {
  output: TranslationOutputMessage[] = []
}

class FixedTranslationTransport implements ComicResponsesHttpTransport {
  requestCount: number = 0
  requestBody: string = ''
  private readonly responseBody: string

  constructor(payload: TranslationOutputPayload) {
    const text: TranslationOutputText = new TranslationOutputText()
    text.text = JSON.stringify(payload)
    const message: TranslationOutputMessage = new TranslationOutputMessage()
    message.content = [text]
    const envelope: TranslationResponsesEnvelope = new TranslationResponsesEnvelope()
    envelope.output = [message]
    this.responseBody = JSON.stringify(envelope)
  }

  requestText(
    _url: string,
    _method: string,
    _headers: Record<string, string>,
    body: string,
    _connectTimeoutMs: number,
    _readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    this.requestCount++
    this.requestBody = body
    const response: AxiosTextResponse = new AxiosTextResponse()
    response.statusCode = 200
    response.body = this.responseBody
    return Promise.resolve(response)
  }
}

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function writeBytes(path: string, bytes: Uint8Array): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function sha256(bytes: Uint8Array): string {
  const md = cryptoFramework.createMd('SHA256')
  md.updateSync({ data: bytes })
  const digest: Uint8Array = md.digestSync().data
  const parts: string[] = []
  for (let index: number = 0; index < digest.length; index++) {
    parts.push(digest[index].toString(16).padStart(2, '0'))
  }
  return parts.join('')
}

function textBlock(blockId: string, readingOrder: number, sourceText: string): ComicTextBlock {
  const block: ComicTextBlock = new ComicTextBlock()
  block.blockId = blockId
  block.readingOrder = readingOrder
  block.kind = ComicTextKind.DIALOGUE
  block.sourceText = sourceText
  block.normalizedSourceText = sourceText
  block.styleHint = 'horizontal'
  block.sourceRevision = 1
  block.polygon = [
    new ComicPoint(10, 10),
    new ComicPoint(200, 10),
    new ComicPoint(200, 120),
    new ComicPoint(10, 120),
  ]
  return block
}

function translationRequest(imageFilePath: string, imageHash: string): ComicTextTranslationRequest {
  const request: ComicTextTranslationRequest = new ComicTextTranslationRequest()
  const source: ComicVisualPageSource = new ComicVisualPageSource()
  source.projectId = 'visual-project:zh-CN'
  source.pageIndex = 2
  source.imageFilePath = imageFilePath
  source.imageHash = imageHash
  source.imageWidth = 1024
  source.imageHeight = 1536
  request.source = source

  const document: ComicPageDocument = new ComicPageDocument()
  document.projectId = source.projectId
  document.pageIndex = source.pageIndex
  document.imageHash = source.imageHash
  document.imageWidth = source.imageWidth
  document.imageHeight = source.imageHeight
  document.analysisRevision = 1
  document.hasText = true
  document.blocks = [
    textBlock('p2-r0', 0, 'お兄ちゃん'),
    textBlock('p2-r1', 1, '待って！'),
  ]
  request.document = document
  request.context.sourceLanguage = 'ja'
  request.context.targetLanguage = 'zh-CN'
  request.context.rollingSummary = '优正在寻找失踪的哥哥。'
  request.context.styleGuide = 'Use concise natural Chinese.'
  request.context.glossaryRevision = 3
  request.context.styleGuideRevision = 1
  request.context.contextRevision = 4
  const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
  previous.pageIndex = 1
  previous.sourceText = 'お兄ちゃんを探してる。'
  previous.translatedText = '我在找哥哥。'
  previous.pageSummary = '优仍在寻找哥哥。'
  request.context.previousPages = [previous]
  request.requestedTranslationRevision = 1
  return request
}

function outputPayload(request: ComicTextTranslationRequest): TranslationOutputPayload {
  const payload: TranslationOutputPayload = new TranslationOutputPayload()
  payload.projectId = request.source.projectId
  payload.pageIndex = request.source.pageIndex
  payload.sourceImageHash = request.source.imageHash
  payload.targetLanguage = request.context.targetLanguage
  payload.pageSummary = '优发现哥哥就在前方并叫他停下。'
  const first: TranslationOutputBlock = new TranslationOutputBlock()
  first.blockId = 'p2-r0'
  first.translatedText = '哥哥'
  const second: TranslationOutputBlock = new TranslationOutputBlock()
  second.blockId = 'p2-r1'
  second.translatedText = '等等！'
  payload.blocks = [first, second]
  return payload
}

function clonePayload(source: TranslationOutputPayload): TranslationOutputPayload {
  const value: TranslationOutputPayload = new TranslationOutputPayload()
  value.projectId = source.projectId
  value.pageIndex = source.pageIndex
  value.sourceImageHash = source.sourceImageHash
  value.targetLanguage = source.targetLanguage
  value.pageSummary = source.pageSummary
  for (let index: number = 0; index < source.blocks.length; index++) {
    const block: TranslationOutputBlock = new TranslationOutputBlock()
    block.blockId = source.blocks[index].blockId
    block.translatedText = source.blocks[index].translatedText
    value.blocks.push(block)
  }
  return value
}

export default function comicResponsesTextTranslatorTest(): void {
  describe('ComicResponsesTextTranslator', () => {
    it('sends full-page vision plus bounded cross-page context for exact detected blocks', 0,
      async (done: Function) => {
        const context: common.UIAbilityContext = await appContext()
        const path: string = `${context.cacheDir}/comic-text-translator-fixture.jpg`
        const fixtureContext = await application.createModuleContext(context, 'entry_test')
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          'comic_translation_eval_page_01.png',
        )
        const request: ComicTextTranslationRequest = translationRequest(path, sha256(bytes))
        const transport: FixedTranslationTransport =
          new FixedTranslationTransport(outputPayload(request))
        const translator: OpenAiApiComicTextTranslator = new OpenAiApiComicTextTranslator(
          'https://api.example.com/v1',
          'fixture-key',
          'fixture-model',
          transport,
          'source-fixture',
          7,
        )
        try {
          writeBytes(path, bytes)
          const result = await translator.translate(request)
          expect(transport.requestCount).assertEqual(1)
          expect(transport.requestBody.includes('"type":"input_image"')).assertEqual(true)
          expect(transport.requestBody.includes('data:image/png;base64,')).assertEqual(true)
          expect(transport.requestBody.split('"type":"input_image"').length - 1).assertEqual(3)
          expect(transport.requestBody.includes('Region crop blockId=p2-r0')).assertEqual(true)
          expect(transport.requestBody.includes('data:image/jpeg;base64,')).assertEqual(true)
          expect(transport.requestBody.includes('お兄ちゃん')).assertEqual(true)
          expect(transport.requestBody.includes('我在找哥哥。')).assertEqual(true)
          expect(result.batch.blocks.length).assertEqual(2)
          expect(result.batch.blocks[0].translatedText).assertEqual('哥哥')
          expect(result.batch.sourceProfileId).assertEqual('source-fixture')
          expect(result.batch.sourceRevision).assertEqual(7)
          expect(result.batch.contextFingerprint).assertEqual(
            translator.contextFingerprint(request),
          )
          expect(result.pageSummary).assertEqual('优发现哥哥就在前方并叫他停下。')
        } finally {
          try {
            fileIo.unlinkSync(path)
          } catch (_error) {
          }
        }
        done()
      })

    it('fingerprints exactly the current blocks and bounded context sent in the prompt', 0,
      (done: Function) => {
        const first: ComicTextTranslationRequest = translationRequest(
          '/cache/page.jpg',
          'a'.repeat(64),
        )
        const second: ComicTextTranslationRequest = translationRequest(
          '/cache/page.jpg',
          'a'.repeat(64),
        )
        for (let pageIndex: number = 0; pageIndex < 2; pageIndex++) {
          const previous: ComicPreviousPageContext = new ComicPreviousPageContext()
          previous.pageIndex = pageIndex
          previous.sourceText = `source-${pageIndex}`
          previous.translatedText = `translation-${pageIndex}`
          previous.pageSummary = `summary-${pageIndex}`
          first.context.previousPages.unshift(previous.copy())
          second.context.previousPages.unshift(previous.copy())
        }
        second.context.previousPages[0].translatedText = 'omitted-context-change'
        const firstFingerprint: string =
          ComicResponsesTextTranslationProtocol.contextFingerprint(first)
        expect(ComicResponsesTextTranslationProtocol.contextFingerprint(second))
          .assertEqual(firstFingerprint)
        second.document.blocks[0].sourceText = 'visible-current-page-change'
        expect(ComicResponsesTextTranslationProtocol.contextFingerprint(second) ===
          firstFingerprint).assertEqual(false)
        const prompt: string = ComicResponsesTextTranslationProtocol.buildPrompt(first)
        expect(prompt.includes('attached full page image')).assertEqual(true)
        expect(prompt.includes('OCR text is evidence rather than ground truth')).assertEqual(true)
        expect(prompt.includes('do not copy an OCR mistake into the translation')).assertEqual(true)
        expect(prompt.includes('labeled enlarged region crops')).assertEqual(true)
        expect(prompt.includes('Never invent parenthetical narration')).assertEqual(true)
        expect(prompt.includes('blocks marked kind="sfx"')).assertEqual(true)
        expect(prompt.includes('copy its sourceText exactly')).assertEqual(true)
        expect(prompt.includes('"polygon":[[10,10],[200,10]')).assertEqual(true)
        expect(prompt.includes('Every supplied blockId must appear exactly once')).assertEqual(true)
        done()
      })

    it('rejects missing, duplicate, unknown, empty, and mismatched translation output', 0,
      (done: Function) => {
        const request: ComicTextTranslationRequest = translationRequest(
          '/cache/page.jpg',
          'b'.repeat(64),
        )
        const base: TranslationOutputPayload = outputPayload(request)
        const candidates: TranslationOutputPayload[] = []

        const missing: TranslationOutputPayload = clonePayload(base)
        missing.blocks.pop()
        candidates.push(missing)
        const duplicate: TranslationOutputPayload = clonePayload(base)
        duplicate.blocks[1].blockId = duplicate.blocks[0].blockId
        candidates.push(duplicate)
        const unknown: TranslationOutputPayload = clonePayload(base)
        unknown.blocks[1].blockId = 'unknown-block'
        candidates.push(unknown)
        const empty: TranslationOutputPayload = clonePayload(base)
        empty.blocks[1].translatedText = '   '
        candidates.push(empty)
        const mismatch: TranslationOutputPayload = clonePayload(base)
        mismatch.sourceImageHash = 'c'.repeat(64)
        candidates.push(mismatch)

        for (let index: number = 0; index < candidates.length; index++) {
          let rejected: boolean = false
          try {
            ComicResponsesTextTranslationProtocol.parse(
              request,
              JSON.stringify(candidates[index]),
              'source-fixture',
              1,
              'model-fixture',
              'prompt-fixture-v1',
            )
          } catch (_error) {
            rejected = true
          }
          expect(rejected).assertEqual(true)
        }
        done()
      })
  })
}
