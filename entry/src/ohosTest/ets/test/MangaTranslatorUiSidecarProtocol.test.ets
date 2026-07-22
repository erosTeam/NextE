import { application } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicBlockTranslation,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicTranslationBatch,
  ComicTranslationErrorClassifier,
  ComicVisualPageSource,
  MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY,
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MANGA_TRANSLATOR_UI_NON_JAPANESE_PROFILE_ID,
  MANGA_TRANSLATOR_UI_PROFILE_ID,
  MANGA_TRANSLATOR_UI_UPSTREAM_COMMIT,
  MANGA_TRANSLATOR_UI_UPSTREAM_TAG,
  MangaTranslatorUiSidecarProtocol,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'comic_manga_translator_ui_v1_9_9_fixture.json'
const CONTEXT_HASH: string =
  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'

class RawSidecarRegion {
  lines: number[][][] = []
  texts: string[] = []
  text: string = ''
  translation: string = ''
  angle: number = 0
}

class RawSidecarPage {
  regions: RawSidecarRegion[] = []
  original_width: number = 0
  original_height: number = 0
  mask_raw: string | null = null
  mask_is_refined: boolean = false
}

class RawSidecarEnvelope {
  temp_image: RawSidecarPage = new RawSidecarPage()
}

class RawFixtureTranslation {
  blockId: string = ''
  translatedText: string = ''
}

class RawSidecarFixture {
  provenance: string = ''
  upstreamTag: string = ''
  upstreamCommit: string = ''
  profileId: string = ''
  exportEndpoint: string = ''
  importEndpoint: string = ''
  zipEntries: string[] = []
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  targetLanguage: string = ''
  originalText: string = ''
  translationJson: RawSidecarEnvelope = new RawSidecarEnvelope()
  translations: RawFixtureTranslation[] = []
}

async function loadFixture(): Promise<RawSidecarFixture> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  const context = await application.createModuleContext(ability.context, FIXTURE_MODULE)
  const bytes: Uint8Array = await context.resourceManager.getRawFileContent(FIXTURE_PATH)
  const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  return JSON.parse(decoder.decodeToString(bytes)) as RawSidecarFixture
}

function analysisRequest(raw: RawSidecarFixture): ComicRegionAnalysisRequest {
  const source: ComicVisualPageSource = new ComicVisualPageSource()
  source.projectId = raw.projectId
  source.pageIndex = raw.pageIndex
  source.imageFilePath = '/fixture/manga-translator-ui-source.png'
  source.imageHash = raw.sourceImageHash
  source.imageWidth = raw.imageWidth
  source.imageHeight = raw.imageHeight
  const request: ComicRegionAnalysisRequest = new ComicRegionAnalysisRequest()
  request.source = source
  request.requestedRegionRevision = 1
  request.requestedDocumentRevision = 1
  return request
}

function translationBatch(
  raw: RawSidecarFixture,
  analysis: ComicRegionAnalysisResult,
): ComicTranslationBatch {
  const batch: ComicTranslationBatch = new ComicTranslationBatch()
  batch.projectId = raw.projectId
  batch.pageIndex = raw.pageIndex
  batch.sourceImageHash = raw.sourceImageHash
  batch.targetLanguage = raw.targetLanguage
  batch.sourceProfileId = 'fixture-llm-source'
  batch.sourceRevision = 1
  batch.modelId = 'fixture-context-model'
  batch.promptVersion = 'fixture-block-translation-v1'
  batch.contextFingerprint = CONTEXT_HASH
  batch.translationRevision = 1
  for (let index: number = 0; index < raw.translations.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = raw.translations[index].blockId
    block.translatedText = raw.translations[index].translatedText
    batch.blocks.push(block)
  }
  expect(batch.blocks.length).assertEqual(analysis.document.blocks.length)
  return batch
}

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value)
}

function parseFixture(
  raw: RawSidecarFixture,
  profileId: string = MANGA_TRANSLATOR_UI_PROFILE_ID,
): ComicRegionAnalysisResult {
  return MangaTranslatorUiSidecarProtocol.parseExport(
    analysisRequest(raw),
    encode(JSON.stringify(raw.translationJson)),
    encode(raw.originalText),
    profileId,
  )
}

export default function mangaTranslatorUiSidecarProtocolTest(): void {
  describe('Manga translator UI sidecar protocol', () => {
    it('pins a released export/import profile and normalizes its synthetic fixture', 0,
      async (done: Function) => {
        const raw: RawSidecarFixture = await loadFixture()
        expect(raw.provenance.includes('synthetic fixture')).assertEqual(true)
        expect(raw.upstreamTag).assertEqual(MANGA_TRANSLATOR_UI_UPSTREAM_TAG)
        expect(raw.upstreamCommit).assertEqual(MANGA_TRANSLATOR_UI_UPSTREAM_COMMIT)
        expect(raw.profileId).assertEqual(MANGA_TRANSLATOR_UI_PROFILE_ID)
        expect(raw.exportEndpoint).assertEqual(MANGA_TRANSLATOR_UI_EXPORT_PATH)
        expect(raw.importEndpoint).assertEqual(MANGA_TRANSLATOR_UI_IMPORT_PATH)
        expect(raw.zipEntries[0]).assertEqual(MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY)
        expect(raw.zipEntries[1]).assertEqual(MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY)

        const analysis: ComicRegionAnalysisResult = parseFixture(raw)
        expect(analysis.document.blocks.length).assertEqual(2)
        expect(analysis.document.blocks[0].blockId).assertEqual('p3-r0')
        expect(analysis.document.blocks[0].sourceText).assertEqual('テストです')
        expect(analysis.document.blocks[0].polygon.length).assertEqual(4)
        expect(analysis.document.blocks[1].blockId).assertEqual('p3-r1')
        expect(analysis.adapterTemplate.profileId).assertEqual(MANGA_TRANSLATOR_UI_PROFILE_ID)
        const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
        const filtered: RawSidecarEnvelope = JSON.parse(
          decoder.decodeToString(analysis.adapterTemplate.payload),
        ) as RawSidecarEnvelope
        expect(raw.translationJson.temp_image.regions.length).assertEqual(3)
        expect(filtered.temp_image.regions.length).assertEqual(2)
        expect(filtered.temp_image.mask_raw === null).assertEqual(true)
        expect(filtered.temp_image.mask_is_refined).assertEqual(false)
        done()
      })

    it('keeps a non-Japanese OCR profile in analysis and render template identity', 0,
      async (done: Function) => {
        const raw: RawSidecarFixture = await loadFixture()
        const analysis: ComicRegionAnalysisResult = parseFixture(
          raw,
          MANGA_TRANSLATOR_UI_NON_JAPANESE_PROFILE_ID,
        )
        expect(analysis.profileId).assertEqual(MANGA_TRANSLATOR_UI_NON_JAPANESE_PROFILE_ID)
        expect(analysis.adapterTemplate.profileId).assertEqual(
          MANGA_TRANSLATOR_UI_NON_JAPANESE_PROFILE_ID,
        )
        expect(analysis.document.imagePreparationProfile.profileId).assertEqual(
          MANGA_TRANSLATOR_UI_NON_JAPANESE_PROFILE_ID + ':source-original',
        )
        const output: Uint8Array = MangaTranslatorUiSidecarProtocol.buildImportJson(
          analysis.document,
          translationBatch(raw, analysis),
          analysis.adapterTemplate,
        )
        expect(output.length > 0).assertEqual(true)
        done()
      })

    it('writes complete blockId translations into the pinned JSON render template', 0,
      async (done: Function) => {
        const raw: RawSidecarFixture = await loadFixture()
        const analysis: ComicRegionAnalysisResult = parseFixture(raw)
        const output: Uint8Array = MangaTranslatorUiSidecarProtocol.buildImportJson(
          analysis.document,
          translationBatch(raw, analysis),
          analysis.adapterTemplate,
        )
        const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
        const envelope: RawSidecarEnvelope =
          JSON.parse(decoder.decodeToString(output)) as RawSidecarEnvelope
        expect(envelope.temp_image.regions[0].translation).assertEqual('这是测试')
        expect(envelope.temp_image.regions[1].translation).assertEqual('去下一处吧')
        expect(envelope.temp_image.regions[0].text).assertEqual('テストです')
        done()
      })

    it('restores uneven rotated edge regions around the upstream mean-vertex center', 0,
      async (done: Function) => {
        const raw: RawSidecarFixture = JSON.parse(
          JSON.stringify(await loadFixture()),
        ) as RawSidecarFixture
        raw.imageWidth = 720
        raw.imageHeight = 1000
        raw.originalText = 'edge text\n'
        raw.translationJson.temp_image.original_width = raw.imageWidth
        raw.translationJson.temp_image.original_height = raw.imageHeight
        const region: RawSidecarRegion = raw.translationJson.temp_image.regions[1]
        region.lines = [
          [[88.703, 570.562], [171.543, 538.804], [192.421, 593.261], [109.58, 625.02]],
          [[34.135, 740.241], [95.483, 716.722], [105.315, 742.367], [43.967, 765.886]],
        ]
        region.texts = ['edge', 'text']
        region.text = 'edge text'
        region.angle = 20.975346376842644
        raw.translationJson.temp_image.regions = [region]

        const analysis: ComicRegionAnalysisResult = parseFixture(raw)
        expect(analysis.document.blocks.length).assertEqual(1)
        const polygon = analysis.document.blocks[0].polygon
        expect(polygon.length).assertEqual(4)
        expect(Math.abs(polygon[0].x - 10.692400900315931) < 0.001).assertEqual(true)
        expect(Math.abs(polygon[0].y - 570.7100979751775) < 0.001).assertEqual(true)
        expect(Math.abs(polygon[2].x - 211.10337986559188) < 0.001).assertEqual(true)
        expect(Math.abs(polygon[2].y - 737.0768954721725) < 0.001).assertEqual(true)
        done()
      })

    it('classifies rejected sidecar geometry as invalid output instead of provider failure', 0,
      () => {
        const code: string = ComicTranslationErrorClassifier.classify(new Error(
          'Manga translator UI region is outside the source image ' +
            '(region=4,axis=x,value=-2,edge=720)',
        ))
        expect(code).assertEqual('output_geometry_invalid')
      })

    it('classifies rendered artifact contract failures separately from provider errors', 0, () => {
      const code: string = ComicTranslationErrorClassifier.classify(new Error(
        'Comic rendered page artifact path is invalid',
      ))
      expect(code).assertEqual('render_artifact_invalid')
    })

    it('rejects the known v2 field drift and mismatched page identity locally', 0,
      async (done: Function) => {
        const raw: RawSidecarFixture = await loadFixture()
        const valid: string = JSON.stringify(raw.translationJson)
        const drifted: string = valid.replace(
          '"default_stroke_width":0.2,"adjust_bg_color":true',
          '"stroke_width":0.2',
        )
        const wrongSize: RawSidecarEnvelope = JSON.parse(valid) as RawSidecarEnvelope
        wrongSize.temp_image.original_width++
        const candidates: string[] = [drifted, JSON.stringify(wrongSize)]
        for (let index: number = 0; index < candidates.length; index++) {
          let rejected: boolean = false
          try {
            MangaTranslatorUiSidecarProtocol.parseExport(
              analysisRequest(raw),
              encode(candidates[index]),
              encode(raw.originalText),
            )
          } catch (_error) {
            rejected = true
          }
          expect(rejected).assertEqual(true)
        }
        done()
      })

    it('rejects a modified render template before translations are imported', 0,
      async (done: Function) => {
        const raw: RawSidecarFixture = await loadFixture()
        const analysis: ComicRegionAnalysisResult = parseFixture(raw)
        analysis.adapterTemplate.payload[0] = analysis.adapterTemplate.payload[0] ^ 1
        let rejected: boolean = false
        try {
          MangaTranslatorUiSidecarProtocol.buildImportJson(
            analysis.document,
            translationBatch(raw, analysis),
            analysis.adapterTemplate,
          )
        } catch (_error) {
          rejected = true
        }
        expect(rejected).assertEqual(true)
        done()
      })
  })
}
