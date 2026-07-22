import { application, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicBlockTranslation,
  ComicLocalOcrEngine,
  ComicLocalOcrLine,
  ComicLocalOcrPoint,
  ComicLocalOcrResult,
  ComicLocalRegionDetector,
  ComicLocalTextRecognizer,
  ComicLocalVisualBackend,
  ComicNativeDetectedRegion,
  ComicNativeRegionDetectionResult,
  ComicNativeRegionPoint,
  ComicNativeTextRecognitionResult,
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
  ComicTranslationModelService,
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
const TALL_FIXTURE_HASH: string =
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
const TALL_FIXTURE_WIDTH: number = 720
const TALL_FIXTURE_HEIGHT: number = 4608
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

class BubbleGroupingOcrEngine implements ComicLocalOcrEngine {
  engineId(): string {
    return 'bubble-grouping-fixture'
  }

  revision(): number {
    return 1
  }

  supportedLanguages(): Promise<string[]> {
    return Promise.resolve(['ja'])
  }

  recognize(_pixelMap: image.PixelMap): Promise<ComicLocalOcrResult> {
    const result: ComicLocalOcrResult = new ComicLocalOcrResult()
    result.lines.push(this.line('はい。', 0, 560, 1126, 594, 1196))
    result.lines.push(this.line('洗うから後ろ向いて。', 1, 529, 1127, 564, 1368))
    result.lines.push(this.line('本日は、', 2, 118, 234, 239, 292))
    result.lines.push(this.line('洗い日です', 3, 129, 283, 294, 339))
    return Promise.resolve(result)
  }

  private line(
    text: string,
    blockIndex: number,
    left: number,
    top: number,
    right: number,
    bottom: number,
  ): ComicLocalOcrLine {
    const line: ComicLocalOcrLine = new ComicLocalOcrLine()
    line.text = text
    line.blockIndex = blockIndex
    line.lineIndex = 0
    line.polygon.push(new ComicLocalOcrPoint(left, top))
    line.polygon.push(new ComicLocalOcrPoint(right, top))
    line.polygon.push(new ComicLocalOcrPoint(right, bottom))
    line.polygon.push(new ComicLocalOcrPoint(left, bottom))
    return line
  }
}

class BubbleGroupingRegionDetector implements ComicLocalRegionDetector {
  profileId(): string {
    return 'fixture-region-detector'
  }

  revision(): number {
    return 1
  }

  detect(_pixelMap: image.PixelMap): Promise<ComicNativeRegionDetectionResult> {
    const result: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
    result.backend = 'fixture'
    result.regions.push(this.region(96, 210, 320, 360))
    result.regions.push(this.region(500, 1090, 620, 1390))
    return Promise.resolve(result)
  }

  private region(
    left: number,
    top: number,
    right: number,
    bottom: number,
  ): ComicNativeDetectedRegion {
    const region: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
    region.score = 0.9
    region.classId = 0
    region.label = 'balloon'
    region.points.push(new ComicNativeRegionPoint(left, top))
    region.points.push(new ComicNativeRegionPoint(right, top))
    region.points.push(new ComicNativeRegionPoint(right, bottom))
    region.points.push(new ComicNativeRegionPoint(left, bottom))
    return region
  }
}

class UnmatchedShortOcrEngine implements ComicLocalOcrEngine {
  engineId(): string {
    return 'unmatched-short-text-fixture'
  }

  revision(): number {
    return 1
  }

  supportedLanguages(): Promise<string[]> {
    return Promise.resolve(['ja'])
  }

  recognize(_pixelMap: image.PixelMap): Promise<ComicLocalOcrResult> {
    const result: ComicLocalOcrResult = new ComicLocalOcrResult()
    const dialogue: ComicLocalOcrLine = new ComicLocalOcrLine()
    dialogue.text = '本日は洗い日です'
    dialogue.blockIndex = 0
    dialogue.polygon.push(new ComicLocalOcrPoint(118, 234))
    dialogue.polygon.push(new ComicLocalOcrPoint(294, 234))
    dialogue.polygon.push(new ComicLocalOcrPoint(294, 339))
    dialogue.polygon.push(new ComicLocalOcrPoint(118, 339))
    result.lines.push(dialogue)
    const sfx: ComicLocalOcrLine = new ComicLocalOcrLine()
    sfx.text = 'パッ'
    sfx.blockIndex = 1
    sfx.polygon.push(new ComicLocalOcrPoint(760, 800))
    sfx.polygon.push(new ComicLocalOcrPoint(820, 800))
    sfx.polygon.push(new ComicLocalOcrPoint(820, 880))
    sfx.polygon.push(new ComicLocalOcrPoint(760, 880))
    result.lines.push(sfx)
    return Promise.resolve(result)
  }
}

class AdjacentColumnOcrEngine implements ComicLocalOcrEngine {
  engineId(): string {
    return 'adjacent-column-ocr-fixture'
  }

  revision(): number {
    return 1
  }

  supportedLanguages(): Promise<string[]> {
    return Promise.resolve(['ja'])
  }

  recognize(_pixelMap: image.PixelMap): Promise<ComicLocalOcrResult> {
    const result: ComicLocalOcrResult = new ComicLocalOcrResult()
    result.lines.push(this.line('右の列です', 0, 300, 220, 340, 420))
    result.lines.push(this.line('左の列です', 1, 245, 225, 285, 415))
    return Promise.resolve(result)
  }

  private line(
    text: string,
    blockIndex: number,
    left: number,
    top: number,
    right: number,
    bottom: number,
  ): ComicLocalOcrLine {
    const line: ComicLocalOcrLine = new ComicLocalOcrLine()
    line.text = text
    line.blockIndex = blockIndex
    line.polygon.push(new ComicLocalOcrPoint(left, top))
    line.polygon.push(new ComicLocalOcrPoint(right, top))
    line.polygon.push(new ComicLocalOcrPoint(right, bottom))
    line.polygon.push(new ComicLocalOcrPoint(left, bottom))
    return line
  }
}

class AdjacentColumnRegionDetector implements ComicLocalRegionDetector {
  profileId(): string {
    return 'adjacent-column-region-fixture'
  }

  revision(): number {
    return 1
  }

  detect(_pixelMap: image.PixelMap): Promise<ComicNativeRegionDetectionResult> {
    const result: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
    result.backend = 'fixture'
    result.regions.push(this.region(292, 200, 350, 440))
    result.regions.push(this.region(232, 205, 290, 435))
    return Promise.resolve(result)
  }

  private region(
    left: number,
    top: number,
    right: number,
    bottom: number,
  ): ComicNativeDetectedRegion {
    const region: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
    region.score = 0.95
    region.classId = 0
    region.label = 'text'
    region.points.push(new ComicNativeRegionPoint(left, top))
    region.points.push(new ComicNativeRegionPoint(right, top))
    region.points.push(new ComicNativeRegionPoint(right, bottom))
    region.points.push(new ComicNativeRegionPoint(left, bottom))
    return region
  }
}

class EmptyFixtureOcrEngine implements ComicLocalOcrEngine {
  engineId(): string {
    return 'empty-ocr-fixture'
  }

  revision(): number {
    return 1
  }

  supportedLanguages(): Promise<string[]> {
    return Promise.resolve(['ja'])
  }

  recognize(_pixelMap: image.PixelMap): Promise<ComicLocalOcrResult> {
    return Promise.resolve(new ComicLocalOcrResult())
  }
}

class MissedTextRegionDetector implements ComicLocalRegionDetector {
  profileId(): string {
    return 'missed-text-region-fixture'
  }

  revision(): number {
    return 1
  }

  detect(_pixelMap: image.PixelMap): Promise<ComicNativeRegionDetectionResult> {
    const result: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
    result.backend = 'fixture'
    const region: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
    region.score = 0.95
    region.classId = 0
    region.label = 'balloon'
    region.points.push(new ComicNativeRegionPoint(595, 188))
    region.points.push(new ComicNativeRegionPoint(875, 188))
    region.points.push(new ComicNativeRegionPoint(875, 278))
    region.points.push(new ComicNativeRegionPoint(595, 278))
    result.regions.push(region)
    return Promise.resolve(result)
  }
}

class TiledFixtureRegionDetector implements ComicLocalRegionDetector {
  callCount: number = 0
  observedWidths: number[] = []
  observedHeights: number[] = []

  profileId(): string {
    return 'tiled-region-detector-fixture'
  }

  revision(): number {
    return 1
  }

  async detect(pixelMap: image.PixelMap): Promise<ComicNativeRegionDetectionResult> {
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const callIndex: number = this.callCount
    this.callCount = this.callCount + 1
    this.observedWidths.push(Math.floor(info.size.width))
    this.observedHeights.push(Math.floor(info.size.height))
    const result: ComicNativeRegionDetectionResult = new ComicNativeRegionDetectionResult()
    result.backend = 'fixture'
    if (callIndex === 0) {
      result.regions.push(this.region(100, 1800, 300, 1900, 0.95))
    } else if (callIndex === 1) {
      result.regions.push(this.region(100, 8, 300, 108, 0.90))
      result.regions.push(this.region(350, 300, 600, 450, 0.94))
    } else {
      result.regions.push(this.region(50, 100, 250, 250, 0.93))
    }
    return result
  }

  private region(
    left: number,
    top: number,
    right: number,
    bottom: number,
    score: number,
  ): ComicNativeDetectedRegion {
    const region: ComicNativeDetectedRegion = new ComicNativeDetectedRegion()
    region.score = score
    region.classId = 0
    region.label = 'balloon'
    region.points.push(new ComicNativeRegionPoint(left, top))
    region.points.push(new ComicNativeRegionPoint(right, top))
    region.points.push(new ComicNativeRegionPoint(right, bottom))
    region.points.push(new ComicNativeRegionPoint(left, bottom))
    return region
  }
}

class FixtureTextRecognizer implements ComicLocalTextRecognizer {
  profileId(): string {
    return 'text-recognizer-fixture'
  }

  revision(): number {
    return 1
  }

  recognize(
    _pixelMap: image.PixelMap,
    _rotateCounterClockwise: boolean,
  ): Promise<ComicNativeTextRecognitionResult> {
    const result: ComicNativeTextRecognitionResult = new ComicNativeTextRecognitionResult()
    result.backend = 'fixture'
    result.text = '月影駅東口'
    result.score = 0.94
    return Promise.resolve(result)
  }
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

async function writeSolidImage(path: string, width: number, height: number): Promise<void> {
  let pixelMap: image.PixelMap | undefined = undefined
  let packer: image.ImagePacker | undefined = undefined
  let outputFile: fileIo.File | null = null
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4)
    new Uint8Array(buffer).fill(255)
    pixelMap = await image.createPixelMap(buffer, {
      size: { width: width, height: height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false,
    })
    outputFile = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    packer = image.createImagePacker()
    await packer.packToFile(pixelMap, outputFile.fd, { format: 'image/png', quality: 100 })
  } finally {
    if (outputFile !== null) {
      fileIo.closeSync(outputFile)
    }
    if (packer !== undefined) {
      await packer.release()
    }
    if (pixelMap !== undefined) {
      await pixelMap.release()
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

function sourceWithDimensions(
  path: string,
  width: number,
  height: number,
): ComicVisualPageSource {
  const value: ComicVisualPageSource = new ComicVisualPageSource()
  value.projectId = 'local-comic-tall-fixture'
  value.pageIndex = 2
  value.imageFilePath = path
  value.imageHash = TALL_FIXTURE_HASH
  value.imageWidth = width
  value.imageHeight = height
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
  profile.profileId = 'reader-local-bubble-layout-v19'
  profile.sourceTreatmentProfileId = 'local-glyph-inpaint-v19'
  profile.layoutProfileId = 'local-bubble-typography-v19'
  profile.targetMimeType = 'image/png'
  profile.revision = 7
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
    it('exposes component licenses for the local manga model pack', 0, () => {
      expect(ComicTranslationModelService.displayName()).assertEqual(
        'YSGYolo + CTD + PP-OCRv5 + AOT',
      )
      expect(ComicTranslationModelService.detectorLicense()).assertEqual('AGPL-3.0-only')
      expect(ComicTranslationModelService.textRecognizerLicense()).assertEqual('Apache-2.0')
      expect(ComicTranslationModelService.sourceInpainterLicense()).assertEqual('GPL-3.0-only')
      expect(ComicTranslationModelService.textMaskLicense()).assertEqual('GPL-3.0-only')
      expect(ComicTranslationModelService.downloadBytes()).assertEqual(82836670)
    })

    it('keeps CJK targets vertical but renders Latin targets horizontally', 0, () => {
      expect(ComicLocalVisualBackend.targetUsesVerticalLayout('zh-CN')).assertEqual(true)
      expect(ComicLocalVisualBackend.targetUsesVerticalLayout('zh-TW')).assertEqual(true)
      expect(ComicLocalVisualBackend.targetUsesVerticalLayout('ja')).assertEqual(true)
      expect(ComicLocalVisualBackend.targetUsesVerticalLayout('en')).assertEqual(false)
      expect(ComicLocalVisualBackend.targetUsesVerticalLayout('de-DE')).assertEqual(false)
    })

    it('keeps the visible comic outline near one normal glyph stroke', 0, () => {
      expect(ComicLocalVisualBackend.outlineWidth(8)).assertEqual(2)
      expect(ComicLocalVisualBackend.outlineWidth(20)).assertEqual(4)
      expect(ComicLocalVisualBackend.outlineWidth(60)).assertEqual(10)
    })

    it('groups split OCR lines into one vertical or horizontal bubble block', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PAGE_01_PATH,
        )
        const sourcePath: string = `${ability.context.cacheDir}/bubble-grouping-source.png`
        writeFile(sourcePath, bytes)
        try {
          const fixture: LocalComicFixture = page01Fixture()
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            new BubbleGroupingOcrEngine(),
          )
          const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          request.source = source(sourcePath, fixture)
          request.requestedRegionRevision = 2
          request.requestedDocumentRevision = 2
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(analysis.document.blocks.length).assertEqual(2)
          expect(analysis.document.blocks[0].sourceText).assertEqual('本日は、\n洗い日です')
          expect(analysis.document.blocks[0].styleHint).assertEqual('horizontal-ltr')
          expect(analysis.document.blocks[1].sourceText).assertEqual('はい。洗うから後ろ向いて。')
          expect(analysis.document.blocks[1].styleHint).assertEqual('vertical-rl')
        } finally {
          removeFile(sourcePath)
        }
        done()
      })

    it('uses an optional manga detector without changing the OCR fallback contract', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PAGE_01_PATH,
        )
        const sourcePath: string = `${ability.context.cacheDir}/detector-grouping-source.png`
        writeFile(sourcePath, bytes)
        try {
          const fixture: LocalComicFixture = page01Fixture()
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            new BubbleGroupingOcrEngine(),
            new BubbleGroupingRegionDetector(),
          )
          const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          request.source = source(sourcePath, fixture)
          request.requestedRegionRevision = 2
          request.requestedDocumentRevision = 2
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(backend.profileId().includes('fixture-region-detector')).assertEqual(true)
          expect(backend.protocolRevision()).assertEqual(20)
          expect(analysis.document.blocks.length).assertEqual(2)
          expect(analysis.document.blocks[0].polygon[0].x).assertEqual(96)
          expect(analysis.document.blocks[0].polygon[0].y).assertEqual(210)
          expect(analysis.document.blocks[0].polygon[2].x).assertEqual(320)
          expect(analysis.document.blocks[0].polygon[2].y).assertEqual(360)
          expect(analysis.document.blocks[1].polygon[0].x).assertEqual(500)
          expect(analysis.document.blocks[1].polygon[0].y).assertEqual(1090)
          expect(analysis.document.blocks[1].polygon[2].x).assertEqual(620)
          expect(analysis.document.blocks[1].polygon[2].y).assertEqual(1390)
          expect(analysis.document.qualitySignals.some((signal) =>
            signal.code === 'local_manga_region_detector_active')).assertEqual(true)
        } finally {
          removeFile(sourcePath)
        }
        done()
      })

    it('uses detector geometry and drops unmatched short OCR fragments', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PAGE_01_PATH,
        )
        const sourcePath: string = `${ability.context.cacheDir}/detector-layout-source.png`
        writeFile(sourcePath, bytes)
        try {
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            new UnmatchedShortOcrEngine(),
            new BubbleGroupingRegionDetector(),
          )
          const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          request.source = source(sourcePath, page01Fixture())
          request.requestedRegionRevision = 2
          request.requestedDocumentRevision = 2
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(analysis.document.blocks.length).assertEqual(1)
          expect(analysis.document.blocks[0].sourceText).assertEqual('本日は洗い日です')
          expect(analysis.document.blocks[0].polygon[0].x).assertEqual(96)
          expect(analysis.document.blocks[0].polygon[0].y).assertEqual(210)
          expect(analysis.document.blocks[0].polygon[2].x).assertEqual(320)
          expect(analysis.document.blocks[0].polygon[2].y).assertEqual(360)
        } finally {
          removeFile(sourcePath)
        }
        done()
      })

    it('merges adjacent detector columns into one vertical paragraph', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PAGE_01_PATH,
        )
        const sourcePath: string = `${ability.context.cacheDir}/adjacent-column-source.png`
        writeFile(sourcePath, bytes)
        try {
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            new AdjacentColumnOcrEngine(),
            new AdjacentColumnRegionDetector(),
          )
          const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          request.source = source(sourcePath, page01Fixture())
          request.requestedRegionRevision = 2
          request.requestedDocumentRevision = 2
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(analysis.document.blocks.length).assertEqual(1)
          expect(analysis.document.blocks[0].sourceText).assertEqual('右の列です左の列です')
          expect(analysis.document.blocks[0].styleHint).assertEqual('vertical-rl')
          expect(analysis.document.blocks[0].polygon[0].x).assertEqual(232)
          expect(analysis.document.blocks[0].polygon[0].y).assertEqual(200)
          expect(analysis.document.blocks[0].polygon[2].x).assertEqual(350)
          expect(analysis.document.blocks[0].polygon[2].y).assertEqual(440)
        } finally {
          removeFile(sourcePath)
        }
        done()
      })

    it('tiles a long page and deduplicates detector regions in source coordinates', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const sourcePath: string = `${ability.context.cacheDir}/tall-detector-source.png`
        await writeSolidImage(sourcePath, TALL_FIXTURE_WIDTH, TALL_FIXTURE_HEIGHT)
        try {
          const detector: TiledFixtureRegionDetector = new TiledFixtureRegionDetector()
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            new EmptyFixtureOcrEngine(),
            detector,
            new FixtureTextRecognizer(),
          )
          const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          request.source = sourceWithDimensions(
            sourcePath,
            TALL_FIXTURE_WIDTH,
            TALL_FIXTURE_HEIGHT,
          )
          request.requestedRegionRevision = 2
          request.requestedDocumentRevision = 2
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(detector.callCount).assertEqual(3)
          expect(detector.observedWidths.join(',')).assertEqual('720,720,720')
          expect(detector.observedHeights.join(',')).assertEqual('2048,2048,1024')
          expect(analysis.document.blocks.length).assertEqual(3)
          let maximumY: number = 0
          for (let blockIndex: number = 0;
            blockIndex < analysis.document.blocks.length; blockIndex++) {
            const polygon = analysis.document.blocks[blockIndex].polygon
            for (let pointIndex: number = 0; pointIndex < polygon.length; pointIndex++) {
              maximumY = Math.max(maximumY, polygon[pointIndex].y)
            }
          }
          expect(maximumY >= 3834).assertEqual(true)
          expect(analysis.document.qualitySignals.some((signal) =>
            signal.code === 'local_manga_region_detector_active')).assertEqual(true)
        } finally {
          removeFile(sourcePath)
        }
        done()
      })

    it('supplements only a detector region missed by system OCR', 0,
      async (done: Function) => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        const bytes: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PAGE_01_PATH,
        )
        const sourcePath: string = `${ability.context.cacheDir}/recognizer-supplement-source.png`
        writeFile(sourcePath, bytes)
        try {
          const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
            ability.context,
            new EmptyFixtureOcrEngine(),
            new MissedTextRegionDetector(),
            new FixtureTextRecognizer(),
          )
          const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
          request.source = source(sourcePath, page01Fixture())
          request.requestedRegionRevision = 2
          request.requestedDocumentRevision = 2
          const analysis: ComicRegionAnalysisResult = await backend.analyze(request)
          expect(backend.profileId().includes('text-recognizer-fixture')).assertEqual(true)
          expect(backend.protocolRevision()).assertEqual(21)
          expect(analysis.document.blocks.length).assertEqual(1)
          expect(analysis.document.blocks[0].sourceText).assertEqual('月影駅東口')
          expect(analysis.document.qualitySignals.some((signal) =>
            signal.code === 'local_manga_text_recognizer_supplemented')).assertEqual(true)
        } finally {
          removeFile(sourcePath)
        }
        done()
      })

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
              expect(page.localFilePath.includes('/comic-translated-pages/')).assertEqual(true)
              const artifactName: string = page.localFilePath.substring(
                page.localFilePath.lastIndexOf('/') + 1,
              )
              expect(/^[a-f0-9]{64}-[a-f0-9]{64}\.png$/.test(artifactName)).assertEqual(true)
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
