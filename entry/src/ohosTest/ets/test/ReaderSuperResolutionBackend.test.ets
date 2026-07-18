import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  connectReadMode,
  ReaderSuperResolutionBackend,
  ReaderSuperResolutionCapabilities,
  ReaderNnrtCapabilities,
  ReaderNnrtCapabilityProbe,
  ReaderSuperResolutionModel,
  ReaderSuperResolutionService,
} from 'shared'

const OVERSIZED_WIDTH: number = 1280
const OVERSIZED_HEIGHT: number = 1810

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

async function writeTestImage(path: string, width: number, height: number): Promise<void> {
  let pixelMap: image.PixelMap | undefined = undefined
  let packer: image.ImagePacker | undefined = undefined
  let outputFile: fileIo.File | null = null
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4)
    const pixels: Uint8Array = new Uint8Array(buffer)
    for (let index: number = 0; index < pixels.length; index += 4) {
      pixels[index] = index % 251
      pixels[index + 1] = (index / 4) % 241
      pixels[index + 2] = 127
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

function writeMarker(path: string): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(file.fd, 'enhanced-cache-marker')
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

export default function readerSuperResolutionBackendTest(): void {
  describe('ReaderSuperResolutionBackend', () => {
    it('reports the native ncnn and Vulkan capability contract', 0, (done: Function) => {
      const capabilities: ReaderSuperResolutionCapabilities =
        ReaderSuperResolutionService.capabilities()
      console.info(
        `ReaderSuperResolutionBackend ncnn=${capabilities.ncnnVersion} ` +
          `vulkan=${capabilities.vulkanAvailable} gpu=${capabilities.gpuName}`,
      )
      expect(capabilities.ncnnVersion.length > 0).assertEqual(true)
      if (capabilities.vulkanAvailable) {
        expect(capabilities.gpuName.length > 0).assertEqual(true)
      }
      const nnrt: ReaderNnrtCapabilities = ReaderNnrtCapabilityProbe.probe()
      console.info(
        `ReaderSuperResolutionBackend nnrtCount=${nnrt.deviceCount} ` +
          `accelerator=${nnrt.acceleratorAvailable} devices=${nnrt.deviceNames.join(',')}`,
      )
      expect(nnrt.deviceCount >= 0).assertEqual(true)
      done()
    })

    it('skips a source above the configured maximum height before invoking the enhancer', 0,
      async (done: Function) => {
        const context: common.UIAbilityContext = await appContext()
        const sourcePath: string = `${context.cacheDir}/reader-super-resolution-oversized-input.jpg`
        const previousEnabled: boolean = connectReadMode().superResolutionEnabled
        const previousModel: string = connectReadMode().superResolutionModel
        const previousBackend: string = connectReadMode().superResolutionBackend
        const previousMaxHeight: number = connectReadMode().superResolutionMaxHeight
        try {
          await writeTestImage(sourcePath, OVERSIZED_WIDTH, OVERSIZED_HEIGHT)
          connectReadMode().superResolutionEnabled = true
          connectReadMode().superResolutionModel = ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X
          connectReadMode().superResolutionBackend = ReaderSuperResolutionBackend.AUTO
          connectReadMode().superResolutionMaxHeight = 1500
          const result = await ReaderSuperResolutionService.process(
            context,
            sourcePath,
            'ohos-test-reader-super-resolution-oversized',
          )
          console.info(
            `ReaderSuperResolutionService source=${result.sourceWidth}x${result.sourceHeight} ` +
              `applied=${result.applied} reason=${result.reason} elapsedMs=${result.elapsedMs}`,
          )
          expect(result.applied).assertEqual(false)
          expect(result.reason).assertEqual('height_limit')
          expect(result.sourceWidth).assertEqual(OVERSIZED_WIDTH)
          expect(result.sourceHeight).assertEqual(OVERSIZED_HEIGHT)
        } finally {
          connectReadMode().superResolutionEnabled = previousEnabled
          connectReadMode().superResolutionModel = previousModel
          connectReadMode().superResolutionBackend = previousBackend
          connectReadMode().superResolutionMaxHeight = previousMaxHeight
          try {
            fileIo.unlinkSync(sourcePath)
          } catch (_error) {}
        }
        done()
      })

    it('reports and clears generated image cache entries', 0, async (done: Function) => {
      const context: common.UIAbilityContext = await appContext()
      const cacheDir: string = `${context.cacheDir}/reader-super-resolution-cache`
      const cachePath: string = `${cacheDir}/ohos-test-cache-entry.jpg`
      try {
        try {
          fileIo.mkdirSync(cacheDir, true)
        } catch (error) {
          if (!fileIo.accessSync(cacheDir)) {
            throw error as Error
          }
        }
        writeMarker(cachePath)
        const before = await ReaderSuperResolutionService.stat(context)
        expect(before.count > 0).assertEqual(true)
        expect(before.bytes > 0).assertEqual(true)
        await ReaderSuperResolutionService.clear(context)
        const after = await ReaderSuperResolutionService.stat(context)
        expect(after.count).assertEqual(0)
        expect(after.bytes).assertEqual(0)
      } finally {
        try {
          fileIo.unlinkSync(cachePath)
        } catch (_error) {}
      }
      done()
    })
  })
}
