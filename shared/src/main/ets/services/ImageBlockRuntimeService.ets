import { common } from '@kit.AbilityKit'
import { taskpool } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { EhConstants } from '../constants/EhConstants'
import { EhGalleryImage } from '../model/EhGalleryImage'
import {
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_SCOPE_WHOLE,
  IMAGE_BLOCK_SOURCE_LOCAL,
  ImageBlockDecision,
  ImageBlockRule,
} from '../model/ImageBlockRule'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhApiService, GalleryDetailResult } from '../network/EhApiService'
import { connectImageBlockSettings } from '../state/ImageBlockSettingsState'
import { connectImageBlockRuntime } from '../state/ImageBlockRuntimeState'
import { connectSiteMode } from '../state/SiteModeState'
import { ImageBlockRepository } from '../storage/ImageBlockRepository'
import { EhUrlRouter, GalleryRef, ImagePageRef } from '../utils/EhUrlRouter'
import { CachedImageFileResult, CachedImageFileService } from './CachedImageFileService'
import { ImageBlockService } from './ImageBlockService'
import { ImagePageRouteService, ImagePageRouteTarget } from './ImagePageRouteService'
import { PHashService } from './PHashService'

export class ImageBlockThumbnailDecision {
  decision: ImageBlockDecision = new ImageBlockDecision()
  previewUri: string = ''
  previewPath: string = ''
  bytes: number = 0
}

class ImageBlockSourcePreviewTarget {
  gid: string = ''
  token: string = ''
  page: number = 0
  imgkey: string = ''
  isEx: boolean = false
}

@Concurrent
async function writeImageBlockThumbnailPreview(
  sourcePath: string,
  outputPath: string,
  thumbWidth: number,
  thumbHeight: number,
  offsetX: number,
): Promise<boolean> {
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  let packer: image.ImagePacker | undefined = undefined
  let file: fileIo.File | null = null
  try {
    source = image.createImageSource(sourcePath)
    const options: image.DecodingOptions = {
      editable: false,
      desiredRegion: {
        x: Math.max(0, Math.floor(offsetX)),
        y: 0,
        size: {
          width: Math.max(1, Math.floor(thumbWidth)),
          height: Math.max(1, Math.floor(thumbHeight)),
        },
      },
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
    }
    pixelMap = await source.createPixelMap(options)
    file = fileIo.openSync(outputPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    packer = image.createImagePacker()
    const packOptions: image.PackingOption = { format: 'image/jpeg', quality: 92 }
    await packer.packToFile(pixelMap, file.fd, packOptions)
    return true
  } catch (_error) {
    return false
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file)
      } catch (_error) {
      }
    }
    if (packer !== undefined) {
      await packer.release()
    }
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      await source.release()
    }
  }
}

export class ImageBlockRuntimeService {
  private static cachedRulesSignal: string = '#unset'
  private static cachedRules: ImageBlockRule[] = []
  private static thumbnailColdChain: Promise<void> = Promise.resolve()
  private static thumbnailHashInFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>()
  private static thumbnailHashMemoryCache: Map<string, string> = new Map<string, string>()

  static async decisionForFile(
    context: common.UIAbilityContext,
    filePath: string,
  ): Promise<ImageBlockDecision> {
    const path: string = ImageBlockRuntimeService.normalizeFilePath(filePath)
    const empty: ImageBlockDecision = new ImageBlockDecision()
    if (path.length === 0) {
      return empty
    }
    if (!connectImageBlockSettings().enabled) {
      return empty
    }
    const bytes: number = ImageBlockRuntimeService.fileBytes(path)
    if (bytes <= 0) {
      return empty
    }

    const rules: ImageBlockRule[] = await ImageBlockRuntimeService.loadEnabledRulesCached(context)
    if (rules.length === 0) {
      return empty
    }

    const hash: string = await ImageBlockRuntimeService.hashForFile(context, path, bytes)
    if (hash.length === 0) {
      return empty
    }

    return ImageBlockService.decisionForHash(hash, rules)
  }

  static async decisionForThumbnail(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
    sourceKey: string = '',
    computeWhenMissing: boolean = true,
  ): Promise<ImageBlockDecision> {
    const empty: ImageBlockDecision = new ImageBlockDecision()
    if (thumbUrl.length === 0) {
      return empty
    }
    if (!connectImageBlockSettings().enabled) {
      return empty
    }
    let hash: string = ''
    const stableKey: string = ImageBlockRuntimeService.stableThumbnailHashKey(sourceKey)
    if (stableKey.length > 0) {
      hash = await ImageBlockRuntimeService.loadStableThumbnailHash(context, stableKey)
    }
    const cached: CachedImageFileResult | null = ImageBlockRuntimeService.cachedThumbnailFile(
      context,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    if (hash.length === 0 && cached !== null) {
      hash = await ImageBlockRuntimeService.hashForThumbnail(
        context,
        cached.filePath,
        cached.bytes,
        thumbWidth,
        thumbHeight,
        offsetX,
        spriteWidth,
        spriteHeight,
        sourceKey,
        false,
      )
    }
    if (hash.length === 0 && computeWhenMissing) {
      hash = await ImageBlockRuntimeService.loadAndHashThumbnailQueued(
        context,
        thumbUrl,
        thumbWidth,
        thumbHeight,
        offsetX,
        spriteWidth,
        spriteHeight,
        sourceKey,
      )
    }
    if (hash.length === 0) {
      return empty
    }
    const rules: ImageBlockRule[] = await ImageBlockRuntimeService.loadEnabledRulesCached(context)
    if (rules.length === 0) {
      return empty
    }
    return ImageBlockService.decisionForHash(hash, rules)
  }

  static async decisionForCachedThumbnail(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
    sourceKey: string = '',
  ): Promise<ImageBlockThumbnailDecision> {
    const out: ImageBlockThumbnailDecision = new ImageBlockThumbnailDecision()
    if (thumbUrl.length === 0 || !connectImageBlockSettings().enabled) {
      return out
    }
    const cached: CachedImageFileResult | null = ImageBlockRuntimeService.cachedThumbnailFile(
      context,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    if (cached === null) {
      return out
    }
    const hash: string = await ImageBlockRuntimeService.hashForThumbnail(
      context,
      cached.filePath,
      cached.bytes,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
      sourceKey,
      false,
    )
    if (hash.length === 0) {
      return out
    }
    const rules: ImageBlockRule[] = await ImageBlockRuntimeService.loadEnabledRulesCached(context)
    if (rules.length === 0) {
      return out
    }
    out.decision = ImageBlockService.decisionForHash(hash, rules)
    if (out.decision.blocked) {
      out.previewUri = cached.displayUri
      out.previewPath = cached.filePath
      out.bytes = cached.bytes
    }
    return out
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
    rule.previewPath = ''
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
    return ImageBlockRepository.upsertWhitelistHash(context, hash, '')
  }

  static async addWhitelistForHash(
    context: common.UIAbilityContext,
    hash: string,
    previewPath: string = '',
  ): Promise<string> {
    return ImageBlockRepository.upsertWhitelistHash(context, hash, previewPath)
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
    sourceKey: string = '',
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
      sourceKey,
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
    rule.previewPath = ''
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
    return ImageBlockRepository.upsertWhitelistHash(context, hash, '')
  }

  static async previewPathForRuleSource(
    context: common.UIAbilityContext,
    rule: ImageBlockRule,
  ): Promise<string> {
    DiagnosticLogger.info(
      'image_block',
      'source_preview_start',
      `rule=${DiagnosticLogger.ownerHash(rule.id)} source=${DiagnosticLogger.ownerHash(rule.sourceUrl)} page=${rule.sourcePage}`,
    )
    const image: EhGalleryImage = await ImageBlockRuntimeService.previewImageForRuleSource(rule)
    if (image.thumbUrl.length === 0) {
      DiagnosticLogger.info(
        'image_block',
        'source_preview_no_image',
        `rule=${DiagnosticLogger.ownerHash(rule.id)} source=${DiagnosticLogger.ownerHash(rule.sourceUrl)} page=${rule.sourcePage}`,
      )
      return ''
    }
    const cached: CachedImageFileResult = await ImageBlockRuntimeService.loadThumbnailFile(
      context,
      image.thumbUrl,
      image.thumbWidth,
      image.thumbHeight,
      image.thumbOffsetX,
      image.spriteWidth,
      image.spriteHeight,
    )
    const key: string = rule.hash.length > 0 ? rule.hash : rule.id
    const path: string = await ImageBlockRuntimeService.thumbnailPreviewPath(
      context,
      cached.filePath,
      key,
      image.thumbWidth,
      image.thumbHeight,
      image.thumbOffsetX,
      image.spriteWidth,
      image.spriteHeight,
    )
    DiagnosticLogger.info(
      'image_block',
      'source_preview_done',
      `rule=${DiagnosticLogger.ownerHash(rule.id)} imagePage=${image.page} path=${DiagnosticLogger.ownerHash(path)}`,
    )
    return path
  }

  static logPreviewRepairFailure(rule: ImageBlockRule, message: string): void {
    DiagnosticLogger.warn(
      'image_block',
      'source_preview_failed',
      `rule=${DiagnosticLogger.ownerHash(rule.id)} source=${DiagnosticLogger.ownerHash(rule.sourceUrl)} page=${rule.sourcePage} error=${message}`,
    )
  }

  private static async previewImageForRuleSource(rule: ImageBlockRule): Promise<EhGalleryImage> {
    const target: ImageBlockSourcePreviewTarget = await ImageBlockRuntimeService.previewTargetForRule(rule)
    if (target.gid.length === 0 || target.token.length === 0) {
      DiagnosticLogger.info(
        'image_block',
        'source_preview_no_target',
        `rule=${DiagnosticLogger.ownerHash(rule.id)} source=${DiagnosticLogger.ownerHash(rule.sourceUrl)} page=${rule.sourcePage}`,
      )
      return new EhGalleryImage()
    }
    const detail: GalleryDetailResult = await EhApiService.getInstance().getGalleryDetail(
      target.gid,
      target.token,
      target.isEx,
    )
    const firstMatch: EhGalleryImage | null = ImageBlockRuntimeService.findPreviewImage(detail.images, target)
    if (firstMatch !== null) {
      DiagnosticLogger.info(
        'image_block',
        'source_preview_match_first',
        `rule=${DiagnosticLogger.ownerHash(rule.id)} targetPage=${target.page} firstImages=${detail.images.length}`,
      )
      return firstMatch
    }
    const candidates: number[] = ImageBlockRuntimeService.previewPageCandidates(target.page, detail.images.length, detail.previewPageCount)
    for (let i: number = 0; i < candidates.length; i++) {
      const p: number = candidates[i]
      if (p <= 0) {
        continue
      }
      const images: EhGalleryImage[] = await EhApiService.getInstance().getPreviewImages(
        target.gid,
        target.token,
        target.isEx,
        p,
      )
      const match: EhGalleryImage | null = ImageBlockRuntimeService.findPreviewImage(images, target)
      if (match !== null) {
        DiagnosticLogger.info(
          'image_block',
          'source_preview_match_page',
          `rule=${DiagnosticLogger.ownerHash(rule.id)} targetPage=${target.page} previewPage=${p} images=${images.length}`,
        )
        return match
      }
    }
    DiagnosticLogger.info(
      'image_block',
      'source_preview_no_match',
      `rule=${DiagnosticLogger.ownerHash(rule.id)} targetPage=${target.page} candidates=${candidates.length}`,
    )
    return new EhGalleryImage()
  }

  private static async previewTargetForRule(rule: ImageBlockRule): Promise<ImageBlockSourcePreviewTarget> {
    const out: ImageBlockSourcePreviewTarget = new ImageBlockSourcePreviewTarget()
    const sourceUrl: string = ImageBlockRuntimeService.normalizedSourceUrl(rule.sourceUrl)
    if (sourceUrl.length === 0) {
      return out
    }
    out.isEx = ImageBlockRuntimeService.sourceIsEx(sourceUrl)
    const galleryRef: GalleryRef | null = EhUrlRouter.parseGallery(sourceUrl)
    if (galleryRef !== null) {
      out.gid = galleryRef.gid
      out.token = galleryRef.token
      out.page = rule.sourcePage > 0 ? Math.floor(rule.sourcePage) : 0
      return out
    }
    const imageRef: ImagePageRef | null = EhUrlRouter.parseImagePage(sourceUrl)
    if (imageRef !== null) {
      const resolved: ImagePageRouteTarget = await ImagePageRouteService.resolve(sourceUrl)
      out.gid = resolved.gid.length > 0 ? resolved.gid : imageRef.gid
      out.token = resolved.token
      out.page = rule.sourcePage > 0 ? Math.floor(rule.sourcePage) : imageRef.page
      out.imgkey = imageRef.imgkey
      out.isEx = ImageBlockRuntimeService.sourceIsEx(sourceUrl)
    }
    return out
  }

  private static normalizedSourceUrl(sourceUrl: string): string {
    let out: string = sourceUrl.trim()
    if (out.length === 0 || out.startsWith('http://') || out.startsWith('https://')) {
      return out
    }
    while (out.startsWith('/')) {
      out = out.substring(1)
    }
    if (out.startsWith('g/') || out.startsWith('s/')) {
      const host: string = ImageBlockRuntimeService.sourceIsEx(out) ? 'exhentai.org' : 'e-hentai.org'
      return `https://${host}/${out}`
    }
    return out
  }

  private static sourceIsEx(sourceUrl: string): boolean {
    if (sourceUrl.indexOf('exhentai.org') >= 0) {
      return true
    }
    if (sourceUrl.indexOf('e-hentai.org') >= 0) {
      return false
    }
    return connectSiteMode().isEx
  }

  private static findPreviewImage(images: EhGalleryImage[], target: ImageBlockSourcePreviewTarget): EhGalleryImage | null {
    for (let i: number = 0; i < images.length; i++) {
      const imageItem: EhGalleryImage = images[i]
      if (target.imgkey.length > 0 && imageItem.imgkey === target.imgkey) {
        return imageItem
      }
      if (target.page > 0 && imageItem.page === target.page) {
        return imageItem
      }
    }
    return null
  }

  private static previewPageCandidates(page: number, firstPageCount: number, previewPageCount: number): number[] {
    const out: number[] = []
    if (page <= 0 || previewPageCount <= 1) {
      return out
    }
    const normalizedFirstCount: number = firstPageCount > 0 ? firstPageCount : 20
    ImageBlockRuntimeService.pushPreviewCandidate(out, Math.floor((page - 1) / normalizedFirstCount), previewPageCount)
    ImageBlockRuntimeService.pushPreviewCandidate(out, Math.floor((page - 1) / 40), previewPageCount)
    ImageBlockRuntimeService.pushPreviewCandidate(out, Math.floor((page - 1) / 20), previewPageCount)
    return out
  }

  private static pushPreviewCandidate(out: number[], candidate: number, previewPageCount: number): void {
    if (candidate <= 0 || candidate >= previewPageCount || out.indexOf(candidate) >= 0) {
      return
    }
    out.push(candidate)
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

  private static async loadEnabledRulesCached(context: common.UIAbilityContext): Promise<ImageBlockRule[]> {
    const signal: string = connectImageBlockRuntime().signal
    if (ImageBlockRuntimeService.cachedRulesSignal === signal) {
      return ImageBlockRuntimeService.cachedRules
    }
    const rules: ImageBlockRule[] = await ImageBlockRepository.loadEnabledRules(context)
    ImageBlockRuntimeService.cachedRules = rules
    ImageBlockRuntimeService.cachedRulesSignal = signal
    return rules
  }

  private static async thumbnailPreviewPath(
    context: common.UIAbilityContext,
    sourcePath: string,
    hash: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): Promise<string> {
    if (spriteWidth <= 0 || thumbWidth <= 0 || thumbHeight <= 0) {
      return sourcePath
    }
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (normalizedHash.length === 0) {
      return ''
    }
    const dir: string = `${context.cacheDir}/image-block-preview`
    ImageBlockRuntimeService.ensureDir(dir)
    const path: string = `${dir}/${normalizedHash}_${thumbWidth}_${thumbHeight}_${offsetX}_${spriteWidth}_${spriteHeight}.jpg`
    if (ImageBlockRuntimeService.fileBytes(path) > 0) {
      return path
    }
    const ok: boolean = await taskpool.execute<[string, string, number, number, number], boolean>(
      writeImageBlockThumbnailPreview,
      sourcePath,
      path,
      thumbWidth,
      thumbHeight,
      offsetX,
    )
    return ok && ImageBlockRuntimeService.fileBytes(path) > 0 ? path : ''
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

  private static cachedThumbnailFile(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): CachedImageFileResult | null {
    const url: string = EhConstants.cdnThumb(thumbUrl)
    const cacheKey: string = `thumb-block:${url}:${thumbWidth}:${thumbHeight}:${offsetX}:${spriteWidth}:${spriteHeight}`
    return CachedImageFileService.cached(context, url, cacheKey)
  }

  private static async loadAndHashThumbnailQueued(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
    sourceKey: string = '',
  ): Promise<string> {
    const key: string = ImageBlockRuntimeService.thumbnailHashKey(
      sourceKey,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    const inFlight: Promise<string> | undefined = ImageBlockRuntimeService.thumbnailHashInFlight.get(key)
    if (inFlight !== undefined) {
      ImageBlockRuntimeService.logThumbHash('thumb_hash_queue_join', key)
      return inFlight
    }
    ImageBlockRuntimeService.logThumbHash('thumb_hash_queue_enqueue', key)
    const task: Promise<string> = ImageBlockRuntimeService.loadAndHashThumbnailAfterPrevious(
      context,
      thumbUrl,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
      sourceKey,
    )
    ImageBlockRuntimeService.thumbnailHashInFlight.set(key, task)
    try {
      return await task
    } finally {
      ImageBlockRuntimeService.thumbnailHashInFlight.delete(key)
    }
  }

  private static async loadAndHashThumbnailAfterPrevious(
    context: common.UIAbilityContext,
    thumbUrl: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
    sourceKey: string = '',
  ): Promise<string> {
    const previous: Promise<void> = ImageBlockRuntimeService.thumbnailColdChain
    let release: () => void = () => {}
    ImageBlockRuntimeService.thumbnailColdChain = new Promise<void>((resolve: () => void) => {
      release = resolve
    })
    await previous
    try {
      ImageBlockRuntimeService.logThumbHash('thumb_hash_queue_start', sourceKey.length > 0 ? sourceKey : thumbUrl)
      const cached: CachedImageFileResult = await ImageBlockRuntimeService.loadThumbnailFile(
        context,
        thumbUrl,
        thumbWidth,
        thumbHeight,
        offsetX,
        spriteWidth,
        spriteHeight,
      )
      return await ImageBlockRuntimeService.hashForThumbnail(
        context,
        cached.filePath,
        cached.bytes,
        thumbWidth,
        thumbHeight,
        offsetX,
        spriteWidth,
        spriteHeight,
        sourceKey,
        true,
      )
    } finally {
      release()
    }
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
    sourceKey: string = '',
    computeWhenMissing: boolean = true,
  ): Promise<string> {
    const regionKey: string = ImageBlockRuntimeService.thumbnailHashKey(
      sourceKey,
      filePath,
      thumbWidth,
      thumbHeight,
      offsetX,
      spriteWidth,
      spriteHeight,
    )
    const memoryHash: string | undefined = ImageBlockRuntimeService.thumbnailHashMemoryCache.get(regionKey)
    if (memoryHash !== undefined && memoryHash.length > 0) {
      ImageBlockRuntimeService.logThumbHash('thumb_hash_memory_hit', regionKey)
      return memoryHash
    }
    let hash: string = await ImageBlockRepository.loadCachedFileHash(context, regionKey, bytes)
    if (hash.length > 0) {
      ImageBlockRuntimeService.thumbnailHashMemoryCache.set(regionKey, hash)
      ImageBlockRuntimeService.logThumbHash('thumb_hash_store_hit', regionKey)
      return hash
    }
    if (!computeWhenMissing) {
      return ''
    }
    ImageBlockRuntimeService.logThumbHash('thumb_hash_compute_start', regionKey)
    if (spriteWidth > 0 && thumbWidth > 0 && thumbHeight > 0) {
      hash = await PHashService.hashImageFileRegionDct64(filePath, offsetX, 0, thumbWidth, thumbHeight)
    } else {
      hash = await PHashService.hashImageFileDct64(filePath)
    }
    if (hash.length > 0) {
      await ImageBlockRepository.upsertFileHash(context, regionKey, bytes, hash)
      ImageBlockRuntimeService.thumbnailHashMemoryCache.set(regionKey, hash)
      ImageBlockRuntimeService.logThumbHash('thumb_hash_compute_done', regionKey)
    } else {
      ImageBlockRuntimeService.logThumbHash('thumb_hash_compute_miss', regionKey)
    }
    return hash
  }

  private static async loadStableThumbnailHash(
    context: common.UIAbilityContext,
    stableKey: string,
  ): Promise<string> {
    const memoryHash: string | undefined = ImageBlockRuntimeService.thumbnailHashMemoryCache.get(stableKey)
    if (memoryHash !== undefined && memoryHash.length > 0) {
      return memoryHash
    }
    const hash: string = await ImageBlockRepository.loadCachedFileHashByPath(context, stableKey)
    if (hash.length > 0) {
      ImageBlockRuntimeService.thumbnailHashMemoryCache.set(stableKey, hash)
      ImageBlockRuntimeService.logThumbHash('thumb_hash_stable_hit', stableKey)
    }
    return hash
  }

  private static stableThumbnailHashKey(sourceKey: string): string {
    return sourceKey.length > 0 ? `eh-thumb:${sourceKey}` : ''
  }

  private static logThumbHash(event: string, key: string): void {
    DiagnosticLogger.info('image-block', event, `key=${DiagnosticLogger.ownerHash(key)}`)
  }

  private static thumbnailHashKey(
    sourceKey: string,
    fallback: string,
    thumbWidth: number,
    thumbHeight: number,
    offsetX: number,
    spriteWidth: number,
    spriteHeight: number,
  ): string {
    if (sourceKey.length > 0) {
      return ImageBlockRuntimeService.stableThumbnailHashKey(sourceKey)
    }
    return `${fallback}#thumb-v2:${thumbWidth}:${thumbHeight}:${offsetX}:${spriteWidth}:${spriteHeight}`
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

  private static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      if (!fileIo.accessSync(dir)) {
        throw error as Error
      }
    }
  }
}
