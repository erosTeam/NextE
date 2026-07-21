import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { common2D, drawing } from '@kit.ArkGraphics2D'
import { image } from '@kit.ImageKit'
import {
  ComicAnalysisState,
  ComicPageDocument,
  ComicPoint,
  ComicQualitySeverity,
  ComicQualitySignal,
  ComicRenderState,
  ComicSourceOrigin,
  ComicTextBlock,
  ComicTextKind,
  ComicTranslationState,
} from '../model/ComicTranslation'
import {
  ComicBackendTemplate,
  ComicRenderedPage,
  ComicRegionAnalysisResult,
} from '../model/ComicVisualTranslation'
import {
  ComicRegionAnalysisRequest,
  ComicRegionRenderBackend,
  ComicRegionRenderRequest,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import {
  ComicLocalOcrEngine,
  ComicLocalOcrLine,
  ComicLocalOcrPoint,
  ComicLocalOcrResult,
  HarmonyComicLocalOcrEngine,
} from './ComicHarmonyOcrService'

const LOCAL_VISUAL_BACKEND_ID: string = 'harmony-local-comic-visual'
const LOCAL_VISUAL_PROFILE_ID: string = 'core-vision-ocr-basic-render-v1'
const LOCAL_VISUAL_PROTOCOL_REVISION: number = 1
const LOCAL_TEMPLATE_MIME: string = 'application/vnd.nexte.comic-local-template+json'
const LOCAL_RENDER_CACHE_DIR: string = 'comic-local-rendered-pages'
const LOCAL_OCR_TILE_EDGE: number = 2048
const LOCAL_OCR_TILE_OVERLAP: number = 128
const LOCAL_MAX_BLOCKS: number = 512
const LOCAL_MAX_SOURCE_TEXT_CHARS: number = 8192
const LOCAL_HASH_CHUNK_BYTES: number = 256 * 1024
const LOCAL_MAX_RENDERED_BYTES: number = 80 * 1024 * 1024
const LOCAL_MAX_RENDER_PIXELS: number = 16 * 1024 * 1024
const LOCAL_MIN_FONT_SIZE: number = 8
const LOCAL_MAX_FONT_SIZE: number = 42

class LocalOcrTile {
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
}

class LocalMappedLine {
  text: string = ''
  polygon: ComicPoint[] = []
  tileIndex: number = 0
}

class LocalTemplatePoint {
  x: number = 0
  y: number = 0
}

class LocalTemplateBlock {
  blockId: string = ''
  polygon: LocalTemplatePoint[] = []
}

class LocalTemplateEnvelope {
  schemaVersion: number = 1
  backendId: string = LOCAL_VISUAL_BACKEND_ID
  profileId: string = LOCAL_VISUAL_PROFILE_ID
  sourceImageHash: string = ''
  width: number = 0
  height: number = 0
  blocks: LocalTemplateBlock[] = []
}

class LocalRenderRect {
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0

  width(): number {
    return this.right - this.left
  }

  height(): number {
    return this.bottom - this.top
  }
}

class LocalTextLayout {
  fontSize: number = 0
  lines: string[] = []
}

/** First endpoint-free visual backend: system OCR geometry plus deterministic local source treatment and text drawing. */
export class ComicLocalVisualBackend implements ComicRegionRenderBackend {
  private readonly context: common.UIAbilityContext
  private readonly ocr: ComicLocalOcrEngine

  constructor(
    context: common.UIAbilityContext,
    ocr: ComicLocalOcrEngine = new HarmonyComicLocalOcrEngine(),
  ) {
    this.context = context
    this.ocr = ocr
  }

  backendId(): string {
    return LOCAL_VISUAL_BACKEND_ID
  }

  profileId(): string {
    return LOCAL_VISUAL_PROFILE_ID
  }

  protocolRevision(): number {
    return LOCAL_VISUAL_PROTOCOL_REVISION
  }

  async analyze(request: ComicRegionAnalysisRequest): Promise<ComicRegionAnalysisResult> {
    ComicVisualTranslationContract.validateRegionAnalysisRequest(request)
    let source: image.ImageSource | undefined = undefined
    try {
      source = image.createImageSource(request.source.imageFilePath)
      const info: image.ImageInfo = await source.getImageInfo()
      if (Math.floor(info.size.width) !== request.source.imageWidth ||
        Math.floor(info.size.height) !== request.source.imageHeight) {
        throw new Error('Local comic OCR source dimensions do not match the request')
      }
      const tiles: LocalOcrTile[] = ComicLocalVisualBackend.tiles(
        request.source.imageWidth,
        request.source.imageHeight,
      )
      const mapped: LocalMappedLine[] = []
      for (let tileIndex: number = 0; tileIndex < tiles.length; tileIndex++) {
        const tile: LocalOcrTile = tiles[tileIndex]
        let pixelMap: image.PixelMap | undefined = undefined
        try {
          pixelMap = await source.createPixelMap({
            editable: false,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
            desiredRegion: {
              x: tile.x,
              y: tile.y,
              size: { width: tile.width, height: tile.height },
            },
            cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          })
          const recognized: ComicLocalOcrResult = await this.ocr.recognize(pixelMap)
          ComicLocalVisualBackend.appendMappedLines(
            mapped,
            recognized.lines,
            tile,
            tileIndex,
            request.source.imageWidth,
            request.source.imageHeight,
          )
        } finally {
          if (pixelMap !== undefined) {
            await pixelMap.release()
          }
        }
      }
      const lines: LocalMappedLine[] = ComicLocalVisualBackend.deduplicate(mapped)
      const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
      result.backendId = this.backendId()
      result.profileId = this.profileId()
      result.regionRevision = request.requestedRegionRevision
      result.document = ComicLocalVisualBackend.document(request, lines, tiles.length)
      result.adapterTemplate = ComicLocalVisualBackend.template(request, result.document)
      ComicVisualTranslationContract.validateRegionAnalysisResult(
        request,
        result.backendId,
        result.profileId,
        result.regionRevision,
        result.document,
        result.adapterTemplate,
      )
      return result
    } finally {
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  async render(request: ComicRegionRenderRequest): Promise<ComicRenderedPage> {
    ComicVisualTranslationContract.validateStagedRenderRequest(request)
    ComicLocalVisualBackend.validateTemplate(request)
    if (request.source.imageWidth * request.source.imageHeight > LOCAL_MAX_RENDER_PIXELS) {
      throw new Error('Local comic rendered page exceeds the on-device pixel boundary')
    }
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let outputFile: fileIo.File | null = null
    const identityHash: string = ComicLocalVisualBackend.sha256Text(request.identity.cacheKey())
    const dir: string = `${this.context.cacheDir}/${LOCAL_RENDER_CACHE_DIR}`
    ComicLocalVisualBackend.ensureDir(dir)
    const path: string = `${dir}/${identityHash}.png`
    const partial: string = `${path}.part-${util.generateRandomUUID(true)}`
    try {
      source = image.createImageSource(request.source.imageFilePath)
      pixelMap = await source.createPixelMap({
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const canvas: drawing.Canvas = new drawing.Canvas(pixelMap)
      const translations: Map<string, string> = new Map<string, string>()
      for (let index: number = 0; index < request.translations.blocks.length; index++) {
        translations.set(
          request.translations.blocks[index].blockId,
          request.translations.blocks[index].translatedText,
        )
      }
      for (let index: number = 0; index < request.document.blocks.length; index++) {
        const block: ComicTextBlock = request.document.blocks[index]
        const translated: string | undefined = translations.get(block.blockId)
        if (translated === undefined || translated.trim().length <= 0) {
          throw new Error('Local comic renderer is missing a translated block')
        }
        ComicLocalVisualBackend.drawBlock(
          canvas,
          block,
          translated.trim(),
          request.source.imageWidth,
          request.source.imageHeight,
        )
      }
      packer = image.createImagePacker()
      outputFile = fileIo.openSync(
        partial,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      await packer.packToFile(pixelMap, outputFile.fd, { format: 'image/png', quality: 100 })
      fileIo.closeSync(outputFile)
      outputFile = null
      const stat: fileIo.Stat = fileIo.statSync(partial)
      if (!stat.isFile() || stat.size <= 0 || stat.size > LOCAL_MAX_RENDERED_BYTES) {
        throw new Error('Local comic rendered page size is invalid')
      }
      ComicLocalVisualBackend.removeFile(path)
      fileIo.renameSync(partial, path)
      const now: number = Date.now()
      const page: ComicRenderedPage = new ComicRenderedPage()
      page.identity = request.identity.copy()
      page.artifactHash = ComicLocalVisualBackend.sha256File(path)
      page.mimeType = 'image/png'
      page.width = request.source.imageWidth
      page.height = request.source.imageHeight
      page.byteLength = Math.floor(stat.size)
      page.localFilePath = path
      page.createdAt = now
      page.lastAccessAt = now
      ComicVisualTranslationContract.validateRenderedPage(request.identity, page)
      return page
    } catch (error) {
      ComicLocalVisualBackend.removeFile(partial)
      throw error as Error
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
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  private static tiles(width: number, height: number): LocalOcrTile[] {
    const values: LocalOcrTile[] = []
    const step: number = LOCAL_OCR_TILE_EDGE - LOCAL_OCR_TILE_OVERLAP
    for (let y: number = 0; y < height; y += step) {
      const tileHeight: number = Math.min(LOCAL_OCR_TILE_EDGE, height - y)
      for (let x: number = 0; x < width; x += step) {
        const tile: LocalOcrTile = new LocalOcrTile()
        tile.x = x
        tile.y = y
        tile.width = Math.min(LOCAL_OCR_TILE_EDGE, width - x)
        tile.height = tileHeight
        values.push(tile)
        if (x + tile.width >= width) {
          break
        }
      }
      if (y + tileHeight >= height) {
        break
      }
    }
    return values
  }

  private static appendMappedLines(
    output: LocalMappedLine[],
    lines: ComicLocalOcrLine[],
    tile: LocalOcrTile,
    tileIndex: number,
    sourceWidth: number,
    sourceHeight: number,
  ): void {
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      if (output.length >= LOCAL_MAX_BLOCKS * 2) {
        throw new Error('Local comic OCR candidate count exceeds its boundary')
      }
      const source: ComicLocalOcrLine = lines[lineIndex]
      const text: string = source.text.trim()
      // A single glyph from system OCR is usually a furigana/SFX fragment or a false positive.
      // Until the manga detector can classify these regions, leaving the artwork untouched is
      // safer than covering a large area with a low-confidence translation.
      if (text.length < 2 || text.length > LOCAL_MAX_SOURCE_TEXT_CHARS ||
        source.polygon.length < 3 || source.polygon.length > 64) {
        continue
      }
      const mapped: LocalMappedLine = new LocalMappedLine()
      mapped.text = text
      mapped.tileIndex = tileIndex
      for (let pointIndex: number = 0; pointIndex < source.polygon.length; pointIndex++) {
        const point: ComicLocalOcrPoint = source.polygon[pointIndex]
        const x: number = Math.max(0, Math.min(sourceWidth, point.x + tile.x))
        const y: number = Math.max(0, Math.min(sourceHeight, point.y + tile.y))
        mapped.polygon.push(new ComicPoint(x, y))
      }
      output.push(mapped)
    }
  }

  private static deduplicate(values: LocalMappedLine[]): LocalMappedLine[] {
    const output: LocalMappedLine[] = []
    for (let index: number = 0; index < values.length; index++) {
      const candidate: LocalMappedLine = values[index]
      let duplicate: boolean = false
      for (let acceptedIndex: number = 0; acceptedIndex < output.length; acceptedIndex++) {
        if (ComicLocalVisualBackend.sameLine(candidate, output[acceptedIndex])) {
          duplicate = true
          break
        }
      }
      if (!duplicate) {
        output.push(candidate)
      }
      if (output.length > LOCAL_MAX_BLOCKS) {
        throw new Error('Local comic OCR block count exceeds its boundary')
      }
    }
    output.sort((left: LocalMappedLine, right: LocalMappedLine): number => {
      const leftRect: LocalRenderRect = ComicLocalVisualBackend.bounds(left.polygon)
      const rightRect: LocalRenderRect = ComicLocalVisualBackend.bounds(right.polygon)
      const verticalDelta: number = leftRect.top - rightRect.top
      if (Math.abs(verticalDelta) > 12) {
        return verticalDelta
      }
      return rightRect.right - leftRect.right
    })
    return output
  }

  private static sameLine(left: LocalMappedLine, right: LocalMappedLine): boolean {
    if (left.text.replace(/\s+/g, '') !== right.text.replace(/\s+/g, '')) {
      return false
    }
    const leftRect: LocalRenderRect = ComicLocalVisualBackend.bounds(left.polygon)
    const rightRect: LocalRenderRect = ComicLocalVisualBackend.bounds(right.polygon)
    const leftCenterX: number = (leftRect.left + leftRect.right) / 2
    const leftCenterY: number = (leftRect.top + leftRect.bottom) / 2
    const rightCenterX: number = (rightRect.left + rightRect.right) / 2
    const rightCenterY: number = (rightRect.top + rightRect.bottom) / 2
    return Math.abs(leftCenterX - rightCenterX) <= LOCAL_OCR_TILE_OVERLAP &&
      Math.abs(leftCenterY - rightCenterY) <= LOCAL_OCR_TILE_OVERLAP
  }

  private static document(
    request: ComicRegionAnalysisRequest,
    lines: LocalMappedLine[],
    tileCount: number,
  ): ComicPageDocument {
    const document: ComicPageDocument = new ComicPageDocument()
    document.projectId = request.source.projectId
    document.pageIndex = request.source.pageIndex
    document.imageHash = request.source.imageHash
    document.imageWidth = request.source.imageWidth
    document.imageHeight = request.source.imageHeight
    document.imagePreparationProfile.profileId = LOCAL_VISUAL_PROFILE_ID
    document.imagePreparationProfile.mimeType = 'image/rgba8888'
    document.imagePreparationProfile.preparedWidth = request.source.imageWidth
    document.imagePreparationProfile.preparedHeight = request.source.imageHeight
    document.imagePreparationProfile.tileCount = tileCount
    document.analysisRevision = request.requestedDocumentRevision
    document.translationRevision = 0
    document.renderRevision = 0
    document.analysisState = ComicAnalysisState.READY
    document.translationState = ComicTranslationState.MISSING
    document.renderState = ComicRenderState.UNAVAILABLE
    document.hasText = lines.length > 0
    for (let index: number = 0; index < lines.length; index++) {
      const block: ComicTextBlock = new ComicTextBlock()
      block.blockId = `p${request.source.pageIndex}-local-${index + 1}`
      block.readingOrder = index
      block.kind = ComicTextKind.OTHER
      block.sourceText = lines[index].text
      block.normalizedSourceText = lines[index].text.replace(/\s+/g, ' ').trim()
      block.polygon = lines[index].polygon
      block.sourceOrigin = ComicSourceOrigin.OCR
      block.sourceRevision = request.requestedDocumentRevision
      document.blocks.push(block)
    }
    const signal: ComicQualitySignal = new ComicQualitySignal()
    signal.code = 'local_system_ocr_requires_visual_review'
    signal.severity = ComicQualitySeverity.INFO
    signal.message = 'System OCR can miss stylized text; the translation model should verify the page image.'
    document.qualitySignals.push(signal)
    return document
  }

  private static template(
    request: ComicRegionAnalysisRequest,
    document: ComicPageDocument,
  ): ComicBackendTemplate {
    const envelope: LocalTemplateEnvelope = new LocalTemplateEnvelope()
    envelope.sourceImageHash = request.source.imageHash
    envelope.width = request.source.imageWidth
    envelope.height = request.source.imageHeight
    for (let index: number = 0; index < document.blocks.length; index++) {
      const source: ComicTextBlock = document.blocks[index]
      const block: LocalTemplateBlock = new LocalTemplateBlock()
      block.blockId = source.blockId
      for (let pointIndex: number = 0; pointIndex < source.polygon.length; pointIndex++) {
        const point: LocalTemplatePoint = new LocalTemplatePoint()
        point.x = source.polygon[pointIndex].x
        point.y = source.polygon[pointIndex].y
        block.polygon.push(point)
      }
      envelope.blocks.push(block)
    }
    const payload: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(envelope))
    const template: ComicBackendTemplate = new ComicBackendTemplate()
    template.backendId = LOCAL_VISUAL_BACKEND_ID
    template.profileId = LOCAL_VISUAL_PROFILE_ID
    template.protocolRevision = LOCAL_VISUAL_PROTOCOL_REVISION
    template.contentHash = ComicLocalVisualBackend.sha256(payload)
    template.mimeType = LOCAL_TEMPLATE_MIME
    template.payload = payload
    return template
  }

  private static validateTemplate(request: ComicRegionRenderRequest): void {
    if (request.adapterTemplate.backendId !== LOCAL_VISUAL_BACKEND_ID ||
      request.adapterTemplate.profileId !== LOCAL_VISUAL_PROFILE_ID ||
      request.adapterTemplate.protocolRevision !== LOCAL_VISUAL_PROTOCOL_REVISION ||
      request.adapterTemplate.mimeType !== LOCAL_TEMPLATE_MIME ||
      request.adapterTemplate.contentHash !==
        ComicLocalVisualBackend.sha256(request.adapterTemplate.payload)) {
      throw new Error('Local comic render template identity is invalid')
    }
    let envelope: LocalTemplateEnvelope
    try {
      envelope = JSON.parse(
        new util.TextDecoder().decodeToString(request.adapterTemplate.payload),
      ) as LocalTemplateEnvelope
    } catch (_error) {
      throw new Error('Local comic render template is invalid JSON')
    }
    if (envelope.schemaVersion !== 1 || envelope.backendId !== LOCAL_VISUAL_BACKEND_ID ||
      envelope.profileId !== LOCAL_VISUAL_PROFILE_ID ||
      envelope.sourceImageHash !== request.source.imageHash ||
      envelope.width !== request.source.imageWidth ||
      envelope.height !== request.source.imageHeight ||
      envelope.blocks.length !== request.document.blocks.length) {
      throw new Error('Local comic render template does not match the request')
    }
    for (let index: number = 0; index < envelope.blocks.length; index++) {
      if (envelope.blocks[index].blockId !== request.document.blocks[index].blockId) {
        throw new Error('Local comic render template block order is invalid')
      }
    }
  }

  private static drawBlock(
    canvas: drawing.Canvas,
    block: ComicTextBlock,
    translatedText: string,
    imageWidth: number,
    imageHeight: number,
  ): void {
    const raw: LocalRenderRect = ComicLocalVisualBackend.bounds(block.polygon)
    const rect: LocalRenderRect = ComicLocalVisualBackend.expandedRect(
      raw,
      translatedText,
      imageWidth,
      imageHeight,
    )
    const background: drawing.Brush = new drawing.Brush()
    background.setColor(255, 250, 250, 248)
    canvas.attachBrush(background)
    const radius: number = Math.max(4, Math.min(18, Math.min(rect.width(), rect.height()) * 0.18))
    canvas.drawRoundRect(new drawing.RoundRect({
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
    }, radius, radius))
    canvas.detachBrush()

    const horizontalPadding: number = Math.max(4, Math.min(12, rect.width() * 0.08))
    const verticalPadding: number = Math.max(4, Math.min(10, rect.height() * 0.08))
    const contentWidth: number = Math.max(1, rect.width() - horizontalPadding * 2)
    const contentHeight: number = Math.max(1, rect.height() - verticalPadding * 2)
    const font: drawing.Font = new drawing.Font()
    font.enableSubpixel(true)
    const layout: LocalTextLayout = ComicLocalVisualBackend.layout(
      translatedText,
      contentWidth,
      contentHeight,
      font,
    )
    font.setSize(layout.fontSize)
    const textBrush: drawing.Brush = new drawing.Brush()
    textBrush.setColor(255, 24, 24, 24)
    canvas.attachBrush(textBrush)
    const lineHeight: number = layout.fontSize * 1.18
    const totalHeight: number = layout.lines.length * lineHeight
    const metrics: drawing.FontMetrics = font.getMetrics()
    let baseline: number = rect.top + verticalPadding +
      Math.max(0, (contentHeight - totalHeight) / 2) - metrics.ascent
    for (let index: number = 0; index < layout.lines.length; index++) {
      const line: string = layout.lines[index]
      const width: number = font.measureText(line, drawing.TextEncoding.TEXT_ENCODING_UTF8)
      const x: number = rect.left + horizontalPadding + Math.max(0, (contentWidth - width) / 2)
      canvas.drawTextBlob(drawing.TextBlob.makeFromString(line, font), x, baseline)
      baseline += lineHeight
    }
    canvas.detachBrush()
  }

  private static expandedRect(
    raw: LocalRenderRect,
    text: string,
    imageWidth: number,
    imageHeight: number,
  ): LocalRenderRect {
    const rawWidth: number = Math.max(1, raw.width())
    const rawHeight: number = Math.max(1, raw.height())
    let width: number = rawWidth + Math.max(8, Math.min(24, rawWidth * 0.24)) * 2
    let height: number = rawHeight + Math.max(8, Math.min(24, rawHeight * 0.18)) * 2
    if (rawHeight > rawWidth * 1.35) {
      width = Math.max(width, Math.min(imageWidth * 0.38, 36 + Math.sqrt(text.length) * 28))
    } else {
      height = Math.max(height, Math.min(imageHeight * 0.16, 36 + Math.sqrt(text.length) * 18))
    }
    width = Math.min(imageWidth, Math.max(44, width))
    height = Math.min(imageHeight, Math.max(38, height))
    const centerX: number = (raw.left + raw.right) / 2
    const centerY: number = (raw.top + raw.bottom) / 2
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = Math.max(0, Math.min(imageWidth - width, centerX - width / 2))
    rect.top = Math.max(0, Math.min(imageHeight - height, centerY - height / 2))
    rect.right = rect.left + width
    rect.bottom = rect.top + height
    return rect
  }

  private static layout(
    text: string,
    width: number,
    height: number,
    font: drawing.Font,
  ): LocalTextLayout {
    const initialSize: number = Math.max(
      LOCAL_MIN_FONT_SIZE,
      Math.min(LOCAL_MAX_FONT_SIZE, Math.floor(height * 0.62)),
    )
    for (let size: number = initialSize; size >= LOCAL_MIN_FONT_SIZE; size--) {
      font.setSize(size)
      const lines: string[] = ComicLocalVisualBackend.wrap(text, width, font)
      if (lines.length * size * 1.18 <= height) {
        const result: LocalTextLayout = new LocalTextLayout()
        result.fontSize = size
        result.lines = lines
        return result
      }
    }
    throw new Error('Local comic translation does not fit its detected region')
  }

  private static wrap(text: string, width: number, font: drawing.Font): string[] {
    const lines: string[] = []
    let current: string = ''
    for (let index: number = 0; index < text.length; index++) {
      const character: string = text.charAt(index)
      if (character === '\n') {
        if (current.length > 0) {
          lines.push(current)
          current = ''
        }
        continue
      }
      const candidate: string = current + character
      const measured: number = font.measureText(candidate, drawing.TextEncoding.TEXT_ENCODING_UTF8)
      if (current.length > 0 && measured > width) {
        lines.push(current)
        current = character
      } else {
        current = candidate
      }
    }
    if (current.length > 0) {
      lines.push(current)
    }
    if (lines.length === 0) {
      lines.push(text)
    }
    return lines
  }

  private static bounds(points: ComicPoint[]): LocalRenderRect {
    const rect: LocalRenderRect = new LocalRenderRect()
    rect.left = Number.POSITIVE_INFINITY
    rect.top = Number.POSITIVE_INFINITY
    rect.right = Number.NEGATIVE_INFINITY
    rect.bottom = Number.NEGATIVE_INFINITY
    for (let index: number = 0; index < points.length; index++) {
      rect.left = Math.min(rect.left, points[index].x)
      rect.top = Math.min(rect.top, points[index].y)
      rect.right = Math.max(rect.right, points[index].x)
      rect.bottom = Math.max(rect.bottom, points[index].y)
    }
    if (!Number.isFinite(rect.left) || !Number.isFinite(rect.top) ||
      !Number.isFinite(rect.right) || !Number.isFinite(rect.bottom) ||
      rect.right <= rect.left || rect.bottom <= rect.top) {
      throw new Error('Local comic OCR polygon has invalid bounds')
    }
    return rect
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

  private static removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  private static sha256Text(value: string): string {
    return ComicLocalVisualBackend.sha256(new util.TextEncoder().encodeInto(value))
  }

  private static sha256(bytes: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: bytes })
    return ComicLocalVisualBackend.toHex(md.digestSync().data)
  }

  private static sha256File(path: string): string {
    const md = cryptoFramework.createMd('SHA256')
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(LOCAL_HASH_CHUNK_BYTES)
        const read: number = fileIo.readSync(file.fd, buffer, { length: buffer.byteLength })
        if (read <= 0) {
          break
        }
        md.updateSync({ data: new Uint8Array(buffer, 0, read) })
      }
      return ComicLocalVisualBackend.toHex(md.digestSync().data)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}
