import { common } from '@kit.AbilityKit'
import { thermal } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  ComicNativeInpaintingResult,
  ComicNativeSourceInpainter,
  EhHttpClient,
} from 'shared'

function integrationEnabled(): boolean {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s comicInpainterIntegration'] === 'true'
}

function parameter(name: string): string {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters[`-s ${name}`] ?? ''
}

function continuousIterations(): number {
  const parsed: number = Number(parameter('comicContinuousIterations'))
  if (!Number.isFinite(parsed)) {
    return 0
  }
  return Math.max(0, Math.min(20, Math.floor(parsed)))
}

function percentile(values: number[], quantile: number): number {
  if (values.length <= 0) {
    return 0
  }
  const sorted: number[] = values.slice().sort((left: number, right: number): number => left - right)
  const index: number = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil(sorted.length * quantile) - 1),
  )
  return sorted[index]
}

function maximum(values: number[]): number {
  let result: number = 0
  for (let index: number = 0; index < values.length; index++) {
    result = Math.max(result, values[index])
  }
  return result
}

function fixture(width: number, height: number): ArrayBuffer {
  const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4)
  const pixels: Uint8Array = new Uint8Array(buffer)
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const offset: number = (y * width + x) * 4
      const stripe: number = Math.floor(x / 12) % 2 === 0 ? 232 : 206
      pixels[offset] = stripe
      pixels[offset + 1] = Math.max(0, stripe - Math.floor(y / 8) * 2)
      pixels[offset + 2] = Math.max(0, stripe - 18)
      pixels[offset + 3] = 255
    }
  }
  return buffer
}

function fixtureMask(width: number, height: number): ArrayBuffer {
  const buffer: ArrayBuffer = new ArrayBuffer(width * height)
  const mask: Uint8Array = new Uint8Array(buffer)
  for (let y: number = 28; y < height - 28; y++) {
    for (let x: number = 42; x < width - 42; x++) {
      if ((x + y) % 7 <= 4) {
        mask[y * width + x] = 1
      }
    }
  }
  return buffer
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

function removeDownloadedModel(pathParameter: string, path: string): void {
  if (parameter(pathParameter).length > 0) {
    return
  }
  try {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path)
    }
  } catch (_error) {}
}

async function repeatedInferenceMs(
  width: number,
  height: number,
  paramPath: string,
  modelPath: string,
): Promise<number> {
  const repeated: ComicNativeInpaintingResult =
    await ComicNativeSourceInpainter.inpaintBgra(
      fixture(width, height),
      fixtureMask(width, height),
      width,
      height,
      width * 4,
      paramPath,
      modelPath,
      4,
    )
  expect(repeated.modelLoadMs).assertEqual(0)
  expect(repeated.inferenceWidth).assertEqual(176)
  expect(repeated.inferenceHeight).assertEqual(256)
  return repeated.inferenceMs
}

export default function comicNativeSourceInpainterTest(): void {
  describe('ComicNativeSourceInpainter', (): void => {
    it('preserves every unmasked source byte around a bounded repair', 0, async (): Promise<void> => {
      if (!integrationEnabled()) {
        expect(true).assertEqual(true)
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const paramPath: string = await externalModelPath(
        context,
        'comicInpainterParam',
        'comicInpainterParamUrl',
        'aot.ncnn.param',
      )
      const modelPath: string = await externalModelPath(
        context,
        'comicInpainterModel',
        'comicInpainterModelUrl',
        'aot.ncnn.bin',
      )
      expect(paramPath.length > 0).assertEqual(true)
      expect(modelPath.length > 0).assertEqual(true)
      const width: number = 192
      const height: number = 128
      const stride: number = width * 4
      const pixels: ArrayBuffer = fixture(width, height)
      const mask: ArrayBuffer = fixtureMask(width, height)
      const coldStartedAt: number = Date.now()
      const result: ComicNativeInpaintingResult =
        await ComicNativeSourceInpainter.inpaintBgra(
          pixels,
          mask,
          width,
          height,
          stride,
          paramPath,
          modelPath,
          4,
        )
      const source: Uint8Array = new Uint8Array(pixels)
      const output: Uint8Array = new Uint8Array(result.pixels)
      const maskBytes: Uint8Array = new Uint8Array(mask)
      let changedMaskedBytes: number = 0
      let maskedPixels: number = 0
      let saturatedMaskedPixels: number = 0
      let excessiveChromaMaskedPixels: number = 0
      for (let index: number = 0; index < width * height; index++) {
        const offset: number = index * 4
        expect(output[offset + 3]).assertEqual(source[offset + 3])
        if (maskBytes[index] === 0) {
          expect(output[offset]).assertEqual(source[offset])
          expect(output[offset + 1]).assertEqual(source[offset + 1])
          expect(output[offset + 2]).assertEqual(source[offset + 2])
        } else {
          maskedPixels++
          const blue: number = output[offset]
          const green: number = output[offset + 1]
          const red: number = output[offset + 2]
          const minimum: number = Math.min(blue, green, red)
          const maximum: number = Math.max(blue, green, red)
          if (minimum <= 4 || maximum >= 251) {
            saturatedMaskedPixels++
          }
          if (maximum - minimum >= 96) {
            excessiveChromaMaskedPixels++
          }
          if (blue !== source[offset] || green !== source[offset + 1] ||
            red !== source[offset + 2]) {
            changedMaskedBytes++
          }
        }
      }
      console.info(
        `Comic inpainter cold benchmark load=${result.modelLoadMs}ms ` +
        `inference=${result.inferenceMs}ms total=${Date.now() - coldStartedAt}ms ` +
        `changed=${changedMaskedBytes} masked=${maskedPixels} ` +
        `saturated=${saturatedMaskedPixels} chroma=${excessiveChromaMaskedPixels}`,
      )
      expect(changedMaskedBytes > 0).assertEqual(true)
      expect(saturatedMaskedPixels * 20 < maskedPixels).assertEqual(true)
      expect(excessiveChromaMaskedPixels * 20 < maskedPixels).assertEqual(true)
      expect(result.backend).assertEqual('ncnn-fp32-cpu')
      expect(result.inferenceWidth).assertEqual(192)
      expect(result.inferenceHeight).assertEqual(128)

      const warmStartedAt: number = Date.now()
      const warmResult: ComicNativeInpaintingResult =
        await ComicNativeSourceInpainter.inpaintBgra(
          pixels,
          mask,
          width,
          height,
          stride,
          paramPath,
          modelPath,
          4,
        )
      console.info(
        `Comic inpainter warm benchmark load=${warmResult.modelLoadMs}ms ` +
        `inference=${warmResult.inferenceMs}ms total=${Date.now() - warmStartedAt}ms`,
      )
      expect(warmResult.modelLoadMs).assertEqual(0)
      expect(warmResult.backend).assertEqual('ncnn-fp32-cpu')

      const largeWidth: number = 427
      const largeHeight: number = 644
      const largeResult: ComicNativeInpaintingResult =
        await ComicNativeSourceInpainter.inpaintBgra(
          fixture(largeWidth, largeHeight),
          fixtureMask(largeWidth, largeHeight),
          largeWidth,
          largeHeight,
          largeWidth * 4,
          paramPath,
          modelPath,
          4,
        )
      expect(largeResult.inferenceWidth).assertEqual(176)
      expect(largeResult.inferenceHeight).assertEqual(256)
      expect(largeResult.pixels.byteLength).assertEqual(largeWidth * largeHeight * 4)
      const iterations: number = continuousIterations()
      if (iterations > 0) {
        const inferenceTimes: number[] = []
        const pssSamples: number[] = [Number(hidebug.getAppNativeMemInfo().pss)]
        const thermalSamples: thermal.ThermalLevel[] = [thermal.getLevel()]
        for (let index: number = 0; index < iterations; index++) {
          inferenceTimes.push(await repeatedInferenceMs(
            largeWidth,
            largeHeight,
            paramPath,
            modelPath,
          ))
          pssSamples.push(Number(hidebug.getAppNativeMemInfo().pss))
          thermalSamples.push(thermal.getLevel())
        }
        console.info(
          `Comic continuous AOT iterations=${iterations} ` +
          `p50=${percentile(inferenceTimes, 0.5)}ms ` +
          `p95=${percentile(inferenceTimes, 0.95)}ms ` +
          `pssStart=${pssSamples[0]}kB ` +
          `pssPeak=${maximum(pssSamples)}kB ` +
          `pssFinal=${pssSamples[pssSamples.length - 1]}kB ` +
          `pssSeries=${pssSamples.join(',')} ` +
          `thermalSeries=${thermalSamples.join(',')}`,
        )
      }
      removeDownloadedModel('comicInpainterParam', paramPath)
      removeDownloadedModel('comicInpainterModel', modelPath)
    })
  })
}
