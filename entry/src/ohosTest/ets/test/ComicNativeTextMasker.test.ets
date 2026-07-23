import { application, common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicNativeTextMaskResult,
  ComicNativeTextMasker,
  EhHttpClient,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'comic_translation_eval_page_01.png'

function integrationEnabled(): boolean {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s comicTextMaskIntegration'] === 'true'
}

function parameter(name: string): string {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters[`-s ${name}`] ?? ''
}

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

async function externalModelPath(
  context: common.UIAbilityContext,
  pathParameter: string,
  urlParameter: string,
  fileName: string,
): Promise<string> {
  const existing: string = parameter(pathParameter)
  if (existing.length > 0) {
    return existing
  }
  const url: string = parameter(urlParameter)
  if (url.length <= 0) {
    return ''
  }
  const target: string = `${context.filesDir}/${fileName}`
  await EhHttpClient.getInstance().downloadBinaryToFileInStream(
    url,
    target,
    (_loaded: number, _total: number): void => {},
    15000,
    0,
    'application/octet-stream,*/*',
    1,
    120000,
  )
  return target
}

export default function comicNativeTextMaskerTest(): void {
  describe('ComicNativeTextMasker', (): void => {
    it('segments text pixels on the owned manga fixture with a warm model cache', 0,
      async (): Promise<void> => {
        if (!integrationEnabled()) {
          expect(true).assertEqual(true)
          return
        }
        const context: common.UIAbilityContext = await appContext()
        const paramPath: string = await externalModelPath(
          context,
          'comicTextMaskParam',
          'comicTextMaskParamUrl',
          'comic-text-mask-ctd-1024.ncnn.param',
        )
        const modelPath: string = await externalModelPath(
          context,
          'comicTextMaskModel',
          'comicTextMaskModelUrl',
          'comic-text-mask-ctd-1024.ncnn.bin',
        )
        expect(paramPath.length > 0).assertEqual(true)
        expect(modelPath.length > 0).assertEqual(true)
        const fixtureContext: common.Context = await application.createModuleContext(
          context,
          FIXTURE_MODULE,
        )
        const encoded: Uint8Array = await fixtureContext.resourceManager.getRawFileContent(
          FIXTURE_PATH,
        )
        const encodedBuffer: ArrayBuffer = encoded.buffer.slice(
          encoded.byteOffset,
          encoded.byteOffset + encoded.byteLength,
        )
        let source: image.ImageSource | undefined = undefined
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          source = image.createImageSource(encodedBuffer)
          pixelMap = await source.createPixelMap({
            editable: false,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          })
          const info: image.ImageInfo = await pixelMap.getImageInfo()
          const width: number = Math.floor(info.size.width)
          const height: number = Math.floor(info.size.height)
          const pixels: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
          await pixelMap.readPixelsToBuffer(pixels)
          const stride: number = Math.floor(pixels.byteLength / height)
          const coldStartedAt: number = Date.now()
          const result: ComicNativeTextMaskResult = await ComicNativeTextMasker.inferBgra(
            pixels,
            width,
            height,
            stride,
            paramPath,
            modelPath,
            0.3,
            4,
          )
          const coverage: number = result.maskedPixels / (width * height)
          console.info(
            `Comic text mask cold benchmark load=${result.modelLoadMs}ms ` +
            `inference=${result.inferenceMs}ms total=${Date.now() - coldStartedAt}ms ` +
            `page=${width}x${height} masked=${result.maskedPixels} coverage=${coverage}`,
          )
          expect(result.mask.byteLength).assertEqual(width * height)
          expect(result.backend).assertEqual('ncnn-fp16-cpu')
          expect(result.maskedPixels > 100).assertEqual(true)
          expect(coverage > 0.0001 && coverage < 0.35).assertEqual(true)

          const warmStartedAt: number = Date.now()
          const warm: ComicNativeTextMaskResult = await ComicNativeTextMasker.inferBgra(
            pixels,
            width,
            height,
            stride,
            paramPath,
            modelPath,
            0.3,
            4,
          )
          console.info(
            `Comic text mask warm benchmark load=${warm.modelLoadMs}ms ` +
            `inference=${warm.inferenceMs}ms total=${Date.now() - warmStartedAt}ms`,
          )
          expect(warm.modelLoadMs).assertEqual(0)
          expect(warm.maskedPixels).assertEqual(result.maskedPixels)

          const paired: ComicNativeTextMaskResult = await ComicNativeTextMasker.inferBgra(
            pixels,
            width,
            height,
            stride,
            paramPath,
            modelPath,
            0.15,
            4,
            0.3,
          )
          expect(paired.secondaryMask.byteLength).assertEqual(width * height)
          expect(paired.secondaryMaskedPixels).assertEqual(result.maskedPixels)
          expect(paired.maskedPixels >= paired.secondaryMaskedPixels).assertEqual(true)
          const proposalMask: Uint8Array = new Uint8Array(paired.mask)
          const treatmentMask: Uint8Array = new Uint8Array(paired.secondaryMask)
          let subsetViolations: number = 0
          for (let index: number = 0; index < treatmentMask.length; index++) {
            if (treatmentMask[index] !== 0 && proposalMask[index] === 0) {
              subsetViolations = subsetViolations + 1
            }
          }
          expect(subsetViolations).assertEqual(0)
        } finally {
          if (pixelMap !== undefined) {
            await pixelMap.release()
          }
          if (source !== undefined) {
            await source.release()
          }
        }
      })
  })
}
