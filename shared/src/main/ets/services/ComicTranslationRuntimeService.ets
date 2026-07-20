import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { ComicImagePreparationProfile } from '../model/ComicTranslation'
import { ComicTranslationProviderSettingsSnapshot } from '../model/ComicTranslationProvider'
import { ComicTranslationProviderSettings } from '../settings/ComicTranslationProviderSettings'
import { ComicPageAnalysisRequest, ComicPageAnalyzer } from './ComicPageAnalyzer'
import { ComicPageAnalyzerFactory } from './ComicResponsesPageAnalyzer'
import { ComicTranslationOrchestrator, ComicTranslationRunResult } from './ComicTranslationOrchestrator'
import { ComicTranslationRepository } from './ComicTranslationRepository'
import { PersistentComicTranslationRepository } from './ComicTranslationPersistentRepository'

const COMIC_READER_MAX_IMAGE_BYTES: number = 20 * 1024 * 1024
const COMIC_READER_HASH_CHUNK_BYTES: number = 256 * 1024
const COMIC_READER_PROFILE_ID: string = 'reader-current-file-v1'
const MAX_RUNTIME_ORCHESTRATORS: number = 4

class ComicTranslationReaderFileMetadata {
  imageHash: string = ''
  mimeType: string = ''
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
  private static repository: ComicTranslationRepository | null = null
  private static orchestrators: Map<string, ComicTranslationOrchestrator> = new Map()

  static async runReaderPage(
    context: common.UIAbilityContext,
    input: ComicTranslationReaderPageInput,
    forceRefresh: boolean = false,
  ): Promise<ComicTranslationRunResult> {
    ComicTranslationRuntimeService.validateInput(input)
    const metadata: ComicTranslationReaderFileMetadata =
      ComicTranslationRuntimeService.fileMetadata(input.imageFilePath)
    const analyzer: ComicPageAnalyzer = ComicPageAnalyzerFactory.create(context)
    const orchestrator: ComicTranslationOrchestrator =
      ComicTranslationRuntimeService.orchestrator(context, analyzer)
    const request: ComicPageAnalysisRequest = new ComicPageAnalysisRequest()
    request.projectId = input.projectId
    request.pageIndex = input.pageIndex
    request.imageFilePath = input.imageFilePath
    request.imageHash = metadata.imageHash
    request.sourceWidth = input.imageWidth
    request.sourceHeight = input.imageHeight
    request.requestedAnalysisRevision = 1
    request.requestedTranslationRevision = 1
    request.imagePreparationProfile = ComicTranslationRuntimeService.profile(
      metadata.mimeType,
      input.imageWidth,
      input.imageHeight,
    )
    request.context.sourceLanguage = input.sourceLanguage
    request.context.targetLanguage = input.targetLanguage
    request.context.styleGuide =
      'Use concise natural Chinese. Keep names, forms of address, tone, and references consistent across pages.'
    request.context.glossaryRevision = 0
    request.context.styleGuideRevision = 1
    request.context.contextRevision = 1
    return orchestrator.run(request, forceRefresh)
  }

  static async clearGeneratedCache(context: common.UIAbilityContext): Promise<void> {
    ComicTranslationRuntimeService.orchestrators.clear()
    const repository: ComicTranslationRepository =
      ComicTranslationRuntimeService.repositoryFor(context)
    await repository.clear()
  }

  private static orchestrator(
    context: common.UIAbilityContext,
    analyzer: ComicPageAnalyzer,
  ): ComicTranslationOrchestrator {
    const settings: ComicTranslationProviderSettingsSnapshot =
      ComicTranslationProviderSettings.current()
    const runtimeKey: string = ComicTranslationRuntimeService.digest(JSON.stringify([
      analyzer.providerId(),
      analyzer.modelId(),
      analyzer.analysisPromptVersion(),
      settings.provider,
      settings.apiBaseUrl,
      settings.apiKey,
      settings.apiModel,
      settings.codexModel,
    ]))
    const existing: ComicTranslationOrchestrator | undefined =
      ComicTranslationRuntimeService.orchestrators.get(runtimeKey)
    if (existing !== undefined) {
      return existing
    }
    if (ComicTranslationRuntimeService.orchestrators.size >= MAX_RUNTIME_ORCHESTRATORS) {
      ComicTranslationRuntimeService.orchestrators.clear()
    }
    const created: ComicTranslationOrchestrator = new ComicTranslationOrchestrator(
      analyzer,
      ComicTranslationRuntimeService.repositoryFor(context),
    )
    ComicTranslationRuntimeService.orchestrators.set(runtimeKey, created)
    return created
  }

  private static repositoryFor(context: common.UIAbilityContext): ComicTranslationRepository {
    const existing: ComicTranslationRepository | null = ComicTranslationRuntimeService.repository
    if (existing !== null) {
      return existing
    }
    const created: ComicTranslationRepository = new PersistentComicTranslationRepository(context)
    ComicTranslationRuntimeService.repository = created
    return created
  }

  private static profile(
    mimeType: string,
    width: number,
    height: number,
  ): ComicImagePreparationProfile {
    const profile: ComicImagePreparationProfile = new ComicImagePreparationProfile()
    profile.profileId = COMIC_READER_PROFILE_ID
    profile.mimeType = mimeType
    profile.preparedWidth = width
    profile.preparedHeight = height
    profile.tileCount = 1
    return profile
  }

  private static validateInput(input: ComicTranslationReaderPageInput): void {
    if (input.projectId.trim().length === 0 || input.pageIndex < 0 ||
      input.imageFilePath.trim().length === 0 || input.imageWidth <= 0 || input.imageHeight <= 0 ||
      input.sourceLanguage.trim().length === 0 || input.targetLanguage.trim().length === 0) {
      throw new Error('Comic reader image source is invalid')
    }
  }

  private static fileMetadata(path: string): ComicTranslationReaderFileMetadata {
    const stat: fileIo.Stat = fileIo.statSync(path)
    if (stat.size <= 0 || stat.size > COMIC_READER_MAX_IMAGE_BYTES) {
      throw new Error('Comic provider image file size is invalid')
    }
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const headerBuffer: ArrayBuffer = new ArrayBuffer(16)
      const headerRead: number = fileIo.readSync(file.fd, headerBuffer, { length: 16 })
      const metadata: ComicTranslationReaderFileMetadata = new ComicTranslationReaderFileMetadata()
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
      return metadata
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
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
