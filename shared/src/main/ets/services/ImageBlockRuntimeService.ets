import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { EhConstants } from '../constants/EhConstants'
import {
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_SCOPE_WHOLE,
  IMAGE_BLOCK_SOURCE_LOCAL,
  ImageBlockDecision,
  ImageBlockRule,
} from '../model/ImageBlockRule'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ImageBlockRepository } from '../storage/ImageBlockRepository'
import { CachedImageFileResult, CachedImageFileService } from './CachedImageFileService'
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
    const decision: ImageBlockDecision = ImageBlockService.decisionForHash(hash, rules, whitelist)
    if (decision.blocked) {
      await ImageBlockRepository.rememberRulePreview(context, decision.ruleId, path)
    }
    return decision
  }

  static async decisionForThumbnail(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): Promise<ImageBlockDecision> {
    const empty: ImageBlockDecision = new ImageBlockDecision()
    if (thumbUrl.length === 0) {
      return empty
    }
    const rules: ImageBlockRule[] = await ImageBlockRepository.loadEnabledRules(context)
    if (rules.length === 0) {
      return empty
    }
    const cached: CachedImageFileResult = await ImageBlockRuntimeService.loadThumbnailFile(
      context,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    const hash: string = await ImageBlockRuntimeService.hashForThumbnail(
      context,
      cached.filePath,
      cached.bytes,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
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
    rule.previewPath = path
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
    return ImageBlockRepository.upsertWhitelistHash(context, hash, path)
  }

  static async addLocalRuleForThumbnail(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
    sourceUrl: string = '',
    sourcePage: number = 0,
  ): Promise<ImageBlockRule> {
    const cached: CachedImageFileResult = await ImageBlockRuntimeService.loadThumbnailFile(
      context,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    const hash: string = await ImageBlockRuntimeService.hashForThumbnail(
      context,
      cached.filePath,
      cached.bytes,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    if (hash.length === 0) {
      throw new Error('Image block pHash unavailable')
    }
    const rule: ImageBlockRule = new ImageBlockRule()
    rule.id = 'local:' + hash
    rule.hash = hash
    rule.threshold = IMAGE_BLOCK_DEFAULT_THRESHOLD
    rule.label = 'scanlator-ad'
    rule.scope = IMAGE_BLOCK_SCOPE_WHOLE
    rule.sourceType = IMAGE_BLOCK_SOURCE_LOCAL
    rule.sourceUrl = sourceUrl
    rule.sourcePage = sourcePage > 0 ? Math.floor(sourcePage) : 0
    rule.previewPath = cached.filePath
    rule.enabled = true
    rule.updatedAt = Date.now()
    await ImageBlockRepository.upsertLocalRule(context, rule)
    return rule
  }

  static async addWhitelistForThumbnail(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): Promise<string> {
    const cached: CachedImageFileResult = await ImageBlockRuntimeService.loadThumbnailFile(
      context,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    const hash: string = await ImageBlockRuntimeService.hashForThumbnail(
      context,
      cached.filePath,
      cached.bytes,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    if (hash.length === 0) {
      throw new Error('Image block pHash unavailable')
    }
    return ImageBlockRepository.upsertWhitelistHash(context, hash, cached.filePath)
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

  private static async loadThumbnailFile(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): Promise<CachedImageFileResult> {
    if (thumbUrl.length === 0) {
      throw new Error('Image block thumbnail url is empty')
    }
    const url: string = EhConstants.cdnThumb(thumbUrl)
    const cacheKey: string = `thumb-block:${url}:${thumbWidth}:${thumbHeight}:${offsetX}:${spriteWidth}:${spriteHeight}`
    return CachedImageFileService.load(context, url, cacheKey, (_progress) => {})
  }

  private static async hashForThumbnail(
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): Promise<string> {
    const regionKey: string = `${filePath}#thumb-v2:${thumbWidth}:${thumbHeight}:${offsetX}:${spriteWidth}:${spriteHeight}`
    let hash: string = await ImageBlockRepository.loadCachedFileHash(context, regionKey, bytes)
    if (hash.length > 0) {
      return hash
    }
    if (spriteWidth > 0 && thumbWidth > 0 && thumbHeight > 0) {
      hash = await PHashService.hashImageFileRegionDct64(filePath, offsetX, 0, thumbWidth, thumbHeight)
    } else {
      hash = await PHashService.hashImageFileDct64(filePath)
    }
    if (hash.length > 0) {
      await ImageBlockRepository.upsertFileHash(context, regionKey, bytes, hash)
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
