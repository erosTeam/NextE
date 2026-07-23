import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { ComicRenderProfile } from '../model/ComicVisualTranslation'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  COMIC_VISUAL_ROUTE_TORII,
  ComicVisualProviderSettings,
  ComicVisualProviderSettingsSnapshot,
} from '../settings/ComicVisualProviderSettings'
import { CacheStat } from './CacheStat'
import {
  ComicWholePageTranslationOrchestrator,
  ComicWholePageTranslationRequest,
} from './ComicWholePageTranslationOrchestrator'
import { PersistentComicRenderedPageRepository } from './ComicRenderedPageRepository'
import { ComicLocalVisualBackend } from './ComicLocalVisualBackend'
import { HarmonyComicLocalOcrEngine } from './ComicHarmonyOcrService'
import { ComicNcnnLocalRegionDetector } from './ComicNativeRegionDetector'
import { ComicNcnnLocalSourceInpainter } from './ComicNativeSourceInpainter'
import { ComicNcnnLocalTextMasker } from './ComicNativeTextMasker'
import { ComicNcnnLocalTextRecognizer } from './ComicNativeTextRecognizer'
import {
  ComicSourceInpaintingModelPaths,
  ComicTextMaskModelPaths,
  ComicTextRecognitionModelPaths,
  ComicTranslationModelPaths,
  ComicTranslationModelService,
} from './ComicTranslationModelService'
import { ComicTextTranslatorFactory } from './ComicResponsesTextTranslator'
import { ComicTranslationRepository } from './ComicTranslationRepository'
import { PersistentComicTranslationRepository } from './ComicTranslationPersistentRepository'
import {
  ComicRegionRenderBackend,
  ComicTextTranslator,
  ComicVisualPageSource,
} from './ComicVisualTranslationBackend'
import {
  ComicVisualTranslationOrchestrator,
  ComicVisualTranslationRequest,
  ComicVisualTranslationRunResult,
} from './ComicVisualTranslationOrchestrator'
import { ToriiWholePageContextStore } from './ToriiWholePageContextStore'
import {
  TORII_WHOLE_PAGE_LAYOUT_PROFILE_ID,
  TORII_WHOLE_PAGE_RENDER_PROFILE_ID,
  TORII_WHOLE_PAGE_SOURCE_TREATMENT_PROFILE_ID,
  ToriiWholePageConfig,
  ToriiWholePageRenderBackend,
} from './ToriiWholePageRenderBackend'
import {
  ToriiWholePageCredential,
  ToriiWholePageSecretStore,
} from './ToriiWholePageSecretStore'

const COMIC_READER_MAX_IMAGE_BYTES: number = 20 * 1024 * 1024
const COMIC_READER_HASH_CHUNK_BYTES: number = 256 * 1024
const COMIC_READER_RENDER_PROFILE_ID: string = 'reader-local-bubble-layout-v43'
const COMIC_READER_SOURCE_TREATMENT_PROFILE_ID: string = 'local-ctd-aot-inpaint-v29'
const COMIC_READER_LAYOUT_PROFILE_ID: string = 'local-bubble-typography-v37'
const MAX_RUNTIME_ORCHESTRATORS: number = 4
const MAX_COMIC_READER_IDENTIFIER_CHARS: number = 160
const MAX_COMIC_READER_IMAGE_PATH_CHARS: number = 4096
const MAX_COMIC_READER_IMAGE_EDGE: number = 100000

class ComicTranslationReaderFileMetadata {
  imageHash: string = ''
  mimeType: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
}

export class ComicTranslationReaderPageInput {
  projectId: string = ''
  pageIndex: number = -1
  imageFilePath: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  sourceLanguage: string = 'auto'
  targetLanguage: string = 'zh-CN'
}

/** Production Reader bridge. Provider calls occur only through the explicit run method. */
export class ComicTranslationRuntimeService {
  private static documentRepository: ComicTranslationRepository | null = null
  private static renderedRepository: PersistentComicRenderedPageRepository | null = null
  private static orchestrators: Map<string, ComicVisualTranslationOrchestrator> = new Map()
  private static wholePageOrchestrators: Map<string, ComicWholePageTranslationOrchestrator> =
    new Map<string, ComicWholePageTranslationOrchestrator>()
  private static toriiContextStore: ToriiWholePageContextStore | null = null

  static async runReaderPage(
    context: common.UIAbilityContext,
    input: ComicTranslationReaderPageInput,
    forceRefresh: boolean = false,
  ): Promise<ComicVisualTranslationRunResult> {
    ComicTranslationRuntimeService.validateInput(input)
    const metadata: ComicTranslationReaderFileMetadata =
      await ComicTranslationRuntimeService.fileMetadata(input.imageFilePath)
    DiagnosticLogger.info(
      'comic-translation',
      'source_identity_resolved',
      `reader=${input.imageWidth}x${input.imageHeight} file=${metadata.imageWidth}x${metadata.imageHeight}`,
    )
    const visualSettings: ComicVisualProviderSettingsSnapshot =
      await ComicVisualProviderSettings.load(context)
    if (visualSettings.route === COMIC_VISUAL_ROUTE_TORII) {
      return ComicTranslationRuntimeService.runToriiWholePage(
        context,
        input,
        metadata,
        visualSettings,
        forceRefresh,
      )
    }
    const backend: ComicRegionRenderBackend =
      ComicTranslationRuntimeService.localBackendFor(context)
    const translator: ComicTextTranslator = await ComicTextTranslatorFactory.create(context)
    const regionRevision: number = backend.protocolRevision()
    const orchestrator: ComicVisualTranslationOrchestrator =
      ComicTranslationRuntimeService.orchestrator(
        context,
        backend,
        translator,
        regionRevision,
      )
    const request: ComicVisualTranslationRequest = new ComicVisualTranslationRequest()
    request.source = new ComicVisualPageSource()
    request.source.projectId = input.projectId
    request.source.pageIndex = input.pageIndex
    request.source.imageFilePath = input.imageFilePath
    request.source.imageHash = metadata.imageHash
    request.source.imageWidth = metadata.imageWidth
    request.source.imageHeight = metadata.imageHeight
    request.context.sourceLanguage = input.sourceLanguage
    request.context.targetLanguage = input.targetLanguage
    request.context.styleGuide =
      'Use concise natural phrasing in the requested target language. Keep names, forms of address, tone, and references consistent across pages.'
    request.context.glossaryRevision = 0
    request.context.styleGuideRevision = 2
    request.context.contextRevision = 1
    request.renderProfile = ComicTranslationRuntimeService.renderProfile()
    request.requestedRegionRevision = regionRevision
    request.requestedDocumentRevision = 1
    request.requestedTranslationRevision = 1
    return orchestrator.run(request, forceRefresh)
  }

  static async clearGeneratedCache(context: common.UIAbilityContext): Promise<void> {
    ComicTranslationRuntimeService.orchestrators.forEach(
      (orchestrator: ComicVisualTranslationOrchestrator): void => {
        orchestrator.invalidateCacheWrites()
      },
    )
    ComicTranslationRuntimeService.orchestrators.clear()
    ComicTranslationRuntimeService.wholePageOrchestrators.forEach(
      (orchestrator: ComicWholePageTranslationOrchestrator): void => {
        orchestrator.invalidateCacheWrites()
      },
    )
    ComicTranslationRuntimeService.wholePageOrchestrators.clear()
    await Promise.all([
      ComicTranslationRuntimeService.documentRepositoryFor(context).clear(),
      ComicTranslationRuntimeService.renderedRepositoryFor(context).clear(),
      ComicTranslationRuntimeService.toriiContextStoreFor(context).clear(),
    ])
  }

  static async statGeneratedCache(context: common.UIAbilityContext): Promise<CacheStat> {
    const stats: CacheStat[] = await Promise.all([
      ComicTranslationRuntimeService.documentRepositoryFor(context).stat(),
      ComicTranslationRuntimeService.renderedRepositoryFor(context).stat(),
      ComicTranslationRuntimeService.toriiContextStoreFor(context).stat(),
    ])
    const result: CacheStat = new CacheStat()
    for (let index: number = 0; index < stats.length; index++) {
      result.count += stats[index].count
      result.bytes += stats[index].bytes
    }
    return result
  }

  private static async runToriiWholePage(
    context: common.UIAbilityContext,
    input: ComicTranslationReaderPageInput,
    metadata: ComicTranslationReaderFileMetadata,
    settings: ComicVisualProviderSettingsSnapshot,
    forceRefresh: boolean,
  ): Promise<ComicVisualTranslationRunResult> {
    const credential: ToriiWholePageCredential =
      await ToriiWholePageSecretStore.read(context)
    const config: ToriiWholePageConfig = new ToriiWholePageConfig()
    config.toriiApiKey = credential.toriiApiKey
    config.fontId = settings.toriiFontId
    config.modelId = settings.toriiModelId
    config.assertValid()
    const contextStore: ToriiWholePageContextStore =
      ComicTranslationRuntimeService.toriiContextStoreFor(context)
    const backend: ToriiWholePageRenderBackend = new ToriiWholePageRenderBackend(
      context,
      config,
      contextStore,
    )
    const request: ComicWholePageTranslationRequest =
      new ComicWholePageTranslationRequest()
    request.source = ComicTranslationRuntimeService.visualSource(input, metadata)
    request.context.sourceLanguage = input.sourceLanguage
    request.context.targetLanguage = input.targetLanguage
    request.context.styleGuide =
      'Use concise natural phrasing in the requested target language. Keep names, forms of address, tone, and references consistent across pages.'
    request.context.rollingSummary = await contextStore.loadPrevious(
      backend.contextScope(input.projectId, input.pageIndex, input.targetLanguage),
    )
    request.context.glossaryRevision = 0
    request.context.styleGuideRevision = 2
    request.context.contextRevision = 1
    request.renderProfile = ComicTranslationRuntimeService.toriiRenderProfile()
    request.requestedTranslationRevision = 1
    const orchestrator: ComicWholePageTranslationOrchestrator =
      ComicTranslationRuntimeService.wholePageOrchestrator(
        context,
        backend,
      )
    return orchestrator.run(request, forceRefresh)
  }

  private static orchestrator(
    context: common.UIAbilityContext,
    backend: ComicRegionRenderBackend,
    translator: ComicTextTranslator,
    regionRevision: number,
  ): ComicVisualTranslationOrchestrator {
    const runtimeKey: string = ComicTranslationRuntimeService.digest(JSON.stringify([
      backend.backendId(),
      backend.profileId(),
      `${backend.protocolRevision()}`,
      `${regionRevision}`,
      translator.sourceProfileId(),
      `${translator.sourceRevision()}`,
      translator.modelId(),
      translator.promptVersion(),
    ]))
    const existing: ComicVisualTranslationOrchestrator | undefined =
      ComicTranslationRuntimeService.orchestrators.get(runtimeKey)
    if (existing !== undefined) {
      return existing
    }
    if (ComicTranslationRuntimeService.orchestrators.size >= MAX_RUNTIME_ORCHESTRATORS) {
      ComicTranslationRuntimeService.orchestrators.clear()
    }
    const created: ComicVisualTranslationOrchestrator = new ComicVisualTranslationOrchestrator(
      backend,
      translator,
      ComicTranslationRuntimeService.documentRepositoryFor(context),
      ComicTranslationRuntimeService.renderedRepositoryFor(context),
    )
    ComicTranslationRuntimeService.orchestrators.set(runtimeKey, created)
    return created
  }

  private static localBackendFor(context: common.UIAbilityContext): ComicRegionRenderBackend {
    const detectorPaths: ComicTranslationModelPaths | null =
      ComicTranslationModelService.pathsIfReady(context)
    if (detectorPaths === null) {
      return new ComicLocalVisualBackend(context)
    }
    const recognizerPaths: ComicTextRecognitionModelPaths | null =
      ComicTranslationModelService.ocrPathsIfReady(context)
    const inpaintingPaths: ComicSourceInpaintingModelPaths | null =
      ComicTranslationModelService.inpaintingPathsIfReady(context)
    const textMaskPaths: ComicTextMaskModelPaths | null =
      ComicTranslationModelService.textMaskPathsIfReady(context)
    return new ComicLocalVisualBackend(
      context,
      new HarmonyComicLocalOcrEngine(),
      new ComicNcnnLocalRegionDetector(detectorPaths.paramPath, detectorPaths.modelPath),
      recognizerPaths === null
        ? null
        : new ComicNcnnLocalTextRecognizer(
          recognizerPaths.paramPath,
          recognizerPaths.modelPath,
          recognizerPaths.dictionaryPath,
        ),
      inpaintingPaths === null || textMaskPaths === null
        ? null
        : new ComicNcnnLocalSourceInpainter(
          inpaintingPaths.paramPath,
          inpaintingPaths.modelPath,
          4,
        ),
      inpaintingPaths === null || textMaskPaths === null
        ? null
        : new ComicNcnnLocalTextMasker(
          textMaskPaths.paramPath,
          textMaskPaths.modelPath,
          0.3,
          4,
        ),
      inpaintingPaths === null || textMaskPaths === null
        ? null
        : new ComicNcnnLocalTextMasker(
          textMaskPaths.paramPath,
          textMaskPaths.modelPath,
          0.15,
          4,
          0.3,
        ),
    )
  }

  private static wholePageOrchestrator(
    context: common.UIAbilityContext,
    backend: ToriiWholePageRenderBackend,
  ): ComicWholePageTranslationOrchestrator {
    const runtimeKey: string = ComicTranslationRuntimeService.digest(JSON.stringify([
      backend.sourceProfileId(),
      `${backend.sourceRevision()}`,
      backend.modelId(),
      backend.promptVersion(),
    ]))
    const existing: ComicWholePageTranslationOrchestrator | undefined =
      ComicTranslationRuntimeService.wholePageOrchestrators.get(runtimeKey)
    if (existing !== undefined) {
      return existing
    }
    if (ComicTranslationRuntimeService.wholePageOrchestrators.size >=
      MAX_RUNTIME_ORCHESTRATORS) {
      ComicTranslationRuntimeService.wholePageOrchestrators.clear()
    }
    const created: ComicWholePageTranslationOrchestrator =
      new ComicWholePageTranslationOrchestrator(
        backend,
        ComicTranslationRuntimeService.renderedRepositoryFor(context),
      )
    ComicTranslationRuntimeService.wholePageOrchestrators.set(runtimeKey, created)
    return created
  }

  private static toriiContextStoreFor(
    context: common.UIAbilityContext,
  ): ToriiWholePageContextStore {
    const existing: ToriiWholePageContextStore | null =
      ComicTranslationRuntimeService.toriiContextStore
    if (existing !== null) {
      return existing
    }
    const created: ToriiWholePageContextStore = new ToriiWholePageContextStore(context)
    ComicTranslationRuntimeService.toriiContextStore = created
    return created
  }

  private static documentRepositoryFor(
    context: common.UIAbilityContext,
  ): ComicTranslationRepository {
    const existing: ComicTranslationRepository | null =
      ComicTranslationRuntimeService.documentRepository
    if (existing !== null) {
      return existing
    }
    const created: ComicTranslationRepository = new PersistentComicTranslationRepository(context)
    ComicTranslationRuntimeService.documentRepository = created
    return created
  }

  private static renderedRepositoryFor(
    context: common.UIAbilityContext,
  ): PersistentComicRenderedPageRepository {
    const existing: PersistentComicRenderedPageRepository | null =
      ComicTranslationRuntimeService.renderedRepository
    if (existing !== null) {
      return existing
    }
    const created: PersistentComicRenderedPageRepository =
      new PersistentComicRenderedPageRepository(context)
    ComicTranslationRuntimeService.renderedRepository = created
    return created
  }

  private static renderProfile(): ComicRenderProfile {
    const profile: ComicRenderProfile = new ComicRenderProfile()
    profile.profileId = COMIC_READER_RENDER_PROFILE_ID
    profile.sourceTreatmentProfileId = COMIC_READER_SOURCE_TREATMENT_PROFILE_ID
    profile.layoutProfileId = COMIC_READER_LAYOUT_PROFILE_ID
    profile.targetMimeType = 'image/png'
    profile.revision = 29
    return profile
  }

  private static toriiRenderProfile(): ComicRenderProfile {
    const profile: ComicRenderProfile = new ComicRenderProfile()
    profile.profileId = TORII_WHOLE_PAGE_RENDER_PROFILE_ID
    profile.sourceTreatmentProfileId = TORII_WHOLE_PAGE_SOURCE_TREATMENT_PROFILE_ID
    profile.layoutProfileId = TORII_WHOLE_PAGE_LAYOUT_PROFILE_ID
    profile.targetMimeType = 'image/png'
    profile.revision = 1
    return profile
  }

  private static visualSource(
    input: ComicTranslationReaderPageInput,
    metadata: ComicTranslationReaderFileMetadata,
  ): ComicVisualPageSource {
    const source: ComicVisualPageSource = new ComicVisualPageSource()
    source.projectId = input.projectId
    source.pageIndex = input.pageIndex
    source.imageFilePath = input.imageFilePath
    source.imageHash = metadata.imageHash
    source.imageWidth = metadata.imageWidth
    source.imageHeight = metadata.imageHeight
    return source
  }

  private static validateInput(input: ComicTranslationReaderPageInput): void {
    if (!ComicTranslationRuntimeService.boundedExactIdentifier(
      input.projectId,
      MAX_COMIC_READER_IDENTIFIER_CHARS,
    ) || !ComicTranslationRuntimeService.nonNegativeSafeInteger(input.pageIndex) ||
      !ComicTranslationRuntimeService.boundedRequired(
        input.imageFilePath,
        MAX_COMIC_READER_IMAGE_PATH_CHARS,
      ) || !ComicTranslationRuntimeService.positiveImageEdge(input.imageWidth) ||
      !ComicTranslationRuntimeService.positiveImageEdge(input.imageHeight) ||
      !ComicTranslationRuntimeService.boundedExactIdentifier(
        input.sourceLanguage,
        MAX_COMIC_READER_IDENTIFIER_CHARS,
      ) || !ComicTranslationRuntimeService.boundedExactIdentifier(
        input.targetLanguage,
        MAX_COMIC_READER_IDENTIFIER_CHARS,
      )) {
      throw new Error('Comic reader image source is invalid')
    }
  }

  private static boundedRequired(value: string, maxChars: number): boolean {
    const normalized: string = value.trim()
    return normalized.length > 0 && value.length <= maxChars
  }

  private static boundedExactIdentifier(value: string, maxChars: number): boolean {
    return value.length > 0 && value.length <= maxChars && value === value.trim()
  }

  private static nonNegativeSafeInteger(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  private static positiveImageEdge(value: number): boolean {
    return value > 0 && value <= MAX_COMIC_READER_IMAGE_EDGE &&
      ComicTranslationRuntimeService.nonNegativeSafeInteger(value)
  }

  private static async fileMetadata(path: string): Promise<ComicTranslationReaderFileMetadata> {
    const stat: fileIo.Stat = fileIo.statSync(path)
    if (stat.size <= 0 || stat.size > COMIC_READER_MAX_IMAGE_BYTES) {
      throw new Error('Comic provider image file size is invalid')
    }
    const metadata: ComicTranslationReaderFileMetadata = new ComicTranslationReaderFileMetadata()
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const headerBuffer: ArrayBuffer = new ArrayBuffer(16)
      const headerRead: number = fileIo.readSync(file.fd, headerBuffer, { length: 16 })
      metadata.mimeType = ComicTranslationRuntimeService.detectMime(
        new Uint8Array(headerBuffer, 0, headerRead),
      )
      const md = cryptoFramework.createMd('SHA256')
      md.updateSync({ data: new Uint8Array(headerBuffer, 0, headerRead) })
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(COMIC_READER_HASH_CHUNK_BYTES)
        const read: number = fileIo.readSync(file.fd, buffer, {
          length: COMIC_READER_HASH_CHUNK_BYTES,
        })
        if (read <= 0) {
          break
        }
        md.updateSync({ data: new Uint8Array(buffer, 0, read) })
      }
      metadata.imageHash = ComicTranslationRuntimeService.toHex(md.digestSync().data)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
    let source: image.ImageSource | undefined = undefined
    try {
      source = image.createImageSource(path)
      const info: image.ImageInfo = await source.getImageInfo()
      metadata.imageWidth = Math.floor(info.size.width)
      metadata.imageHeight = Math.floor(info.size.height)
      if (!ComicTranslationRuntimeService.positiveImageEdge(metadata.imageWidth) ||
        !ComicTranslationRuntimeService.positiveImageEdge(metadata.imageHeight)) {
        throw new Error('Comic provider image dimensions are invalid')
      }
      return metadata
    } catch (error) {
      const message: string = error instanceof Error ? error.message : `${error}`
      if (message === 'Comic provider image dimensions are invalid') {
        throw new Error(message)
      }
      throw new Error('Comic provider image dimensions cannot be decoded')
    } finally {
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  private static detectMime(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return 'image/jpeg'
    }
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4e && bytes[3] === 0x47) {
      return 'image/png'
    }
    if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return 'image/gif'
    }
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
      bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'image/webp'
    }
    throw new Error('Comic provider image MIME type is unsupported')
  }

  private static digest(value: string): string {
    const encoded: Uint8Array = new util.TextEncoder().encodeInto(value)
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: encoded })
    return ComicTranslationRuntimeService.toHex(md.digestSync().data)
  }

  private static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}
