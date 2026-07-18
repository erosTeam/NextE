import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  connectReadMode,
  ReaderSuperResolutionBackend,
  ReaderSuperResolutionModel,
  ReaderSuperResolutionModelService,
  ReaderSuperResolutionResult,
  ReaderSuperResolutionService,
  ReaderSuperResolutionTaskPriority,
  ReaderSuperResolutionTaskState,
} from 'shared'

const INPUT_WIDTH: number = 64
const INPUT_HEIGHT: number = 48
const READER_SIZED_INPUT_WIDTH: number = 1280
const READER_SIZED_INPUT_HEIGHT: number = 1837
const CANCELLATION_INPUT_WIDTH: number = 640
const CANCELLATION_INPUT_HEIGHT: number = 900

function integrationEnabled(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionIntegration'] === 'true'
}

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function waitFor(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, milliseconds)
  })
}

async function writeTestImage(
  path: string,
  width: number = INPUT_WIDTH,
  height: number = INPUT_HEIGHT,
): Promise<void> {
  let pixelMap: image.PixelMap | undefined = undefined
  let packer: image.ImagePacker | undefined = undefined
  let outputFile: fileIo.File | null = null
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4)
    const pixels: Uint8Array = new Uint8Array(buffer)
    for (let index: number = 0; index < pixels.length; index += 4) {
      const pixel: number = index / 4
      pixels[index] = (pixel * 13) % 251
      pixels[index + 1] = (pixel * 7) % 241
      pixels[index + 2] = (pixel * 3) % 239
      pixels[index + 3] = 255
    }
    const options: image.InitializationOptions = {
      size: { width: width, height: height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false,
    }
    pixelMap = await image.createPixelMap(buffer, options)
    outputFile = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    packer = image.createImagePacker()
    await packer.packToFile(pixelMap, outputFile.fd, { format: 'image/jpeg', quality: 95 })
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

async function verifyOutputHasSignal(path: string): Promise<void> {
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(path)
    pixelMap = await source.createPixelMap({
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    })
    const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    await pixelMap.readPixelsToBuffer(buffer)
    const pixels: Uint8Array = new Uint8Array(buffer)
    let minimum: number = 255
    let maximum: number = 0
    for (let index: number = 0; index + 2 < pixels.length; index += 4) {
      minimum = Math.min(minimum, pixels[index], pixels[index + 1], pixels[index + 2])
      maximum = Math.max(maximum, pixels[index], pixels[index + 1], pixels[index + 2])
    }
    console.info(
      'ReaderSuperResolutionModelIntegration outputSignal=' + minimum + '..' + maximum,
    )
    expect(maximum).assertLarger(16)
    expect(maximum - minimum).assertLarger(16)
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
  }
}

async function verifyModel(
  context: common.UIAbilityContext,
  model: string,
  backend: string,
  sourcePath: string,
  sourceKey: string,
  expectedWidth: number = INPUT_WIDTH,
  expectedHeight: number = INPUT_HEIGHT,
): Promise<void> {
  connectReadMode().superResolutionEnabled = true
  connectReadMode().superResolutionModel = model
  connectReadMode().superResolutionBackend = backend
  connectReadMode().superResolutionMaxHeight = 2000
  const result: ReaderSuperResolutionResult =
    await ReaderSuperResolutionService.process(context, sourcePath, sourceKey)
  console.info(
    'ReaderSuperResolutionModelIntegration model=' + model +
      ' applied=' + result.applied +
      ' source=' + result.sourceWidth + 'x' + result.sourceHeight +
      ' output=' + result.outputWidth + 'x' + result.outputHeight +
      ' backend=' + result.backend +
      ' reason=' + result.reason +
      ' elapsedMs=' + result.elapsedMs,
  )
  expect(result.applied).assertEqual(true)
  expect(result.sourceWidth).assertEqual(expectedWidth)
  expect(result.sourceHeight).assertEqual(expectedHeight)
  expect(result.outputWidth).assertEqual(expectedWidth * 2)
  expect(result.outputHeight).assertEqual(expectedHeight * 2)
  expect(result.backend).assertEqual(backend)
  expect(fileIo.accessSync(result.filePath)).assertEqual(true)
  await verifyOutputHasSignal(result.filePath)
}

async function verifyDownloadedModelThroughVulkan(model: string, slug: string): Promise<void> {
  const context: common.UIAbilityContext = await appContext()
  const sourcePath: string =
    context.cacheDir + `/reader-super-resolution-${slug}-input.jpg`
  const previousEnabled: boolean = connectReadMode().superResolutionEnabled
  const previousModel: string = connectReadMode().superResolutionModel
  const previousBackend: string = connectReadMode().superResolutionBackend
  try {
    await ReaderSuperResolutionModelService.install(context, model)
    await writeTestImage(sourcePath)
    await verifyModel(
      context,
      model,
      ReaderSuperResolutionBackend.VULKAN,
      sourcePath,
      `ohos-test-${slug}-vulkan`,
    )
  } finally {
    connectReadMode().superResolutionEnabled = previousEnabled
    connectReadMode().superResolutionModel = previousModel
    connectReadMode().superResolutionBackend = previousBackend
    await ReaderSuperResolutionService.clear(context)
    try {
      fileIo.unlinkSync(sourcePath)
    } catch (_error) {}
  }
}

export default function readerSuperResolutionModelIntegrationTest(): void {
  describe('ReaderSuperResolutionModelIntegration', () => {
    it('runsWaifu2xPhotoThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
        'waifu2x-photo',
      )
      done()
    })

    it('processesReaderSizedSourceAt2000Limit', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const sourcePath: string =
        context.cacheDir + '/reader-super-resolution-reader-sized-input.jpg'
      const previousEnabled: boolean = connectReadMode().superResolutionEnabled
      const previousModel: string = connectReadMode().superResolutionModel
      const previousBackend: string = connectReadMode().superResolutionBackend
      const previousMaxHeight: number = connectReadMode().superResolutionMaxHeight
      try {
        await ReaderSuperResolutionModelService.installWaifu2x(context)
        await writeTestImage(sourcePath, READER_SIZED_INPUT_WIDTH, READER_SIZED_INPUT_HEIGHT)
        await verifyModel(
          context,
          ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
          ReaderSuperResolutionBackend.VULKAN,
          sourcePath,
          'ohos-test-waifu2x-reader-sized-vulkan',
          READER_SIZED_INPUT_WIDTH,
          READER_SIZED_INPUT_HEIGHT,
        )
      } finally {
        connectReadMode().superResolutionEnabled = previousEnabled
        connectReadMode().superResolutionModel = previousModel
        connectReadMode().superResolutionBackend = previousBackend
        connectReadMode().superResolutionMaxHeight = previousMaxHeight
        await ReaderSuperResolutionService.clear(context)
        try {
          fileIo.unlinkSync(sourcePath)
        } catch (_error) {}
      }
      done()
    })

    it('prioritizesCurrentOwnerAndCancelsStaleInference', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const staleSourcePath: string =
        context.cacheDir + '/reader-super-resolution-stale-owner-input.jpg'
      const currentSourcePath: string =
        context.cacheDir + '/reader-super-resolution-current-owner-input.jpg'
      const staleOwnerKey: string = 'ohos-test-prefetch-reader-owner'
      const currentOwnerKey: string = 'ohos-test-current-reader-owner'
      const previousEnabled: boolean = connectReadMode().superResolutionEnabled
      const previousModel: string = connectReadMode().superResolutionModel
      const previousBackend: string = connectReadMode().superResolutionBackend
      const previousMaxHeight: number = connectReadMode().superResolutionMaxHeight
      try {
        await ReaderSuperResolutionModelService.installWaifu2x(context)
        await writeTestImage(staleSourcePath, CANCELLATION_INPUT_WIDTH, CANCELLATION_INPUT_HEIGHT)
        await writeTestImage(currentSourcePath)
        connectReadMode().superResolutionEnabled = true
        connectReadMode().superResolutionModel = ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X
        connectReadMode().superResolutionBackend = ReaderSuperResolutionBackend.VULKAN
        connectReadMode().superResolutionMaxHeight = 2000

        let staleProcessing: boolean = false
        const stalePromise: Promise<ReaderSuperResolutionResult> =
          ReaderSuperResolutionService.process(
            context,
            staleSourcePath,
            'ohos-test-stale-owner-vulkan',
            (state: ReaderSuperResolutionTaskState): void => {
              staleProcessing = state === ReaderSuperResolutionTaskState.PROCESSING
            },
            staleOwnerKey,
            ReaderSuperResolutionTaskPriority.PREFETCH,
          )
        for (let attempt: number = 0; attempt < 100 && !staleProcessing; attempt++) {
          await waitFor(20)
        }
        expect(staleProcessing).assertEqual(true)

        const currentPromise: Promise<ReaderSuperResolutionResult> =
          ReaderSuperResolutionService.process(
            context,
            currentSourcePath,
            'ohos-test-current-owner-vulkan',
            (_state: ReaderSuperResolutionTaskState): void => {},
            currentOwnerKey,
            ReaderSuperResolutionTaskPriority.CURRENT,
          )
        const staleResult: ReaderSuperResolutionResult = await stalePromise
        const currentResult: ReaderSuperResolutionResult = await currentPromise
        console.info(
          'ReaderSuperResolutionModelIntegration priority stale=' + staleResult.reason +
            ' current=' + currentResult.reason +
            ' currentElapsedMs=' + currentResult.elapsedMs,
        )
        expect(staleResult.applied).assertEqual(false)
        expect(staleResult.reason).assertEqual('superseded')
        expect(currentResult.applied).assertEqual(true)
        expect(currentResult.outputWidth).assertEqual(INPUT_WIDTH * 2)
        expect(currentResult.outputHeight).assertEqual(INPUT_HEIGHT * 2)
        expect(currentResult.backend).assertEqual(ReaderSuperResolutionBackend.VULKAN)
        await verifyOutputHasSignal(currentResult.filePath)
      } finally {
        ReaderSuperResolutionService.releaseOwner(staleOwnerKey)
        ReaderSuperResolutionService.releaseOwner(currentOwnerKey)
        connectReadMode().superResolutionEnabled = previousEnabled
        connectReadMode().superResolutionModel = previousModel
        connectReadMode().superResolutionBackend = previousBackend
        connectReadMode().superResolutionMaxHeight = previousMaxHeight
        await ReaderSuperResolutionService.clear(context)
        try {
          fileIo.unlinkSync(staleSourcePath)
        } catch (_error) {}
        try {
          fileIo.unlinkSync(currentSourcePath)
        } catch (_error) {}
      }
      done()
    })

    it('runsRealEsrganX2plusThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS,
        'realesrgan-photo',
      )
      done()
    })

    it('runsRealEsrganAnimevideoV3ThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.REAL_ESRGAN_ANIMEVIDEO_V3_X2,
        'realesrgan-animevideo-v3',
      )
      done()
    })

    it('runsWaifu2xArtThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X,
        'waifu2x-art',
      )
      done()
    })

    it('runsWaifu2xCunetThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X,
        'waifu2x-cunet',
      )
      done()
    })

    it('runsRealCuganSeThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
        'realcugan-se-conservative',
      )
      done()
    })

    it('runsWaifu2xThroughCpu', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const sourcePath: string =
        context.cacheDir + '/reader-super-resolution-waifu2x-cpu-input.jpg'
      const previousEnabled: boolean = connectReadMode().superResolutionEnabled
      const previousModel: string = connectReadMode().superResolutionModel
      const previousBackend: string = connectReadMode().superResolutionBackend
      try {
        await ReaderSuperResolutionModelService.installWaifu2x(context)
        await writeTestImage(sourcePath)
        await verifyModel(
          context,
          ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
          ReaderSuperResolutionBackend.CPU,
          sourcePath,
          'ohos-test-waifu2x-cpu',
        )
      } finally {
        connectReadMode().superResolutionEnabled = previousEnabled
        connectReadMode().superResolutionModel = previousModel
        connectReadMode().superResolutionBackend = previousBackend
        await ReaderSuperResolutionService.clear(context)
        try {
          fileIo.unlinkSync(sourcePath)
        } catch (_error) {}
      }
      done()
    })

    it('runsRealEsrganX2plusThroughCpu', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const sourcePath: string =
        context.cacheDir + '/reader-super-resolution-realesrgan-cpu-input.jpg'
      const previousEnabled: boolean = connectReadMode().superResolutionEnabled
      const previousModel: string = connectReadMode().superResolutionModel
      const previousBackend: string = connectReadMode().superResolutionBackend
      try {
        await ReaderSuperResolutionModelService.installRealEsrgan(context)
        await writeTestImage(sourcePath)
        await verifyModel(
          context,
          ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS,
          ReaderSuperResolutionBackend.CPU,
          sourcePath,
          'ohos-test-realesrgan-cpu',
        )
      } finally {
        connectReadMode().superResolutionEnabled = previousEnabled
        connectReadMode().superResolutionModel = previousModel
        connectReadMode().superResolutionBackend = previousBackend
        await ReaderSuperResolutionService.clear(context)
        try {
          fileIo.unlinkSync(sourcePath)
        } catch (_error) {}
      }
      done()
    })
  })
}
