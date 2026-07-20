import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { ComicGlossaryTerm, ComicGlossaryTermStatus } from '../model/ComicTranslation'
import {
  ComicPageAnalysisRequest,
  ComicPreviousPageContext,
  ComicTranslationMemoryEntry,
} from './ComicPageAnalyzer'
import {
  ComicPreviousPageContextPolicy,
  MAX_COMIC_PREVIOUS_PAGE_CONTEXT,
} from './ComicPreviousPageContextPolicy'

const MAX_COMIC_RESPONSES_BODY_CHARS: number = 8 * 1024 * 1024
const MAX_COMIC_PROMPT_CONTEXT_CHARS: number = 48000
const MAX_ROLLING_SUMMARY_LINE_CHARS: number = 5000
const MAX_STYLE_GUIDE_LINE_CHARS: number = 2000
const MAX_GLOSSARY_SECTION_CHARS: number = 7000
const MAX_GLOSSARY_TERM_LINE_CHARS: number = 900
const MAX_GLOSSARY_FIELD_JSON_CHARS: number = 256
const MAX_GLOSSARY_ALIASES_JSON_CHARS: number = 320
const MAX_GLOSSARY_ALIASES: number = 16
const MAX_GLOSSARY_ALIAS_CHARS: number = 96
const MAX_TRANSLATION_MEMORY_SECTION_CHARS: number = 1800
const MAX_TRANSLATION_MEMORY_SOURCE_JSON_CHARS: number = 420
const MAX_TRANSLATION_MEMORY_TARGET_JSON_CHARS: number = 840
const MAX_PREVIOUS_PAGE_LINE_CHARS: number = 15000
const MAX_PREVIOUS_SOURCE_JSON_CHARS: number = 6000
const MAX_PREVIOUS_TRANSLATION_JSON_CHARS: number = 6000
const MAX_PREVIOUS_SUMMARY_JSON_CHARS: number = 2500

class RawResponsesContentPart {
  type: string = ''
  text: string = ''
}

class RawResponsesOutputItem {
  type: string = ''
  phase: string = ''
  content: RawResponsesContentPart[] = []
}

class RawResponsesEnvelope {
  output: RawResponsesOutputItem[] | null = []
}

class RawResponsesError {
  code: string = ''
  message: string = ''
}

class RawResponsesStreamEvent {
  type: string = ''
  delta: string = ''
  item: RawResponsesOutputItem | null = null
  error: RawResponsesError | null = null
}

export class ComicResponsesProtocol {
  static buildPrompt(request: ComicPageAnalysisRequest): string {
    const lines: string[] = []
    lines.push('Analyze this single comic page and translate its visible text.')
    lines.push('Return exactly one JSON object. Do not use Markdown fences or commentary.')
    lines.push('Preserve every visible text block in reading order; do not invent unreadable text.')
    lines.push('When text or order is uncertain, add a qualitySignals entry instead of guessing silently.')
    lines.push('Set pageSummary to a concise cumulative rolling summary: update the supplied rollingSummary and ' +
      'previous-page facts with only essential current-page plot, identity, relationship, and naming facts.')
    lines.push('Keep pageSummary short and do not copy the transcript into it.')
    lines.push('Set polygon=[] for every block. Geometry is not requested in this text-only phase.')
    lines.push('Use sourceOrigin="vision". Use translationOrigin="vision" when translatedText is present, otherwise "none".')
    lines.push('For every block with translatedText="", set translationOrigin="none". Never use "none" when translatedText is non-empty.')
    lines.push('Allowed kind values: dialogue, narration, sfx, annotation, other.')
    lines.push('Allowed quality severity values: info, warning, error.')
    lines.push('Required JSON shape:')
    lines.push('{"schemaVersion":1,"projectId":"...","pageIndex":0,"imageHash":"...",' +
      '"imageWidth":1,"imageHeight":1,"hasText":true,"pageSummary":"...",' +
      '"blocks":[{"blockId":"p0-b0","readingOrder":0,"kind":"dialogue",' +
      '"sourceText":"...","normalizedSourceText":"...","translatedText":"...",' +
      '"polygon":[],"speakerId":"","styleHint":"","sourceOrigin":"vision",' +
      '"translationOrigin":"vision","providerConfidence":null}],' +
      '"qualitySignals":[{"code":"uncertain_text","severity":"warning",' +
      '"blockId":"p0-b0","message":"..."}]}')
    lines.push('Identity fields must be copied exactly:')
    lines.push('projectId=' + JSON.stringify(request.projectId))
    lines.push('pageIndex=' + request.pageIndex)
    lines.push('imageHash=' + JSON.stringify(request.imageHash))
    lines.push('imageWidth=' + request.sourceWidth)
    lines.push('imageHeight=' + request.sourceHeight)
    lines.push('sourceLanguage=' + JSON.stringify(request.context.sourceLanguage))
    lines.push('targetLanguage=' + JSON.stringify(request.context.targetLanguage))
    const contextLines: string[] = ComicResponsesProtocol.contextLines(request)
    for (let index: number = 0; index < contextLines.length; index++) {
      lines.push(contextLines[index])
    }
    const prompt: string = lines.join('\n')
    if (prompt.length > MAX_COMIC_PROMPT_CONTEXT_CHARS) {
      throw new Error('Comic analysis context is too large')
    }
    return prompt
  }

  static contextFingerprint(request: ComicPageAnalysisRequest): string {
    const encoded: Uint8Array = new util.TextEncoder().encodeInto(
      JSON.stringify(ComicResponsesProtocol.contextLines(request)),
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

  private static contextLines(request: ComicPageAnalysisRequest): string[] {
    const lines: string[] = []
    ComicResponsesProtocol.appendContextLine(
      lines,
      'rollingSummary',
      request.context.rollingSummary,
      MAX_ROLLING_SUMMARY_LINE_CHARS,
    )
    ComicResponsesProtocol.appendContextLine(
      lines,
      'styleGuide',
      request.context.styleGuide,
      MAX_STYLE_GUIDE_LINE_CHARS,
    )
    ComicResponsesProtocol.appendGlossary(lines, request.context.glossary)
    ComicResponsesProtocol.appendTranslationMemory(lines, request.context.translationMemory)
    ComicResponsesProtocol.appendPreviousPages(
      lines,
      ComicPreviousPageContextPolicy.normalize(request.context.previousPages, request.pageIndex),
    )
    return lines
  }

  static extractAssistantJson(body: string, eventStream: boolean): string {
    if (body.length === 0 || body.length > MAX_COMIC_RESPONSES_BODY_CHARS) {
      throw new Error('Comic provider response size is invalid')
    }
    const text: string = eventStream
      ? ComicResponsesProtocol.extractEventStreamText(body)
      : ComicResponsesProtocol.extractJsonResponseText(body)
    return ComicResponsesProtocol.normalizeJsonText(text)
  }

  private static appendContextLine(
    lines: string[],
    label: string,
    value: string,
    maxLineChars: number,
  ): void {
    const normalized: string = value.trim()
    if (normalized.length > 0) {
      const valueBudget: number = Math.max(2, maxLineChars - label.length - 1)
      lines.push(label + '=' + ComicResponsesProtocol.boundedJsonString(normalized, valueBudget))
    }
  }

  private static appendGlossary(lines: string[], glossary: ComicGlossaryTerm[]): void {
    if (glossary.length === 0) {
      return
    }
    const header: string = 'Glossary terms. Locked terms must be followed exactly:'
    lines.push(header)
    let sectionChars: number = header.length
    let appended: number = 0
    for (let pass: number = 0; pass < 2; pass++) {
      const expectedStatus: ComicGlossaryTermStatus = pass === 0
        ? ComicGlossaryTermStatus.LOCKED
        : ComicGlossaryTermStatus.PROVISIONAL
      for (let index: number = 0; index < glossary.length; index++) {
        const term: ComicGlossaryTerm = glossary[index]
        if (term.status !== expectedStatus) {
          continue
        }
        const line: string = ComicResponsesProtocol.glossaryLine(term)
        if (sectionChars + line.length + 1 > MAX_GLOSSARY_SECTION_CHARS) {
          continue
        }
        lines.push(line)
        sectionChars += line.length + 1
        appended++
      }
    }
    if (appended < glossary.length) {
      const omitted: string = '- additional glossary terms omitted by prompt budget'
      if (sectionChars + omitted.length + 1 <= MAX_GLOSSARY_SECTION_CHARS) {
        lines.push(omitted)
      }
    }
  }

  private static appendPreviousPages(lines: string[], pages: ComicPreviousPageContext[]): void {
    if (pages.length === 0) {
      return
    }
    lines.push('Previous-page context for name, address, tone, and reference consistency:')
    const startIndex: number = Math.max(0, pages.length - MAX_COMIC_PREVIOUS_PAGE_CONTEXT)
    for (let index: number = startIndex; index < pages.length; index++) {
      const page: ComicPreviousPageContext = pages[index]
      const line: string =
        '- pageIndex=' + page.pageIndex +
        ' source=' + ComicResponsesProtocol.boundedJsonString(
          page.sourceText,
          MAX_PREVIOUS_SOURCE_JSON_CHARS,
        ) +
        ' translation=' + ComicResponsesProtocol.boundedJsonString(
          page.translatedText,
          MAX_PREVIOUS_TRANSLATION_JSON_CHARS,
        ) +
        ' summary=' + ComicResponsesProtocol.boundedJsonString(
          page.pageSummary,
          MAX_PREVIOUS_SUMMARY_JSON_CHARS,
        )
      if (line.length > MAX_PREVIOUS_PAGE_LINE_CHARS) {
        throw new Error('Comic previous-page context budget is invalid')
      }
      lines.push(line)
    }
  }

  private static appendTranslationMemory(
    lines: string[],
    entries: ComicTranslationMemoryEntry[],
  ): void {
    if (entries.length === 0) {
      return
    }
    const header: string = 'Generated exact-match translation memory from repeated prior pages. ' +
      'Apply only when normalized source text is exactly equal; glossary terms take priority:'
    const memoryLines: string[] = []
    let sectionChars: number = header.length
    for (let index: number = 0; index < entries.length; index++) {
      const source: string = JSON.stringify(entries[index].sourceText)
      const translated: string = JSON.stringify(entries[index].translatedText)
      if (source.length > MAX_TRANSLATION_MEMORY_SOURCE_JSON_CHARS ||
        translated.length > MAX_TRANSLATION_MEMORY_TARGET_JSON_CHARS) {
        continue
      }
      const line: string = '- source=' + source + ' translation=' + translated +
        ' firstSeenPageIndex=' + entries[index].firstSeenPageIndex +
        ' occurrences=' + entries[index].occurrenceCount
      if (sectionChars + line.length + 1 > MAX_TRANSLATION_MEMORY_SECTION_CHARS) {
        continue
      }
      memoryLines.push(line)
      sectionChars += line.length + 1
    }
    if (memoryLines.length === 0) {
      return
    }
    lines.push(header)
    for (let index: number = 0; index < memoryLines.length; index++) {
      lines.push(memoryLines[index])
    }
  }

  private static glossaryLine(term: ComicGlossaryTerm): string {
    const line: string =
      '- source=' + ComicResponsesProtocol.boundedJsonString(
        term.sourceTerm,
        MAX_GLOSSARY_FIELD_JSON_CHARS,
      ) +
      ' target=' + ComicResponsesProtocol.boundedJsonString(
        term.targetTerm,
        MAX_GLOSSARY_FIELD_JSON_CHARS,
      ) +
      ' status=' + term.status +
      ' aliases=' + ComicResponsesProtocol.boundedAliases(term.aliases)
    if (line.length > MAX_GLOSSARY_TERM_LINE_CHARS) {
      throw new Error('Comic glossary context budget is invalid')
    }
    return line
  }

  private static boundedAliases(aliases: string[]): string {
    const bounded: string[] = []
    const count: number = Math.min(MAX_GLOSSARY_ALIASES, aliases.length)
    for (let index: number = 0; index < count; index++) {
      bounded.push(ComicResponsesProtocol.boundedText(
        aliases[index],
        MAX_GLOSSARY_ALIAS_CHARS,
      ))
      const encoded: string = JSON.stringify(bounded)
      if (encoded.length > MAX_GLOSSARY_ALIASES_JSON_CHARS) {
        bounded.pop()
        break
      }
    }
    return JSON.stringify(bounded)
  }

  private static boundedJsonString(value: string, maxEncodedChars: number): string {
    if (value.length <= maxEncodedChars - 2) {
      const full: string = JSON.stringify(value)
      if (full.length <= maxEncodedChars) {
        return full
      }
    }
    let low: number = 0
    let high: number = Math.min(value.length, Math.max(0, maxEncodedChars - 3))
    let best: string = JSON.stringify('…')
    while (low <= high) {
      const middle: number = Math.floor((low + high) / 2)
      const candidate: string = JSON.stringify(value.substring(0, middle) + '…')
      if (candidate.length <= maxEncodedChars) {
        best = candidate
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    return best
  }

  private static boundedText(value: string, maxChars: number): string {
    if (value.length <= maxChars) {
      return value
    }
    return value.substring(0, Math.max(0, maxChars - 1)) + '…'
  }

  private static extractJsonResponseText(body: string): string {
    const envelope: RawResponsesEnvelope = JSON.parse(body) as RawResponsesEnvelope
    if (!Array.isArray(envelope.output)) {
      throw new Error('Comic provider returned no output items')
    }
    const text: string = ComicResponsesProtocol.lastFinalMessageText(envelope.output)
    if (text.length === 0) {
      throw new Error('Comic provider returned empty output')
    }
    return text
  }

  private static extractEventStreamText(body: string): string {
    const lines: string[] = body.split(/\r?\n/)
    const deltas: string[] = []
    let completedMessage: string = ''
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index].trim()
      if (!line.startsWith('data:')) {
        continue
      }
      const payload: string = line.substring(5).trim()
      if (payload.length === 0 || payload === '[DONE]') {
        continue
      }
      const event: RawResponsesStreamEvent = JSON.parse(payload) as RawResponsesStreamEvent
      if (event.type === 'error') {
        const code: string = event.error !== null && typeof event.error.code === 'string'
          ? event.error.code
          : 'unknown'
        throw new Error('Codex response stream failed (' + code + ')')
      }
      if (event.type === 'response.output_text.delta' && typeof event.delta === 'string') {
        deltas.push(event.delta)
      }
      if (event.type === 'response.output_item.done' && event.item !== null) {
        const candidate: string = ComicResponsesProtocol.outputItemText(event.item)
        const phase: string = typeof event.item.phase === 'string' ? event.item.phase.toLowerCase() : ''
        if (candidate.length > 0 && phase !== 'analysis' && phase !== 'commentary') {
          completedMessage = candidate
        }
      }
    }
    if (completedMessage.length > 0) {
      return completedMessage
    }
    const streamed: string = deltas.join('')
    if (streamed.length === 0) {
      throw new Error('Codex response stream returned empty output')
    }
    return streamed
  }

  private static lastFinalMessageText(items: RawResponsesOutputItem[]): string {
    let result: string = ''
    for (let index: number = 0; index < items.length; index++) {
      const item: RawResponsesOutputItem = items[index]
      const phase: string = typeof item.phase === 'string' ? item.phase.toLowerCase() : ''
      if (phase === 'analysis' || phase === 'commentary') {
        continue
      }
      const candidate: string = ComicResponsesProtocol.outputItemText(item)
      if (candidate.length > 0) {
        result = candidate
      }
    }
    return result
  }

  private static outputItemText(item: RawResponsesOutputItem): string {
    if (item.type !== 'message' || !Array.isArray(item.content)) {
      return ''
    }
    const parts: string[] = []
    for (let index: number = 0; index < item.content.length; index++) {
      const part: RawResponsesContentPart = item.content[index]
      if (part.type === 'output_text' && typeof part.text === 'string') {
        parts.push(part.text)
      }
    }
    return parts.join('')
  }

  private static normalizeJsonText(value: string): string {
    let normalized: string = value.trim()
    if (normalized.startsWith('```')) {
      const firstLineEnd: number = normalized.indexOf('\n')
      const fenceEnd: number = normalized.lastIndexOf('```')
      if (firstLineEnd >= 0 && fenceEnd > firstLineEnd) {
        normalized = normalized.substring(firstLineEnd + 1, fenceEnd).trim()
      }
    }
    const objectStart: number = normalized.indexOf('{')
    const objectEnd: number = normalized.lastIndexOf('}')
    if (objectStart >= 0 && objectEnd >= objectStart) {
      normalized = normalized.substring(objectStart, objectEnd + 1)
    }
    if (normalized.length === 0) {
      throw new Error('Comic provider returned no JSON document')
    }
    return normalized
  }
}
