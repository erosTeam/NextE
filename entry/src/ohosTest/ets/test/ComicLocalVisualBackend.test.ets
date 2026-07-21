import { application, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicBlockTranslation,
  ComicLocalVisualBackend,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicRegionRenderRequest,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicTranslationBatch,
  ComicTranslationAccuracySnapshot,
  ComicTranslationEvaluator,
  ComicTranslationReferenceBlock,
  ComicTranslationReferencePage,
  ComicVisualPageSource,
  ComicVisualTranslationContract,
  ComicVisualTranslationRoute,
  HarmonyComicLocalOcrEngine,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PAGE_01_PATH: string = 'comic_translation_eval_page_01.png'
const FIXTURE_PAGE_01_HASH: string =
  'b12a64700e64a9e707152d0570a8af8c5296055226f953c769307cb59e3176a9'
const FIXTURE_PAGE_02_PATH: string = 'comic_translation_eval_page_02.png'
const FIXTURE_PAGE_02_HASH: string =
  '72ee2ef048ec6035f0ade14f7a07c9f50302f377907076fa677b95977c0c246c'
const CONTEXT_HASH: string =
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

class LocalComicFixture {
  pageIndex: number = 0
  rawFile: string = ''
  imageHash: string = ''
  expectedSourceVariants: string[][] = []
}

class LocalComicQualityMeasurement {
  page: number = 0
  expected: number = 0
  actual: number = 0
  matched: number = 0
  missing: number = 0
  unexpected: number = 0
  readingOrderErrors: number = 0
  verticalBlocks: number = 0
  horizontalBlocks: number = 0
  directionExpected: number = 0
  directionMatched: number = 0
  analysisMs: number = 0
  renderMs: number = 0
  changedPixelPercent: number = 0
  pssBeforeKb: string = ''
  pssAfterAnalysisKb: string = ''
  pssAfterRenderKb: string = ''
  recognizedText: string = ''
  blockGeometry: string = ''
  artifactPath: string = ''
  artifactBytes: number = 0
}

function writeFile(path: string, bytes: Uint8Array): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    const buffer: ArrayBuffer = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    )
    const written: number = fileIo.writeSync(file.fd, buffer, { length: buffer.byteLength })
    if (written !== bytes.length) {
      throw new Error('Local comic fixture write failed')
    }
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function removeFile(path: string): void {
  try {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path)
    }
  } catch (_error) {}
}

function translated(sourceText: string): string {
  switch (sourceText.trim()) {
    case '午後七時、雨。':
      return '晚上七点，雨。'
    case '月影駅 東口':
    case '月影駅東口':
      return '月影站 东口'
    case 'ゆう':
    case '優':
      return '优'
    case '駅で迷った。':
      return '我在车站迷路了。'
    case 'ごめん。':
      return '抱歉。'
    case '優、遅かったね。':
      return '优，你来晚了。'
    case 'ごめん。駅で迷った。':
      return '抱歉，我在车站迷路了。'
    case 'その夜。':
      return '那天晚上。'
    case '優、これを見て。':
      return '优，看看这个。'
    case '兄さんの手紙？':
    case '兄さんの手紙?':
      return '哥哥的信？'
    case 'パラ…':
      return '沙啦……'
    case '七月二十日':
      return '七月二十日'
    default:
      return sourceText.trim()
  }
}

function source(path: string, fixture: LocalComicFixture): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = 'local-comic-visual-fixture'
  value.pageIndex = fixture.pageIndex
  value.imageFilePath = path
  value.imageHash = fixture.imageHash
  value.imageWidth = 1024
  value.imageHeight = 1536
  return value
}

function renderRequest(
  backend: ComicLocalVisualBackend,
  sourcePath: string,
  fixture: LocalComicFixture,
  analysis: ComicRegionAnalysisResult,
): ComicRegionRenderRequest {
  const request: ComicRegionRenderRequest = new ComicRegionRenderRequest()
  request.source = source(sourcePath, fixture)
  request.regionRevision = analysis.regionRevision
  request.document = analysis.document
  request.adapterTemplate = analysis.adapterTemplate

  const translations: ComicTranslationBatch = new ComicTranslationBatch()
  translations.projectId = request.source.projectId
  translations.pageIndex = request.source.pageIndex
  translations.sourceImageHash = request.source.imageHash
  translations.targetLanguage = 'zh-CN'
  translations.sourceProfileId = 'local-comic-test-translator'
  translations.sourceRevision = 1
  translations.modelId = 'deterministic-fixture-translator'
  translations.promptVersion = 'local-comic-fixture-v1'
  translations.contextFingerprint = CONTEXT_HASH
  translations.translationRevision = 1
  for (let index: number = 0; index < analysis.document.blocks.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = analysis.document.blocks[index].blockId
    block.translatedText = translated(analysis.document.blocks[index].sourceText)
    translations.blocks.push(block)
  }
  request.translations = translations

  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'reader-local-directional-render-v13'
  profile.sourceTreatmentProfileId = 'local-glyph-inpaint-v13'
  profile.layoutProfileId = 'local-page-typography-v13'
  profile.targetMimeType = 'image/png'
  profile.revision = 1
  request.renderProfile = profile

  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.STAGED
  identity.projectId = request.source.projectId
  identity.pageIndex = request.source.pageIndex
  identity.sourceImageHash = request.source.imageHash
  identity.sourceWidth = request.source.imageWidth
  identity.sourceHeight = request.source.imageHeight
  identity.targetLanguage = translations.targetLanguage
  identity.regionBackendId = backend.backendId()
  identity.regionProfileId = backend.profileId()
  identity.regionRevision = analysis.regionRevision
  identity.documentRevision = analysis.document.analysisRevision
  identity.translationSourceProfileId = translations.sourceProfileId
  identity.translationSourceRevision = translations.sourceRevision
  identity.translationModelId = translations.modelId
  identity.translationPromptVersion = translations.promptVersion
  identity.translationContextFingerprint = translations.contextFingerprint
  identity.glossaryRevision = translations.glossaryRevision
  identity.translationRevision = translations.translationRevision
  identity.sourceTreatmentProfileId = profile.sourceTreatmentProfileId
  identity.layoutProfileId = profile.layoutProfileId
  identity.renderBackendId = backend.backendId()
  identity.renderProfileId = profile.profileId
  identity.renderTargetMimeType = profile.targetMimeType
  identity.renderRevision = profile.revision
  request.identity = identity
  return request
}

function page01Fixture(): LocalComicFixture {
  const fixture: LocalComicFixture = new LocalComicFixture()
  fixture.pageIndex = 0
  fixture.rawFile = FIXTURE_PAGE_01_PATH
  fixture.imageHash = FIXTURE_PAGE_01_HASH
  fixture.expectedSourceVariants.push(['午後七時、雨。'])
  fixture.expectedSourceVariants.push(['月影駅 東口', '月影駅東口'])
  fixture.expectedSourceVariants.push(['ザアア…', 'ザアア・・・', 'ザアア...'])
  fixture.expectedSourceVariants.push(['優、遅かったね。', '優（ゆう）、遅かったね。'])
  fixture.expectedSourceVariants.push(['ごめん。駅で迷った。'])
  return fixture
}

function page02Fixture(): LocalComicFixture {
  const fixture: LocalComicFixture = new LocalComicFixture()
  fixture.pageIndex = 1
  fixture.rawFile = FIXTURE_PAGE_02_PATH
  fixture.imageHash = FIXTURE_PAGE_02_HASH
  fixture.expectedSourceVariants.push(['その夜。'])
  fixture.expectedSourceVariants.push(['月影駅 東口', '月影駅東口'])
  fixture.expectedSourceVariants.push(['優、これを見て。', '優（ゆう）、これを見て。'])
  fixture.expectedSourceVariants.push(['兄さんの手紙？', '兄さんの手紙?'])
  fixture.expectedSourceVariants.push(['パラ…', 'パラ・・・', 'パラ...'])
  fixture.expectedSourceVariants.push(['七月二十日'])
  return fixture
}

function reference(fixture: LocalComicFixture): ComicTranslationReferencePage {
  const page: ComicTranslationReferencePage = new ComicTranslationReferencePage()
  page.projectId = 'local-comic-visual-fixture'
  page.pageIndex = fixture.pageIndex
  page.imageHash = fixture.imageHash
  for (let index: number = 0; index < fixture.expectedSourceVariants.length; index++) {
    const block: ComicTranslationReferenceBlock = new ComicTranslationReferenceBlock()
    const variants: string[] = fixture.expectedSourceVariants[index]
    for (let variantIndex: number = 0; variantIndex < variants.length; variantIndex++) {
      block.sourceVariants.push(variants[variantIndex])
    }
    page.blocks.push(block)
  }
  return page
}

function reviewedDirection(sourceText: string, fixture: LocalComicFixture): string {
  const normalized: string = sourceText.replace(/\s+/g, '')
  if (normalized === '月影駅東口' || normalized === '七月二十日') {
    return 'horizontal-ltr'
  }
  if (normalized.startsWith('ザアア') || normalized.startsWith('パラ')) {
    return ''
  }
  for (let blockIndex: number = 0; blockIndex < fixture.expectedSourceVariants.length; blockIndex++) {
    const variants: string[] = fixture.expectedSourceVariants[blockIndex]
    for (let variantIndex: number = 0; variantIndex < variants.length; variantIndex++) {
      if (variants[variantIndex].replace(/\s+/g, '') === normalized) {
        return 'vertical-rl'
      }
    }
  }
  return ''
}

async function changedPixelPercent(sourcePath: string, renderedPath: string): Promise<number> {
  let sourceImage: image.ImageSource | undefined = undefined
  let renderedImage: image.ImageSource | undefined = undefined
  let sourceMap: image.PixelMap | undefined = undefined
  let renderedMap: image.PixelMap | undefined = undefined
  try {
    sourceImage = image.createImageSource(sourcePath)
    renderedImage = image.createImageSource(renderedPath)
    sourceMap = await sourceImage.createPixelMap({
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    })
    renderedMap = await renderedImage.createPixelMap({
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    })
    const sourceBuffer: ArrayBuffer = new ArrayBuffer(sourceMap.getPixelBytesNumber())
    const renderedBuffer: ArrayBuffer = new ArrayBuffer(renderedMap.getPixelBytesNumber())
    await sourceMap.readPixelsToBuffer(sourceBuffer)
    await renderedMap.readPixelsToBuffer(renderedBuffer)
    const sourceBytes: Uint8Array = new Uint8Array(sourceBuffer)
    const renderedBytes: Uint8Array = new Uint8Array(renderedBuffer)
    if (sourceBytes.length !== renderedBytes.length || sourceBytes.length % 4 !== 0) {
      throw new Error('Local comic comparison image dimensions are invalid')
    }
    let changed: number = 0
    const pixels: number = sourceBytes.length / 4
    for (let offset: number = 0; offset < sourceBytes.length; offset += 4) {
      const redDelta: number = Math.abs(sourceBytes[offset] - renderedBytes[offset])
      const greenDelta: number = Math.abs(sourceBytes[offset + 1] - renderedBytes[offset + 1])
      const blueDelta: number = Math.abs(sourceBytes[offset + 2] - renderedBytes[offset + 2])
      if (Math.max(redDelta, greenDelta, blueDelta) > 16) {
        changed = changed + 1
      }
    }
    return Math.round(changed * 100000 / pixels) / 1000
  } finally {
    if (renderedMap !== undefined) {
      await renderedMap.release()
    }
    if (sourceMap !== undefined) {
      await sourceMap.release()
    }
    if (renderedImage !== undefined) {
      await renderedImage.release()
    }
    if (sourceImage !== undefined) {
      await sourceImage.release()
    }
  }
}

export default function comicLocalVisualBackendTest(): void {
  describe('ComicLocalVisualBackend', () => {
    it('measures endpoint-free OCR accuracy, direction, coverage, and latency', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const ocr: HarmonyComicLocalOcrEngine = new HarmonyComicLocalOcrEngine()
        try {
          const languages: string[] = await ocr.supportedLanguages()
          expect(languages.includes('ja')).assertEqual(true)
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            ocr,
          )
          const measurements: LocalComicQualityMeasurement[] = []
          let totalExpected: number = 0
          let totalMatched: number = 0
          let totalUnexpected: number = 0
          let totalDirectionExpected: number = 0
          let totalDirectionMatched: number = 0
          const fixtures: LocalComicFixture[] = [page01Fixture(), page02Fixture()]
          for (let fixtureIndex: number = 0; fixtureIndex < fixtures.length; fixtureIndex++) {
            const fixture: LocalComicFixture = fixtures[fixtureIndex]
            const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
              fixture.rawFile,
            )
            const sourcePath: string =
              `${ability.context.cacheDir}/local-comic-visual-source-${fixture.pageIndex}.png`
            writeFile(sourcePath, bytes)
            try {
              const analysisRequest: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
              analysisRequest.source = source(sourcePath, fixture)
              analysisRequest.requestedRegionRevision = 2
              analysisRequest.requestedDocumentRevision = 2
              const pssBeforeKb: string = hidebug.getAppNativeMemInfo().pss.toString()
              const analysisStartedAt: number = Date.now()
              const analysis: ComicRegionAnalysisResult = await backend.analyze(analysisRequest)
              const analysisMs: number = Date.now() - analysisStartedAt
              const pssAfterAnalysisKb: string = hidebug.getAppNativeMemInfo().pss.toString()
              expect(analysis.document.blocks.length > 0).assertEqual(true)
              const recognized: string[] = []
              const blockGeometry: string[] = []
              let verticalBlocks: number = 0
              let horizontalBlocks: number = 0
              let directionExpected: number = 0
              let directionMatched: number = 0
              for (let index: number = 0; index < analysis.document.blocks.length; index++) {
                const block = analysis.document.blocks[index]
                recognized.push(block.sourceText)
                let left: number = Number.POSITIVE_INFINITY
                let top: number = Number.POSITIVE_INFINITY
                let right: number = Number.NEGATIVE_INFINITY
                let bottom: number = Number.NEGATIVE_INFINITY
                for (let pointIndex: number = 0; pointIndex < block.polygon.length; pointIndex++) {
                  left = Math.min(left, block.polygon[pointIndex].x)
                  top = Math.min(top, block.polygon[pointIndex].y)
                  right = Math.max(right, block.polygon[pointIndex].x)
                  bottom = Math.max(bottom, block.polygon[pointIndex].y)
                }
                blockGeometry.push(
                  `${block.styleHint}:${Math.round(left)},${Math.round(top)},` +
                    `${Math.round(right - left)},${Math.round(bottom - top)}:${block.sourceText}`,
                )
                const expectedDirection: string = reviewedDirection(block.sourceText, fixture)
                if (expectedDirection.length > 0) {
                  directionExpected = directionExpected + 1
                  if (expectedDirection === block.styleHint) {
                    directionMatched = directionMatched + 1
                  }
                }
                if (block.styleHint === 'vertical-rl') {
                  verticalBlocks = verticalBlocks + 1
                } else if (block.styleHint === 'horizontal-ltr') {
                  horizontalBlocks = horizontalBlocks + 1
                }
              }
              expect(recognized.includes('小')).assertEqual(false)
              expect(verticalBlocks > 0).assertEqual(true)
              const accuracy: ComicTranslationAccuracySnapshot = ComicTranslationEvaluator.accuracy(
                analysis.document,
                reference(fixture),
              )
              totalExpected = totalExpected + accuracy.expectedBlocks
              totalMatched = totalMatched + accuracy.matchedSourceBlocks
              totalUnexpected = totalUnexpected + accuracy.unexpectedSourceBlocks
              totalDirectionExpected = totalDirectionExpected + directionExpected
              totalDirectionMatched = totalDirectionMatched + directionMatched
              const request: ComicRegionRenderRequest = renderRequest(
                backend,
                sourcePath,
                fixture,
                analysis,
              )
              const renderStartedAt: number = Date.now()
              const page: ComicRenderedPage = await backend.render(request)
              const renderMs: number = Date.now() - renderStartedAt
              const pssAfterRenderKb: string = hidebug.getAppNativeMemInfo().pss.toString()
              ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
              expect(page.width).assertEqual(1024)
              expect(page.height).assertEqual(1536)
              expect(fileIo.accessSync(page.localFilePath)).assertEqual(true)
              const changedPercent: number = await changedPixelPercent(
                sourcePath,
                page.localFilePath,
              )
              expect(changedPercent < 5).assertEqual(true)
              const measurement: LocalComicQualityMeasurement =
                new LocalComicQualityMeasurement()
              measurement.page = fixture.pageIndex + 1
              measurement.expected = accuracy.expectedBlocks
              measurement.actual = accuracy.actualBlocks
              measurement.matched = accuracy.matchedSourceBlocks
              measurement.missing = accuracy.missingSourceBlocks
              measurement.unexpected = accuracy.unexpectedSourceBlocks
              measurement.readingOrderErrors = accuracy.readingOrderErrors
              measurement.verticalBlocks = verticalBlocks
              measurement.horizontalBlocks = horizontalBlocks
              measurement.directionExpected = directionExpected
              measurement.directionMatched = directionMatched
              measurement.analysisMs = analysisMs
              measurement.renderMs = renderMs
              measurement.changedPixelPercent = changedPercent
              measurement.pssBeforeKb = pssBeforeKb
              measurement.pssAfterAnalysisKb = pssAfterAnalysisKb
              measurement.pssAfterRenderKb = pssAfterRenderKb
              measurement.recognizedText = recognized.join('|')
              measurement.blockGeometry = blockGeometry.join('|')
              measurement.artifactPath = page.localFilePath
              measurement.artifactBytes = page.byteLength
              measurements.push(measurement)
              console.info(
                `ComicLocalVisualQuality page=${fixture.pageIndex + 1} ` +
                  `expected=${accuracy.expectedBlocks} actual=${accuracy.actualBlocks} ` +
                  `matched=${accuracy.matchedSourceBlocks} missing=${accuracy.missingSourceBlocks} ` +
                  `unexpected=${accuracy.unexpectedSourceBlocks} order=${accuracy.readingOrderErrors} ` +
                  `vertical=${verticalBlocks} horizontal=${horizontalBlocks} ` +
                  `analysisMs=${analysisMs} renderMs=${renderMs} changedPercent=${changedPercent} ` +
                  `text=${recognized.join('|')} artifact=${page.localFilePath} ` +
                  `hash=${page.artifactHash} bytes=${page.byteLength}`,
              )
            } finally {
              removeFile(sourcePath)
            }
          }
          expect(totalExpected).assertEqual(11)
          expect(totalMatched >= 9).assertEqual(true)
          expect(totalUnexpected).assertEqual(0)
          expect(totalDirectionExpected >= 9).assertEqual(true)
          expect(totalDirectionMatched).assertEqual(totalDirectionExpected)
          const reportPath: string =
            `${ability.context.cacheDir}/comic-local-quality-report.json`
          writeFile(
            reportPath,
            new util.TextEncoder().encodeInto(JSON.stringify(measurements)),
          )
        } finally {
          await ocr.release()
        }
        done()
      })
  })
}
