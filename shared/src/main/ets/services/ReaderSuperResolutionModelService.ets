import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { zlib } from '@kit.BasicServicesKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'
import { ReaderSuperResolutionModel } from '../state/ReadModeState'
import {
  ReaderSuperResolutionInstallStrategy,
  ReaderSuperResolutionModelDefinition,
  ReaderSuperResolutionModelRegistry,
} from './ReaderSuperResolutionModelRegistry'

const MODEL_DIR_NAME: string = 'reader-super-resolution-models'
const WAIFU2X_DIR_NAME: string = 'waifu2x-photo-noise0-2x-ncnn-v1'
const WAIFU2X_PARAM_FILE_NAME: string = 'noise0_scale2.0x_model.param'
const WAIFU2X_MODEL_FILE_NAME: string = 'noise0_scale2.0x_model.bin'
const WAIFU2X_PARAM_BYTES: number = 1047
const WAIFU2X_MODEL_BYTES: number = 1106248
const WAIFU2X_PARAM_SHA256: string =
  '413195ffde05b4d43807792c6c020c916cecdf25dcf002ee83f5e28d5cc246c6'
const WAIFU2X_MODEL_SHA256: string =
  'fbfc8d57e4333748c9c6db2ec4d5454c98cd1c6aa53289f2989c3bdb4e84b673'
const SOURCE_REVISION: string = '64914665c45893135c9e50c1c296170a121b9f77'
const SOURCE_PATH: string = 'models/models-upconv_7_photo'
const REAL_ESRGAN_DIR_NAME: string = 'realesrgan-x2plus-ncnn-fp32-v1'
const REAL_ESRGAN_SOURCE_PARAM_FILE_NAME: string = 'realesrgan_x2plus.param'
const REAL_ESRGAN_RUNTIME_PARAM_FILE_NAME: string = 'realesrgan_x2plus.compat.param'
const REAL_ESRGAN_MODEL_FILE_NAME: string = 'realesrgan_x2plus.bin'
const REAL_ESRGAN_SOURCE_PARAM_BYTES: number = 292200
const REAL_ESRGAN_RUNTIME_PARAM_BYTES: number = 288376
const REAL_ESRGAN_SOURCE_MODEL_BYTES: number = 66814128
const REAL_ESRGAN_RUNTIME_MODEL_BYTES: number = 66814088
const REAL_ESRGAN_MODEL_PREFIX_BYTES: number = 40
const REAL_ESRGAN_SOURCE_PARAM_SHA256: string =
  '79cb4938c0465a3b7d66aa21e9dc0e595a2ab2015b453831426f37a536b925b5'
const REAL_ESRGAN_RUNTIME_PARAM_SHA256: string =
  'b17f57a46574e28bbe405ed1d95edc99d6fa2abc777b477a2ba8399ffa3ea4dd'
const REAL_ESRGAN_SOURCE_MODEL_SHA256: string =
  '119cbbcf701a976a016d03fc5c457157e52a94f5e3e929e562e9ec87596d782b'
const REAL_ESRGAN_RUNTIME_MODEL_SHA256: string =
  '80154ed738cd609c639fed031e9d2bc5d612f4895b91b73e623e88fa0c19f8b9'
// The pinned NCNN pair was audited locally against the official RealESRGAN_x2plus
// params_ema checkpoint: all 351 convolution weights and biases matched bit-for-bit.
const REAL_ESRGAN_SOURCE_REVISION: string = '2533a62c56b4f080eb90a039250752bc21e96259'
const REAL_ESRGAN_SOURCE_REPOSITORY: string = 'bpawnzZ/Real-ESRGAN-x2plus-NCNN'
const DOWNLOAD_CONNECT_TIMEOUT_MS: number = 15000
const DOWNLOAD_READ_TIMEOUT_MS: number = 10 * 60 * 1000
const HASH_CHUNK_BYTES: number = 256 * 1024
const ESPCN_PACKAGE_FILE_NAME: string = 'espcn_x2.download.zip'
const ESPCN_EXTRACT_DIR_NAME: string = 'espcn_x2.extract'
const ESPCN_ONNX_FILE_NAME: string = 'espcn_x2_156x240.onnx'
const ESPCN_ONNX_BYTES: number = 86056
const ESPCN_ONNX_SHA256: string =
  '6004f76f2699323e72186dae30f5e611dfb58478109391391bbc003dfbab950e'
const ESPCN_NCNN_FP16_TAG: number = 0x01306b47
const ESPCN_RUNTIME_PARAM: string =
  '7767517\n' +
  '7 7\n' +
  'Input                    in0                      0 1 in0\n' +
  'Convolution              conv_3                   1 1 in0 1 0=64 1=5 11=5 12=1 13=1 14=2 2=1 3=1 4=2 5=1 6=1600\n' +
  'TanH                     tanh_1                   1 1 1 2\n' +
  'Convolution              conv_4                   1 1 2 3 0=32 1=3 11=3 12=1 13=1 14=1 2=1 3=1 4=1 5=1 6=18432\n' +
  'TanH                     tanh_2                   1 1 3 4\n' +
  'Convolution              conv_5                   1 1 4 5 0=4 1=3 11=3 12=1 13=1 14=1 2=1 3=1 4=1 5=1 6=1152\n' +
  'PixelShuffle             pixel_shuffle_0          1 1 5 out0 0=2 1=0\n'

export class ReaderSuperResolutionModelPaths {
  paramPath: string = ''
  modelPath: string = ''
  acceleratedModelPath: string = ''
}

/** Downloads and verifies immutable model assets before the native runtime can see them. */
export class ReaderSuperResolutionModelService {
  private static waifu2xInstallTask: Promise<void> | null = null
  private static realEsrganInstallTask: Promise<void> | null = null
  private static directInstallTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>()

  static definitions(): ReaderSuperResolutionModelDefinition[] {
    return ReaderSuperResolutionModelRegistry.all()
  }

  static modelBytes(model: string): number {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    return definition === null ? 0 : definition.bytes()
  }

  static async isInstalled(context: common.UIAbilityContext, model: string): Promise<boolean> {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    if (definition === null) {
      return false
    }
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.paths(context, definition)
    const runtimeInstalled: boolean = ReaderSuperResolutionModelService.validateFile(
      paths.paramPath,
      definition.paramBytes,
      definition.paramSha256,
    ) && ReaderSuperResolutionModelService.validateFile(
      paths.modelPath,
      definition.modelBytes,
      definition.modelSha256,
    )
    return runtimeInstalled && ReaderSuperResolutionModelService.acceleratedAssetInstalled(
      paths,
      definition,
    )
  }

  static async installedModels(context: common.UIAbilityContext): Promise<string[]> {
    const installed: string[] = []
    const definitions: ReaderSuperResolutionModelDefinition[] =
      ReaderSuperResolutionModelRegistry.all()
    for (let i: number = 0; i < definitions.length; i++) {
      if (await ReaderSuperResolutionModelService.isInstalled(context, definitions[i].id)) {
        installed.push(definitions[i].id)
      }
    }
    return installed
  }

  static async pathsIfReady(
    context: common.UIAbilityContext,
    model: string,
  ): Promise<ReaderSuperResolutionModelPaths | null> {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    if (definition === null) {
      return null
    }
    if (definition.installStrategy ===
      ReaderSuperResolutionInstallStrategy.REAL_ESRGAN_X2PLUS_COMPAT) {
      return ReaderSuperResolutionModelService.realEsrganPathsIfReady(context)
    }
    if (!await ReaderSuperResolutionModelService.isInstalled(context, model)) {
      return null
    }
    return ReaderSuperResolutionModelService.paths(context, definition)
  }

  static async install(context: common.UIAbilityContext, model: string): Promise<void> {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    if (definition === null) {
      throw new Error(`unsupported super-resolution model: ${model}`)
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X) {
      await ReaderSuperResolutionModelService.installWaifu2x(context)
      return
    }
    if (definition.installStrategy ===
      ReaderSuperResolutionInstallStrategy.REAL_ESRGAN_X2PLUS_COMPAT) {
      await ReaderSuperResolutionModelService.installRealEsrgan(context)
      return
    }
    if (definition.installStrategy === ReaderSuperResolutionInstallStrategy.ESPCN_ONNX_ZIP) {
      await ReaderSuperResolutionModelService.installEspcn(context, definition)
      return
    }
    if (await ReaderSuperResolutionModelService.isInstalled(context, model)) {
      return
    }
    const existing: Promise<void> | undefined =
      ReaderSuperResolutionModelService.directInstallTasks.get(model)
    if (existing !== undefined) {
      await existing
      return
    }
    const task: Promise<void> = ReaderSuperResolutionModelService.installDirectNow(
      context,
      definition,
    )
    ReaderSuperResolutionModelService.directInstallTasks.set(model, task)
    try {
      await task
    } finally {
      ReaderSuperResolutionModelService.directInstallTasks.delete(model)
    }
  }

  static remove(context: common.UIAbilityContext, model: string): void {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(model)
    if (definition === null) {
      return
    }
    if (definition.installStrategy ===
      ReaderSuperResolutionInstallStrategy.REAL_ESRGAN_X2PLUS_COMPAT) {
      ReaderSuperResolutionModelService.removeRealEsrgan(context)
      return
    }
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.paths(context, definition)
    ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
    ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.paramPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.modelPath}.part`)
    if (definition.installStrategy === ReaderSuperResolutionInstallStrategy.ESPCN_ONNX_ZIP) {
      ReaderSuperResolutionModelService.cleanupEspcnTemporaryFiles(context, definition)
    }
  }

  static waifu2xModelBytes(): number {
    return WAIFU2X_PARAM_BYTES + WAIFU2X_MODEL_BYTES
  }

  static realEsrganModelBytes(): number {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS)
    return definition === null ? 0 : definition.bytes()
  }

  static async isWaifu2xInstalled(context: common.UIAbilityContext): Promise<boolean> {
    return ReaderSuperResolutionModelService.isInstalled(
      context,
      ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
    )
  }

  static async isRealEsrganInstalled(context: common.UIAbilityContext): Promise<boolean> {
    return ReaderSuperResolutionModelService.isInstalled(
      context,
      ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS,
    )
  }

  static async waifu2xPathsIfReady(
    context: common.UIAbilityContext,
  ): Promise<ReaderSuperResolutionModelPaths | null> {
    if (!await ReaderSuperResolutionModelService.isWaifu2xInstalled(context)) {
      return null
    }
    return ReaderSuperResolutionModelService.waifu2xPaths(context)
  }

  static async realEsrganPathsIfReady(
    context: common.UIAbilityContext,
  ): Promise<ReaderSuperResolutionModelPaths | null> {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS)
    if (definition === null) {
      return null
    }
    let paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.realEsrganPaths(context)
    if (!ReaderSuperResolutionModelService.runtimePairInstalled(paths, definition) &&
      ReaderSuperResolutionModelService.hasRealEsrganSourceAssets(context)) {
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_migration_start',
        'model=realesrgan_x2plus',
      )
      await ReaderSuperResolutionModelService.installRealEsrganRuntime(context, definition, paths)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_migration_success',
        'model=realesrgan_x2plus',
      )
      paths = ReaderSuperResolutionModelService.realEsrganPaths(context)
    }
    if (!ReaderSuperResolutionModelService.runtimePairInstalled(paths, definition)) {
      return null
    }
    return paths
  }

  static realEsrganNnrtPathIfReady(context: common.UIAbilityContext): string | null {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS)
    if (definition === null) {
      return null
    }
    const path: string = ReaderSuperResolutionModelService.realEsrganPaths(context).acceleratedModelPath
    return ReaderSuperResolutionModelService.validateFile(
      path,
      definition.acceleratedModelBytes,
      definition.acceleratedModelSha256,
    ) ? path : null
  }

  static async installWaifu2x(context: common.UIAbilityContext): Promise<void> {
    if (await ReaderSuperResolutionModelService.isWaifu2xInstalled(context)) {
      return
    }
    if (ReaderSuperResolutionModelService.waifu2xInstallTask === null) {
      ReaderSuperResolutionModelService.waifu2xInstallTask =
        ReaderSuperResolutionModelService.installWaifu2xNow(context)
    }
    try {
      await ReaderSuperResolutionModelService.waifu2xInstallTask
    } finally {
      ReaderSuperResolutionModelService.waifu2xInstallTask = null
    }
  }

  static async installRealEsrgan(context: common.UIAbilityContext): Promise<void> {
    if (await ReaderSuperResolutionModelService.isRealEsrganInstalled(context)) {
      return
    }
    if (ReaderSuperResolutionModelService.realEsrganInstallTask === null) {
      ReaderSuperResolutionModelService.realEsrganInstallTask =
        ReaderSuperResolutionModelService.installRealEsrganNow(context)
    }
    try {
      await ReaderSuperResolutionModelService.realEsrganInstallTask
    } finally {
      ReaderSuperResolutionModelService.realEsrganInstallTask = null
    }
  }

  private static async installEspcn(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
  ): Promise<void> {
    if (await ReaderSuperResolutionModelService.isInstalled(context, definition.id)) {
      return
    }
    const existing: Promise<void> | undefined =
      ReaderSuperResolutionModelService.directInstallTasks.get(definition.id)
    if (existing !== undefined) {
      await existing
      return
    }
    const task: Promise<void> = ReaderSuperResolutionModelService.installEspcnNow(
      context,
      definition,
    )
    ReaderSuperResolutionModelService.directInstallTasks.set(definition.id, task)
    try {
      await task
    } finally {
      ReaderSuperResolutionModelService.directInstallTasks.delete(definition.id)
    }
  }

  static removeWaifu2x(context: common.UIAbilityContext): void {
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.waifu2xPaths(context)
    ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
    ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.paramPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.modelPath}.part`)
  }

  static removeRealEsrgan(context: common.UIAbilityContext): void {
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.realEsrganPaths(context)
    const sourceParamPath: string =
      ReaderSuperResolutionModelService.realEsrganSourceParamPath(context)
    ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
    ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
    ReaderSuperResolutionModelService.removeIfExists(sourceParamPath)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.paramPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.modelPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.modelPath}.runtime`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.modelPath}.part.runtime`)
    ReaderSuperResolutionModelService.removeIfExists(`${sourceParamPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(paths.acceleratedModelPath)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.acceleratedModelPath}.part`)
  }

  private static async installDirectNow(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
  ): Promise<void> {
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.paths(context, definition)
    ReaderSuperResolutionModelService.ensureDir(
      ReaderSuperResolutionModelService.definitionDir(context, definition),
    )
    const paramPart: string = `${paths.paramPath}.part`
    const modelPart: string = `${paths.modelPath}.part`
    ReaderSuperResolutionModelService.removeIfExists(paramPart)
    ReaderSuperResolutionModelService.removeIfExists(modelPart)
    DiagnosticLogger.info(
      'reader-super-resolution',
      'model_download_start',
      `model=${definition.id}`,
    )
    try {
      await ReaderSuperResolutionModelService.downloadAsset(definition.paramUrls, paramPart)
      if (!ReaderSuperResolutionModelService.validateFile(
        paramPart,
        definition.paramBytes,
        definition.paramSha256,
      )) {
        throw new Error(`${definition.id} param checksum mismatch`)
      }
      await ReaderSuperResolutionModelService.downloadAsset(definition.modelUrls, modelPart)
      if (!ReaderSuperResolutionModelService.validateFile(
        modelPart,
        definition.modelBytes,
        definition.modelSha256,
      )) {
        throw new Error(`${definition.id} model checksum mismatch`)
      }
      ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
      ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
      fileIo.renameSync(paramPart, paths.paramPath)
      fileIo.renameSync(modelPart, paths.modelPath)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_download_success',
        `model=${definition.id} bytes=${definition.bytes()}`,
      )
    } catch (error) {
      ReaderSuperResolutionModelService.removeIfExists(paramPart)
      ReaderSuperResolutionModelService.removeIfExists(modelPart)
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'model_download_failed',
        `model=${definition.id} message=${(error as Error).message}`,
      )
      throw error as Error
    }
  }

  private static async installEspcnNow(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
  ): Promise<void> {
    const dir: string = ReaderSuperResolutionModelService.definitionDir(context, definition)
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.paths(context, definition)
    const packagePath: string = `${dir}/${ESPCN_PACKAGE_FILE_NAME}`
    const extractDir: string = `${dir}/${ESPCN_EXTRACT_DIR_NAME}`
    const onnxPath: string = `${extractDir}/${ESPCN_ONNX_FILE_NAME}`
    const paramPart: string = `${paths.paramPath}.part`
    const modelPart: string = `${paths.modelPath}.part`
    ReaderSuperResolutionModelService.ensureDir(dir)
    ReaderSuperResolutionModelService.cleanupEspcnTemporaryFiles(context, definition)
    ReaderSuperResolutionModelService.ensureDir(extractDir)
    DiagnosticLogger.info(
      'reader-super-resolution',
      'model_download_start',
      `model=${definition.id}`,
    )
    try {
      await ReaderSuperResolutionModelService.downloadAsset(definition.packageUrls, packagePath)
      if (!ReaderSuperResolutionModelService.validateFile(
        packagePath,
        definition.packageBytes,
        definition.packageSha256,
      )) {
        throw new Error('ESPCN package checksum mismatch')
      }
      const options: zlib.Options = {
        parallel: zlib.ParallelStrategy.PARALLEL_STRATEGY_PARALLEL_DECOMPRESSION,
        pathSeparatorStrategy: zlib.PathSeparatorStrategy.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH,
      }
      await zlib.decompressFile(packagePath, extractDir, options)
      if (!ReaderSuperResolutionModelService.validateFile(
        onnxPath,
        ESPCN_ONNX_BYTES,
        ESPCN_ONNX_SHA256,
      )) {
        throw new Error('ESPCN ONNX checksum mismatch')
      }
      ReaderSuperResolutionModelService.createEspcnRuntimeFiles(
        onnxPath,
        paramPart,
        modelPart,
      )
      if (!ReaderSuperResolutionModelService.validateFile(
        paramPart,
        definition.paramBytes,
        definition.paramSha256,
      )) {
        throw new Error('ESPCN generated param checksum mismatch')
      }
      if (!ReaderSuperResolutionModelService.validateFile(
        modelPart,
        definition.modelBytes,
        definition.modelSha256,
      )) {
        throw new Error('ESPCN generated model checksum mismatch')
      }
      ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
      ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
      fileIo.renameSync(paramPart, paths.paramPath)
      fileIo.renameSync(modelPart, paths.modelPath)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_download_success',
        `model=${definition.id} downloadBytes=${definition.packageBytes} runtimeBytes=${definition.bytes()}`,
      )
    } catch (error) {
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'model_download_failed',
        `model=${definition.id} message=${(error as Error).message}`,
      )
      throw error as Error
    } finally {
      ReaderSuperResolutionModelService.cleanupEspcnTemporaryFiles(context, definition)
    }
  }

  private static createEspcnRuntimeFiles(
    onnxPath: string,
    paramPath: string,
    modelPath: string,
  ): void {
    // These tensor byte ranges belong only to the SHA-pinned Hailo ONNX above. The generated pair is
    // independently hash-checked before it can replace an installed runtime.
    const onnx: ArrayBuffer = ReaderSuperResolutionModelService.readExactFile(
      onnxPath,
      ESPCN_ONNX_BYTES,
    )
    const model: ArrayBuffer = new ArrayBuffer(42780)
    let cursor: number = 0
    cursor = ReaderSuperResolutionModelService.appendEspcnConvolution(
      onnx,
      model,
      cursor,
      682,
      7082,
      7113,
      7369,
    )
    cursor = ReaderSuperResolutionModelService.appendEspcnConvolution(
      onnx,
      model,
      cursor,
      7410,
      81138,
      81169,
      81297,
    )
    cursor = ReaderSuperResolutionModelService.appendEspcnConvolution(
      onnx,
      model,
      cursor,
      81333,
      85941,
      85967,
      85983,
    )
    if (cursor !== model.byteLength) {
      throw new Error('ESPCN generated model size mismatch')
    }
    const paramBytes: Uint8Array = new util.TextEncoder().encodeInto(ESPCN_RUNTIME_PARAM)
    const paramBuffer: ArrayBuffer = new ArrayBuffer(paramBytes.byteLength)
    new Uint8Array(paramBuffer).set(paramBytes)
    ReaderSuperResolutionModelService.writeFile(paramPath, paramBuffer)
    ReaderSuperResolutionModelService.writeFile(modelPath, model)
  }

  private static appendEspcnConvolution(
    onnx: ArrayBuffer,
    model: ArrayBuffer,
    cursor: number,
    weightStart: number,
    weightEnd: number,
    biasStart: number,
    biasEnd: number,
  ): number {
    const input: DataView = new DataView(onnx)
    const output: DataView = new DataView(model)
    const outputBytes: Uint8Array = new Uint8Array(model)
    output.setUint32(cursor, ESPCN_NCNN_FP16_TAG, true)
    cursor += 4
    for (let offset: number = weightStart; offset < weightEnd; offset += 4) {
      output.setUint16(
        cursor,
        ReaderSuperResolutionModelService.float32BitsToNcnnFloat16(
          input.getUint32(offset, true),
        ),
        true,
      )
      cursor += 2
    }
    const biasBytes: Uint8Array = new Uint8Array(onnx, biasStart, biasEnd - biasStart)
    outputBytes.set(biasBytes, cursor)
    return cursor + biasBytes.byteLength
  }

  private static float32BitsToNcnnFloat16(bits: number): number {
    const sign: number = (bits >>> 16) & 0x8000
    const exponent: number = (bits >>> 23) & 0xff
    const significand: number = bits & 0x7fffff
    if (exponent === 0) {
      return sign
    }
    if (exponent === 0xff) {
      return sign | 0x7c00 | (significand >>> 13)
    }
    const halfExponent: number = exponent - 127 + 15
    if (halfExponent >= 31) {
      return sign | 0x7c00
    }
    if (halfExponent <= 0) {
      return sign
    }
    return sign | (halfExponent << 10) | (significand >>> 13)
  }

  private static readExactFile(path: string, expectedBytes: number): ArrayBuffer {
    const buffer: ArrayBuffer = new ArrayBuffer(expectedBytes)
    const output: Uint8Array = new Uint8Array(buffer)
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (offset < expectedBytes) {
        const chunk: ArrayBuffer = new ArrayBuffer(expectedBytes - offset)
        const read: number = fileIo.readSync(
          file.fd,
          chunk,
          { length: chunk.byteLength },
        )
        if (read <= 0) {
          throw new Error('unexpected end of ESPCN ONNX file')
        }
        output.set(new Uint8Array(chunk, 0, read), offset)
        offset += read
      }
      return buffer
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static writeFile(path: string, buffer: ArrayBuffer): void {
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      while (offset < buffer.byteLength) {
        const remaining: ArrayBuffer = buffer.slice(offset)
        const written: number = fileIo.writeSync(
          file.fd,
          remaining,
          { length: remaining.byteLength },
        )
        if (written <= 0) {
          throw new Error('failed to write ESPCN runtime file')
        }
        offset += written
      }
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static async installWaifu2xNow(context: common.UIAbilityContext): Promise<void> {
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.waifu2xPaths(context)
    ReaderSuperResolutionModelService.ensureDir(ReaderSuperResolutionModelService.modelDir(context))
    const paramPart: string = `${paths.paramPath}.part`
    const modelPart: string = `${paths.modelPath}.part`
    ReaderSuperResolutionModelService.removeIfExists(paramPart)
    ReaderSuperResolutionModelService.removeIfExists(modelPart)
    DiagnosticLogger.info('reader-super-resolution', 'model_download_start', 'model=waifu2x_photo_noise0_2x')
    try {
      await ReaderSuperResolutionModelService.downloadAsset(
        ReaderSuperResolutionModelService.waifu2xAssetUrls(WAIFU2X_PARAM_FILE_NAME),
        paramPart,
      )
      if (!ReaderSuperResolutionModelService.validateFile(
        paramPart,
        WAIFU2X_PARAM_BYTES,
        WAIFU2X_PARAM_SHA256,
      )) {
        throw new Error('waifu2x param checksum mismatch')
      }
      await ReaderSuperResolutionModelService.downloadAsset(
        ReaderSuperResolutionModelService.waifu2xAssetUrls(WAIFU2X_MODEL_FILE_NAME),
        modelPart,
      )
      if (!ReaderSuperResolutionModelService.validateFile(
        modelPart,
        WAIFU2X_MODEL_BYTES,
        WAIFU2X_MODEL_SHA256,
      )) {
        throw new Error('waifu2x model checksum mismatch')
      }
      ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
      ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
      fileIo.renameSync(paramPart, paths.paramPath)
      fileIo.renameSync(modelPart, paths.modelPath)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_download_success',
        `model=waifu2x_photo_noise0_2x bytes=${WAIFU2X_PARAM_BYTES + WAIFU2X_MODEL_BYTES}`,
      )
    } catch (error) {
      ReaderSuperResolutionModelService.removeIfExists(paramPart)
      ReaderSuperResolutionModelService.removeIfExists(modelPart)
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'model_download_failed',
        (error as Error).message,
      )
      throw error as Error
    }
  }

  private static async installRealEsrganNow(context: common.UIAbilityContext): Promise<void> {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS)
    if (definition === null) {
      throw new Error('Real-ESRGAN model definition is missing')
    }
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.realEsrganPaths(context)
    ReaderSuperResolutionModelService.ensureDir(
      ReaderSuperResolutionModelService.realEsrganModelDir(context),
    )
    DiagnosticLogger.info(
      'reader-super-resolution',
      'model_download_start',
      'model=realesrgan_x2plus',
    )
    try {
      if (!ReaderSuperResolutionModelService.runtimePairInstalled(paths, definition)) {
        await ReaderSuperResolutionModelService.installRealEsrganRuntime(
          context,
          definition,
          paths,
        )
      }
      await ReaderSuperResolutionModelService.installAcceleratedAsset(paths, definition)
      DiagnosticLogger.info(
        'reader-super-resolution',
        'model_download_success',
        `model=realesrgan_x2plus bytes=${definition.bytes()}`,
      )
    } catch (error) {
      ReaderSuperResolutionModelService.removeIfExists(`${paths.acceleratedModelPath}.part`)
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'model_download_failed',
        (error as Error).message,
      )
      throw error as Error
    }
  }

  private static async installRealEsrganRuntime(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
    paths: ReaderSuperResolutionModelPaths,
  ): Promise<void> {
    const sourceParamPath: string =
      ReaderSuperResolutionModelService.realEsrganSourceParamPath(context)
    const sourceParamPart: string = sourceParamPath + '.part'
    const runtimeParamPart: string = paths.paramPath + '.part'
    const modelPart: string = paths.modelPath + '.part'
    ReaderSuperResolutionModelService.removeIfExists(sourceParamPart)
    ReaderSuperResolutionModelService.removeIfExists(runtimeParamPart)
    ReaderSuperResolutionModelService.removeIfExists(modelPart)
    try {
      if (!ReaderSuperResolutionModelService.validateFile(
        sourceParamPath,
        REAL_ESRGAN_SOURCE_PARAM_BYTES,
        REAL_ESRGAN_SOURCE_PARAM_SHA256,
      )) {
        await ReaderSuperResolutionModelService.downloadAsset(
          ReaderSuperResolutionModelService.realEsrganAssetUrls(
            REAL_ESRGAN_SOURCE_PARAM_FILE_NAME,
          ),
          sourceParamPart,
        )
        if (!ReaderSuperResolutionModelService.validateFile(
          sourceParamPart,
          REAL_ESRGAN_SOURCE_PARAM_BYTES,
          REAL_ESRGAN_SOURCE_PARAM_SHA256,
        )) {
          throw new Error('Real-ESRGAN source param checksum mismatch')
        }
        ReaderSuperResolutionModelService.removeIfExists(sourceParamPath)
        fileIo.renameSync(sourceParamPart, sourceParamPath)
      }
      ReaderSuperResolutionModelService.createRealEsrganRuntimeParam(
        sourceParamPath,
        runtimeParamPart,
      )
      if (!ReaderSuperResolutionModelService.validateFile(
        runtimeParamPart,
        REAL_ESRGAN_RUNTIME_PARAM_BYTES,
        REAL_ESRGAN_RUNTIME_PARAM_SHA256,
      )) {
        throw new Error('Real-ESRGAN runtime param checksum mismatch')
      }
      if (ReaderSuperResolutionModelService.validateFile(
        paths.modelPath,
        REAL_ESRGAN_SOURCE_MODEL_BYTES,
        REAL_ESRGAN_SOURCE_MODEL_SHA256,
      )) {
        ReaderSuperResolutionModelService.createRealEsrganRuntimeModel(paths.modelPath)
      }
      if (!ReaderSuperResolutionModelService.validateFile(
        paths.modelPath,
        REAL_ESRGAN_RUNTIME_MODEL_BYTES,
        REAL_ESRGAN_RUNTIME_MODEL_SHA256,
      )) {
        await ReaderSuperResolutionModelService.downloadAsset(
          ReaderSuperResolutionModelService.realEsrganAssetUrls(REAL_ESRGAN_MODEL_FILE_NAME),
          modelPart,
        )
        if (!ReaderSuperResolutionModelService.validateFile(
          modelPart,
          REAL_ESRGAN_SOURCE_MODEL_BYTES,
          REAL_ESRGAN_SOURCE_MODEL_SHA256,
        )) {
          throw new Error('Real-ESRGAN source model checksum mismatch')
        }
        ReaderSuperResolutionModelService.createRealEsrganRuntimeModel(modelPart)
        if (!ReaderSuperResolutionModelService.validateFile(
          modelPart,
          REAL_ESRGAN_RUNTIME_MODEL_BYTES,
          REAL_ESRGAN_RUNTIME_MODEL_SHA256,
        )) {
          throw new Error('Real-ESRGAN runtime model checksum mismatch')
        }
        ReaderSuperResolutionModelService.removeIfExists(paths.modelPath)
        fileIo.renameSync(modelPart, paths.modelPath)
      }
      ReaderSuperResolutionModelService.removeIfExists(paths.paramPath)
      fileIo.renameSync(runtimeParamPart, paths.paramPath)
      ReaderSuperResolutionModelService.removeIfExists(sourceParamPath)
      if (!ReaderSuperResolutionModelService.runtimePairInstalled(paths, definition)) {
        throw new Error('Real-ESRGAN runtime pair validation failed')
      }
    } catch (error) {
      ReaderSuperResolutionModelService.removeIfExists(sourceParamPart)
      ReaderSuperResolutionModelService.removeIfExists(runtimeParamPart)
      ReaderSuperResolutionModelService.removeIfExists(modelPart)
      throw error as Error
    }
  }

  /**
   * The source graph expands PixelUnshuffle into dynamic shape operators that the HarmonyOS ncnn
   * build cannot load. Reorg(stride=2, mode=0) is the same space-to-depth channel order, so the
   * compatible graph replaces only that prelude and leaves every learned layer untouched.
   */
  private static createRealEsrganRuntimeParam(sourcePath: string, targetPath: string): void {
    const source: string = fileIo.readTextSync(sourcePath)
    const sourceLines: string[] = source.split('\n')
    if (sourceLines.length < 3 || sourceLines[0] !== '7767517' ||
      sourceLines[1] !== '1408 2199') {
      throw new Error('unsupported Real-ESRGAN source param header')
    }
    let convFirstIndex: number = -1
    for (let i: number = 2; i < sourceLines.length; i++) {
      if (sourceLines[i].startsWith('Convolution') &&
        sourceLines[i].includes('/conv_first/Conv')) {
        convFirstIndex = i
        break
      }
    }
    if (convFirstIndex < 0) {
      throw new Error('Real-ESRGAN conv_first layer is missing')
    }
    const layers: string[] = [
      'Input            input                    0 1 input',
    ]
    layers.push(
      'Reorg            pixel_unshuffle          1 1 input /Reshape_1_output_0 0=2 1=0',
    )
    for (let i: number = convFirstIndex; i < sourceLines.length; i++) {
      layers.push(sourceLines[i])
    }
    const runtimeParam: string = '7767517\n1371 2154\n' + layers.join('\n')
    let output: fileIo.File | null = null
    try {
      output = fileIo.openSync(
        targetPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      fileIo.writeSync(output.fd, runtimeParam)
    } finally {
      if (output !== null) {
        fileIo.closeSync(output)
      }
    }
  }

  /**
   * The pinned model bin starts with five int64 values used only by the removed dynamic-shape
   * prelude. They are verified as part of the immutable source hash, then omitted while writing a
   * temporary runtime file. The verified runtime file atomically replaces the source file.
   */
  private static createRealEsrganRuntimeModel(path: string): void {
    if (fileIo.statSync(path).size !== REAL_ESRGAN_SOURCE_MODEL_BYTES) {
      throw new Error('unexpected Real-ESRGAN source model size')
    }
    const runtimePath: string = path + '.runtime'
    ReaderSuperResolutionModelService.removeIfExists(runtimePath)
    let source: fileIo.File | null = null
    let output: fileIo.File | null = null
    let readOffset: number = REAL_ESRGAN_MODEL_PREFIX_BYTES
    let totalWritten: number = 0
    try {
      source = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      output = fileIo.openSync(
        runtimePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      while (totalWritten < REAL_ESRGAN_RUNTIME_MODEL_BYTES) {
        const length: number = Math.min(
          HASH_CHUNK_BYTES,
          REAL_ESRGAN_RUNTIME_MODEL_BYTES - totalWritten,
        )
        const buffer: ArrayBuffer = new ArrayBuffer(length)
        const read: number = fileIo.readSync(
          source.fd,
          buffer,
          { offset: readOffset, length: length },
        )
        if (read !== length) {
          throw new Error('failed to read Real-ESRGAN runtime model chunk')
        }
        let written: number = 0
        while (written < read) {
          const remaining: ArrayBuffer = written === 0
            ? buffer
            : buffer.slice(written, read)
          const count: number = fileIo.writeSync(
            output.fd,
            remaining,
            { length: read - written },
          )
          if (count <= 0) {
            throw new Error('failed to write Real-ESRGAN runtime model chunk')
          }
          written += count
        }
        readOffset += read
        totalWritten += read
      }
    } finally {
      if (output !== null) {
        fileIo.closeSync(output)
      }
      if (source !== null) {
        fileIo.closeSync(source)
      }
    }
    if (!ReaderSuperResolutionModelService.validateFile(
      runtimePath,
      REAL_ESRGAN_RUNTIME_MODEL_BYTES,
      REAL_ESRGAN_RUNTIME_MODEL_SHA256,
    )) {
      ReaderSuperResolutionModelService.removeIfExists(runtimePath)
      throw new Error('Real-ESRGAN generated runtime model checksum mismatch')
    }
    ReaderSuperResolutionModelService.removeIfExists(path)
    fileIo.renameSync(runtimePath, path)
  }

  private static async downloadAsset(urls: string[], path: string): Promise<void> {
    let lastError: Error | null = null
    for (let i: number = 0; i < urls.length; i++) {
      try {
        const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
          urls[i],
          path,
          (_loaded: number, _total: number): void => {},
          DOWNLOAD_CONNECT_TIMEOUT_MS,
          0,
          'application/octet-stream,text/plain,*/*',
          2,
          DOWNLOAD_READ_TIMEOUT_MS,
        )
        if (bytes <= 0) {
          throw new Error('model asset response is empty')
        }
        return
      } catch (error) {
        lastError = error as Error
        ReaderSuperResolutionModelService.removeIfExists(path)
      }
    }
    throw lastError !== null ? lastError : new Error('model asset download failed')
  }

  private static async installAcceleratedAsset(
    paths: ReaderSuperResolutionModelPaths,
    definition: ReaderSuperResolutionModelDefinition,
  ): Promise<void> {
    if (ReaderSuperResolutionModelService.acceleratedAssetInstalled(paths, definition)) {
      return
    }
    if (definition.acceleratedModelFileName.length === 0 ||
      definition.acceleratedModelUrls.length === 0) {
      throw new Error(`${definition.id} accelerated model source is missing`)
    }
    const partPath: string = `${paths.acceleratedModelPath}.part`
    ReaderSuperResolutionModelService.removeIfExists(partPath)
    await ReaderSuperResolutionModelService.downloadAsset(
      definition.acceleratedModelUrls,
      partPath,
    )
    if (!ReaderSuperResolutionModelService.validateFile(
      partPath,
      definition.acceleratedModelBytes,
      definition.acceleratedModelSha256,
    )) {
      ReaderSuperResolutionModelService.removeIfExists(partPath)
      throw new Error(`${definition.id} accelerated model checksum mismatch`)
    }
    ReaderSuperResolutionModelService.removeIfExists(paths.acceleratedModelPath)
    fileIo.renameSync(partPath, paths.acceleratedModelPath)
  }

  private static runtimePairInstalled(
    paths: ReaderSuperResolutionModelPaths,
    definition: ReaderSuperResolutionModelDefinition,
  ): boolean {
    return ReaderSuperResolutionModelService.validateFile(
      paths.paramPath,
      definition.paramBytes,
      definition.paramSha256,
    ) && ReaderSuperResolutionModelService.validateFile(
      paths.modelPath,
      definition.modelBytes,
      definition.modelSha256,
    )
  }

  private static acceleratedAssetInstalled(
    paths: ReaderSuperResolutionModelPaths,
    definition: ReaderSuperResolutionModelDefinition,
  ): boolean {
    if (definition.acceleratedModelFileName.length === 0) {
      return true
    }
    return ReaderSuperResolutionModelService.validateFile(
      paths.acceleratedModelPath,
      definition.acceleratedModelBytes,
      definition.acceleratedModelSha256,
    )
  }

  private static waifu2xAssetUrls(fileName: string): string[] {
    return [
      `https://raw.githubusercontent.com/nihui/waifu2x-ncnn-vulkan/${SOURCE_REVISION}/${SOURCE_PATH}/${fileName}`,
      `https://github.com/nihui/waifu2x-ncnn-vulkan/raw/${SOURCE_REVISION}/${SOURCE_PATH}/${fileName}`,
    ]
  }

  private static realEsrganAssetUrls(fileName: string): string[] {
    return [
      `https://huggingface.co/${REAL_ESRGAN_SOURCE_REPOSITORY}/resolve/` +
        `${REAL_ESRGAN_SOURCE_REVISION}/${fileName}`,
    ]
  }

  private static validateFile(path: string, expectedBytes: number, expectedSha256: string): boolean {
    try {
      const stat: fileIo.Stat = fileIo.statSync(path)
      return stat.size === expectedBytes &&
        ReaderSuperResolutionModelService.hashFile(path) === expectedSha256
    } catch (_error) {
      return false
    }
  }

  private static hashFile(path: string): string {
    const md = cryptoFramework.createMd('SHA256')
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(HASH_CHUNK_BYTES)
        const read: number = fileIo.readSync(file.fd, buffer, { length: HASH_CHUNK_BYTES })
        if (read <= 0) {
          break
        }
        md.updateSync({ data: new Uint8Array(buffer, 0, read) })
      }
      return ReaderSuperResolutionModelService.toHex(md.digestSync().data)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let i: number = 0; i < bytes.length; i++) {
      parts.push(bytes[i].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  private static waifu2xPaths(context: common.UIAbilityContext): ReaderSuperResolutionModelPaths {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(
        ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
      )
    if (definition === null) {
      return new ReaderSuperResolutionModelPaths()
    }
    return ReaderSuperResolutionModelService.paths(context, definition)
  }

  private static realEsrganPaths(context: common.UIAbilityContext): ReaderSuperResolutionModelPaths {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS)
    if (definition === null) {
      return new ReaderSuperResolutionModelPaths()
    }
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.paths(context, definition)
    paths.acceleratedModelPath = ReaderSuperResolutionModelService.realEsrganNnrtModelPath(context)
    return paths
  }

  private static realEsrganNnrtModelPath(context: common.UIAbilityContext): string {
    const definition: ReaderSuperResolutionModelDefinition | null =
      ReaderSuperResolutionModelRegistry.find(ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS)
    return definition === null || definition.acceleratedModelFileName.length === 0
      ? ''
      : `${context.filesDir}/${definition.acceleratedModelFileName}`
  }

  private static realEsrganSourceParamPath(context: common.UIAbilityContext): string {
    return `${ReaderSuperResolutionModelService.realEsrganModelDir(context)}/` +
      REAL_ESRGAN_SOURCE_PARAM_FILE_NAME
  }

  private static hasRealEsrganSourceAssets(context: common.UIAbilityContext): boolean {
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.realEsrganPaths(context)
    return ReaderSuperResolutionModelService.validateFile(
      ReaderSuperResolutionModelService.realEsrganSourceParamPath(context),
      REAL_ESRGAN_SOURCE_PARAM_BYTES,
      REAL_ESRGAN_SOURCE_PARAM_SHA256,
    ) && ReaderSuperResolutionModelService.validateFile(
      paths.modelPath,
      REAL_ESRGAN_SOURCE_MODEL_BYTES,
      REAL_ESRGAN_SOURCE_MODEL_SHA256,
    )
  }

  private static modelDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${MODEL_DIR_NAME}/${WAIFU2X_DIR_NAME}`
  }

  private static realEsrganModelDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${MODEL_DIR_NAME}/${REAL_ESRGAN_DIR_NAME}`
  }

  private static definitionDir(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
  ): string {
    return `${context.filesDir}/${MODEL_DIR_NAME}/${definition.directoryName}`
  }

  private static cleanupEspcnTemporaryFiles(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
  ): void {
    const dir: string = ReaderSuperResolutionModelService.definitionDir(context, definition)
    const paths: ReaderSuperResolutionModelPaths =
      ReaderSuperResolutionModelService.paths(context, definition)
    const extractDir: string = `${dir}/${ESPCN_EXTRACT_DIR_NAME}`
    ReaderSuperResolutionModelService.removeIfExists(`${dir}/${ESPCN_PACKAGE_FILE_NAME}`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.paramPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(`${paths.modelPath}.part`)
    ReaderSuperResolutionModelService.removeIfExists(`${extractDir}/${ESPCN_ONNX_FILE_NAME}`)
    try {
      if (fileIo.accessSync(extractDir)) {
        fileIo.rmdirSync(extractDir)
      }
    } catch (_error) {}
  }

  private static paths(
    context: common.UIAbilityContext,
    definition: ReaderSuperResolutionModelDefinition,
  ): ReaderSuperResolutionModelPaths {
    const dir: string = ReaderSuperResolutionModelService.definitionDir(context, definition)
    const paths: ReaderSuperResolutionModelPaths = new ReaderSuperResolutionModelPaths()
    paths.paramPath = `${dir}/${definition.paramFileName}`
    paths.modelPath = `${dir}/${definition.modelFileName}`
    if (definition.acceleratedModelFileName.length > 0) {
      paths.acceleratedModelPath = `${context.filesDir}/${definition.acceleratedModelFileName}`
    }
    return paths
  }

  private static ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true)
    } catch (error) {
      if (!fileIo.accessSync(path)) {
        throw error as Error
      }
    }
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {}
  }
}
