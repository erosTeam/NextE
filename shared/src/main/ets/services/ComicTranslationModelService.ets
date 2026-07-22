import { common } from '@kit.AbilityKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhHttpClient } from '../network/EhHttpClient'

const MODEL_DIRECTORY: string = 'comic-translation-models/ysgyolo-1.2-os1-ncnn-fp32-v1'
const MODEL_RELEASE_TAG: string = 'model-pack-v1.1.2'
const PARAM_FILE_NAME: string = 'ysgyolo_1.2_OS1.0.ncnn.param'
const MODEL_FILE_NAME: string = 'ysgyolo_1.2_OS1.0.ncnn.bin'
const PARAM_BYTES: number = 27031
const MODEL_BYTES: number = 10720760
const PARAM_SHA256: string =
  'f3617c7834bf3f7ae67521db908a53709140aeb1c11a02f8c64b7c091b569987'
const MODEL_SHA256: string =
  '7658e654db1a2e8a77c387607def85d5d297b26f110cc2b334dd52ae17a4fe00'
const HASH_CHUNK_BYTES: number = 256 * 1024
const DOWNLOAD_CONNECT_TIMEOUT_MS: number = 15000
const DOWNLOAD_READ_TIMEOUT_MS: number = 10 * 60 * 1000

export class ComicTranslationModelPaths {
  paramPath: string = ''
  modelPath: string = ''
}

/** Installs the optional, separately licensed manga region detector outside the HAP. */
export class ComicTranslationModelService {
  private static installTask: Promise<void> | null = null
  private static readiness: Map<string, ComicTranslationModelPaths | null> =
    new Map<string, ComicTranslationModelPaths | null>()

  static displayName(): string {
    return 'YSGYolo 1.2 OS1.0'
  }

  static license(): string {
    return 'AGPL-3.0-only'
  }

  static downloadBytes(): number {
    return PARAM_BYTES + MODEL_BYTES
  }

  static pathsIfReady(context: common.UIAbilityContext): ComicTranslationModelPaths | null {
    const directory: string = ComicTranslationModelService.directory(context)
    if (ComicTranslationModelService.readiness.has(directory)) {
      return ComicTranslationModelService.readiness.get(directory) ?? null
    }
    const paths: ComicTranslationModelPaths = ComicTranslationModelService.paths(context)
    const ready: boolean = ComicTranslationModelService.validateFile(
      paths.paramPath,
      PARAM_BYTES,
      PARAM_SHA256,
    ) && ComicTranslationModelService.validateFile(
      paths.modelPath,
      MODEL_BYTES,
      MODEL_SHA256,
    )
    ComicTranslationModelService.readiness.set(directory, ready ? paths : null)
    return ready ? paths : null
  }

  static async isInstalled(context: common.UIAbilityContext): Promise<boolean> {
    return ComicTranslationModelService.pathsIfReady(context) !== null
  }

  static async install(context: common.UIAbilityContext): Promise<void> {
    if (ComicTranslationModelService.pathsIfReady(context) !== null) {
      return
    }
    if (ComicTranslationModelService.installTask === null) {
      ComicTranslationModelService.installTask =
        ComicTranslationModelService.installNow(context)
    }
    try {
      await ComicTranslationModelService.installTask
    } finally {
      ComicTranslationModelService.installTask = null
    }
  }

  static remove(context: common.UIAbilityContext): void {
    const paths: ComicTranslationModelPaths = ComicTranslationModelService.paths(context)
    ComicTranslationModelService.removeIfExists(paths.paramPath)
    ComicTranslationModelService.removeIfExists(paths.modelPath)
    ComicTranslationModelService.removeIfExists(`${paths.paramPath}.part`)
    ComicTranslationModelService.removeIfExists(`${paths.modelPath}.part`)
    ComicTranslationModelService.readiness.set(
      ComicTranslationModelService.directory(context),
      null,
    )
  }

  private static async installNow(context: common.UIAbilityContext): Promise<void> {
    const directory: string = ComicTranslationModelService.directory(context)
    const paths: ComicTranslationModelPaths = ComicTranslationModelService.paths(context)
    const paramPart: string = `${paths.paramPath}.part`
    const modelPart: string = `${paths.modelPath}.part`
    ComicTranslationModelService.ensureDir(directory)
    ComicTranslationModelService.removeIfExists(paramPart)
    ComicTranslationModelService.removeIfExists(modelPart)
    DiagnosticLogger.info('comic-translation-model', 'download_start', 'model=ysgyolo')
    try {
      await ComicTranslationModelService.download(PARAM_FILE_NAME, paramPart)
      if (!ComicTranslationModelService.validateFile(
        paramPart,
        PARAM_BYTES,
        PARAM_SHA256,
      )) {
        throw new Error('YSGYolo param checksum mismatch')
      }
      await ComicTranslationModelService.download(MODEL_FILE_NAME, modelPart)
      if (!ComicTranslationModelService.validateFile(
        modelPart,
        MODEL_BYTES,
        MODEL_SHA256,
      )) {
        throw new Error('YSGYolo model checksum mismatch')
      }
      ComicTranslationModelService.removeIfExists(paths.paramPath)
      ComicTranslationModelService.removeIfExists(paths.modelPath)
      fileIo.renameSync(paramPart, paths.paramPath)
      fileIo.renameSync(modelPart, paths.modelPath)
      ComicTranslationModelService.readiness.set(directory, paths)
      DiagnosticLogger.info(
        'comic-translation-model',
        'download_success',
        `model=ysgyolo bytes=${ComicTranslationModelService.downloadBytes()}`,
      )
    } catch (error) {
      ComicTranslationModelService.removeIfExists(paramPart)
      ComicTranslationModelService.removeIfExists(modelPart)
      ComicTranslationModelService.readiness.set(directory, null)
      DiagnosticLogger.warn(
        'comic-translation-model',
        'download_failed',
        (error as Error).message,
      )
      throw error as Error
    }
  }

  private static async download(fileName: string, path: string): Promise<void> {
    const url: string = `https://github.com/erosTeam/NextE-Models/releases/download/` +
      `${MODEL_RELEASE_TAG}/${fileName}`
    const bytes: number = await EhHttpClient.getInstance().downloadBinaryToFileInStream(
      url,
      path,
      (_loaded: number, _total: number): void => {},
      DOWNLOAD_CONNECT_TIMEOUT_MS,
      0,
      'application/octet-stream,text/plain,*/*',
      2,
      DOWNLOAD_READ_TIMEOUT_MS,
    )
    if (bytes <= 0) {
      throw new Error('YSGYolo asset response is empty')
    }
  }

  private static paths(context: common.UIAbilityContext): ComicTranslationModelPaths {
    const directory: string = ComicTranslationModelService.directory(context)
    const paths: ComicTranslationModelPaths = new ComicTranslationModelPaths()
    paths.paramPath = `${directory}/${PARAM_FILE_NAME}`
    paths.modelPath = `${directory}/${MODEL_FILE_NAME}`
    return paths
  }

  private static directory(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${MODEL_DIRECTORY}`
  }

  private static validateFile(
    path: string,
    expectedBytes: number,
    expectedSha256: string,
  ): boolean {
    try {
      const stat: fileIo.Stat = fileIo.statSync(path)
      return stat.isFile() && stat.size === expectedBytes &&
        ComicTranslationModelService.hashFile(path) === expectedSha256
    } catch (_error) {
      return false
    }
  }

  private static hashFile(path: string): string {
    const digest = cryptoFramework.createMd('SHA256')
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(HASH_CHUNK_BYTES)
        const read: number = fileIo.readSync(file.fd, buffer, { length: HASH_CHUNK_BYTES })
        if (read <= 0) {
          break
        }
        digest.updateSync({ data: new Uint8Array(buffer, 0, read) })
      }
      const bytes: Uint8Array = digest.digestSync().data
      const output: string[] = []
      for (let index: number = 0; index < bytes.length; index++) {
        output.push(bytes[index].toString(16).padStart(2, '0'))
      }
      return output.join('')
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
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
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {
      // Best-effort cleanup; validation prevents partial files from becoming active.
    }
  }
}
