import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { ComicPageDocument } from '../model/ComicTranslation'
import {
  ComicBackendTemplate,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicTranslationBatch,
} from '../model/ComicVisualTranslation'
import { ComicVisualPageSource } from './ComicVisualTranslationBackend'

const COMIC_LOCAL_VISUAL_RECORDING_SCHEMA_VERSION: number = 1
const COMIC_LOCAL_VISUAL_RECORDING_DIR: string = 'comic-local-visual-recordings'
const COMIC_LOCAL_VISUAL_RECORDING_MAX_TEXT_BYTES: number = 8 * 1024 * 1024

export class ComicLocalVisualAnalysisTimings {
  detectorMs: number = 0
  systemOcrMs: number = 0
  proposalMaskMs: number = 0
  supplementalOcrMs: number = 0
  layoutMs: number = 0
  totalMs: number = 0
  tileCount: number = 0
  blockCount: number = 0

  copy(): ComicLocalVisualAnalysisTimings {
    const value: ComicLocalVisualAnalysisTimings = new ComicLocalVisualAnalysisTimings()
    value.detectorMs = this.detectorMs
    value.systemOcrMs = this.systemOcrMs
    value.proposalMaskMs = this.proposalMaskMs
    value.supplementalOcrMs = this.supplementalOcrMs
    value.layoutMs = this.layoutMs
    value.totalMs = this.totalMs
    value.tileCount = this.tileCount
    value.blockCount = this.blockCount
    return value
  }
}

export class ComicLocalVisualRenderTimings {
  decodeMs: number = 0
  maskMs: number = 0
  layoutMs: number = 0
  inpaintMs: number = 0
  drawMs: number = 0
  encodeMs: number = 0
  finalizeMs: number = 0
  totalMs: number = 0
  inpaintCallCount: number = 0
  inpaintNativeCallMs: number = 0
  inpaintModelLoadMs: number = 0
  inpaintPreprocessingMs: number = 0
  inpaintInferenceMs: number = 0
  inpaintPostprocessingMs: number = 0
  drawableGroupCount: number = 0
  skippedGroupCount: number = 0
  horizontalFontCap: number = 0
  layoutProfileId: string = ''

  copy(): ComicLocalVisualRenderTimings {
    const value: ComicLocalVisualRenderTimings = new ComicLocalVisualRenderTimings()
    value.decodeMs = this.decodeMs
    value.maskMs = this.maskMs
    value.layoutMs = this.layoutMs
    value.inpaintMs = this.inpaintMs
    value.drawMs = this.drawMs
    value.encodeMs = this.encodeMs
    value.finalizeMs = this.finalizeMs
    value.totalMs = this.totalMs
    value.inpaintCallCount = this.inpaintCallCount
    value.inpaintNativeCallMs = this.inpaintNativeCallMs
    value.inpaintModelLoadMs = this.inpaintModelLoadMs
    value.inpaintPreprocessingMs = this.inpaintPreprocessingMs
    value.inpaintInferenceMs = this.inpaintInferenceMs
    value.inpaintPostprocessingMs = this.inpaintPostprocessingMs
    value.drawableGroupCount = this.drawableGroupCount
    value.skippedGroupCount = this.skippedGroupCount
    value.horizontalFontCap = this.horizontalFontCap
    value.layoutProfileId = this.layoutProfileId
    return value
  }
}

export class ComicLocalVisualRecordedRect {
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0
  shapeConstrained: boolean = false
  containerConfidence: number = 0
  containerRawCoverage: number = 0
  containerSolidity: number = 0
  containerAreaRatio: number = 0
  containerLuminanceStd: number = 0
  containerProbeOutcome: string = ''
  rectBorderLeftScore: number = 0
  rectBorderRightScore: number = 0
  rectBorderTopScore: number = 0
  rectBorderBottomScore: number = 0
  rectBorderTopLeftCornerScore: number = 0
  rectBorderTopRightCornerScore: number = 0
  rectBorderBottomLeftCornerScore: number = 0
  rectBorderBottomRightCornerScore: number = 0
  rectBorderProbeOutcome: string = ''

  copy(): ComicLocalVisualRecordedRect {
    const value: ComicLocalVisualRecordedRect = new ComicLocalVisualRecordedRect()
    value.left = this.left
    value.top = this.top
    value.right = this.right
    value.bottom = this.bottom
    value.shapeConstrained = this.shapeConstrained
    value.containerConfidence = this.containerConfidence
    value.containerRawCoverage = this.containerRawCoverage
    value.containerSolidity = this.containerSolidity
    value.containerAreaRatio = this.containerAreaRatio
    value.containerLuminanceStd = this.containerLuminanceStd
    value.containerProbeOutcome = this.containerProbeOutcome
    value.rectBorderLeftScore = this.rectBorderLeftScore
    value.rectBorderRightScore = this.rectBorderRightScore
    value.rectBorderTopScore = this.rectBorderTopScore
    value.rectBorderBottomScore = this.rectBorderBottomScore
    value.rectBorderTopLeftCornerScore = this.rectBorderTopLeftCornerScore
    value.rectBorderTopRightCornerScore = this.rectBorderTopRightCornerScore
    value.rectBorderBottomLeftCornerScore = this.rectBorderBottomLeftCornerScore
    value.rectBorderBottomRightCornerScore = this.rectBorderBottomRightCornerScore
    value.rectBorderProbeOutcome = this.rectBorderProbeOutcome
    return value
  }
}

export class ComicLocalVisualRecordedColor {
  red: number = 0
  green: number = 0
  blue: number = 0

  copy(): ComicLocalVisualRecordedColor {
    const value: ComicLocalVisualRecordedColor = new ComicLocalVisualRecordedColor()
    value.red = this.red
    value.green = this.green
    value.blue = this.blue
    return value
  }
}

export class ComicLocalVisualRecordedSourceBlock {
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0
  styleHint: string = ''
  sourceText: string = ''
  textLength: number = 0
  tileIndex: number = 0
  detectorRegionIndexes: number[] = []
  sourceGroupIndexes: number[] = []
  detectorLabels: string[] = []
  preserveSource: boolean = false
  lineWidthScale: number = 0
  lineHeightScale: number = 0

  copy(): ComicLocalVisualRecordedSourceBlock {
    const value: ComicLocalVisualRecordedSourceBlock =
      new ComicLocalVisualRecordedSourceBlock()
    value.left = this.left
    value.top = this.top
    value.right = this.right
    value.bottom = this.bottom
    value.styleHint = this.styleHint
    value.sourceText = this.sourceText
    value.textLength = this.textLength
    value.tileIndex = this.tileIndex
    value.detectorRegionIndexes = this.detectorRegionIndexes.slice()
    value.sourceGroupIndexes = this.sourceGroupIndexes.slice()
    value.detectorLabels = this.detectorLabels.slice()
    value.preserveSource = this.preserveSource
    value.lineWidthScale = this.lineWidthScale
    value.lineHeightScale = this.lineHeightScale
    return value
  }
}

export class ComicLocalVisualGroupingStages {
  grouped: ComicLocalVisualRecordedSourceBlock[] = []
  verticalMerged: ComicLocalVisualRecordedSourceBlock[] = []
  horizontalMerged: ComicLocalVisualRecordedSourceBlock[] = []
  output: ComicLocalVisualRecordedSourceBlock[] = []

  copy(): ComicLocalVisualGroupingStages {
    const value: ComicLocalVisualGroupingStages = new ComicLocalVisualGroupingStages()
    for (let index: number = 0; index < this.grouped.length; index++) {
      value.grouped.push(this.grouped[index].copy())
    }
    for (let index: number = 0; index < this.verticalMerged.length; index++) {
      value.verticalMerged.push(this.verticalMerged[index].copy())
    }
    for (let index: number = 0; index < this.horizontalMerged.length; index++) {
      value.horizontalMerged.push(this.horizontalMerged[index].copy())
    }
    for (let index: number = 0; index < this.output.length; index++) {
      value.output.push(this.output[index].copy())
    }
    return value
  }
}

export class ComicLocalVisualRecordedLayout {
  blockIds: string[] = []
  sourceRects: ComicLocalVisualRecordedRect[] = []
  treatmentRects: ComicLocalVisualRecordedRect[] = []
  textRect: ComicLocalVisualRecordedRect = new ComicLocalVisualRecordedRect()
  writingMode: string = ''
  fontSize: number = 0
  outlineWidth: number = 0
  rotationDegrees: number = 0
  translatedTextLength: number = 0
  containerLabel: number = 0
  fillColor: ComicLocalVisualRecordedColor = new ComicLocalVisualRecordedColor()
  textColor: ComicLocalVisualRecordedColor = new ComicLocalVisualRecordedColor()

  copy(): ComicLocalVisualRecordedLayout {
    const value: ComicLocalVisualRecordedLayout = new ComicLocalVisualRecordedLayout()
    for (let index: number = 0; index < this.blockIds.length; index++) {
      value.blockIds.push(this.blockIds[index])
    }
    for (let index: number = 0; index < this.sourceRects.length; index++) {
      value.sourceRects.push(this.sourceRects[index].copy())
    }
    for (let index: number = 0; index < this.treatmentRects.length; index++) {
      value.treatmentRects.push(this.treatmentRects[index].copy())
    }
    value.textRect = this.textRect.copy()
    value.writingMode = this.writingMode
    value.fontSize = this.fontSize
    value.outlineWidth = this.outlineWidth
    value.rotationDegrees = this.rotationDegrees
    value.translatedTextLength = this.translatedTextLength
    value.containerLabel = this.containerLabel
    value.fillColor = this.fillColor.copy()
    value.textColor = this.textColor.copy()
    return value
  }
}

export class ComicLocalVisualAnalysisRecording {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  backendId: string = ''
  profileId: string = ''
  regionRevision: number = 0
  document: ComicPageDocument = new ComicPageDocument()
  adapterTemplate: ComicBackendTemplate = new ComicBackendTemplate()
  timings: ComicLocalVisualAnalysisTimings = new ComicLocalVisualAnalysisTimings()
  groupingStages: ComicLocalVisualGroupingStages = new ComicLocalVisualGroupingStages()

  copy(): ComicLocalVisualAnalysisRecording {
    const value: ComicLocalVisualAnalysisRecording = new ComicLocalVisualAnalysisRecording()
    value.source = this.source.copy()
    value.backendId = this.backendId
    value.profileId = this.profileId
    value.regionRevision = this.regionRevision
    value.document = this.document.copy()
    value.adapterTemplate = this.adapterTemplate.copy()
    value.timings = this.timings.copy()
    value.groupingStages = this.groupingStages.copy()
    return value
  }
}

export class ComicLocalVisualRenderRecording {
  source: ComicVisualPageSource = new ComicVisualPageSource()
  document: ComicPageDocument = new ComicPageDocument()
  translations: ComicTranslationBatch = new ComicTranslationBatch()
  identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  renderedPage: ComicRenderedPage = new ComicRenderedPage()
  textMask: Uint8Array | null = null
  containerMask: Uint8Array | null = null
  containerLabels: Uint8Array | null = null
  layouts: ComicLocalVisualRecordedLayout[] = []
  timings: ComicLocalVisualRenderTimings = new ComicLocalVisualRenderTimings()

  copy(): ComicLocalVisualRenderRecording {
    const value: ComicLocalVisualRenderRecording = new ComicLocalVisualRenderRecording()
    value.source = this.source.copy()
    value.document = this.document.copy()
    value.translations = this.translations.copy()
    value.identity = this.identity.copy()
    value.renderedPage = this.renderedPage.copy()
    value.textMask = this.textMask === null ? null : new Uint8Array(this.textMask)
    value.containerMask =
      this.containerMask === null ? null : new Uint8Array(this.containerMask)
    value.containerLabels =
      this.containerLabels === null ? null : new Uint8Array(this.containerLabels)
    for (let index: number = 0; index < this.layouts.length; index++) {
      value.layouts.push(this.layouts[index].copy())
    }
    value.timings = this.timings.copy()
    return value
  }
}

export interface ComicLocalVisualRecordingSink {
  recordAnalysis(recording: ComicLocalVisualAnalysisRecording): void

  recordRender(recording: ComicLocalVisualRenderRecording): void
}

class ComicLocalVisualRecordedSource {
  projectId: string = ''
  pageIndex: number = -1
  imageHash: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
  fileName: string = ''
}

class ComicLocalVisualRecordedTemplate {
  backendId: string = ''
  profileId: string = ''
  protocolRevision: number = 0
  contentHash: string = ''
  mimeType: string = ''
  fileName: string = ''
  byteLength: number = 0
}

class ComicLocalVisualRecordedPage {
  identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  artifactHash: string = ''
  mimeType: string = ''
  width: number = 0
  height: number = 0
  byteLength: number = 0
  fileName: string = ''
}

class ComicLocalVisualAnalysisFile {
  schemaVersion: number = COMIC_LOCAL_VISUAL_RECORDING_SCHEMA_VERSION
  source: ComicLocalVisualRecordedSource = new ComicLocalVisualRecordedSource()
  backendId: string = ''
  profileId: string = ''
  regionRevision: number = 0
  document: ComicPageDocument = new ComicPageDocument()
  adapterTemplate: ComicLocalVisualRecordedTemplate = new ComicLocalVisualRecordedTemplate()
  timings: ComicLocalVisualAnalysisTimings = new ComicLocalVisualAnalysisTimings()
  groupingStages: ComicLocalVisualGroupingStages = new ComicLocalVisualGroupingStages()
}

class ComicLocalVisualRenderFile {
  schemaVersion: number = COMIC_LOCAL_VISUAL_RECORDING_SCHEMA_VERSION
  source: ComicLocalVisualRecordedSource = new ComicLocalVisualRecordedSource()
  document: ComicPageDocument = new ComicPageDocument()
  translations: ComicTranslationBatch = new ComicTranslationBatch()
  identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  renderedPage: ComicLocalVisualRecordedPage = new ComicLocalVisualRecordedPage()
  textMaskFile: string = ''
  textMaskWidth: number = 0
  textMaskHeight: number = 0
  containerMaskFile: string = ''
  containerMaskWidth: number = 0
  containerMaskHeight: number = 0
  containerLabelsFile: string = ''
  containerLabelsWidth: number = 0
  containerLabelsHeight: number = 0
  layouts: ComicLocalVisualRecordedLayout[] = []
  timings: ComicLocalVisualRenderTimings = new ComicLocalVisualRenderTimings()
}

class ComicLocalVisualRecordingManifest {
  schemaVersion: number = COMIC_LOCAL_VISUAL_RECORDING_SCHEMA_VERSION
  recordingId: string = ''
  pageIndex: number = -1
  sourceImage: string = ''
  analysis: string = ''
  adapterTemplate: string = ''
  render: string = ''
  renderedImage: string = ''
  textMask: string = ''
  containerMask: string = ''
  containerLabels: string = ''
}

/**
 * Explicit, developer-facing recording sink. It writes only when a caller constructs and injects it.
 * All artifacts remain in the app cache and are never uploaded by this class.
 */
export class ComicLocalVisualFileRecorder implements ComicLocalVisualRecordingSink {
  private readonly recordingId: string
  private readonly rootDir: string
  private readonly pageRuns: Map<number, number> = new Map<number, number>()
  private readonly activePageDirs: Map<number, string> = new Map<number, string>()

  constructor(context: common.UIAbilityContext, recordingId: string) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(recordingId)) {
      throw new Error('Comic local visual recording id is invalid')
    }
    this.recordingId = recordingId
    const parent: string = `${context.cacheDir}/${COMIC_LOCAL_VISUAL_RECORDING_DIR}`
    ComicLocalVisualFileRecorder.ensureDir(parent)
    this.rootDir = `${parent}/${recordingId}`
    if (fileIo.accessSync(this.rootDir)) {
      throw new Error('Comic local visual recording already exists')
    }
    ComicLocalVisualFileRecorder.ensureDir(this.rootDir)
  }

  recordingDirectory(): string {
    return this.rootDir
  }

  recordAnalysis(recording: ComicLocalVisualAnalysisRecording): void {
    const pageDir: string = this.beginPageDir(recording.source.pageIndex)
    ComicLocalVisualFileRecorder.ensureDir(pageDir)
    const sourceFile: string = this.copySource(recording.source, pageDir)
    const templateFile: string = 'adapter-template.bin'
    ComicLocalVisualFileRecorder.writeBytes(
      `${pageDir}/${templateFile}`,
      recording.adapterTemplate.payload,
    )
    const file: ComicLocalVisualAnalysisFile = new ComicLocalVisualAnalysisFile()
    file.source = ComicLocalVisualFileRecorder.recordedSource(recording.source, sourceFile)
    file.backendId = recording.backendId
    file.profileId = recording.profileId
    file.regionRevision = recording.regionRevision
    file.document = recording.document.copy()
    file.adapterTemplate.backendId = recording.adapterTemplate.backendId
    file.adapterTemplate.profileId = recording.adapterTemplate.profileId
    file.adapterTemplate.protocolRevision = recording.adapterTemplate.protocolRevision
    file.adapterTemplate.contentHash = recording.adapterTemplate.contentHash
    file.adapterTemplate.mimeType = recording.adapterTemplate.mimeType
    file.adapterTemplate.fileName = templateFile
    file.adapterTemplate.byteLength = recording.adapterTemplate.payload.byteLength
    file.timings = recording.timings.copy()
    file.groupingStages = recording.groupingStages.copy()
    ComicLocalVisualFileRecorder.writeJson(`${pageDir}/analysis.json`, file)
    this.writeManifest(pageDir, recording.source.pageIndex, sourceFile, false, false, false, false)
  }

  recordRender(recording: ComicLocalVisualRenderRecording): void {
    const pageDir: string = this.activePageDir(recording.source.pageIndex)
    ComicLocalVisualFileRecorder.ensureDir(pageDir)
    const sourceFile: string = this.copySource(recording.source, pageDir)
    const renderedFile: string = 'rendered.png'
    ComicLocalVisualFileRecorder.copyFile(recording.renderedPage.localFilePath,
      `${pageDir}/${renderedFile}`)
    let textMaskFile: string = ''
    if (recording.textMask !== null) {
      textMaskFile = 'glyph-mask.u8'
      ComicLocalVisualFileRecorder.writeBytes(`${pageDir}/${textMaskFile}`, recording.textMask)
    }
    let containerMaskFile: string = ''
    if (recording.containerMask !== null) {
      containerMaskFile = 'container-mask.u8'
      ComicLocalVisualFileRecorder.writeBytes(
        `${pageDir}/${containerMaskFile}`,
        recording.containerMask,
      )
    }
    let containerLabelsFile: string = ''
    if (recording.containerLabels !== null) {
      containerLabelsFile = 'container-labels.u8'
      ComicLocalVisualFileRecorder.writeBytes(
        `${pageDir}/${containerLabelsFile}`,
        recording.containerLabels,
      )
    }
    const file: ComicLocalVisualRenderFile = new ComicLocalVisualRenderFile()
    file.source = ComicLocalVisualFileRecorder.recordedSource(recording.source, sourceFile)
    file.document = recording.document.copy()
    file.translations = recording.translations.copy()
    file.identity = recording.identity.copy()
    file.renderedPage.identity = recording.renderedPage.identity.copy()
    file.renderedPage.artifactHash = recording.renderedPage.artifactHash
    file.renderedPage.mimeType = recording.renderedPage.mimeType
    file.renderedPage.width = recording.renderedPage.width
    file.renderedPage.height = recording.renderedPage.height
    file.renderedPage.byteLength = recording.renderedPage.byteLength
    file.renderedPage.fileName = renderedFile
    file.textMaskFile = textMaskFile
    file.textMaskWidth = textMaskFile.length > 0 ? recording.source.imageWidth : 0
    file.textMaskHeight = textMaskFile.length > 0 ? recording.source.imageHeight : 0
    file.containerMaskFile = containerMaskFile
    file.containerMaskWidth =
      containerMaskFile.length > 0 ? recording.source.imageWidth : 0
    file.containerMaskHeight =
      containerMaskFile.length > 0 ? recording.source.imageHeight : 0
    file.containerLabelsFile = containerLabelsFile
    file.containerLabelsWidth =
      containerLabelsFile.length > 0 ? recording.source.imageWidth : 0
    file.containerLabelsHeight =
      containerLabelsFile.length > 0 ? recording.source.imageHeight : 0
    for (let index: number = 0; index < recording.layouts.length; index++) {
      file.layouts.push(recording.layouts[index].copy())
    }
    file.timings = recording.timings.copy()
    ComicLocalVisualFileRecorder.writeJson(`${pageDir}/render.json`, file)
    this.writeManifest(
      pageDir,
      recording.source.pageIndex,
      sourceFile,
      true,
      textMaskFile.length > 0,
      containerMaskFile.length > 0,
      containerLabelsFile.length > 0,
    )
    this.activePageDirs.delete(recording.source.pageIndex)
  }

  private beginPageDir(pageIndex: number): string {
    ComicLocalVisualFileRecorder.validatePageIndex(pageIndex)
    const previous: number = this.pageRuns.get(pageIndex) ?? 0
    const run: number = previous + 1
    this.pageRuns.set(pageIndex, run)
    const pageDir: string =
      `${this.rootDir}/page-${pageIndex.toString().padStart(4, '0')}` +
        `-run-${run.toString().padStart(4, '0')}`
    this.activePageDirs.set(pageIndex, pageDir)
    return pageDir
  }

  private activePageDir(pageIndex: number): string {
    ComicLocalVisualFileRecorder.validatePageIndex(pageIndex)
    const pageDir: string | undefined = this.activePageDirs.get(pageIndex)
    if (pageDir === undefined) {
      throw new Error('Comic local visual render has no matching analysis recording')
    }
    return pageDir
  }

  private static validatePageIndex(pageIndex: number): void {
    if (!Number.isFinite(pageIndex) || pageIndex < 0 || Math.floor(pageIndex) !== pageIndex) {
      throw new Error('Comic local visual recording page index is invalid')
    }
  }

  private copySource(source: ComicVisualPageSource, pageDir: string): string {
    const fileName: string = `source${ComicLocalVisualFileRecorder.imageSuffix(
      source.imageFilePath,
    )}`
    const target: string = `${pageDir}/${fileName}`
    if (!fileIo.accessSync(target)) {
      ComicLocalVisualFileRecorder.copyFile(source.imageFilePath, target)
    }
    return fileName
  }

  private writeManifest(
    pageDir: string,
    pageIndex: number,
    sourceFile: string,
    hasRender: boolean,
    hasMask: boolean,
    hasContainerMask: boolean,
    hasContainerLabels: boolean,
  ): void {
    const value: ComicLocalVisualRecordingManifest = new ComicLocalVisualRecordingManifest()
    value.recordingId = this.recordingId
    value.pageIndex = pageIndex
    value.sourceImage = sourceFile
    value.analysis = 'analysis.json'
    value.adapterTemplate = 'adapter-template.bin'
    value.render = hasRender ? 'render.json' : ''
    value.renderedImage = hasRender ? 'rendered.png' : ''
    value.textMask = hasMask ? 'glyph-mask.u8' : ''
    value.containerMask = hasContainerMask ? 'container-mask.u8' : ''
    value.containerLabels = hasContainerLabels ? 'container-labels.u8' : ''
    ComicLocalVisualFileRecorder.writeJson(`${pageDir}/manifest.json`, value)
  }

  private static recordedSource(
    source: ComicVisualPageSource,
    fileName: string,
  ): ComicLocalVisualRecordedSource {
    const value: ComicLocalVisualRecordedSource = new ComicLocalVisualRecordedSource()
    value.projectId = source.projectId
    value.pageIndex = source.pageIndex
    value.imageHash = source.imageHash
    value.imageWidth = source.imageWidth
    value.imageHeight = source.imageHeight
    value.fileName = fileName
    return value
  }

  private static imageSuffix(path: string): string {
    const lower: string = path.toLowerCase()
    if (lower.endsWith('.png')) {
      return '.png'
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return '.jpg'
    }
    if (lower.endsWith('.webp')) {
      return '.webp'
    }
    return '.img'
  }

  private static writeJson(path: string, value: Object): void {
    const text: string = JSON.stringify(value)
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(text)
    if (bytes.byteLength <= 0 || bytes.byteLength > COMIC_LOCAL_VISUAL_RECORDING_MAX_TEXT_BYTES) {
      throw new Error('Comic local visual recording metadata size is invalid')
    }
    ComicLocalVisualFileRecorder.writeBytes(path, bytes)
  }

  private static writeBytes(path: string, bytes: Uint8Array): void {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      const buffer: ArrayBuffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength,
      )
      const written: number = fileIo.writeSync(file.fd, buffer, { length: buffer.byteLength })
      if (written !== buffer.byteLength) {
        throw new Error('Comic local visual recording write is incomplete')
      }
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static copyFile(sourcePath: string, targetPath: string): void {
    fileIo.copyFileSync(sourcePath, targetPath)
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
}
