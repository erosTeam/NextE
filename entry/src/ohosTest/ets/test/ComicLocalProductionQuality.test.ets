import { application, common } from '@kit.AbilityKit'
import { thermal } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicBlockTranslation,
  ComicNcnnLocalRegionDetector,
  ComicNcnnLocalSourceInpainter,
  ComicNcnnLocalTextMasker,
  ComicNcnnLocalTextRecognizer,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicRegionRenderRequest,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicSourceInpaintingModelPaths,
  ComicTranslationBatch,
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
  ComicVisualTranslationContract,
  ComicVisualTranslationRoute,
  DiagnosticLogger,
  HarmonyComicLocalOcrEngine,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const MAIN_MODULE: string = 'entry'
const FIXTURE_WIDTH: number = 1024
const FIXTURE_HEIGHT: number = 1536
const LONG_FIXTURE_HEIGHT: number = FIXTURE_HEIGHT * 2
const CONTEXT_HASH: string =
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
const LONG_FIXTURE_HASH: string =
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

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

function benchmarkIterations(): number {
  const configured: number = Number.parseInt(parameter('comicProductionPipelineIterations'), 10)
  if (!Number.isFinite(configured)) {
    return 1
  }
  return Math.max(1, Math.min(5, Math.floor(configured)))
}

function keepArtifacts(): boolean {
  return parameter('comicProductionKeepArtifacts') === 'true'
}

function heavyModelThreads(): number {
  return parameter('comicProductionHeavyThreads') === '2' ? 2 : 4
}

function percentile(values: number[], percentileValue: number): number {
  if (values.length <= 0) {
    return 0
  }
  const sorted: number[] = values.slice().sort((left: number, right: number): number => left - right)
  const index: number = Math.max(
    0,
    Math.min(sorted.length - 1, Math.ceil(sorted.length * percentileValue) - 1),
  )
  return sorted[index]
}

function diagnosticEventMessage(eventName: string): string {
  const lines: string[] = DiagnosticLogger.exportBufferedText().split('\n')
  const marker: string = `comic-translation.${eventName}`
  for (let index: number = 0; index < lines.length; index++) {
    const markerIndex: number = lines[index].indexOf(marker)
    if (markerIndex < 0) {
      continue
    }
    return lines[index].substring(markerIndex + marker.length).trim()
  }
  return 'missing'
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

function source(
  path: string,
  fixture: ProductionQualityFixture,
  width: number = FIXTURE_WIDTH,
  height: number = FIXTURE_HEIGHT,
): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = 'nexte-original-manga-eval-v1:production-models'
  value.pageIndex = fixture.pageIndex
  value.imageFilePath = path
  value.imageHash = fixture.imageHash
  value.imageWidth = width
  value.imageHeight = height
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

function translated(sourceText: string): string {
  switch (sourceText.trim()) {
    case '午後七時、雨。':
      return '晚上七点，雨。'
    case '月影駅 東口':
    case '月影駅東口':
      return '月影站 东口'
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

function renderRequest(
  backend: ComicLocalVisualBackend,
  pageSource: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  revision: number,
): ComicRegionRenderRequest {
  const request: ComicRegionRenderRequest = new ComicRegionRenderRequest()
  request.source = pageSource
  request.regionRevision = analysis.regionRevision
  request.document = analysis.document
  request.adapterTemplate = analysis.adapterTemplate

  const translations: ComicTranslationBatch = new ComicTranslationBatch()
  translations.projectId = pageSource.projectId
  translations.pageIndex = pageSource.pageIndex
  translations.sourceImageHash = pageSource.imageHash
  translations.targetLanguage = 'zh-CN'
  translations.sourceProfileId = 'production-pipeline-benchmark'
  translations.sourceRevision = 1
  translations.modelId = 'deterministic-fixture-translator'
  translations.promptVersion = 'production-pipeline-v1'
  translations.contextFingerprint = CONTEXT_HASH
  translations.translationRevision = revision
  for (let index: number = 0; index < analysis.document.blocks.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = analysis.document.blocks[index].blockId
    block.translatedText = translated(analysis.document.blocks[index].sourceText)
    translations.blocks.push(block)
  }
  request.translations = translations

  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'reader-local-bubble-layout-v30'
  profile.sourceTreatmentProfileId = 'local-glyph-inpaint-v30'
  profile.layoutProfileId = 'local-bubble-typography-v30'
  profile.targetMimeType = 'image/png'
  profile.revision = 8
  request.renderProfile = profile

  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.STAGED
  identity.projectId = pageSource.projectId
  identity.pageIndex = pageSource.pageIndex
  identity.sourceImageHash = pageSource.imageHash
  identity.sourceWidth = pageSource.imageWidth
  identity.sourceHeight = pageSource.imageHeight
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

async function writeStackedImage(path: string, sourcePaths: string[]): Promise<void> {
  const rowBytes: number = FIXTURE_WIDTH * 4
  const outputBuffer: ArrayBuffer = new ArrayBuffer(rowBytes * LONG_FIXTURE_HEIGHT)
  const outputPixels: Uint8Array = new Uint8Array(outputBuffer)
  for (let sourceIndex: number = 0; sourceIndex < sourcePaths.length; sourceIndex++) {
    let sourceImage: image.ImageSource | undefined = undefined
    let sourcePixelMap: image.PixelMap | undefined = undefined
    try {
      sourceImage = image.createImageSource(sourcePaths[sourceIndex])
      sourcePixelMap = await sourceImage.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const info: image.ImageInfo = await sourcePixelMap.getImageInfo()
      const sourceStride: number = Math.max(rowBytes, Math.floor(info.stride))
      const sourceBuffer: ArrayBuffer = new ArrayBuffer(sourcePixelMap.getPixelBytesNumber())
      await sourcePixelMap.readPixelsToBuffer(sourceBuffer)
      const sourcePixels: Uint8Array = new Uint8Array(sourceBuffer)
      for (let y: number = 0; y < FIXTURE_HEIGHT; y++) {
        const sourceOffset: number = y * sourceStride
        const targetOffset: number = (sourceIndex * FIXTURE_HEIGHT + y) * rowBytes
        outputPixels.set(
          sourcePixels.subarray(sourceOffset, sourceOffset + rowBytes),
          targetOffset,
        )
      }
    } finally {
      if (sourcePixelMap !== undefined) {
        await sourcePixelMap.release()
      }
      if (sourceImage !== undefined) {
        sourceImage.release()
      }
    }
  }
  let outputPixelMap: image.PixelMap | undefined = undefined
  let packer: image.ImagePacker | undefined = undefined
  let outputFile: fileIo.File | null = null
  try {
    outputPixelMap = await image.createPixelMap(outputBuffer, {
      size: { width: FIXTURE_WIDTH, height: LONG_FIXTURE_HEIGHT },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false,
    })
    outputFile = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    packer = image.createImagePacker()
    await packer.packToFile(outputPixelMap, outputFile.fd, { format: 'image/png', quality: 100 })
  } finally {
    if (outputFile !== null) {
      fileIo.closeSync(outputFile)
    }
    if (packer !== undefined) {
      await packer.release()
    }
    if (outputPixelMap !== undefined) {
      await outputPixelMap.release()
    }
  }
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
    it('measures the complete production visual pipeline on owned manga fixtures', 0,
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
        if (modelRoot.length <= 0 &&
          parameter('comicProductionInstallModels') === 'true') {
          await ComicTranslationModelService.install(mainContext)
        }
        let detectorPaths: ComicTranslationModelPaths | null =
          ComicTranslationModelService.pathsIfReady(mainContext)
        let recognizerPaths: ComicTextRecognitionModelPaths | null =
          ComicTranslationModelService.ocrPathsIfReady(mainContext)
        let textMaskPaths: ComicTextMaskModelPaths | null =
          ComicTranslationModelService.textMaskPathsIfReady(mainContext)
        let inpaintingPaths: ComicSourceInpaintingModelPaths | null =
          ComicTranslationModelService.inpaintingPathsIfReady(mainContext)
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
          inpaintingPaths = new ComicSourceInpaintingModelPaths()
          inpaintingPaths.paramPath = `${modelRoot}/aot-manga-inpainting-256.ncnn.param`
          inpaintingPaths.modelPath = `${modelRoot}/aot-manga-inpainting-256.ncnn.bin`
        }
        expect(detectorPaths !== null).assertEqual(true)
        expect(recognizerPaths !== null).assertEqual(true)
        expect(textMaskPaths !== null).assertEqual(true)
        expect(inpaintingPaths !== null).assertEqual(true)
        if (detectorPaths === null || recognizerPaths === null || textMaskPaths === null ||
          inpaintingPaths === null) {
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
          new ComicNcnnLocalSourceInpainter(
            inpaintingPaths.paramPath,
            inpaintingPaths.modelPath,
            heavyModelThreads(),
          ),
          new ComicNcnnLocalTextMasker(
            textMaskPaths.paramPath,
            textMaskPaths.modelPath,
            0.3,
            heavyModelThreads(),
          ),
          new ComicNcnnLocalTextMasker(
            textMaskPaths.paramPath,
            textMaskPaths.modelPath,
            0.15,
            heavyModelThreads(),
            0.3,
          ),
        )
        const fixtures: ProductionQualityFixture[] = [page01Fixture(), page02Fixture()]
        let totalExpected: number = 0
        let totalMatched: number = 0
        let totalUnexpected: number = 0
        const analysisSamples: number[] = []
        const renderSamples: number[] = []
        const pssSamples: number[] = [Number(hidebug.getAppNativeMemInfo().pss)]
        const thermalSamples: thermal.ThermalLevel[] = [thermal.getLevel()]
        const stageSnapshots: string[] = []
        const sourcePaths: string[] = []
        const renderedPaths: string[] = []
        const longSourcePath: string =
          `${ability.context.cacheDir}/comic-production-quality-long.png`
        let longRenderedPath: string = ''
        try {
          for (let fixtureIndex: number = 0; fixtureIndex < fixtures.length; fixtureIndex++) {
            const fixture: ProductionQualityFixture = fixtures[fixtureIndex]
            const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
              fixture.rawFile,
            )
            const sourcePath: string =
              `${ability.context.cacheDir}/comic-production-quality-${fixture.pageIndex}.png`
            writeFile(sourcePath, bytes)
            sourcePaths.push(sourcePath)
            for (let iteration: number = 0; iteration < benchmarkIterations(); iteration++) {
              DiagnosticLogger.clear()
              const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
              request.source = source(sourcePath, fixture)
              request.requestedRegionRevision = 2
              request.requestedDocumentRevision = 2
              const analysisStartedAt: number = Date.now()
              const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
              const analysisMs: number = Date.now() - analysisStartedAt
              analysisSamples.push(analysisMs)
              const productionSource: ComicVisualPageSource = source(sourcePath, fixture)
              const productionRenderRequest: ComicRegionRenderRequest = renderRequest(
                backend,
                productionSource,
                analysis,
                fixtureIndex * benchmarkIterations() + iteration + 1,
              )
              const renderStartedAt: number = Date.now()
              const rendered: ComicRenderedPage = await backend.render(productionRenderRequest)
              const renderMs: number = Date.now() - renderStartedAt
              renderSamples.push(renderMs)
              ComicVisualTranslationContract.validateRenderedPage(
                productionRenderRequest.identity,
                rendered,
              )
              expect(rendered.width).assertEqual(FIXTURE_WIDTH)
              expect(rendered.height).assertEqual(FIXTURE_HEIGHT)
              expect(rendered.byteLength > 0).assertEqual(true)
              pssSamples.push(Number(hidebug.getAppNativeMemInfo().pss))
              thermalSamples.push(thermal.getLevel())
              console.info(
                `ComicProductionPipeline page=${fixture.pageIndex + 1} ` +
                  `iteration=${iteration + 1}/${benchmarkIterations()} ` +
                  `blocks=${analysis.document.blocks.length} analysisMs=${analysisMs} ` +
                  `renderMs=${renderMs} bytes=${rendered.byteLength} ` +
                  `pssKb=${pssSamples[pssSamples.length - 1]} ` +
                  `thermal=${thermalSamples[thermalSamples.length - 1]} ` +
                  `artifact=${rendered.localFilePath}`,
              )
              stageSnapshots.push(
                `p${fixture.pageIndex + 1}i${iteration + 1} ` +
                  `analysis{${diagnosticEventMessage('local_analysis_stage_timings')}} ` +
                  `render{${diagnosticEventMessage('local_render_stage_timings')}}`,
              )
              if (keepArtifacts()) {
                renderedPaths.push(rendered.localFilePath)
              } else {
                removeFile(rendered.localFilePath)
              }
              if (iteration === 0) {
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
                    `matched=${accuracy.matchedSourceBlocks} ` +
                    `missing=${accuracy.missingSourceBlocks} ` +
                    `unexpected=${accuracy.unexpectedSourceBlocks} ` +
                    `text=${recognized.join('|')}`,
                )
                const artworkText: string = fixture.pageIndex === 0 ?
                  await recognizeSystemCrop(ocr, sourcePath, 232, 36, 192, 388) :
                  await recognizeSystemCrop(ocr, sourcePath, 100, 1092, 152, 92)
                console.info(
                  `ComicProductionArtworkProbe page=${fixture.pageIndex + 1} ` +
                    `text=${artworkText}`,
                )
              }
            }
          }
          await writeStackedImage(longSourcePath, sourcePaths)
          const longFixture: ProductionQualityFixture = new ProductionQualityFixture()
          longFixture.pageIndex = 2
          longFixture.imageHash = LONG_FIXTURE_HASH
          const longPageSource: ComicVisualPageSource = source(
            longSourcePath,
            longFixture,
            FIXTURE_WIDTH,
            LONG_FIXTURE_HEIGHT,
          )
          const longAnalysisRequest: ComicRegionAnalysisRequest =
            new ComicRegionAnalysisRequest()
          longAnalysisRequest.source = longPageSource
          longAnalysisRequest.requestedRegionRevision = 2
          longAnalysisRequest.requestedDocumentRevision = 2
          DiagnosticLogger.clear()
          const longAnalysisStartedAt: number = Date.now()
          const longAnalysis: ComicRegionAnalysisResult =
            await backend.analyze(longAnalysisRequest)
          const longAnalysisMs: number = Date.now() - longAnalysisStartedAt
          expect(longAnalysis.document.blocks.length > 0).assertEqual(true)
          const longRenderRequest: ComicRegionRenderRequest = renderRequest(
            backend,
            longPageSource,
            longAnalysis,
            fixtures.length * benchmarkIterations() + 1,
          )
          const longRenderStartedAt: number = Date.now()
          const longRendered: ComicRenderedPage = await backend.render(longRenderRequest)
          const longRenderMs: number = Date.now() - longRenderStartedAt
          longRenderedPath = longRendered.localFilePath
          ComicVisualTranslationContract.validateRenderedPage(
            longRenderRequest.identity,
            longRendered,
          )
          expect(longRendered.width).assertEqual(FIXTURE_WIDTH)
          expect(longRendered.height).assertEqual(LONG_FIXTURE_HEIGHT)
          pssSamples.push(Number(hidebug.getAppNativeMemInfo().pss))
          thermalSamples.push(thermal.getLevel())
          console.info(
            `ComicProductionPipeline long=controlled-stacked-2x ` +
              `dimensions=${FIXTURE_WIDTH}x${LONG_FIXTURE_HEIGHT} ` +
              `blocks=${longAnalysis.document.blocks.length} ` +
              `analysisMs=${longAnalysisMs} renderMs=${longRenderMs} ` +
              `bytes=${longRendered.byteLength} pssKb=${pssSamples[pssSamples.length - 1]} ` +
              `thermal=${thermalSamples[thermalSamples.length - 1]} ` +
              `artifact=${longRendered.localFilePath}`,
          )
          stageSnapshots.push(
            `long analysis{${diagnosticEventMessage('local_analysis_stage_timings')}} ` +
              `render{${diagnosticEventMessage('local_render_stage_timings')}}`,
          )
          console.info(
            `ComicProductionVisualQuality total expected=${totalExpected} ` +
              `matched=${totalMatched} unexpected=${totalUnexpected}`,
          )
          console.info(
            `ComicProductionPipeline normalSamples=${analysisSamples.length} ` +
              `heavyThreads=${heavyModelThreads()} ` +
              `analysisP50=${percentile(analysisSamples, 0.5)}ms ` +
              `analysisP95=${percentile(analysisSamples, 0.95)}ms ` +
              `renderP50=${percentile(renderSamples, 0.5)}ms ` +
              `renderP95=${percentile(renderSamples, 0.95)}ms ` +
              `pssSeriesKb=${pssSamples.join(',')} ` +
              `thermalSeries=${thermalSamples.join(',')}`,
          )
          console.info(`ComicProductionPipeline stages=${stageSnapshots.join(' || ')}`)
          expect(totalExpected).assertEqual(11)
          expect(totalMatched >= 9).assertEqual(true)
          expect(totalUnexpected).assertEqual(0)
        } finally {
          if (!keepArtifacts()) {
            removeFile(longRenderedPath)
          }
          removeFile(longSourcePath)
          for (let sourceIndex: number = 0; sourceIndex < sourcePaths.length; sourceIndex++) {
            removeFile(sourcePaths[sourceIndex])
          }
          if (!keepArtifacts()) {
            for (let renderedIndex: number = 0;
              renderedIndex < renderedPaths.length; renderedIndex++) {
              removeFile(renderedPaths[renderedIndex])
            }
          }
          await ocr.release()
        }
      })
  })
}
