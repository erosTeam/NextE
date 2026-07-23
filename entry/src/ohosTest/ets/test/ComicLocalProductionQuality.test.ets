import { application, common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicNcnnLocalRegionDetector,
  ComicNcnnLocalTextMasker,
  ComicNcnnLocalTextRecognizer,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicTranslationAccuracySnapshot,
  ComicTranslationEvaluator,
  ComicTranslationModelPaths,
  ComicTranslationModelService,
  ComicTranslationReferenceBlock,
  ComicTranslationReferencePage,
  ComicTextMaskModelPaths,
  ComicTextRecognitionModelPaths,
  ComicLocalVisualBackend,
  ComicVisualPageSource,
  HarmonyComicLocalOcrEngine,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const MAIN_MODULE: string = 'entry'
const FIXTURE_WIDTH: number = 1024
const FIXTURE_HEIGHT: number = 1536

class ProductionQualityFixture {
  pageIndex: number = 0
  rawFile: string = ''
  imageHash: string = ''
  expectedSourceVariants: string[][] = []
}

function integrationEnabled(): boolean {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s comicProductionVisualQuality'] === 'true'
}

function parameter(name: string): string {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters[`-s ${name}`] ?? ''
}

function page01Fixture(): ProductionQualityFixture {
  const fixture: ProductionQualityFixture = new ProductionQualityFixture()
  fixture.pageIndex = 0
  fixture.rawFile = 'comic_translation_eval_page_01.png'
  fixture.imageHash = 'b12a64700e64a9e707152d0570a8af8c5296055226f953c769307cb59e3176a9'
  fixture.expectedSourceVariants.push(['午後七時、雨。'])
  fixture.expectedSourceVariants.push(['月影駅 東口', '月影駅東口'])
  fixture.expectedSourceVariants.push(['ザアア…', 'ザアア・・・', 'ザアア...'])
  fixture.expectedSourceVariants.push(['優、遅かったね。', '優（ゆう）、遅かったね。'])
  fixture.expectedSourceVariants.push(['ごめん。駅で迷った。'])
  return fixture
}

function page02Fixture(): ProductionQualityFixture {
  const fixture: ProductionQualityFixture = new ProductionQualityFixture()
  fixture.pageIndex = 1
  fixture.rawFile = 'comic_translation_eval_page_02.png'
  fixture.imageHash = '72ee2ef048ec6035f0ade14f7a07c9f50302f377907076fa677b95977c0c246c'
  fixture.expectedSourceVariants.push(['その夜。'])
  fixture.expectedSourceVariants.push(['月影駅 東口', '月影駅東口'])
  fixture.expectedSourceVariants.push(['優、これを見て。', '優（ゆう）、これを見て。'])
  fixture.expectedSourceVariants.push(['兄さんの手紙？', '兄さんの手紙?'])
  fixture.expectedSourceVariants.push(['パラ…', 'パラ・・・', 'パラ...'])
  fixture.expectedSourceVariants.push(['七月二十日'])
  return fixture
}

function source(path: string, fixture: ProductionQualityFixture): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = 'nexte-original-manga-eval-v1:production-models'
  value.pageIndex = fixture.pageIndex
  value.imageFilePath = path
  value.imageHash = fixture.imageHash
  value.imageWidth = FIXTURE_WIDTH
  value.imageHeight = FIXTURE_HEIGHT
  return value
}

function reference(fixture: ProductionQualityFixture): ComicTranslationReferencePage {
  const page: ComicTranslationReferencePage = new ComicTranslationReferencePage()
  page.projectId = 'nexte-original-manga-eval-v1:production-models'
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
    if (written !== bytes.byteLength) {
      throw new Error('Production quality fixture write failed')
    }
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function removeFile(path: string): void {
  try {
    if (path.length > 0 && fileIo.accessSync(path)) {
      fileIo.unlinkSync(path)
    }
  } catch (_error) {}
}

async function recognizeSystemCrop(
  ocr: HarmonyComicLocalOcrEngine,
  sourcePath: string,
  x: number,
  y: number,
  width: number,
  height: number,
): Promise<string> {
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(sourcePath)
    const scale: number = Math.min(3, Math.max(2, 512 / Math.max(width, height)))
    pixelMap = await source.createPixelMap({
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      desiredRegion: {
        x: x,
        y: y,
        size: { width: width, height: height },
      },
      desiredSize: {
        width: Math.round(width * scale),
        height: Math.round(height * scale),
      },
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
    })
    const recognized = await ocr.recognize(pixelMap)
    const texts: string[] = []
    for (let index: number = 0; index < recognized.lines.length; index++) {
      const text: string = recognized.lines[index].text.trim()
      if (text.length > 0) {
        texts.push(text)
      }
    }
    return texts.join(' ')
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      source.release()
    }
  }
}

export default function comicLocalProductionQualityTest(): void {
  describe('ComicLocalProductionQuality', (): void => {
    it('measures installed detector recognizer and CTD on owned manga fixtures', 0,
      async (): Promise<void> => {
        if (!integrationEnabled()) {
          expect(true).assertEqual(true)
          return
        }
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const mainContext: common.UIAbilityContext = await application.createModuleContext(
          ability.context,
          MAIN_MODULE,
        ) as common.UIAbilityContext
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const modelRoot: string = parameter('comicProductionModelRoot').trim()
        let detectorPaths: ComicTranslationModelPaths | null =
          ComicTranslationModelService.pathsIfReady(mainContext)
        let recognizerPaths: ComicTextRecognitionModelPaths | null =
          ComicTranslationModelService.ocrPathsIfReady(mainContext)
        let textMaskPaths: ComicTextMaskModelPaths | null =
          ComicTranslationModelService.textMaskPathsIfReady(mainContext)
        if (modelRoot.length > 0) {
          detectorPaths = new ComicTranslationModelPaths()
          detectorPaths.paramPath = `${modelRoot}/ysgyolo_1.2_OS1.0.ncnn.param`
          detectorPaths.modelPath = `${modelRoot}/ysgyolo_1.2_OS1.0.ncnn.bin`
          recognizerPaths = new ComicTextRecognitionModelPaths()
          recognizerPaths.paramPath = `${modelRoot}/ppocrv5_mobile_rec.ncnn.param`
          recognizerPaths.modelPath = `${modelRoot}/ppocrv5_mobile_rec.ncnn.bin`
          recognizerPaths.dictionaryPath = `${modelRoot}/ppocrv5_mobile_rec.dict.txt`
          textMaskPaths = new ComicTextMaskModelPaths()
          textMaskPaths.paramPath = `${modelRoot}/comic-text-mask-ctd-1024.ncnn.param`
          textMaskPaths.modelPath = `${modelRoot}/comic-text-mask-ctd-1024.ncnn.bin`
        }
        expect(detectorPaths !== null).assertEqual(true)
        expect(recognizerPaths !== null).assertEqual(true)
        expect(textMaskPaths !== null).assertEqual(true)
        if (detectorPaths === null || recognizerPaths === null || textMaskPaths === null) {
          return
        }
        const ocr: HarmonyComicLocalOcrEngine = new HarmonyComicLocalOcrEngine()
        const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
          mainContext,
          ocr,
          new ComicNcnnLocalRegionDetector(detectorPaths.paramPath, detectorPaths.modelPath),
          new ComicNcnnLocalTextRecognizer(
            recognizerPaths.paramPath,
            recognizerPaths.modelPath,
            recognizerPaths.dictionaryPath,
          ),
          null,
          null,
          new ComicNcnnLocalTextMasker(
            textMaskPaths.paramPath,
            textMaskPaths.modelPath,
            0.15,
            4,
            0.3,
          ),
        )
        const fixtures: ProductionQualityFixture[] = [page01Fixture(), page02Fixture()]
        let totalExpected: number = 0
        let totalMatched: number = 0
        let totalUnexpected: number = 0
        try {
          for (let fixtureIndex: number = 0; fixtureIndex < fixtures.length; fixtureIndex++) {
            const fixture: ProductionQualityFixture = fixtures[fixtureIndex]
            const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
              fixture.rawFile,
            )
            const sourcePath: string =
              `${ability.context.cacheDir}/comic-production-quality-${fixture.pageIndex}.png`
            writeFile(sourcePath, bytes)
            try {
              const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
              request.source = source(sourcePath, fixture)
              request.requestedRegionRevision = 2
              request.requestedDocumentRevision = 2
              const startedAt: number = Date.now()
              const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
              const accuracy: ComicTranslationAccuracySnapshot =
                ComicTranslationEvaluator.accuracy(analysis.document, reference(fixture))
              totalExpected = totalExpected + accuracy.expectedBlocks
              totalMatched = totalMatched + accuracy.matchedSourceBlocks
              totalUnexpected = totalUnexpected + accuracy.unexpectedSourceBlocks
              const recognized: string[] = []
              for (let blockIndex: number = 0;
                blockIndex < analysis.document.blocks.length;
                blockIndex++) {
                recognized.push(analysis.document.blocks[blockIndex].sourceText)
              }
              console.info(
                `ComicProductionVisualQuality page=${fixture.pageIndex + 1} ` +
                  `expected=${accuracy.expectedBlocks} actual=${accuracy.actualBlocks} ` +
                  `matched=${accuracy.matchedSourceBlocks} missing=${accuracy.missingSourceBlocks} ` +
                  `unexpected=${accuracy.unexpectedSourceBlocks} ` +
                  `analysisMs=${Date.now() - startedAt} text=${recognized.join('|')}`,
              )
              const artworkText: string = fixture.pageIndex === 0 ?
                await recognizeSystemCrop(ocr, sourcePath, 232, 36, 192, 388) :
                await recognizeSystemCrop(ocr, sourcePath, 100, 1092, 152, 92)
              console.info(
                `ComicProductionArtworkProbe page=${fixture.pageIndex + 1} ` +
                  `text=${artworkText}`,
              )
            } finally {
              removeFile(sourcePath)
            }
          }
          console.info(
            `ComicProductionVisualQuality total expected=${totalExpected} ` +
              `matched=${totalMatched} unexpected=${totalUnexpected}`,
          )
          expect(totalExpected).assertEqual(11)
          expect(totalMatched >= 9).assertEqual(true)
          expect(totalUnexpected).assertEqual(0)
        } finally {
          await ocr.release()
        }
      })
  })
}
