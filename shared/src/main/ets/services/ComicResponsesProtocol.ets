import { ComicGlossaryTerm } from '../model/ComicTranslation'
import { ComicPageAnalysisRequest, ComicPreviousPageContext } from './ComicPageAnalyzer'

const MAX_COMIC_RESPONSES_BODY_CHARS: number = 8 * 1024 * 1024
const MAX_COMIC_PROMPT_CONTEXT_CHARS: number = 48000

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
    lines.push('Set polygon=[] for every block. Geometry is not requested in this text-only phase.')
    lines.push('Use sourceOrigin="vision". Use translationOrigin="vision" when translatedText is present, otherwise "none".')
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
    ComicResponsesProtocol.appendContextLine(lines, 'rollingSummary', request.context.rollingSummary)
    ComicResponsesProtocol.appendContextLine(lines, 'styleGuide', request.context.styleGuide)
    ComicResponsesProtocol.appendGlossary(lines, request.context.glossary)
    ComicResponsesProtocol.appendPreviousPages(lines, request.context.previousPages)
    const prompt: string = lines.join('\n')
    if (prompt.length > MAX_COMIC_PROMPT_CONTEXT_CHARS) {
      throw new Error('Comic analysis context is too large')
    }
    return prompt
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

  private static appendContextLine(lines: string[], label: string, value: string): void {
    const normalized: string = value.trim()
    if (normalized.length > 0) {
      lines.push(label + '=' + JSON.stringify(normalized))
    }
  }

  private static appendGlossary(lines: string[], glossary: ComicGlossaryTerm[]): void {
    if (glossary.length === 0) {
      return
    }
    lines.push('Glossary terms. Locked terms must be followed exactly:')
    for (let index: number = 0; index < glossary.length; index++) {
      const term: ComicGlossaryTerm = glossary[index]
      lines.push(
        '- source=' + JSON.stringify(term.sourceTerm) +
        ' target=' + JSON.stringify(term.targetTerm) +
        ' status=' + term.status +
        ' aliases=' + JSON.stringify(term.aliases),
      )
    }
  }

  private static appendPreviousPages(lines: string[], pages: ComicPreviousPageContext[]): void {
    if (pages.length === 0) {
      return
    }
    lines.push('Previous-page context for name, address, tone, and reference consistency:')
    for (let index: number = 0; index < pages.length; index++) {
      const page: ComicPreviousPageContext = pages[index]
      lines.push(
        '- pageIndex=' + page.pageIndex +
        ' source=' + JSON.stringify(page.sourceText) +
        ' translation=' + JSON.stringify(page.translatedText) +
        ' summary=' + JSON.stringify(page.pageSummary),
      )
    }
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
