import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { mindSporeLite } from '@kit.MindSporeLiteKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  connectReadMode,
  EhHttpClient,
  ReaderMindSporeSuperResolution,
  ReaderMindSporeSuperResolutionResult,
  ReaderNativeBackendPreference,
  ReaderNativeModelKind,
  ReaderNativeSuperResolution,
  ReaderNativeSuperResolutionConfig,
  ReaderNativeSuperResolutionPrepareResult,
  ReaderNativeSuperResolutionResult,
  ReaderSuperResolutionBackend,
  ReaderSuperResolutionModel,
  ReaderSuperResolutionModelDefinition,
  ReaderSuperResolutionModelPaths,
  ReaderSuperResolutionModelRegistry,
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
const BENCHMARK_INPUT_WIDTH: number = 800
const BENCHMARK_INPUT_HEIGHT: number = 1149

function integrationEnabled(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionIntegration'] === 'true'
}

function benchmarkModel(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionBenchmarkModel'] ??
    ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X
}

function benchmarkBackend(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionBenchmarkBackend'] ??
    ReaderSuperResolutionBackend.VULKAN
}

function benchmarkExpectedBackend(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionBenchmarkExpectedBackend'] ??
    ReaderSuperResolutionBackend.VULKAN
}

function benchmarkSkipModelInstall(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionSkipModelInstall'] === 'true'
}

function benchmarkOutputPath(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionBenchmarkOutput'] ?? ''
}

async function installExternalMindSporeModelForBenchmark(
  context: common.UIAbilityContext,
): Promise<void> {
  const sourcePath: string = await prepareExternalMindSporeModel(context)
  if (sourcePath.length === 0) {
    return
  }
  let fileName: string = 'realesrgan-x2plus-180-fp16.ms'
  if (benchmarkModel() === ReaderSuperResolutionModel.ESPCN_X2) {
    fileName = 'espcn-x2-180-fp16.ms'
  } else if (benchmarkModel() === ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X) {
    fileName = 'waifu2x-photo-noise0-x2-156-fp16.ms'
  } else if (benchmarkModel() === ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X) {
    fileName = 'waifu2x-art-noise0-x2-156-fp16.ms'
  } else if (benchmarkModel() === ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X) {
    fileName = 'waifu2x-cunet-noise0-x2-164-fp16.ms'
  } else if (benchmarkModel() ===
    ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE) {
    fileName = 'realcugan-se-2x-conservative-164-fp16.ms'
  }
  const targetPath: string = context.filesDir + '/' + fileName
  if (sourcePath === targetPath) {
    return
  }
  fileIo.copyFileSync(sourcePath, targetPath)
}

function externalModelPaths(): string[] {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  const paramPath: string = parameters['-s superResolutionExternalParam'] ?? ''
  const modelPath: string = parameters['-s superResolutionExternalModel'] ?? ''
  return [paramPath, modelPath]
}

function externalModelKind(): number {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return Number.parseInt(parameters['-s superResolutionExternalKind'] ?? '2')
}

function externalTileSize(): number {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return Number.parseInt(parameters['-s superResolutionExternalTileSize'] ?? '128')
}

function externalPrepadding(): number {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return Number.parseInt(parameters['-s superResolutionExternalPrepadding'] ?? '4')
}

function externalInputName(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionExternalInputName'] ?? 'in0'
}

function externalOutputName(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionExternalOutputName'] ?? 'out0'
}

function externalMindSporeModelPath(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionExternalMindSporeModel'] ?? ''
}

function externalMindSporeModelUrl(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionExternalMindSporeUrl'] ?? ''
}

async function prepareExternalMindSporeModel(
  context: common.UIAbilityContext,
): Promise<string> {
  const existingPath: string = externalMindSporeModelPath()
  if (existingPath.length > 0 && fileIo.accessSync(existingPath)) {
    return existingPath
  }
  const url: string = externalMindSporeModelUrl()
  if (url.length === 0) {
    return existingPath
  }
  const targetPath: string = context.cacheDir + '/external-mindspore-model.ms'
  await EhHttpClient.getInstance().downloadBinaryToFileInStream(
    url,
    targetPath,
    (_loaded: number, _total: number): void => {},
    15000,
    0,
    'application/octet-stream,*/*',
    2,
    120000,
  )
  return targetPath
}

function externalMindSporeRepeats(): number {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return Math.max(
    1,
    Number.parseInt(parameters['-s superResolutionMindSporeRepeats'] ?? '1'),
  )
}

function externalMindSporeConcurrency(): number {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return Math.max(
    1,
    Number.parseInt(parameters['-s superResolutionMindSporeConcurrency'] ?? '1'),
  )
}

function externalMindSporeTarget(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionMindSporeTarget'] ?? 'nnrt'
}

function externalMindSporeNativePipelineEnabled(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionMindSporeNativePipeline'] === 'true'
}

function externalMindSporeEspcnPipelineEnabled(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionMindSporeEspcnPipeline'] === 'true'
}

function externalMindSporeRealCuganPipelineEnabled(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionMindSporeRealCuganPipeline'] === 'true'
}

function externalComparisonImagePath(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionComparisonImage'] ?? ''
}

function externalComparisonImageUrl(): string {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionComparisonImageUrl'] ?? ''
}

function forceAcceleratedModelRedownload(): boolean {
  const parameters: Record<string, string> =
    abilityDelegatorRegistry.getArguments().parameters
  return parameters['-s superResolutionForceAcceleratedDownload'] === 'true'
}

function describeTensor(tensor: mindSporeLite.MSTensor): string {
  return 'name=' + tensor.name +
    ' shape=' + tensor.shape.join('x') +
    ' elements=' + tensor.elementNum +
    ' bytes=' + tensor.dataSize +
    ' dtype=' + tensor.dtype +
    ' format=' + tensor.format
}

function benchmarkPixels(width: number, height: number): ArrayBuffer {
  const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4)
  const pixels: Uint8Array = new Uint8Array(buffer)
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const offset: number = (y * width + x) * 4
      pixels[offset] = (x * 11 + y * 3) % 251
      pixels[offset + 1] = (x * 5 + y * 7) % 241
      pixels[offset + 2] = ((x / 8 | 0) + (y / 8 | 0)) % 2 === 0 ? 32 : 224
      pixels[offset + 3] = 255
    }
  }
  return buffer
}

async function nextTimingTurn(): Promise<void> {
  await new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 16)
  })
}

class SuperResolutionComparisonInput {
  pixels: ArrayBuffer = new ArrayBuffer(0)
  width: number = 0
  height: number = 0
  stride: number = 0
}

async function comparisonInput(
  context: common.UIAbilityContext,
): Promise<SuperResolutionComparisonInput> {
  let path: string = externalComparisonImagePath()
  const url: string = externalComparisonImageUrl()
  if (url.length > 0) {
    path = context.cacheDir + '/super-resolution-comparison-input'
    await EhHttpClient.getInstance().downloadBinaryToFileInStream(
      url,
      path,
      (_loaded: number, _total: number): void => {},
      15000,
      0,
      'image/*,*/*',
      2,
      120000,
    )
  }
  const result: SuperResolutionComparisonInput =
    new SuperResolutionComparisonInput()
  if (path.length === 0) {
    result.pixels = benchmarkPixels(BENCHMARK_INPUT_WIDTH, BENCHMARK_INPUT_HEIGHT)
    result.width = BENCHMARK_INPUT_WIDTH
    result.height = BENCHMARK_INPUT_HEIGHT
    result.stride = BENCHMARK_INPUT_WIDTH * 4
    return result
  }
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(path)
    if (source === undefined) {
      throw new Error('Comparison image source is unavailable: ' + path)
    }
    pixelMap = await source.createPixelMap({
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    })
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    result.pixels = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    await pixelMap.readPixelsToBuffer(result.pixels)
    result.width = info.size.width
    result.height = info.size.height
    result.stride = Math.max(Math.floor(info.stride), result.width * 4)
    return result
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
  }
}

function verifyRawOutputHasSignal(buffer: ArrayBuffer): void {
  const pixels: Uint8Array = new Uint8Array(buffer)
  let minimum: number = 255
  let maximum: number = 0
  for (let index: number = 0; index + 2 < pixels.length; index += 4) {
    minimum = Math.min(minimum, pixels[index], pixels[index + 1], pixels[index + 2])
    maximum = Math.max(maximum, pixels[index], pixels[index + 1], pixels[index + 2])
  }
  console.info(
    'ReaderSuperResolutionExternalBenchmark outputSignal=' + minimum + '..' + maximum,
  )
  expect(maximum - minimum).assertLarger(16)
}

function compareRgbaOutputs(
  reference: ArrayBuffer,
  candidate: ArrayBuffer,
  outputWidth: number,
  outputHeight: number,
): number {
  expect(candidate.byteLength).assertEqual(reference.byteLength)
  const referencePixels: Uint8Array = new Uint8Array(reference)
  const candidatePixels: Uint8Array = new Uint8Array(candidate)
  let absoluteError: number = 0
  let maximumError: number = 0
  let overFour: number = 0
  let overSixteen: number = 0
  let overSixtyFour: number = 0
  let severeMinimumX: number = outputWidth
  let severeMinimumY: number = outputHeight
  let severeMaximumX: number = -1
  let severeMaximumY: number = -1
  let severeExamples: string = ''
  let samples: number = 0
  for (let index: number = 0; index + 2 < referencePixels.length; index += 4) {
    for (let channel: number = 0; channel < 3; channel++) {
      const error: number = Math.abs(
        referencePixels[index + channel] - candidatePixels[index + channel],
      )
      absoluteError += error
      maximumError = Math.max(maximumError, error)
      if (error > 4) {
        overFour += 1
      }
      if (error > 16) {
        overSixteen += 1
      }
      if (error > 64) {
        overSixtyFour += 1
        const pixelIndex: number = Math.floor(index / 4)
        const x: number = pixelIndex % outputWidth
        const y: number = Math.floor(pixelIndex / outputWidth)
        severeMinimumX = Math.min(severeMinimumX, x)
        severeMinimumY = Math.min(severeMinimumY, y)
        severeMaximumX = Math.max(severeMaximumX, x)
        severeMaximumY = Math.max(severeMaximumY, y)
        if (overSixtyFour <= 8) {
          severeExamples +=
            (severeExamples.length === 0 ? '' : ';') +
              x + ',' + y + ',' + channel + ':' +
              referencePixels[index + channel] + '>' +
              candidatePixels[index + channel]
        }
      }
      samples += 1
    }
  }
  const meanAbsoluteError: number = samples === 0 ? 0 : absoluteError / samples
  console.info(
    'ReaderSuperResolutionMindSporeComparison meanAbsoluteError=' + meanAbsoluteError +
      ' maximumError=' + maximumError +
      ' overFour=' + overFour +
      ' overSixteen=' + overSixteen +
      ' overSixtyFour=' + overSixtyFour +
      ' severeBounds=' + severeMinimumX + ',' + severeMinimumY + '-' +
        severeMaximumX + ',' + severeMaximumY +
      ' severeExamples=' + severeExamples +
      ' samples=' + samples,
  )
  return meanAbsoluteError
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

class ReaderEventLoopProbe {
  private active: boolean = false
  private expectedAt: number = 0
  private delays: number[] = []

  start(): void {
    this.active = true
    this.expectedAt = Date.now() + 16
    this.schedule()
  }

  stop(): void {
    this.active = false
  }

  sampleCount(): number {
    return this.delays.length
  }

  maximumDelayMs(): number {
    if (this.delays.length === 0) {
      return 0
    }
    return Math.max(...this.delays)
  }

  percentile95DelayMs(): number {
    if (this.delays.length === 0) {
      return 0
    }
    const ordered: number[] = this.delays.slice().sort((left: number, right: number): number => {
      return left - right
    })
    const index: number = Math.min(
      ordered.length - 1,
      Math.floor(ordered.length * 0.95),
    )
    return ordered[index]
  }

  private schedule(): void {
    setTimeout((): void => {
      if (!this.active) {
        return
      }
      const now: number = Date.now()
      this.delays.push(Math.max(0, now - this.expectedAt))
      this.expectedAt = now + 16
      this.schedule()
    }, 16)
  }
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
    it('downloadsPublishedWaifu2xRuntimeAsset', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      ReaderSuperResolutionModelService.remove(
        context,
        ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
      )
      expect(await ReaderSuperResolutionModelService.isWaifu2xInstalled(context))
        .assertEqual(false)
      await ReaderSuperResolutionModelService.installWaifu2x(context)
      expect(await ReaderSuperResolutionModelService.isWaifu2xInstalled(context))
        .assertEqual(true)
      const acceleratedPath: string | null =
        ReaderSuperResolutionModelService.acceleratedModelPathIfReady(
          context,
          ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
        )
      expect(acceleratedPath !== null).assertEqual(true)
      if (acceleratedPath !== null) {
        expect(fileIo.accessSync(acceleratedPath)).assertEqual(true)
      }
      done()
    })

    it('downloadsPublishedEspcnRuntimeAndAcceleratedAssets', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      ReaderSuperResolutionModelService.remove(
        context,
        ReaderSuperResolutionModel.ESPCN_X2,
      )
      await ReaderSuperResolutionModelService.install(
        context,
        ReaderSuperResolutionModel.ESPCN_X2,
      )
      const paths: ReaderSuperResolutionModelPaths | null =
        await ReaderSuperResolutionModelService.pathsIfReady(
          context,
          ReaderSuperResolutionModel.ESPCN_X2,
        )
      expect(paths !== null).assertEqual(true)
      if (paths !== null) {
        expect(fileIo.accessSync(paths.paramPath)).assertEqual(true)
        expect(fileIo.accessSync(paths.modelPath)).assertEqual(true)
      }
      const acceleratedPath: string | null =
        ReaderSuperResolutionModelService.acceleratedModelPathIfReady(
          context,
          ReaderSuperResolutionModel.ESPCN_X2,
        )
      expect(acceleratedPath !== null).assertEqual(true)
      if (acceleratedPath !== null) {
        expect(fileIo.accessSync(acceleratedPath)).assertEqual(true)
      }
      done()
    })

    it('downloadsPublishedRealCuganRuntimeAndAcceleratedAssets', 0,
      async (done: Function) => {
        if (!integrationEnabled()) {
          done()
          return
        }
        const context: common.UIAbilityContext = await appContext()
        ReaderSuperResolutionModelService.remove(
          context,
          ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
        )
        await ReaderSuperResolutionModelService.install(
          context,
          ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
        )
        const paths: ReaderSuperResolutionModelPaths | null =
          await ReaderSuperResolutionModelService.pathsIfReady(
            context,
            ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
          )
        expect(paths !== null).assertEqual(true)
        if (paths !== null) {
          expect(fileIo.accessSync(paths.paramPath)).assertEqual(true)
          expect(fileIo.accessSync(paths.modelPath)).assertEqual(true)
        }
        const acceleratedPath: string | null =
          ReaderSuperResolutionModelService.acceleratedModelPathIfReady(
            context,
            ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
          )
        expect(acceleratedPath !== null).assertEqual(true)
        if (acceleratedPath !== null) {
          expect(fileIo.accessSync(acceleratedPath)).assertEqual(true)
        }
        done()
      })

    it('downloadsPublishedWaifu2xArtRuntimeAndAcceleratedAssets', 0,
      async (done: Function) => {
        if (!integrationEnabled()) {
          done()
          return
        }
        const context: common.UIAbilityContext = await appContext()
        const model: string = ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X
        ReaderSuperResolutionModelService.remove(context, model)
        await ReaderSuperResolutionModelService.install(context, model)
        const paths: ReaderSuperResolutionModelPaths | null =
          await ReaderSuperResolutionModelService.pathsIfReady(context, model)
        expect(paths !== null).assertEqual(true)
        if (paths !== null) {
          expect(fileIo.accessSync(paths.paramPath)).assertEqual(true)
          expect(fileIo.accessSync(paths.modelPath)).assertEqual(true)
        }
        const acceleratedPath: string | null =
          ReaderSuperResolutionModelService.acceleratedModelPathIfReady(context, model)
        expect(acceleratedPath !== null).assertEqual(true)
        if (acceleratedPath !== null) {
          expect(fileIo.accessSync(acceleratedPath)).assertEqual(true)
        }
        done()
      })

    it('downloadsPublishedWaifu2xCunetRuntimeAndAcceleratedAssets', 0,
      async (done: Function) => {
        if (!integrationEnabled()) {
          done()
          return
        }
        const context: common.UIAbilityContext = await appContext()
        const model: string = ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X
        ReaderSuperResolutionModelService.remove(context, model)
        await ReaderSuperResolutionModelService.install(context, model)
        const paths: ReaderSuperResolutionModelPaths | null =
          await ReaderSuperResolutionModelService.pathsIfReady(context, model)
        expect(paths !== null).assertEqual(true)
        if (paths !== null) {
          expect(fileIo.accessSync(paths.paramPath)).assertEqual(true)
          expect(fileIo.accessSync(paths.modelPath)).assertEqual(true)
        }
        const acceleratedPath: string | null =
          ReaderSuperResolutionModelService.acceleratedModelPathIfReady(context, model)
        expect(acceleratedPath !== null).assertEqual(true)
        if (acceleratedPath !== null) {
          expect(fileIo.accessSync(acceleratedPath)).assertEqual(true)
        }
        done()
      })

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

    it('preparesSelectedModelBeforeReaderInference', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const sourcePath: string =
        context.cacheDir + '/reader-super-resolution-prepared-waifu2x-input.jpg'
      const previousEnabled: boolean = connectReadMode().superResolutionEnabled
      const previousModel: string = connectReadMode().superResolutionModel
      const previousBackend: string = connectReadMode().superResolutionBackend
      try {
        await ReaderSuperResolutionModelService.installWaifu2x(context)
        connectReadMode().superResolutionEnabled = true
        connectReadMode().superResolutionModel = ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X
        connectReadMode().superResolutionBackend = ReaderSuperResolutionBackend.VULKAN
        await ReaderSuperResolutionService.prepareSelectedModel(context)
        await writeTestImage(sourcePath)
        await verifyModel(
          context,
          ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
          ReaderSuperResolutionBackend.VULKAN,
          sourcePath,
          'ohos-test-prepared-waifu2x-vulkan',
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

    it('benchmarksReaderSizedSelectedModel', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const model: string = benchmarkModel()
      const backend: string = benchmarkBackend()
      const expectedBackend: string = benchmarkExpectedBackend()
      const sourcePath: string =
        context.cacheDir + '/reader-super-resolution-benchmark-input.jpg'
      const previousEnabled: boolean = connectReadMode().superResolutionEnabled
      const previousModel: string = connectReadMode().superResolutionModel
      const previousBackend: string = connectReadMode().superResolutionBackend
      const previousMaxHeight: number = connectReadMode().superResolutionMaxHeight
      try {
        await ReaderSuperResolutionService.clear(context)
        await installExternalMindSporeModelForBenchmark(context)
        if (!benchmarkSkipModelInstall()) {
          await ReaderSuperResolutionModelService.install(context, model)
        }
        connectReadMode().superResolutionEnabled = true
        connectReadMode().superResolutionModel = model
        connectReadMode().superResolutionBackend = backend
        connectReadMode().superResolutionMaxHeight = 2000
        await writeTestImage(sourcePath, BENCHMARK_INPUT_WIDTH, BENCHMARK_INPUT_HEIGHT)
        const preparationStartedAt: number = Date.now()
        await ReaderSuperResolutionService.prepareSelectedModel(context)
        const preparationElapsedMs: number = Date.now() - preparationStartedAt
        const eventLoopProbe: ReaderEventLoopProbe = new ReaderEventLoopProbe()
        eventLoopProbe.start()
        const result: ReaderSuperResolutionResult =
          await ReaderSuperResolutionService.process(
            context,
            sourcePath,
            `ohos-test-reader-benchmark-${model}`,
          )
        eventLoopProbe.stop()
        console.info(
          'ReaderSuperResolutionBenchmark model=' + model +
            ' source=' + BENCHMARK_INPUT_WIDTH + 'x' + BENCHMARK_INPUT_HEIGHT +
            ' preparationElapsedMs=' + preparationElapsedMs +
            ' processElapsedMs=' + result.elapsedMs +
            ' backendPreference=' + backend +
            ' backend=' + result.backend +
            ' reason=' + result.reason +
            ' eventLoopSamples=' + eventLoopProbe.sampleCount() +
            ' eventLoopP95DelayMs=' + eventLoopProbe.percentile95DelayMs() +
            ' eventLoopMaxDelayMs=' + eventLoopProbe.maximumDelayMs(),
        )
        if (!result.applied) {
          throw new Error(
            'Reader super-resolution benchmark failed: reason=' + result.reason +
              ' backend=' + result.backend,
          )
        }
        expect(result.applied).assertEqual(true)
        expect(result.sourceWidth).assertEqual(BENCHMARK_INPUT_WIDTH)
        expect(result.sourceHeight).assertEqual(BENCHMARK_INPUT_HEIGHT)
        expect(result.outputWidth).assertEqual(BENCHMARK_INPUT_WIDTH * 2)
        expect(result.outputHeight).assertEqual(BENCHMARK_INPUT_HEIGHT * 2)
        expect(result.backend).assertEqual(expectedBackend)
        expect(fileIo.accessSync(result.filePath)).assertEqual(true)
        const outputPath: string = benchmarkOutputPath()
        if (outputPath.length > 0) {
          fileIo.copyFileSync(result.filePath, outputPath)
          console.info('ReaderSuperResolutionBenchmark preservedOutput=' + outputPath)
        }
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

    it('benchmarksExternalModel', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const modelPaths: string[] = externalModelPaths()
      const paramPath: string = modelPaths[0]
      const modelPath: string = modelPaths[1]
      if (paramPath.length === 0 || modelPath.length === 0) {
        done()
        return
      }
      expect(fileIo.accessSync(paramPath)).assertEqual(true)
      expect(fileIo.accessSync(modelPath)).assertEqual(true)
      const config: ReaderNativeSuperResolutionConfig =
        new ReaderNativeSuperResolutionConfig()
      config.modelKind = externalModelKind()
      config.backendPreference = ReaderNativeBackendPreference.VULKAN
      config.tileSize = externalTileSize()
      config.prepadding = externalPrepadding()
      config.threads = 2
      config.inputName = externalInputName()
      config.outputName = externalOutputName()
      const startedAt: number = Date.now()
      const prepared: ReaderNativeSuperResolutionPrepareResult =
        await ReaderNativeSuperResolution.prepareModel(paramPath, modelPath, config)
      const input: ArrayBuffer = benchmarkPixels(
        BENCHMARK_INPUT_WIDTH,
        BENCHMARK_INPUT_HEIGHT,
      )
      const result: ReaderNativeSuperResolutionResult =
        await ReaderNativeSuperResolution.upscaleRgba(
          input,
          BENCHMARK_INPUT_WIDTH,
          BENCHMARK_INPUT_HEIGHT,
          BENCHMARK_INPUT_WIDTH * 4,
          paramPath,
          modelPath,
          config,
          900001,
        )
      const totalElapsedMs: number = Date.now() - startedAt
      console.info(
        'ReaderSuperResolutionExternalBenchmark source=' +
          BENCHMARK_INPUT_WIDTH + 'x' + BENCHMARK_INPUT_HEIGHT +
          ' kind=' + config.modelKind +
          ' tileSize=' + config.tileSize +
          ' preparationMs=' + prepared.modelLoadMs +
          ' inferenceMs=' + result.inferenceMs +
          ' totalElapsedMs=' + totalElapsedMs +
          ' backend=' + result.backend,
      )
      expect(prepared.backend).assertEqual(ReaderSuperResolutionBackend.VULKAN)
      expect(result.backend).assertEqual(ReaderSuperResolutionBackend.VULKAN)
      expect(result.pixels.byteLength).assertEqual(
        BENCHMARK_INPUT_WIDTH * 2 * BENCHMARK_INPUT_HEIGHT * 2 * 4,
      )
      verifyRawOutputHasSignal(result.pixels)
      done()
    })

    it('benchmarksExternalMindSporeModel', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const app: common.UIAbilityContext = await appContext()
      const modelPath: string = await prepareExternalMindSporeModel(app)
      if (modelPath.length === 0) {
        done()
        return
      }
      expect(fileIo.accessSync(modelPath)).assertEqual(true)
      const devices: mindSporeLite.NNRTDeviceDescription[] =
        mindSporeLite.getAllNNRTDeviceDescriptions()
      let selectedDevice: mindSporeLite.NNRTDeviceDescription | undefined = undefined
      for (let index: number = 0; index < devices.length; index++) {
        const device: mindSporeLite.NNRTDeviceDescription = devices[index]
        console.info(
          'ReaderSuperResolutionMindSporeBenchmark device=' + device.deviceName() +
            ' id=' + device.deviceID().toString() +
            ' type=' + device.deviceType(),
        )
        if (selectedDevice === undefined &&
          device.deviceType() === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR) {
          selectedDevice = device
        }
      }
      expect(selectedDevice !== undefined).assertEqual(true)
      if (selectedDevice === undefined) {
        done()
        return
      }
      const target: string = externalMindSporeTarget()
      let context: mindSporeLite.Context = {
        target: ['cpu'],
        cpu: {
          threadNum: 4,
          threadAffinityMode: mindSporeLite.ThreadAffinityMode.BIG_CORES_FIRST,
          precisionMode: 'preferred_fp16',
        },
      }
      if (target === 'nnrt') {
        context = {
          target: ['nnrt'],
          nnrt: {
            deviceID: selectedDevice.deviceID(),
            performanceMode: mindSporeLite.PerformanceMode.PERFORMANCE_HIGH,
            priority: mindSporeLite.Priority.PRIORITY_LOW,
          },
        }
      }
      const repeats: number = externalMindSporeRepeats()
      const concurrency: number = Math.min(externalMindSporeConcurrency(), repeats)
      const loadStartedAt: number = Date.now()
      const models: mindSporeLite.Model[] = []
      const modelInputs: mindSporeLite.MSTensor[][] = []
      for (let modelIndex: number = 0; modelIndex < concurrency; modelIndex++) {
        const model: mindSporeLite.Model =
          await mindSporeLite.loadModelFromFile(modelPath, context)
        const inputs: mindSporeLite.MSTensor[] = model.getInputs()
        if (inputs === undefined || inputs === null) {
          throw new Error(
            'MindSpore model inputs unavailable after load target=' + target +
              ' model=' + modelPath,
          )
        }
        expect(inputs.length).assertEqual(1)
        models.push(model)
        modelInputs.push(inputs)
      }
      const modelLoadMs: number = Date.now() - loadStartedAt
      const input: mindSporeLite.MSTensor = modelInputs[0][0]
      console.info(
        'ReaderSuperResolutionMindSporeBenchmark input ' + describeTensor(input),
      )
      expect(input.dtype).assertEqual(mindSporeLite.DataType.NUMBER_TYPE_FLOAT32)
      const inputValues: Float32Array = new Float32Array(input.elementNum)
      for (let index: number = 0; index < inputValues.length; index++) {
        inputValues[index] = (index % 251) / 250.0
      }
      for (let modelIndex: number = 0; modelIndex < concurrency; modelIndex++) {
        modelInputs[modelIndex][0].setData(inputValues.buffer)
      }
      const predictionStartedAt: number = Date.now()
      let firstPredictionMs: number = 0
      let outputs: mindSporeLite.MSTensor[] = []
      let completed: number = 0
      while (completed < repeats) {
        const batchSize: number = Math.min(concurrency, repeats - completed)
        const batchStartedAt: number = Date.now()
        const predictions: Promise<mindSporeLite.MSTensor[]>[] = []
        for (let modelIndex: number = 0; modelIndex < batchSize; modelIndex++) {
          predictions.push(models[modelIndex].predict(modelInputs[modelIndex]))
        }
        const batchOutputs: mindSporeLite.MSTensor[][] = await Promise.all(predictions)
        outputs = batchOutputs[batchOutputs.length - 1]
        if (completed === 0) {
          firstPredictionMs = Date.now() - batchStartedAt
        }
        completed += batchSize
      }
      const predictionMs: number = Date.now() - predictionStartedAt
      expect(outputs.length).assertLarger(0)
      const output: mindSporeLite.MSTensor = outputs[0]
      console.info(
        'ReaderSuperResolutionMindSporeBenchmark output ' + describeTensor(output),
      )
      const outputData: ArrayBuffer = output.getData()
      expect(outputData.byteLength).assertEqual(output.dataSize)
      let minimum: number = Number.MAX_VALUE
      let maximum: number = -Number.MAX_VALUE
      if (output.dtype === mindSporeLite.DataType.NUMBER_TYPE_FLOAT32) {
        const outputValues: Float32Array = new Float32Array(outputData)
        for (let index: number = 0; index < outputValues.length; index++) {
          minimum = Math.min(minimum, outputValues[index])
          maximum = Math.max(maximum, outputValues[index])
        }
      }
      console.info(
        'ReaderSuperResolutionMindSporeBenchmark model=' + modelPath +
          ' target=' + target +
          ' device=' + selectedDevice.deviceName() +
          ' modelLoadMs=' + modelLoadMs +
          ' repeats=' + repeats +
          ' concurrency=' + concurrency +
          ' firstPredictionMs=' + firstPredictionMs +
          ' totalPredictionMs=' + predictionMs +
          ' averagePredictionMs=' + Math.round(predictionMs / repeats) +
          ' outputSignal=' + minimum + '..' + maximum,
      )
      expect(maximum > minimum).assertEqual(true)
      done()
    })

    it('comparesExternalMindSporeWithWaifu2xVulkan', 0, async (done: Function) => {
      if (!integrationEnabled() || !externalMindSporeNativePipelineEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const mindSporeModelPath: string = await prepareExternalMindSporeModel(context)
      if (mindSporeModelPath.length === 0) {
        done()
        return
      }
      const model: string = benchmarkModel()
      const definition: ReaderSuperResolutionModelDefinition | null =
        ReaderSuperResolutionModelRegistry.find(model)
      expect(definition !== null).assertEqual(true)
      if (definition === null) {
        done()
        return
      }
      await ReaderSuperResolutionModelService.install(context, model)
      const modelPaths: ReaderSuperResolutionModelPaths | null =
        await ReaderSuperResolutionModelService.pathsIfReady(context, model)
      expect(modelPaths !== null).assertEqual(true)
      if (modelPaths === null) {
        done()
        return
      }
      const config: ReaderNativeSuperResolutionConfig = definition.nativeConfig()
      config.backendPreference = ReaderNativeBackendPreference.VULKAN
      const input: SuperResolutionComparisonInput = await comparisonInput(context)
      const ncnnStartedAt: number = Date.now()
      const ncnnResult: ReaderNativeSuperResolutionResult =
        await ReaderNativeSuperResolution.upscaleRgba(
          input.pixels,
          input.width,
          input.height,
          input.stride,
          modelPaths.paramPath,
          modelPaths.modelPath,
          config,
          900002,
        )
      const ncnnElapsedMs: number = Date.now() - ncnnStartedAt
      await nextTimingTurn()
      const nnrtStartedAt: number = Date.now()
      const nnrtResult: ReaderMindSporeSuperResolutionResult =
        await ReaderMindSporeSuperResolution.upscaleRgba(
          input.pixels.slice(0),
          input.width,
          input.height,
          input.stride,
          mindSporeModelPath,
          definition.nativeModelKind,
          900003,
        )
      const nnrtElapsedMs: number = Date.now() - nnrtStartedAt
      const meanAbsoluteError: number = compareRgbaOutputs(
        ncnnResult.pixels,
        nnrtResult.pixels,
        input.width * 2,
        input.height * 2,
      )
      console.info(
        'ReaderSuperResolutionMindSporeComparison source=' +
          input.width + 'x' + input.height +
          ' ncnnElapsedMs=' + ncnnElapsedMs +
          ' ncnnInferenceMs=' + ncnnResult.inferenceMs +
          ' nnrtElapsedMs=' + nnrtElapsedMs +
          ' nnrtInferenceMs=' + nnrtResult.inferenceMs +
          ' nnrtTiles=' + nnrtResult.tileCount,
      )
      expect(ncnnResult.backend).assertEqual(ReaderSuperResolutionBackend.VULKAN)
      expect(nnrtResult.backend).assertEqual('nnrt')
      expect(meanAbsoluteError < 3).assertEqual(true)
      verifyRawOutputHasSignal(nnrtResult.pixels)
      done()
    })

    it('comparesExternalMindSporeWithRealCuganVulkan', 0, async (done: Function) => {
      if (!integrationEnabled() || !externalMindSporeRealCuganPipelineEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const mindSporeModelPath: string = await prepareExternalMindSporeModel(context)
      if (mindSporeModelPath.length === 0) {
        done()
        return
      }
      const installedMindSporeModelPath: string =
        context.filesDir + '/realcugan-se-2x-conservative-164-fp16.ms'
      if (mindSporeModelPath !== installedMindSporeModelPath) {
        fileIo.copyFileSync(mindSporeModelPath, installedMindSporeModelPath)
      }
      await ReaderSuperResolutionModelService.install(
        context,
        ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
      )
      const modelPaths: ReaderSuperResolutionModelPaths | null =
        await ReaderSuperResolutionModelService.pathsIfReady(
          context,
          ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE,
        )
      expect(modelPaths !== null).assertEqual(true)
      if (modelPaths === null) {
        done()
        return
      }
      const config: ReaderNativeSuperResolutionConfig =
        new ReaderNativeSuperResolutionConfig()
      config.modelKind = ReaderNativeModelKind.REAL_CUGAN
      config.backendPreference = ReaderNativeBackendPreference.VULKAN
      config.tileSize = 128
      config.prepadding = 18
      config.threads = 2
      config.inputName = 'in0'
      config.outputName = 'out0'
      const input: SuperResolutionComparisonInput = await comparisonInput(context)
      const ncnnStartedAt: number = Date.now()
      const ncnnResult: ReaderNativeSuperResolutionResult =
        await ReaderNativeSuperResolution.upscaleRgba(
          input.pixels,
          input.width,
          input.height,
          input.stride,
          modelPaths.paramPath,
          modelPaths.modelPath,
          config,
          900006,
        )
      const ncnnElapsedMs: number = Date.now() - ncnnStartedAt
      await nextTimingTurn()
      const nnrtInput: ArrayBuffer = input.pixels.slice(0)
      const nnrtStartedAt: number = Date.now()
      const nnrtResult: ReaderMindSporeSuperResolutionResult =
        await ReaderMindSporeSuperResolution.upscaleRgba(
          nnrtInput,
          input.width,
          input.height,
          input.stride,
          installedMindSporeModelPath,
          ReaderNativeModelKind.REAL_CUGAN,
          900007,
        )
      const nnrtElapsedMs: number = Date.now() - nnrtStartedAt
      const meanAbsoluteError: number = compareRgbaOutputs(
        ncnnResult.pixels,
        nnrtResult.pixels,
        input.width * 2,
        input.height * 2,
      )
      console.info(
        'ReaderSuperResolutionRealCuganMindSporeComparison source=' +
          input.width + 'x' + input.height +
          ' ncnnElapsedMs=' + ncnnElapsedMs +
          ' ncnnInferenceMs=' + ncnnResult.inferenceMs +
          ' nnrtElapsedMs=' + nnrtElapsedMs +
          ' nnrtInferenceMs=' + nnrtResult.inferenceMs +
          ' nnrtTiles=' + nnrtResult.tileCount,
      )
      expect(ncnnResult.backend).assertEqual(ReaderSuperResolutionBackend.VULKAN)
      expect(nnrtResult.backend).assertEqual('nnrt')
      expect(meanAbsoluteError < 3).assertEqual(true)
      verifyRawOutputHasSignal(nnrtResult.pixels)
      done()
    })

    it('comparesExternalMindSporeWithEspcnVulkan', 0, async (done: Function) => {
      if (!integrationEnabled() || !externalMindSporeEspcnPipelineEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const mindSporeModelPath: string = await prepareExternalMindSporeModel(context)
      if (mindSporeModelPath.length === 0) {
        done()
        return
      }
      await ReaderSuperResolutionModelService.install(
        context,
        ReaderSuperResolutionModel.ESPCN_X2,
      )
      const modelPaths: ReaderSuperResolutionModelPaths | null =
        await ReaderSuperResolutionModelService.pathsIfReady(
          context,
          ReaderSuperResolutionModel.ESPCN_X2,
        )
      expect(modelPaths !== null).assertEqual(true)
      if (modelPaths === null) {
        done()
        return
      }
      const config: ReaderNativeSuperResolutionConfig =
        new ReaderNativeSuperResolutionConfig()
      config.modelKind = ReaderNativeModelKind.LUMINANCE
      config.backendPreference = ReaderNativeBackendPreference.VULKAN
      config.tileSize = 128
      config.prepadding = 4
      config.threads = 2
      config.inputName = 'in0'
      config.outputName = 'out0'
      const input: SuperResolutionComparisonInput = await comparisonInput(context)
      const ncnnStartedAt: number = Date.now()
      const ncnnResult: ReaderNativeSuperResolutionResult =
        await ReaderNativeSuperResolution.upscaleRgba(
          input.pixels,
          input.width,
          input.height,
          input.stride,
          modelPaths.paramPath,
          modelPaths.modelPath,
          config,
          900004,
        )
      const ncnnElapsedMs: number = Date.now() - ncnnStartedAt
      await nextTimingTurn()
      const nnrtInput: ArrayBuffer = input.pixels.slice(0)
      const nnrtStartedAt: number = Date.now()
      const nnrtResult: ReaderMindSporeSuperResolutionResult =
        await ReaderMindSporeSuperResolution.upscaleRgba(
          nnrtInput,
          input.width,
          input.height,
          input.stride,
          mindSporeModelPath,
          ReaderNativeModelKind.LUMINANCE,
          900005,
        )
      const nnrtElapsedMs: number = Date.now() - nnrtStartedAt
      const meanAbsoluteError: number = compareRgbaOutputs(
        ncnnResult.pixels,
        nnrtResult.pixels,
        input.width * 2,
        input.height * 2,
      )
      console.info(
        'ReaderSuperResolutionEspcnMindSporeComparison source=' +
          input.width + 'x' + input.height +
          ' ncnnElapsedMs=' + ncnnElapsedMs +
          ' ncnnInferenceMs=' + ncnnResult.inferenceMs +
          ' nnrtElapsedMs=' + nnrtElapsedMs +
          ' nnrtInferenceMs=' + nnrtResult.inferenceMs +
          ' nnrtTiles=' + nnrtResult.tileCount,
      )
      expect(ncnnResult.backend).assertEqual(ReaderSuperResolutionBackend.VULKAN)
      expect(nnrtResult.backend).assertEqual('nnrt')
      expect(meanAbsoluteError < 3).assertEqual(true)
      verifyRawOutputHasSignal(nnrtResult.pixels)
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

    it('downloadsRealEsrganAcceleratedAsset', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      const context: common.UIAbilityContext = await appContext()
      const existingPath: string | null =
        ReaderSuperResolutionModelService.realEsrganNnrtPathIfReady(context)
      if (forceAcceleratedModelRedownload() && existingPath !== null) {
        fileIo.unlinkSync(existingPath)
      }
      await ReaderSuperResolutionModelService.installRealEsrgan(context)
      const installedPath: string | null =
        ReaderSuperResolutionModelService.realEsrganNnrtPathIfReady(context)
      expect(installedPath !== null).assertEqual(true)
      if (installedPath !== null) {
        expect(fileIo.accessSync(installedPath)).assertEqual(true)
      }
      expect(await ReaderSuperResolutionModelService.isRealEsrganInstalled(context))
        .assertEqual(true)
      done()
    })

    it('runsEspcnThroughVulkan', 0, async (done: Function) => {
      if (!integrationEnabled()) {
        done()
        return
      }
      await verifyDownloadedModelThroughVulkan(
        ReaderSuperResolutionModel.ESPCN_X2,
        'espcn',
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
