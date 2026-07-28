import { application, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  COMIC_TEXT_TRANSLATION_INPUT_MULTIMODAL,
  COMIC_TEXT_TRANSLATION_INPUT_TEXT_ONLY,
  ComicBlockTranslation,
  ComicBackendTemplate,
  ComicLocalOcrLine,
  ComicLocalOcrResult,
  ComicLocalVisualBackend,
  ComicLocalVisualFileRecorder,
  ComicNcnnLocalRegionDetector,
  ComicNcnnLocalSourceInpainter,
  ComicNcnnLocalTextMasker,
  ComicNcnnLocalTextRecognizer,
  ComicPageDocument,
  ComicPoint,
  ComicRegionAnalysisRequest,
  ComicRegionAnalysisResult,
  ComicRegionRenderRequest,
  ComicRenderedPage,
  ComicRenderedPageIdentity,
  ComicRenderProfile,
  ComicSourceInpaintingModelPaths,
  ComicTextBlock,
  ComicTextTranslationRequest,
  ComicTranslationDebugProbeResult,
  ComicTranslationDebugProbeService,
  ComicTextMaskModelPaths,
  ComicTextRecognitionModelPaths,
  ComicTranslationBatch,
  ComicTranslationModelPaths,
  ComicTranslationModelService,
  ComicVisualPageSource,
  ComicVisualTranslationContract,
  ComicVisualTranslationRoute,
  HarmonyComicLocalOcrEngine,
} from 'shared'

const MAIN_MODULE: string = 'entry'
const FIXTURE_MODULE: string = 'entry_test'
const MAX_REPLAY_PAGES: number = 12
const REPLAY_CONTEXT_HASH: string =
  'f8aaea24f7639193890a4f8ca54b95a27573f890b0c0178e28d57e34ba2396e5'

class ExternalReplayPage {
  id: string = ''
  category: string = ''
  sourcePath: string = ''
  translatedCapturePath: string = ''
  imageHash: string = ''
  width: number = 0
  height: number = 0
}

class ReplayRect {
  left: number = 0
  top: number = 0
  right: number = 0
  bottom: number = 0
}

class ReplayTranslationResult {
  batch: ComicTranslationBatch = new ComicTranslationBatch()
  matchedBlocks: number = 0
  candidateLines: number = 0
}

class CandidateGroupingSegment {
  rect: number[] = []
  sourceGroupIndexes: number[] = []
  textLength: number = 0
  sourceText: string = ''
}

class CandidateGroupingSplit {
  originalRect: number[] = []
  originalSourceGroupIndexes: number[] = []
  segments: CandidateGroupingSegment[] = []
}

class CandidateGroupingPage {
  pageId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  plans: CandidateGroupingSplit[] = []
}

class CandidateGroupingPlan {
  schemaVersion: number = 0
  fixtureSetId: string = ''
  candidateId: string = ''
  pages: CandidateGroupingPage[] = []
}

class CandidateContinuationAttachment {
  splitIndex: number = -1
  segmentIndex: number = -1
  blockIndex: number = -1
  mergedSourceText: string = ''
}

class CandidateTemplateBlock {
  blockId: string = ''
  polygon: ComicPoint[] = []
}

class CandidateTemplateEnvelope {
  schemaVersion: number = 1
  backendId: string = ''
  profileId: string = ''
  sourceImageHash: string = ''
  width: number = 0
  height: number = 0
  blocks: CandidateTemplateBlock[] = []
}

function parameter(name: string): string {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  // Device releases expose custom aa-test arguments either as `-s name` or as the bare
  // name. Accept both shapes so a real-page replay cannot silently skip its requested mode.
  const legacyValue: string = parameters[`-s ${name}`] ?? ''
  return legacyValue.length > 0 ? legacyValue : parameters[name] ?? ''
}

function replayEnabled(): boolean {
  return parameter('comicExternalReplay') === 'true'
}

function containerCalibrationEnabled(): boolean {
  return parameter('comicContainerCalibration') === 'true'
}

function candidateGroupingEnabled(): boolean {
  return parameter('comicCandidateGrouping') === 'true'
}

function candidateParentRenderEnabled(): boolean {
  return parameter('comicCandidateParentRender') === 'true'
}

function candidateContinuationMergeEnabled(): boolean {
  return parameter('comicCandidateContinuationMerge') === 'true'
}

function candidatePageFontNormalizationEnabled(): boolean {
  return parameter('comicCandidatePageFontNormalization') === 'true'
}

function candidateVerticalContainerLayoutEnabled(): boolean {
  return parameter('comicCandidateVerticalContainerLayout') === 'true'
}

function liveTranslationMode(): string {
  const mode: string = parameter('comicLiveTranslationMode').trim()
  if (mode.length > 0 && mode !== 'export' && mode !== 'import') {
    throw new Error('Live translation mode is invalid')
  }
  return mode
}

function liveTranslationInputMode(): string {
  const mode: string = parameter('comicLiveTranslationInputMode').trim()
  if (mode.length === 0) {
    return COMIC_TEXT_TRANSLATION_INPUT_MULTIMODAL
  }
  if (mode !== COMIC_TEXT_TRANSLATION_INPUT_MULTIMODAL &&
    mode !== COMIC_TEXT_TRANSLATION_INPUT_TEXT_ONLY) {
    throw new Error('Live translation input mode is invalid')
  }
  return mode
}

function liveTranslationLanguage(name: string, fallback: string): string {
  const value: string = parameter(name).trim()
  if (value.length === 0) {
    return fallback
  }
  if (!/^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8}){0,3}$/.test(value)) {
    throw new Error('Live translation language is invalid')
  }
  return value
}

function externalReplayManifestName(): string {
  const name: string = parameter('comicExternalReplayManifest').trim()
  if (name.length <= 0) {
    return 'manifest.tsv'
  }
  if (!safeFileName(name)) {
    throw new Error('External replay manifest name is invalid')
  }
  return name
}

function safeFileName(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)
}

function parsePositiveInteger(value: string, label: string): number {
  const parsed: number = Number.parseInt(value, 10)
  if (!Number.isFinite(parsed) || parsed <= 0 || `${parsed}` !== value) {
    throw new Error(`${label} is invalid`)
  }
  return parsed
}

function optionalPageIndex(name: string, label: string): number {
  const raw: string = parameter(name).trim()
  return raw.length <= 0 ? -1 : parsePositiveInteger(raw, label) - 1
}

function validateIntegerArray(
  values: number[],
  expectedLength: number,
  label: string,
): void {
  if (!Array.isArray(values) || (expectedLength >= 0 && values.length !== expectedLength)) {
    throw new Error(`${label} length is invalid`)
  }
  for (let index: number = 0; index < values.length; index++) {
    if (!Number.isFinite(values[index]) || values[index] < 0 ||
      Math.floor(values[index]) !== values[index]) {
      throw new Error(`${label}[${index}] is invalid`)
    }
  }
}

function loadCandidateGroupingPlan(
  root: string,
  encodedPlan: string,
): CandidateGroupingPlan {
  let plan: CandidateGroupingPlan
  try {
    const text: string = encodedPlan.trim().length > 0
      ? new util.TextDecoder().decodeToString(
        new util.Base64Helper().decodeSync(encodedPlan.trim()),
      )
      : fileIo.readTextSync(`${root}/candidate-grouping-plan.json`)
    plan = JSON.parse(
      text,
    ) as CandidateGroupingPlan
  } catch (_error) {
    throw new Error('Candidate grouping plan is invalid JSON')
  }
  if (plan.schemaVersion !== 1 || plan.fixtureSetId.trim().length <= 0 ||
    plan.candidateId.trim().length <= 0 || !Array.isArray(plan.pages) ||
    plan.pages.length <= 0 || plan.pages.length > MAX_REPLAY_PAGES) {
    throw new Error('Candidate grouping plan identity is invalid')
  }
  const pageIndexes: Set<number> = new Set<number>()
  for (let pageOffset: number = 0; pageOffset < plan.pages.length; pageOffset++) {
    const page: CandidateGroupingPage = plan.pages[pageOffset]
    if (!safeFileName(page.pageId) || page.pageIndex < 0 ||
      Math.floor(page.pageIndex) !== page.pageIndex ||
      !/^[0-9a-f]{64}$/.test(page.sourceImageHash) ||
      pageIndexes.has(page.pageIndex) || !Array.isArray(page.plans) ||
      page.plans.length <= 0 || page.plans.length > 16) {
      throw new Error(`Candidate grouping page ${pageOffset} is invalid`)
    }
    pageIndexes.add(page.pageIndex)
    for (let planOffset: number = 0; planOffset < page.plans.length; planOffset++) {
      const split: CandidateGroupingSplit = page.plans[planOffset]
      validateIntegerArray(
        split.originalRect,
        4,
        `candidate page ${pageOffset} plan ${planOffset} originalRect`,
      )
      validateIntegerArray(
        split.originalSourceGroupIndexes,
        -1,
        `candidate page ${pageOffset} plan ${planOffset} sourceGroupIndexes`,
      )
      if (split.originalRect[2] <= split.originalRect[0] ||
        split.originalRect[3] <= split.originalRect[1] ||
        split.originalSourceGroupIndexes.length < 2 ||
        !Array.isArray(split.segments) || split.segments.length < 2 ||
        split.segments.length > 8) {
        throw new Error(`Candidate grouping split ${pageOffset}:${planOffset} is invalid`)
      }
      const sourceGroups: Set<number> =
        new Set<number>(split.originalSourceGroupIndexes)
      const segmentGroups: Set<number> = new Set<number>()
      for (let segmentOffset: number = 0;
        segmentOffset < split.segments.length; segmentOffset++) {
        const segment: CandidateGroupingSegment = split.segments[segmentOffset]
        validateIntegerArray(
          segment.rect,
          4,
          `candidate segment ${pageOffset}:${planOffset}:${segmentOffset} rect`,
        )
        validateIntegerArray(
          segment.sourceGroupIndexes,
          -1,
          `candidate segment ${pageOffset}:${planOffset}:${segmentOffset} groups`,
        )
        if (segment.rect[0] < split.originalRect[0] ||
          segment.rect[1] < split.originalRect[1] ||
          segment.rect[2] > split.originalRect[2] ||
          segment.rect[3] > split.originalRect[3] ||
          segment.rect[2] <= segment.rect[0] ||
          segment.rect[3] <= segment.rect[1] ||
          segment.sourceGroupIndexes.length <= 0 ||
          !Number.isFinite(segment.textLength) || segment.textLength <= 0 ||
          Math.floor(segment.textLength) !== segment.textLength ||
          segment.sourceText.replace(/\s+/g, '').length !== segment.textLength) {
          throw new Error(`Candidate grouping segment ${pageOffset}:${planOffset}:${segmentOffset} is invalid`)
        }
        for (let sourceOffset: number = 0;
          sourceOffset < segment.sourceGroupIndexes.length; sourceOffset++) {
          const sourceGroup: number = segment.sourceGroupIndexes[sourceOffset]
          if (!sourceGroups.has(sourceGroup) || segmentGroups.has(sourceGroup)) {
            throw new Error('Candidate grouping source membership is inconsistent')
          }
          segmentGroups.add(sourceGroup)
        }
      }
      if (segmentGroups.size !== sourceGroups.size) {
        throw new Error('Candidate grouping source membership is incomplete')
      }
    }
  }
  return plan
}

function writeFixtureFile(path: string, bytes: Uint8Array): void {
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
    if (written !== bytes.byteLength) {
      throw new Error('External replay fixture write was incomplete')
    }
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function writeTextFile(path: string, value: string): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    )
    fileIo.writeSync(file.fd, value)
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

function appendTextFile(path: string, value: string): void {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND,
    )
    fileIo.writeSync(file.fd, value)
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}

async function stageRawCalibrationPages(
  context: common.Context,
  rawManifest: string,
): Promise<string> {
  if (!safeFileName(rawManifest)) {
    throw new Error('Container calibration raw manifest is unsafe')
  }
  const manifestBytes: Uint8Array =
    await context.resourceManager.getRawFileContent(rawManifest)
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  const lines: string[] = decoder.decodeToString(manifestBytes).split('\n')
  const sourceNames: string[] = []
  for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
    const line: string = lines[lineIndex].trim()
    if (line.length <= 0 || line.startsWith('#')) {
      continue
    }
    const fields: string[] = line.split('\t')
    if (fields.length !== 6 || !safeFileName(fields[2])) {
      throw new Error(`Container calibration manifest line ${lineIndex + 1} is invalid`)
    }
    sourceNames.push(fields[2])
  }
  if (sourceNames.length <= 0 || sourceNames.length > MAX_REPLAY_PAGES) {
    throw new Error('Container calibration raw page count is invalid')
  }
  const root: string = `${context.cacheDir}/comic-container-calibration-staged`
  if (!fileIo.accessSync(root)) {
    fileIo.mkdirSync(root, true)
  }
  writeFixtureFile(`${root}/manifest.tsv`, manifestBytes)
  for (let index: number = 0; index < sourceNames.length; index++) {
    const bytes: Uint8Array =
      await context.resourceManager.getRawFileContent(sourceNames[index])
    writeFixtureFile(`${root}/${sourceNames[index]}`, bytes)
  }
  return root
}

/**
 * The live-translation debug probe is deliberately limited to the main application's cache so
 * that a request cannot make the app read arbitrary device files. External replay pages are
 * explicitly staged in the app sandbox, therefore copy only the selected, manifest-named page
 * into the probe-owned cache before exporting a provider request. This is test-only staging;
 * Reader never uses it.
 */
function stageLiveTranslationPage(
  context: common.UIAbilityContext,
  page: ExternalReplayPage,
): void {
  const sourceName: string = page.sourcePath.slice(page.sourcePath.lastIndexOf('/') + 1)
  if (!safeFileName(sourceName) || !fileIo.accessSync(page.sourcePath)) {
    throw new Error('Live translation replay source is unsafe')
  }
  const sourceSize: number = fileIo.statSync(page.sourcePath).size
  if (!Number.isFinite(sourceSize) || sourceSize <= 0 || sourceSize > 32 * 1024 * 1024) {
    throw new Error('Live translation replay source size is invalid')
  }
  const root: string = `${context.getApplicationContext().cacheDir}/comic-live-translation-staged`
  if (!fileIo.accessSync(root)) {
    fileIo.mkdirSync(root, true)
  }
  const target: string = `${root}/${page.imageHash}-${sourceName}`
  if (!fileIo.accessSync(target) || fileIo.statSync(target).size !== sourceSize) {
    fileIo.copyFileSync(page.sourcePath, target)
  }
  if (!fileIo.accessSync(target) || fileIo.statSync(target).size !== sourceSize) {
    throw new Error('Live translation replay source staging was incomplete')
  }
  page.sourcePath = target
}

function loadReplayPages(
  root: string,
  calibrationOnly: boolean,
  manifestName: string,
): ExternalReplayPage[] {
  const manifestPath: string = `${root}/${manifestName}`
  if (!fileIo.accessSync(manifestPath)) {
    throw new Error(
      `External replay manifest is unavailable: root=${root}, manifest=${manifestName}`,
    )
  }
  const lines: string[] = fileIo.readTextSync(manifestPath).split('\n')
  const pages: ExternalReplayPage[] = []
  const ids: Set<string> = new Set<string>()
  for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
    const line: string = lines[lineIndex].trim()
    if (line.length <= 0 || line.startsWith('#')) {
      continue
    }
    const fields: string[] = line.split('\t')
    const expectedFieldCount: number = calibrationOnly ? 6 : 7
    if (fields.length !== expectedFieldCount) {
      throw new Error(`External replay manifest line ${lineIndex + 1} is invalid`)
    }
    const page: ExternalReplayPage = new ExternalReplayPage()
    page.id = fields[0]
    page.category = fields[1]
    const sourceName: string = fields[2]
    const translatedName: string = calibrationOnly ? '' : fields[3]
    const hashIndex: number = calibrationOnly ? 3 : 4
    page.imageHash = fields[hashIndex]
    page.width = parsePositiveInteger(fields[hashIndex + 1], 'External replay width')
    page.height = parsePositiveInteger(fields[hashIndex + 2], 'External replay height')
    if (!safeFileName(page.id) || !safeFileName(page.category) ||
      !safeFileName(sourceName) || (!calibrationOnly && !safeFileName(translatedName)) ||
      !/^[0-9a-f]{64}$/.test(page.imageHash) || ids.has(page.id)) {
      throw new Error(`External replay manifest line ${lineIndex + 1} is unsafe`)
    }
    ids.add(page.id)
    page.sourcePath = `${root}/${sourceName}`
    page.translatedCapturePath = calibrationOnly ? '' : `${root}/${translatedName}`
    if (!fileIo.accessSync(page.sourcePath) ||
      (!calibrationOnly && !fileIo.accessSync(page.translatedCapturePath))) {
      throw new Error(`External replay page ${page.id} is missing`)
    }
    pages.push(page)
  }
  if (pages.length <= 0 || pages.length > MAX_REPLAY_PAGES) {
    throw new Error('External replay page count is invalid')
  }
  return pages
}

function pageSource(
  page: ExternalReplayPage,
  pageIndex: number,
  calibrationOnly: boolean,
): ComicVisualPageSource {
  const source: ComicVisualPageSource = new ComicVisualPageSource()
  source.projectId = calibrationOnly
    ? 'local-authorized-container-calibration-v1'
    : 'local-authorized-real-page-replay-v1'
  source.pageIndex = pageIndex
  source.imageFilePath = page.sourcePath
  source.imageHash = page.imageHash
  source.imageWidth = page.width
  source.imageHeight = page.height
  return source
}

function blockRect(block: ComicTextBlock): ReplayRect {
  const rect: ReplayRect = new ReplayRect()
  rect.left = Number.MAX_SAFE_INTEGER
  rect.top = Number.MAX_SAFE_INTEGER
  rect.right = 0
  rect.bottom = 0
  for (let index: number = 0; index < block.polygon.length; index++) {
    rect.left = Math.min(rect.left, block.polygon[index].x)
    rect.top = Math.min(rect.top, block.polygon[index].y)
    rect.right = Math.max(rect.right, block.polygon[index].x)
    rect.bottom = Math.max(rect.bottom, block.polygon[index].y)
  }
  return rect
}

function sameRect(block: ComicTextBlock, values: number[]): boolean {
  const rect: ReplayRect = blockRect(block)
  return Math.floor(rect.left) === values[0] &&
    Math.floor(rect.top) === values[1] &&
    Math.ceil(rect.right) === values[2] &&
    Math.ceil(rect.bottom) === values[3]
}

function candidateBlock(
  source: ComicTextBlock,
  segment: CandidateGroupingSegment,
  segmentIndex: number,
  sourceText: string = '',
): ComicTextBlock {
  const block: ComicTextBlock = source.copy()
  const resolvedSourceText: string =
    sourceText.trim().length > 0 ? sourceText.trim() : segment.sourceText
  block.blockId = `${source.blockId}-s${segmentIndex + 1}`
  block.sourceText = resolvedSourceText
  block.normalizedSourceText = resolvedSourceText.replace(/\s+/g, ' ').trim()
  block.polygon = [
    new ComicPoint(segment.rect[0], segment.rect[1]),
    new ComicPoint(segment.rect[2], segment.rect[1]),
    new ComicPoint(segment.rect[2], segment.rect[3]),
    new ComicPoint(segment.rect[0], segment.rect[3]),
  ]
  return block
}

function continuationSourceText(
  sourceText: string,
  continuationText: string,
): string {
  return `${sourceText.trim()} ${continuationText.trim()}`
    .replace(/\s+/g, ' ')
    .replace(/([A-Za-z])-\s+([A-Za-z])/g, '$1$2')
    .trim()
}

function candidateContinuationAttachments(
  analysis: ComicRegionAnalysisResult,
  page: CandidateGroupingPage,
): CandidateContinuationAttachment[] {
  const attachments: CandidateContinuationAttachment[] = []
  const consumedBlocks: Set<number> = new Set<number>()
  for (let splitIndex: number = 0; splitIndex < page.plans.length; splitIndex++) {
    const split: CandidateGroupingSplit = page.plans[splitIndex]
    const hyphenSegments: number[] = []
    for (let segmentIndex: number = 0;
      segmentIndex < split.segments.length; segmentIndex++) {
      if (/[A-Za-z]-\s*$/.test(split.segments[segmentIndex].sourceText)) {
        hyphenSegments.push(segmentIndex)
      }
    }
    if (hyphenSegments.length !== 1) {
      continue
    }
    const segmentIndex: number = hyphenSegments[0]
    const segment: CandidateGroupingSegment = split.segments[segmentIndex]
    const parentWidth: number = split.originalRect[2] - split.originalRect[0]
    const parentHeight: number = split.originalRect[3] - split.originalRect[1]
    const parentArea: number = parentWidth * parentHeight
    const candidates: number[] = []
    for (let blockIndex: number = 0;
      blockIndex < analysis.document.blocks.length; blockIndex++) {
      const block: ComicTextBlock = analysis.document.blocks[blockIndex]
      if (sameRect(block, split.originalRect) || consumedBlocks.has(blockIndex)) {
        continue
      }
      const text: string = block.sourceText.replace(/\s+/g, ' ').trim()
      if (!/^[A-Za-z]/.test(text) || text.length > 40) {
        continue
      }
      const rect: ReplayRect = blockRect(block)
      const centerX: number = (rect.left + rect.right) / 2
      const centerY: number = (rect.top + rect.bottom) / 2
      const area: number = (rect.right - rect.left) * (rect.bottom - rect.top)
      if (centerX <= split.originalRect[0] || centerX >= split.originalRect[2] ||
        centerY <= split.originalRect[1] || centerY >= split.originalRect[3] ||
        area <= 0 || area > parentArea * 0.2 ||
        centerX < segment.rect[0] - parentWidth * 0.1 ||
        centerX > segment.rect[2] + parentWidth * 0.1 ||
        rect.top > segment.rect[3] + parentHeight * 0.35 ||
        rect.bottom < segment.rect[1] - parentHeight * 0.1) {
        continue
      }
      candidates.push(blockIndex)
    }
    if (candidates.length !== 1) {
      continue
    }
    const attachment: CandidateContinuationAttachment =
      new CandidateContinuationAttachment()
    attachment.splitIndex = splitIndex
    attachment.segmentIndex = segmentIndex
    attachment.blockIndex = candidates[0]
    attachment.mergedSourceText = continuationSourceText(
      segment.sourceText,
      analysis.document.blocks[candidates[0]].sourceText,
    )
    consumedBlocks.add(candidates[0])
    attachments.push(attachment)
  }
  return attachments
}

function continuationAttachment(
  attachments: CandidateContinuationAttachment[],
  splitIndex: number,
  segmentIndex: number,
): CandidateContinuationAttachment | null {
  for (let index: number = 0; index < attachments.length; index++) {
    if (attachments[index].splitIndex === splitIndex &&
      attachments[index].segmentIndex === segmentIndex) {
      return attachments[index]
    }
  }
  return null
}

function sha256(bytes: Uint8Array): string {
  const md = cryptoFramework.createMd('SHA256')
  md.updateSync({ data: bytes })
  const digest: Uint8Array = md.digestSync().data
  let value: string = ''
  for (let index: number = 0; index < digest.length; index++) {
    value = value + digest[index].toString(16).padStart(2, '0')
  }
  return value
}

function candidateTemplate(
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  document: ComicPageDocument,
): ComicBackendTemplate {
  const envelope: CandidateTemplateEnvelope = new CandidateTemplateEnvelope()
  envelope.backendId = analysis.backendId
  envelope.profileId = analysis.profileId
  envelope.sourceImageHash = source.imageHash
  envelope.width = source.imageWidth
  envelope.height = source.imageHeight
  for (let index: number = 0; index < document.blocks.length; index++) {
    const sourceBlock: ComicTextBlock = document.blocks[index]
    const block: CandidateTemplateBlock = new CandidateTemplateBlock()
    block.blockId = sourceBlock.blockId
    for (let pointIndex: number = 0;
      pointIndex < sourceBlock.polygon.length; pointIndex++) {
      block.polygon.push(sourceBlock.polygon[pointIndex].copy())
    }
    envelope.blocks.push(block)
  }
  const payload: Uint8Array =
    new util.TextEncoder().encodeInto(JSON.stringify(envelope))
  const template: ComicBackendTemplate = new ComicBackendTemplate()
  template.backendId = analysis.adapterTemplate.backendId
  template.profileId = analysis.adapterTemplate.profileId
  template.protocolRevision = analysis.adapterTemplate.protocolRevision
  template.contentHash = sha256(payload)
  template.mimeType = analysis.adapterTemplate.mimeType
  template.payload = payload
  return template
}

function candidateGroupingPage(
  plan: CandidateGroupingPlan,
  source: ComicVisualPageSource,
): CandidateGroupingPage | null {
  for (let index: number = 0; index < plan.pages.length; index++) {
    if (plan.pages[index].pageIndex === source.pageIndex) {
      if (plan.pages[index].sourceImageHash !== source.imageHash) {
        throw new Error('Candidate grouping plan source image no longer matches')
      }
      return plan.pages[index]
    }
  }
  return null
}

function candidateGroupingAnalysis(
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  page: CandidateGroupingPage,
  attachments: CandidateContinuationAttachment[] = [],
): ComicRegionAnalysisResult {
  const replacements: Map<number, number> = new Map<number, number>()
  for (let planIndex: number = 0; planIndex < page.plans.length; planIndex++) {
    const split: CandidateGroupingSplit = page.plans[planIndex]
    let match: number = -1
    for (let blockIndex: number = 0;
      blockIndex < analysis.document.blocks.length; blockIndex++) {
      if (sameRect(analysis.document.blocks[blockIndex], split.originalRect)) {
        if (match >= 0) {
          throw new Error('Candidate grouping split matches multiple source blocks')
        }
        match = blockIndex
      }
    }
    if (match < 0 || replacements.has(match)) {
      throw new Error('Candidate grouping split source block is unavailable')
    }
    replacements.set(match, planIndex)
  }
  const excludedBlocks: Set<number> = new Set<number>()
  for (let index: number = 0; index < attachments.length; index++) {
    excludedBlocks.add(attachments[index].blockIndex)
  }
  const document: ComicPageDocument = analysis.document.copy()
  document.blocks = []
  for (let blockIndex: number = 0;
    blockIndex < analysis.document.blocks.length; blockIndex++) {
    if (excludedBlocks.has(blockIndex)) {
      continue
    }
    const sourceBlock: ComicTextBlock = analysis.document.blocks[blockIndex]
    const splitIndex: number | undefined = replacements.get(blockIndex)
    if (splitIndex === undefined) {
      document.blocks.push(sourceBlock.copy())
      continue
    }
    const split: CandidateGroupingSplit = page.plans[splitIndex]
    for (let segmentIndex: number = 0;
      segmentIndex < split.segments.length; segmentIndex++) {
      const attachment: CandidateContinuationAttachment | null =
        continuationAttachment(attachments, splitIndex, segmentIndex)
      document.blocks.push(
        candidateBlock(
          sourceBlock,
          split.segments[segmentIndex],
          segmentIndex,
          attachment === null ? '' : attachment.mergedSourceText,
        ),
      )
    }
  }
  document.analysisRevision = analysis.document.analysisRevision + 1
  for (let index: number = 0; index < document.blocks.length; index++) {
    document.blocks[index].readingOrder = index
    document.blocks[index].sourceRevision = document.analysisRevision
  }
  const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
  result.backendId = analysis.backendId
  result.profileId = analysis.profileId
  result.regionRevision = analysis.regionRevision
  result.document = document
  result.adapterTemplate = candidateTemplate(source, analysis, document)
  return result
}

function candidateParentRenderAnalysis(
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  attachments: CandidateContinuationAttachment[],
): ComicRegionAnalysisResult {
  if (attachments.length <= 0) {
    return analysis
  }
  const excludedBlocks: Set<number> = new Set<number>()
  for (let index: number = 0; index < attachments.length; index++) {
    excludedBlocks.add(attachments[index].blockIndex)
  }
  const document: ComicPageDocument = analysis.document.copy()
  document.blocks = []
  for (let blockIndex: number = 0;
    blockIndex < analysis.document.blocks.length; blockIndex++) {
    if (!excludedBlocks.has(blockIndex)) {
      document.blocks.push(analysis.document.blocks[blockIndex].copy())
    }
  }
  document.analysisRevision = analysis.document.analysisRevision + 1
  for (let index: number = 0; index < document.blocks.length; index++) {
    document.blocks[index].readingOrder = index
    document.blocks[index].sourceRevision = document.analysisRevision
  }
  const result: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
  result.backendId = analysis.backendId
  result.profileId = analysis.profileId
  result.regionRevision = analysis.regionRevision
  result.document = document
  result.adapterTemplate = candidateTemplate(source, analysis, document)
  return result
}

function lineCenter(line: ComicLocalOcrLine): number[] {
  let x: number = 0
  let y: number = 0
  for (let index: number = 0; index < line.polygon.length; index++) {
    x = x + line.polygon[index].x
    y = y + line.polygon[index].y
  }
  return [x / line.polygon.length, y / line.polygon.length]
}

function translatedCandidateText(value: string): string {
  const normalized: string = value.replace(/\s+/g, '').trim()
  if (normalized.length <= 0 || /[\u3040-\u30ff]/.test(normalized) ||
    !/[\u3400-\u9fff]/.test(normalized)) {
    return ''
  }
  return normalized
}

function textForBlock(
  block: ComicTextBlock,
  lines: ComicLocalOcrLine[],
  consumed: Set<number>,
): string {
  if (block.polygon.length < 3) {
    return ''
  }
  const rect: ReplayRect = blockRect(block)
  const marginX: number = Math.max(8, Math.min(48, (rect.right - rect.left) * 0.15))
  const marginY: number = Math.max(8, Math.min(48, (rect.bottom - rect.top) * 0.15))
  const matches: string[] = []
  for (let index: number = 0; index < lines.length; index++) {
    if (consumed.has(index) || lines[index].polygon.length < 3) {
      continue
    }
    const text: string = translatedCandidateText(lines[index].text)
    if (text.length <= 0) {
      continue
    }
    const center: number[] = lineCenter(lines[index])
    if (center[0] < rect.left - marginX || center[0] > rect.right + marginX ||
      center[1] < rect.top - marginY || center[1] > rect.bottom + marginY) {
      continue
    }
    consumed.add(index)
    matches.push(text)
  }
  return matches.join('')
}

async function recognizeCapture(
  ocr: HarmonyComicLocalOcrEngine,
  path: string,
): Promise<ComicLocalOcrResult> {
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(path)
    pixelMap = await source.createPixelMap({
      editable: false,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    })
    return await ocr.recognize(pixelMap)
  } finally {
    if (pixelMap !== undefined) {
      await pixelMap.release()
    }
    if (source !== undefined) {
      source.release()
    }
  }
}

function replayTranslations(
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  candidate: ComicLocalOcrResult,
  translationRevision: number,
): ReplayTranslationResult {
  const result: ReplayTranslationResult = new ReplayTranslationResult()
  result.candidateLines = candidate.lines.length
  result.batch.projectId = source.projectId
  result.batch.pageIndex = source.pageIndex
  result.batch.sourceImageHash = source.imageHash
  result.batch.targetLanguage = 'zh-CN'
  result.batch.sourceProfileId = 'captured-real-result-ocr-replay'
  result.batch.sourceRevision = 1
  result.batch.modelId = 'captured-real-result'
  result.batch.promptVersion = 'replay-v1'
  result.batch.contextFingerprint = REPLAY_CONTEXT_HASH
  result.batch.translationRevision = translationRevision
  const consumed: Set<number> = new Set<number>()
  for (let index: number = 0; index < analysis.document.blocks.length; index++) {
    const translatedText: string = textForBlock(
      analysis.document.blocks[index],
      candidate.lines,
      consumed,
    )
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = analysis.document.blocks[index].blockId
    block.translatedText = translatedText.length > 0
      ? translatedText
      : analysis.document.blocks[index].sourceText
    result.batch.blocks.push(block)
    if (translatedText.length > 0) {
      result.matchedBlocks = result.matchedBlocks + 1
    }
  }
  return result
}

function batchTranslation(
  batch: ComicTranslationBatch,
  blockId: string,
  consumed: Set<string>,
): string {
  let translatedText: string = ''
  let matches: number = 0
  for (let index: number = 0; index < batch.blocks.length; index++) {
    if (batch.blocks[index].blockId !== blockId) {
      continue
    }
    translatedText = batch.blocks[index].translatedText.trim()
    matches = matches + 1
  }
  if (matches !== 1 || translatedText.length <= 0 || consumed.has(blockId)) {
    throw new Error(`Candidate parent render translation is invalid for ${blockId}`)
  }
  consumed.add(blockId)
  return translatedText
}

function candidateParentRenderTranslations(
  analysis: ComicRegionAnalysisResult,
  page: CandidateGroupingPage,
  candidateBatch: ComicTranslationBatch,
): ReplayTranslationResult {
  const result: ReplayTranslationResult = new ReplayTranslationResult()
  result.batch = candidateBatch.copy()
  result.batch.sourceRevision = analysis.document.analysisRevision
  result.batch.blocks = []
  const consumed: Set<string> = new Set<string>()
  for (let blockIndex: number = 0;
    blockIndex < analysis.document.blocks.length; blockIndex++) {
    const sourceBlock: ComicTextBlock = analysis.document.blocks[blockIndex]
    let split: CandidateGroupingSplit | null = null
    for (let planIndex: number = 0; planIndex < page.plans.length; planIndex++) {
      if (!sameRect(sourceBlock, page.plans[planIndex].originalRect)) {
        continue
      }
      if (split !== null) {
        throw new Error('Candidate parent render split is ambiguous')
      }
      split = page.plans[planIndex]
    }
    const translation: ComicBlockTranslation = new ComicBlockTranslation()
    translation.blockId = sourceBlock.blockId
    if (split === null) {
      translation.translatedText =
        batchTranslation(candidateBatch, sourceBlock.blockId, consumed)
    } else {
      const segments: string[] = []
      for (let segmentIndex: number = 0;
        segmentIndex < split.segments.length; segmentIndex++) {
        segments.push(batchTranslation(
          candidateBatch,
          `${sourceBlock.blockId}-s${segmentIndex + 1}`,
          consumed,
        ))
      }
      translation.translatedText = segments.join('\n')
    }
    result.batch.blocks.push(translation)
  }
  if (consumed.size !== candidateBatch.blocks.length) {
    throw new Error('Candidate parent render left translations unconsumed')
  }
  ComicVisualTranslationContract.validateTranslationBatch(
    analysis.document,
    result.batch,
  )
  result.matchedBlocks = result.batch.blocks.length
  return result
}

function containerCalibrationTranslations(
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  translationRevision: number,
): ReplayTranslationResult {
  const result: ReplayTranslationResult = new ReplayTranslationResult()
  result.batch.projectId = source.projectId
  result.batch.pageIndex = source.pageIndex
  result.batch.sourceImageHash = source.imageHash
  result.batch.targetLanguage = 'zh-CN'
  result.batch.sourceProfileId = 'container-calibration-only'
  result.batch.sourceRevision = 1
  result.batch.modelId = 'deterministic-placeholder'
  result.batch.promptVersion = 'container-calibration-v1'
  result.batch.contextFingerprint = REPLAY_CONTEXT_HASH
  result.batch.translationRevision = translationRevision
  for (let index: number = 0; index < analysis.document.blocks.length; index++) {
    const block: ComicBlockTranslation = new ComicBlockTranslation()
    block.blockId = analysis.document.blocks[index].blockId
    block.translatedText = '容器校准文本'
    result.batch.blocks.push(block)
    result.matchedBlocks = result.matchedBlocks + 1
  }
  return result
}

function liveTranslationRequest(
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  translationRevision: number,
  sourceLanguage: string,
  targetLanguage: string,
): ComicTextTranslationRequest {
  const request: ComicTextTranslationRequest = new ComicTextTranslationRequest()
  request.source = source
  request.document = analysis.document
  request.context.sourceLanguage = sourceLanguage
  request.context.targetLanguage = targetLanguage
  request.context.styleGuide =
    'Use concise natural Chinese suitable for comic lettering. Keep names, forms of address, tone, and references consistent across all blocks on the page.'
  request.context.glossaryRevision = 0
  request.context.styleGuideRevision = 1
  request.context.contextRevision = 1
  request.requestedTranslationRevision = translationRevision
  return request
}

function renderRequest(
  backend: ComicLocalVisualBackend,
  source: ComicVisualPageSource,
  analysis: ComicRegionAnalysisResult,
  translations: ComicTranslationBatch,
  pageFontNormalization: boolean,
  verticalContainerLayout: boolean,
): ComicRegionRenderRequest {
  const request: ComicRegionRenderRequest = new ComicRegionRenderRequest()
  request.source = source
  request.regionRevision = analysis.regionRevision
  request.document = analysis.document
  request.translations = translations
  request.adapterTemplate = analysis.adapterTemplate
  const profile: ComicRenderProfile = new ComicRenderProfile()
  profile.profileId = 'reader-local-bubble-layout-v30'
  profile.sourceTreatmentProfileId = 'local-glyph-inpaint-v30'
  profile.layoutProfileId = verticalContainerLayout ?
    'local-bubble-typography-vertical-container-candidate-v1' :
    pageFontNormalization ?
      'local-bubble-typography-page-outlier-v2' :
      'local-bubble-typography-v30'
  profile.targetMimeType = 'image/png'
  profile.revision = 8
  request.renderProfile = profile
  const identity: ComicRenderedPageIdentity = new ComicRenderedPageIdentity()
  identity.route = ComicVisualTranslationRoute.STAGED
  identity.projectId = source.projectId
  identity.pageIndex = source.pageIndex
  identity.sourceImageHash = source.imageHash
  identity.sourceWidth = source.imageWidth
  identity.sourceHeight = source.imageHeight
  identity.targetLanguage = translations.targetLanguage
  identity.regionBackendId = backend.backendId()
  identity.regionProfileId = backend.profileId()
  identity.regionRevision = analysis.regionRevision
  identity.documentRevision = analysis.document.analysisRevision
  identity.translationSourceProfileId = translations.sourceProfileId
  identity.translationSourceRevision = translations.sourceRevision
  identity.translationModelId = translations.modelId
  identity.translationPromptVersion = translations.promptVersion
  identity.translationContextFingerprint = translations.contextFingerprint
  identity.glossaryRevision = translations.glossaryRevision
  identity.translationRevision = translations.translationRevision
  identity.sourceTreatmentProfileId = profile.sourceTreatmentProfileId
  identity.layoutProfileId = profile.layoutProfileId
  identity.renderBackendId = backend.backendId()
  identity.renderProfileId = profile.profileId
  identity.renderTargetMimeType = profile.targetMimeType
  identity.renderRevision = profile.revision
  request.identity = identity
  return request
}

export default function comicLocalExternalReplayTest(): void {
  describe('ComicLocalExternalReplay', (): void => {
    it('merges only an unambiguous clipped hyphen continuation', 0, (): void => {
      const analysis: ComicRegionAnalysisResult = new ComicRegionAnalysisResult()
      analysis.document = new ComicPageDocument()
      const parent: ComicTextBlock = new ComicTextBlock()
      parent.blockId = 'parent'
      parent.sourceText = 'ANY SUGGES- OTHER DIALOGUE'
      parent.polygon = [
        new ComicPoint(80, 50),
        new ComicPoint(540, 50),
        new ComicPoint(540, 245),
        new ComicPoint(80, 245),
      ]
      const continuation: ComicTextBlock = new ComicTextBlock()
      continuation.blockId = 'continuation'
      continuation.sourceText = 'TIONS, GENTLE-\nMEN?'
      continuation.polygon = [
        new ComicPoint(76, 119),
        new ComicPoint(146, 119),
        new ComicPoint(146, 171),
        new ComicPoint(76, 171),
      ]
      analysis.document.blocks = [parent, continuation]
      const page: CandidateGroupingPage = new CandidateGroupingPage()
      const split: CandidateGroupingSplit = new CandidateGroupingSplit()
      split.originalRect = [80, 50, 540, 245]
      const segment: CandidateGroupingSegment = new CandidateGroupingSegment()
      segment.rect = [80, 84, 540, 125]
      segment.sourceText = 'ANY SUGGES-'
      const remaining: CandidateGroupingSegment = new CandidateGroupingSegment()
      remaining.rect = [99, 136, 505, 245]
      remaining.sourceText = 'OTHER DIALOGUE'
      split.segments = [segment, remaining]
      page.plans = [split]

      const matched: CandidateContinuationAttachment[] =
        candidateContinuationAttachments(analysis, page)
      expect(matched.length).assertEqual(1)
      expect(matched[0].blockIndex).assertEqual(1)
      expect(matched[0].mergedSourceText).assertEqual(
        'ANY SUGGESTIONS, GENTLEMEN?',
      )

      const ambiguous: ComicTextBlock = continuation.copy()
      ambiguous.blockId = 'ambiguous'
      ambiguous.sourceText = 'TIVES?'
      ambiguous.polygon = [
        new ComicPoint(150, 119),
        new ComicPoint(205, 119),
        new ComicPoint(205, 151),
        new ComicPoint(150, 151),
      ]
      analysis.document.blocks.push(ambiguous)
      expect(candidateContinuationAttachments(analysis, page).length).assertEqual(0)
      analysis.document.blocks.pop()
      segment.sourceText = 'ANY SUGGESTIONS?'
      expect(candidateContinuationAttachments(analysis, page).length).assertEqual(0)
      segment.sourceText = 'WHO..00-'
      expect(candidateContinuationAttachments(analysis, page).length).assertEqual(0)
    })

    it('records current local rendering on explicitly staged real page pairs', 0,
      async (): Promise<void> => {
        const calibrationOnly: boolean = containerCalibrationEnabled()
        if (!replayEnabled() && !calibrationOnly) {
          expect(true).assertEqual(true)
          return
        }
        let root: string = parameter('comicExternalReplayRoot').trim()
        const rawManifest: string = parameter('comicContainerCalibrationRawManifest').trim()
        const recordingId: string = parameter('comicExternalRecordingId').trim()
        if ((root.length <= 0 && rawManifest.length <= 0) || recordingId.length <= 0) {
          throw new Error('External replay source and recording id are required')
        }
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const ability = await delegator.getCurrentTopAbility()
        const mainContext: common.UIAbilityContext = await application.createModuleContext(
          ability.context,
          MAIN_MODULE,
        ) as common.UIAbilityContext
        const fixtureContext: common.Context = await application.createModuleContext(
          ability.context,
          FIXTURE_MODULE,
        )
        if (rawManifest.length > 0) {
          if (!calibrationOnly) {
            throw new Error('Raw resource replay is only allowed for container calibration')
          }
          root = await stageRawCalibrationPages(
            fixtureContext,
            rawManifest,
          )
        }
        const detectorPaths: ComicTranslationModelPaths | null =
          ComicTranslationModelService.pathsIfReady(mainContext)
        const recognizerPaths: ComicTextRecognitionModelPaths | null =
          ComicTranslationModelService.ocrPathsIfReady(mainContext)
        const textMaskPaths: ComicTextMaskModelPaths | null =
          ComicTranslationModelService.textMaskPathsIfReady(mainContext)
        const inpaintingPaths: ComicSourceInpaintingModelPaths | null =
          ComicTranslationModelService.inpaintingPathsIfReady(mainContext)
        expect(detectorPaths !== null).assertEqual(true)
        expect(recognizerPaths !== null).assertEqual(true)
        expect(textMaskPaths !== null).assertEqual(true)
        expect(inpaintingPaths !== null).assertEqual(true)
        if (detectorPaths === null || recognizerPaths === null || textMaskPaths === null ||
          inpaintingPaths === null) {
          return
        }
        const manifestName: string = externalReplayManifestName()
        if (!fileIo.accessSync(`${root}/${manifestName}`)) {
          throw new Error(
            `External replay manifest is unavailable: root=${root}, manifest=${manifestName}, ` +
            `mainCache=${mainContext.cacheDir}, fixtureCache=${fixtureContext.cacheDir}`,
          )
        }
        const pages: ExternalReplayPage[] = loadReplayPages(
          root,
          calibrationOnly,
          manifestName,
        )
        const selectedPageIndex: number = optionalPageIndex(
          'comicExternalReplayPageNumber',
          'External replay page number',
        )
        if (selectedPageIndex >= pages.length) {
          throw new Error('External replay page number is out of range')
        }
        const translationMode: string = liveTranslationMode()
        const liveTranslation: boolean = translationMode.length > 0
        const translationInputMode: string = liveTranslationInputMode()
        const liveTranslationSourceLanguage: string =
          liveTranslationLanguage('comicLiveTranslationSourceLanguage', 'en')
        const liveTranslationTargetLanguage: string =
          liveTranslationLanguage('comicLiveTranslationTargetLanguage', 'zh-CN')
        const candidateParentRender: boolean = candidateParentRenderEnabled()
        const candidateContinuationMerge: boolean =
          candidateContinuationMergeEnabled()
        const candidatePageFontNormalization: boolean =
          candidatePageFontNormalizationEnabled()
        const candidateVerticalContainerLayout: boolean =
          candidateVerticalContainerLayoutEnabled()
        if (candidatePageFontNormalization && candidateVerticalContainerLayout) {
          throw new Error('Page font and vertical container candidates cannot be combined')
        }
        if (candidateParentRender &&
          (!candidateGroupingEnabled() || translationMode !== 'import')) {
          throw new Error(
            'Candidate parent render requires candidate grouping and imported live translation',
          )
        }
        if (candidateContinuationMerge && !candidateGroupingEnabled()) {
          throw new Error(
            'Candidate continuation merge requires candidate grouping',
          )
        }
        let liveTranslationPageIndex: number = -1
        let liveTranslationProbeId: string = ''
        if (liveTranslation) {
          if (!calibrationOnly) {
            throw new Error('Live translation replay requires calibration-only input')
          }
          liveTranslationPageIndex = parsePositiveInteger(
            parameter('comicLiveTranslationPageNumber'),
            'Live translation page number',
          ) - 1
          if (liveTranslationPageIndex < 0 || liveTranslationPageIndex >= pages.length) {
            throw new Error('Live translation page number is out of range')
          }
          if (selectedPageIndex >= 0 &&
            liveTranslationPageIndex !== selectedPageIndex) {
            throw new Error('Live translation page is outside the selected replay page')
          }
          liveTranslationProbeId = parameter('comicLiveTranslationProbeId').trim()
          if (!safeFileName(liveTranslationProbeId)) {
            throw new Error('Live translation probe id is invalid')
          }
        }
        let candidatePlan: CandidateGroupingPlan | null = null
        if (candidateGroupingEnabled()) {
          if (!calibrationOnly) {
            throw new Error('Candidate grouping replay requires calibration-only input')
          }
          candidatePlan = loadCandidateGroupingPlan(
            root,
            parameter('comicCandidateGroupingPlanBase64'),
          )
        }
        const ocr: HarmonyComicLocalOcrEngine = new HarmonyComicLocalOcrEngine()
        const recorder: ComicLocalVisualFileRecorder =
          new ComicLocalVisualFileRecorder(mainContext, recordingId)
        const timingPath: string = `${recorder.recordingDirectory()}/timings.tsv`
        writeTextFile(
          timingPath,
          '# page\tcategory\tblocks\tmatched\tanalysis_ms\trender_ms\ttotal_ms\n',
        )
        const translationTimingPath: string =
          `${recorder.recordingDirectory()}/translation-timings.tsv`
        if (liveTranslation) {
          writeTextFile(
            translationTimingPath,
            '# page\tblocks\ttranslation_ms\n',
          )
        }
        const backend: ComicLocalVisualBackend = new ComicLocalVisualBackend(
          mainContext,
          ocr,
          new ComicNcnnLocalRegionDetector(detectorPaths.paramPath, detectorPaths.modelPath),
          new ComicNcnnLocalTextRecognizer(
            recognizerPaths.paramPath,
            recognizerPaths.modelPath,
            recognizerPaths.dictionaryPath,
          ),
          new ComicNcnnLocalSourceInpainter(
            inpaintingPaths.paramPath,
            inpaintingPaths.modelPath,
            4,
          ),
          new ComicNcnnLocalTextMasker(
            textMaskPaths.paramPath,
            textMaskPaths.modelPath,
            0.3,
            4,
          ),
          new ComicNcnnLocalTextMasker(
            textMaskPaths.paramPath,
            textMaskPaths.modelPath,
            0.15,
            4,
            0.3,
          ),
          recorder,
        )
        let totalBlocks: number = 0
        let totalMatched: number = 0
        let candidatePages: number = 0
        let liveTranslationPages: number = 0
        let replayedPages: number = 0
        try {
          for (let pageIndex: number = 0; pageIndex < pages.length; pageIndex++) {
            if (selectedPageIndex >= 0 && pageIndex !== selectedPageIndex) {
              continue
            }
            replayedPages = replayedPages + 1
            const page: ExternalReplayPage = pages[pageIndex]
            if (liveTranslation && pageIndex === liveTranslationPageIndex) {
              stageLiveTranslationPage(mainContext, page)
            }
            const source: ComicVisualPageSource = pageSource(page, pageIndex, calibrationOnly)
            const analysisRequest: ComicRegionAnalysisRequest =
              new ComicRegionAnalysisRequest()
            analysisRequest.source = source
            analysisRequest.requestedRegionRevision = 2
            analysisRequest.requestedDocumentRevision = 2
            const analysisStartedAt: number = Date.now()
            const analysis: ComicRegionAnalysisResult = await backend.analyze(analysisRequest)
            const analysisMs: number = Date.now() - analysisStartedAt
            let renderAnalysis: ComicRegionAnalysisResult = analysis
            let candidatePage: CandidateGroupingPage | null = null
            let continuationAttachments: CandidateContinuationAttachment[] = []
            if (candidatePlan !== null) {
              candidatePage =
                candidateGroupingPage(candidatePlan, source)
              if (candidatePage !== null) {
                if (candidateContinuationMerge) {
                  continuationAttachments = candidateContinuationAttachments(
                    analysis,
                    candidatePage,
                  )
                }
                renderAnalysis = candidateGroupingAnalysis(
                  source,
                  analysis,
                  candidatePage,
                  continuationAttachments,
                )
                candidatePages = candidatePages + 1
              }
            }
            let replay: ReplayTranslationResult
            let translationMs: number = 0
            if (liveTranslation && pageIndex === liveTranslationPageIndex) {
              const request: ComicTextTranslationRequest = liveTranslationRequest(
                source,
                renderAnalysis,
                pageIndex + 1,
                liveTranslationSourceLanguage,
                liveTranslationTargetLanguage,
              )
              if (translationMode === 'export') {
                ComicTranslationDebugProbeService.exportRequest(
                  mainContext,
                  liveTranslationProbeId,
                  request,
                  translationInputMode,
                )
                replay = containerCalibrationTranslations(
                  source,
                  renderAnalysis,
                  pageIndex + 1,
                )
              } else {
                const imported: ComicTranslationDebugProbeResult =
                  ComicTranslationDebugProbeService.importResult(
                    mainContext,
                    liveTranslationProbeId,
                    request,
                    translationInputMode,
                  )
                replay = new ReplayTranslationResult()
                replay.batch = imported.result.batch
                replay.matchedBlocks = imported.result.batch.blocks.length
                translationMs = imported.elapsedMs
                if (candidateParentRender) {
                  if (candidatePage === null) {
                    throw new Error('Candidate parent render page is unavailable')
                  }
                  const parentAnalysis: ComicRegionAnalysisResult =
                    candidateParentRenderAnalysis(
                      source,
                      analysis,
                      continuationAttachments,
                    )
                  replay = candidateParentRenderTranslations(
                    parentAnalysis,
                    candidatePage,
                    replay.batch,
                  )
                  renderAnalysis = parentAnalysis
                }
              }
              liveTranslationPages = liveTranslationPages + 1
              if (translationMode === 'import') {
                appendTextFile(
                  translationTimingPath,
                  `${pageIndex}\t${renderAnalysis.document.blocks.length}\t${translationMs}\n`,
                )
              }
            } else if (calibrationOnly) {
              replay = containerCalibrationTranslations(
                source,
                renderAnalysis,
                pageIndex + 1,
              )
            } else {
              const candidate: ComicLocalOcrResult = await recognizeCapture(
                ocr,
                page.translatedCapturePath,
              )
              replay = replayTranslations(
                source,
                analysis,
                candidate,
                pageIndex + 1,
              )
            }
            totalBlocks = totalBlocks + renderAnalysis.document.blocks.length
            totalMatched = totalMatched + replay.matchedBlocks
            expect(renderAnalysis.document.blocks.length > 0).assertEqual(true)
            expect(replay.matchedBlocks > 0).assertEqual(true)
            const request: ComicRegionRenderRequest = renderRequest(
              backend,
              source,
              renderAnalysis,
              replay.batch,
              candidatePageFontNormalization,
              candidateVerticalContainerLayout,
            )
            const renderStartedAt: number = Date.now()
            const rendered: ComicRenderedPage = await backend.render(request)
            const renderMs: number = Date.now() - renderStartedAt
            appendTextFile(
              timingPath,
              `${pageIndex}\t${page.category}\t${renderAnalysis.document.blocks.length}\t` +
                `${replay.matchedBlocks}\t${analysisMs}\t${renderMs}\t` +
                `${analysisMs + renderMs}\n`,
            )
            ComicVisualTranslationContract.validateRenderedPage(request.identity, rendered)
            expect(rendered.width).assertEqual(page.width)
            expect(rendered.height).assertEqual(page.height)
            console.info(
              `ComicExternalReplay page=${pageIndex + 1}/${pages.length} ` +
                `mode=${calibrationOnly ? 'container-calibration' : 'translated-replay'} ` +
                `category=${page.category} blocks=${renderAnalysis.document.blocks.length} ` +
                `matched=${replay.matchedBlocks} candidateLines=${replay.candidateLines} ` +
                `analysisMs=${analysisMs} translationMs=${translationMs} ` +
                `renderMs=${renderMs} artifact=${rendered.localFilePath}`,
            )
          }
          console.info(
            `ComicExternalReplay summary pages=${replayedPages}/${pages.length} ` +
              `blocks=${totalBlocks} ` +
              `matched=${totalMatched} recording=${recorder.recordingDirectory()}`,
          )
          expect(totalMatched > 0).assertEqual(true)
          expect(replayedPages).assertEqual(selectedPageIndex >= 0 ? 1 : pages.length)
          if (candidatePlan !== null) {
            let expectedCandidatePages: number = candidatePlan.pages.length
            if (selectedPageIndex >= 0) {
              expectedCandidatePages = 0
              for (let index: number = 0; index < candidatePlan.pages.length; index++) {
                if (candidatePlan.pages[index].pageIndex === selectedPageIndex) {
                  expectedCandidatePages = 1
                }
              }
            }
            expect(candidatePages).assertEqual(expectedCandidatePages)
          }
          if (liveTranslation) {
            expect(liveTranslationPages).assertEqual(1)
          }
        } finally {
          await ocr.release()
        }
      })
  })
}
