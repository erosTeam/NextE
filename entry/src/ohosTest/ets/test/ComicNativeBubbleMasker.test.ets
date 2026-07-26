import { application, common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import { ComicNativeBubbleMaskResult, ComicNativeBubbleMasker } from 'shared'

function parameter(name: string): string {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  return parameters[`-s ${name}`] ?? ''
}

function integrationEnabled(): boolean {
  return parameter('comicBubbleMaskIntegration') === 'true'
}

function safeRawFileName(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)
}

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

async function stageRawFile(
  context: common.Context,
  parameterName: string,
  fileName: string,
  maxBytes: number,
): Promise<string> {
  const rawFile: string = parameter(parameterName).trim()
  if (!safeRawFileName(rawFile)) {
    throw new Error(`${parameterName} must name a signed test rawfile`)
  }
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(rawFile)
  if (bytes.byteLength <= 0 || bytes.byteLength > maxBytes) {
    throw new Error(`${parameterName} rawfile has an invalid size`)
  }
  const abilityContext: common.UIAbilityContext = await appContext()
  const target: string = `${abilityContext.filesDir}/${fileName}`
  const output: fileIo.File = fileIo.openSync(
    target,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
  )
  try {
    const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    const written: number = fileIo.writeSync(output.fd, buffer, { length: buffer.byteLength })
    if (written !== buffer.byteLength) {
      throw new Error(`${parameterName} rawfile staging was incomplete`)
    }
  } finally {
    fileIo.closeSync(output)
  }
  return target
}

function remove(path: string): void {
  try {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path)
    }
  } catch (_error) {}
}

function countMaskedPixels(mask: ArrayBuffer): number {
  const pixels: Uint8Array = new Uint8Array(mask)
  let count: number = 0
  for (let index: number = 0; index < pixels.length; index++) {
    if (pixels[index] !== 0) {
      count = count + 1
    }
  }
  return count
}

function detectionSummary(result: ComicNativeBubbleMaskResult): string {
  const entries: string[] = []
  for (let index: number = 0; index < result.detections.length; index++) {
    const detection = result.detections[index]
    entries.push(
      `${Math.floor(detection.left)},${Math.floor(detection.top)},` +
      `${Math.floor(detection.right)},${Math.floor(detection.bottom)}@${detection.score.toFixed(3)}`,
    )
  }
  return entries.join('|')
}

/**
 * Explicit opt-in only. The caller supplies signed test rawfiles for the model and a real manga page;
 * no generated page or network download is used for semantic qualification. The raw mask remains in
 * this test sandbox for pull-and-overlay review.
 */
export default function comicNativeBubbleMaskerTest(): void {
  describe('ComicNativeBubbleMasker', (): void => {
    it('records semantic bubble masks on an explicitly supplied real page', 0,
      async (): Promise<void> => {
        if (!integrationEnabled()) {
          expect(true).assertEqual(true)
          return
        }
        const context: common.UIAbilityContext = await appContext()
        const fixtureContext: common.Context = await application.createModuleContext(
          context,
          'entry_test',
        )
        const paramPath: string = await stageRawFile(
          fixtureContext,
          'comicBubbleMaskRawParam',
          'comic-bubble-mask.ncnn.param',
          128 * 1024,
        )
        const modelPath: string = await stageRawFile(
          fixtureContext,
          'comicBubbleMaskRawModel',
          'comic-bubble-mask.ncnn.bin',
          32 * 1024 * 1024,
        )
        const sourcePath: string = await stageRawFile(
          fixtureContext,
          'comicBubbleMaskRawImage',
          'comic-bubble-mask-source.bin',
          16 * 1024 * 1024,
        )
        expect(paramPath.length > 0).assertEqual(true)
        expect(modelPath.length > 0).assertEqual(true)
        expect(sourcePath.length > 0).assertEqual(true)
        let source: image.ImageSource | undefined = undefined
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          source = image.createImageSource(sourcePath)
          pixelMap = await source.createPixelMap({
            editable: false,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          })
          const info: image.ImageInfo = await pixelMap.getImageInfo()
          const width: number = Math.floor(info.size.width)
          const height: number = Math.floor(info.size.height)
          expect(width * height <= 16 * 1024 * 1024).assertEqual(true)
          const pixels: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
          await pixelMap.readPixelsToBuffer(pixels)
          const startedAt: number = Date.now()
          const result: ComicNativeBubbleMaskResult = await ComicNativeBubbleMasker.inferRgba(
            pixels,
            width,
            height,
            Math.floor(pixels.byteLength / height),
            paramPath,
            modelPath,
            0.5,
            0.5,
            2,
          )
          const coverage: number = result.maskedPixels / (width * height)
          console.info(
            `Comic bubble mask real-page benchmark page=${width}x${height} ` +
            `load=${result.modelLoadMs}ms inference=${result.inferenceMs}ms ` +
            `post=${result.postprocessingMs}ms total=${Date.now() - startedAt}ms ` +
            `detections=${result.detections.length} masked=${result.maskedPixels} coverage=${coverage} ` +
            `instances=${detectionSummary(result)}`,
          )
          expect(result.backend).assertEqual('ncnn-fp32-cpu')
          expect(result.mask.byteLength).assertEqual(width * height)
          expect(result.maskedPixels).assertEqual(countMaskedPixels(result.mask))
          expect(coverage >= 0 && coverage <= 1).assertEqual(true)
          const maskPath: string = `${context.cacheDir}/comic-bubble-mask-real-page.raw`
          const output: fileIo.File = fileIo.openSync(
            maskPath,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
          )
          try {
            const written: number = fileIo.writeSync(output.fd, result.mask, {
              length: result.mask.byteLength,
            })
            expect(written).assertEqual(result.mask.byteLength)
          } finally {
            fileIo.closeSync(output)
          }
          console.info(`Comic bubble mask artifact=${maskPath}`)
        } finally {
          if (pixelMap !== undefined) {
            await pixelMap.release()
          }
          if (source !== undefined) {
            source.release()
          }
          remove(paramPath)
          remove(modelPath)
          remove(sourcePath)
        }
      })
  })
}
