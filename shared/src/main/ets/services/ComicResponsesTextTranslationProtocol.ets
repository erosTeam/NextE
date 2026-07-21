import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import {
  ComicBlockTranslation,
  ComicTranslationBatch,
} from '../model/ComicVisualTranslation'
import {
  ComicTextTranslationRequest,
  ComicTextTranslationResult,
} from './ComicVisualTranslationBackend'
import { ComicVisualTranslationContract } from './ComicVisualTranslationContract'
import { ComicResponsesProtocol } from './ComicResponsesProtocol'

const MAX_COMIC_TEXT_TRANSLATION_PAYLOAD_CHARS: number = 2 * 1024 * 1024
const MAX_COMIC_TEXT_TRANSLATION_PROMPT_CHARS: number = 512 * 1024
const MAX_COMIC_TEXT_TRANSLATION_SUMMARY_CHARS: number = 4096
const MAX_COMIC_TEXT_TRANSLATION_TEXT_CHARS: number = 8192
const MAX_COMIC_TEXT_TRANSLATION_IDENTIFIER_CHARS: number = 160

class ComicTextPromptBlock {
  blockId: string = ''
  readingOrder: number = 0
  kind: string = ''
  sourceText: string = ''
  normalizedSourceText: string = ''
  speakerId: string = ''
  styleHint: string = ''
}

class RawComicBlockTranslation {
  blockId: string = ''
  translatedText: string = ''
}

class RawComicTextTranslationPayload {
  projectId: string = ''
  pageIndex: number = -1
  sourceImageHash: string = ''
  targetLanguage: string = ''
  pageSummary: string = ''
  blocks: RawComicBlockTranslation[] = []
}

/** Prompt and strict output protocol for translating sidecar-detected regions with the page image. */
export class ComicResponsesTextTranslationProtocol {
  static buildPrompt(request: ComicTextTranslationRequest): string {
    ComicVisualTranslationContract.validateTextTranslationRequest(request)
    const lines: string[] = []
    lines.push('Translate the detected text regions on this comic page.')
    lines.push('Use the attached full page image to resolve speakers, tone, references, and ambiguous OCR.')
    lines.push('The supplied block text and blockId list are authoritative; do not add, remove, merge, or split blocks.')
    lines.push('Return exactly one JSON object. Do not use Markdown fences or commentary.')
    lines.push('Every supplied blockId must appear exactly once with a non-empty translatedText.')
    lines.push('Follow locked glossary terms exactly and keep names, forms of address, and tone consistent with prior pages.')
    lines.push('Set pageSummary to a concise cumulative rolling summary that retains only essential plot, identity, relationship, and naming facts.')
    lines.push('Required JSON shape:')
    lines.push('{"projectId":"...","pageIndex":0,"sourceImageHash":"...",' +
      '"targetLanguage":"...","pageSummary":"...",' +
      '"blocks":[{"blockId":"p0-r0","translatedText":"..."}]}')
    const payloadLines: string[] = ComicResponsesTextTranslationProtocol.payloadLines(request)
    for (let index: number = 0; index < payloadLines.length; index++) {
      lines.push(payloadLines[index])
    }
    const prompt: string = lines.join('\n')
    if (prompt.length > MAX_COMIC_TEXT_TRANSLATION_PROMPT_CHARS) {
      throw new Error('Comic text translation prompt is too large')
    }
    return prompt
  }

  static contextFingerprint(request: ComicTextTranslationRequest): string {
    ComicVisualTranslationContract.validateTextTranslationRequest(request)
    const encoded: Uint8Array = new util.TextEncoder().encodeInto(
      JSON.stringify(ComicResponsesTextTranslationProtocol.payloadLines(request)),
    )
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: encoded })
    const digest: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < digest.length; index++) {
      parts.push(digest[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  static parse(
    request: ComicTextTranslationRequest,
    rawText: string,
    sourceProfileId: string,
    sourceRevision: number,
    modelId: string,
    promptVersion: string,
  ): ComicTextTranslationResult {
    ComicVisualTranslationContract.validateTextTranslationRequest(request)
    ComicResponsesTextTranslationProtocol.validateProviderIdentity(
      sourceProfileId,
      sourceRevision,
      modelId,
      promptVersion,
    )
    if (rawText.length <= 0 || rawText.length > MAX_COMIC_TEXT_TRANSLATION_PAYLOAD_CHARS) {
      throw new Error('Comic text translation payload size is invalid')
    }
    const raw: RawComicTextTranslationPayload =
      JSON.parse(rawText) as RawComicTextTranslationPayload
    if (typeof raw.projectId !== 'string' || raw.projectId !== request.source.projectId ||
      !Number.isFinite(raw.pageIndex) || Math.floor(raw.pageIndex) !== raw.pageIndex ||
      raw.pageIndex !== request.source.pageIndex ||
      typeof raw.sourceImageHash !== 'string' ||
      raw.sourceImageHash !== request.source.imageHash ||
      typeof raw.targetLanguage !== 'string' ||
      raw.targetLanguage !== request.context.targetLanguage) {
      throw new Error('Comic text translation output identity mismatch')
    }
    if (!Array.isArray(raw.blocks)) {
      throw new Error('Comic text translation output blocks are invalid')
    }

    const translatedById: Map<string, string> = new Map<string, string>()
    for (let index: number = 0; index < raw.blocks.length; index++) {
      const rawBlock: RawComicBlockTranslation = raw.blocks[index]
      const blockId: string = ComicResponsesTextTranslationProtocol.exactRequiredString(
        rawBlock.blockId,
        'block id',
        MAX_COMIC_TEXT_TRANSLATION_IDENTIFIER_CHARS,
      )
      const translatedText: string = ComicResponsesTextTranslationProtocol.requiredString(
        rawBlock.translatedText,
        'translated text',
        MAX_COMIC_TEXT_TRANSLATION_TEXT_CHARS,
      )
      if (translatedById.has(blockId)) {
        throw new Error('Comic text translation output has a duplicate block')
      }
      translatedById.set(blockId, translatedText)
    }

    const batch: ComicTranslationBatch = new ComicTranslationBatch()
    batch.projectId = request.source.projectId
    batch.pageIndex = request.source.pageIndex
    batch.sourceImageHash = request.source.imageHash
    batch.targetLanguage = request.context.targetLanguage
    batch.sourceProfileId = sourceProfileId
    batch.sourceRevision = sourceRevision
    batch.modelId = modelId
    batch.promptVersion = promptVersion
    batch.contextFingerprint = ComicResponsesTextTranslationProtocol.contextFingerprint(request)
    batch.glossaryRevision = request.context.glossaryRevision
    batch.translationRevision = request.requestedTranslationRevision
    for (let index: number = 0; index < request.document.blocks.length; index++) {
      const blockId: string = request.document.blocks[index].blockId
      const translatedText: string | undefined = translatedById.get(blockId)
      if (translatedText === undefined) {
        throw new Error('Comic text translation output is missing a block')
      }
      const block: ComicBlockTranslation = new ComicBlockTranslation()
      block.blockId = blockId
      block.translatedText = translatedText
      batch.blocks.push(block)
    }
    if (translatedById.size !== batch.blocks.length) {
      throw new Error('Comic text translation output contains an unknown block')
    }
    ComicVisualTranslationContract.validateTranslationBatch(request.document, batch)

    const result: ComicTextTranslationResult = new ComicTextTranslationResult()
    result.batch = batch
    result.pageSummary = ComicResponsesTextTranslationProtocol.boundedString(
      raw.pageSummary,
      'page summary',
      MAX_COMIC_TEXT_TRANSLATION_SUMMARY_CHARS,
    )
    return result
  }

  private static payloadLines(request: ComicTextTranslationRequest): string[] {
    const lines: string[] = []
    lines.push('Identity fields must be copied exactly:')
    lines.push('projectId=' + JSON.stringify(request.source.projectId))
    lines.push('pageIndex=' + request.source.pageIndex)
    lines.push('sourceImageHash=' + JSON.stringify(request.source.imageHash))
    lines.push('sourceLanguage=' + JSON.stringify(request.context.sourceLanguage))
    lines.push('targetLanguage=' + JSON.stringify(request.context.targetLanguage))
    lines.push('Detected text regions in reading order:')
    for (let index: number = 0; index < request.document.blocks.length; index++) {
      const source = request.document.blocks[index]
      const block: ComicTextPromptBlock = new ComicTextPromptBlock()
      block.blockId = source.blockId
      block.readingOrder = source.readingOrder
      block.kind = source.kind
      block.sourceText = source.sourceText
      block.normalizedSourceText = source.normalizedSourceText
      block.speakerId = source.speakerId
      block.styleHint = source.styleHint
      lines.push('- ' + JSON.stringify(block))
    }
    const contextLines: string[] = ComicResponsesProtocol.contextLines(
      request.context,
      request.source.pageIndex,
    )
    for (let index: number = 0; index < contextLines.length; index++) {
      lines.push(contextLines[index])
    }
    return lines
  }

  private static validateProviderIdentity(
    sourceProfileId: string,
    sourceRevision: number,
    modelId: string,
    promptVersion: string,
  ): void {
    ComicResponsesTextTranslationProtocol.exactRequiredString(
      sourceProfileId,
      'source profile id',
      MAX_COMIC_TEXT_TRANSLATION_IDENTIFIER_CHARS,
    )
    ComicResponsesTextTranslationProtocol.exactRequiredString(
      modelId,
      'model id',
      MAX_COMIC_TEXT_TRANSLATION_IDENTIFIER_CHARS,
    )
    ComicResponsesTextTranslationProtocol.exactRequiredString(
      promptVersion,
      'prompt version',
      MAX_COMIC_TEXT_TRANSLATION_IDENTIFIER_CHARS,
    )
    if (!Number.isFinite(sourceRevision) || sourceRevision <= 0 ||
      Math.floor(sourceRevision) !== sourceRevision) {
      throw new Error('Comic text translation source revision is invalid')
    }
  }

  private static exactRequiredString(value: string, field: string, maxChars: number): string {
    const normalized: string = ComicResponsesTextTranslationProtocol.requiredString(
      value,
      field,
      maxChars,
    )
    if (normalized !== value) {
      throw new Error('Comic text translation ' + field + ' must not contain outer whitespace')
    }
    return normalized
  }

  private static requiredString(value: string, field: string, maxChars: number): string {
    if (typeof value !== 'string') {
      throw new Error('Comic text translation ' + field + ' must be a string')
    }
    const normalized: string = value.trim()
    if (normalized.length <= 0 || value.length > maxChars) {
      throw new Error('Comic text translation ' + field + ' is invalid')
    }
    return normalized
  }

  private static boundedString(value: string, field: string, maxChars: number): string {
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value !== 'string' || value.length > maxChars) {
      throw new Error('Comic text translation ' + field + ' is invalid')
    }
    return value.trim()
  }
}
