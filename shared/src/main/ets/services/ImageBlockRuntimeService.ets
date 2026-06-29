import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_SCOPE_WHOLE,
  IMAGE_BLOCK_SOURCE_LOCAL,
  ImageBlockDecision,
  ImageBlockRule,
} from '../model/ImageBlockRule'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ImageBlockRepository } from '../storage/ImageBlockRepository'
import { ImageBlockService } from './ImageBlockService'
import { PHashService } from './PHashService'

export class ImageBlockRuntimeService {
  static async decisionForFile(
    context: common.UIAbilityContext,
    filePath: string,
  ): Promise<ImageBlockDecision> {
    const path: string = ImageBlockRuntimeService.normalizeFilePath(filePath)
    const empty: ImageBlockDecision = new ImageBlockDecision()
    if (path.length === 0) {
      return empty
    }
    const bytes: number = ImageBlockRuntimeService.fileBytes(path)
    if (bytes <= 0) {
      return empty
    }

    const rules: ImageBlockRule[] = await ImageBlockRepository.loadEnabledRules(context)
    if (rules.length === 0) {
      return empty
    }

    const hash: string = await ImageBlockRuntimeService.hashForFile(context, path, bytes)
    if (hash.length === 0) {
      return empty
    }

    const whitelist: string[] = await ImageBlockRepository.loadWhitelist(context)
    return ImageBlockService.decisionForHash(hash, rules, whitelist)
  }

  static async addLocalRuleForFile(
    context: common.UIAbilityContext,
    filePath: string,
    label: string = 'local',
    threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD,
    sourceUrl: string = '',
    sourcePage: number = 0,
  ): Promise<ImageBlockRule> {
    const path: string = ImageBlockRuntimeService.normalizeFilePath(filePath)
    if (path.length === 0) {
      throw new Error('Image block file path is empty')
    }
    const bytes: number = ImageBlockRuntimeService.fileBytes(path)
    if (bytes <= 0) {
      throw new Error('Image block file is missing')
    }
    const hash: string = await ImageBlockRuntimeService.hashForFile(context, path, bytes)
    if (hash.length === 0) {
      throw new Error('Image block pHash unavailable')
    }

    const rule: ImageBlockRule = new ImageBlockRule()
    rule.id = 'local:' + hash
    rule.hash = hash
    rule.threshold = PHashService.clampThreshold(threshold)
    rule.label = label.length > 0 ? label : 'local'
    rule.scope = IMAGE_BLOCK_SCOPE_WHOLE
    rule.sourceType = IMAGE_BLOCK_SOURCE_LOCAL
    rule.sourceUrl = sourceUrl
    rule.sourcePage = sourcePage > 0 ? Math.floor(sourcePage) : 0
    rule.enabled = true
    rule.updatedAt = Date.now()
    await ImageBlockRepository.upsertLocalRule(context, rule)
    return rule
  }

  static async addWhitelistForFile(
    context: common.UIAbilityContext,
    filePath: string,
  ): Promise<string> {
    const path: string = ImageBlockRuntimeService.normalizeFilePath(filePath)
    if (path.length === 0) {
      throw new Error('Image block file path is empty')
    }
    const bytes: number = ImageBlockRuntimeService.fileBytes(path)
    if (bytes <= 0) {
      throw new Error('Image block file is missing')
    }
    const hash: string = await ImageBlockRuntimeService.hashForFile(context, path, bytes)
    if (hash.length === 0) {
      throw new Error('Image block pHash unavailable')
    }
    return ImageBlockRepository.upsertWhitelistHash(context, hash)
  }

  private static async hashForFile(
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
  ): Promise<string> {
    let hash: string = await ImageBlockRepository.loadCachedFileHash(context, filePath, bytes)
    if (hash.length > 0) {
      return hash
    }
    hash = await PHashService.hashImageFileDct64(filePath)
    if (hash.length > 0) {
      await ImageBlockRepository.upsertFileHash(context, filePath, bytes, hash)
    }
    return hash
  }

  private static normalizeFilePath(filePath: string): string {
    if (filePath.startsWith('file://')) {
      return filePath.substring('file://'.length)
    }
    return filePath
  }

  private static fileBytes(filePath: string): number {
    try {
      return fileIo.statSync(filePath).size
    } catch (error) {
      DiagnosticLogger.warn('image-block', 'stat_failed', (error as Error).message)
      return 0
    }
  }
}
