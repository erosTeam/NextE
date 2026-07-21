const MAX_RESPONSES_TEXT_BODY_CHARS: number = 8 * 1024 * 1024

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
}

class RawResponsesStreamEvent {
  type: string = ''
  delta: string = ''
  item: RawResponsesOutputItem | null = null
  error: RawResponsesError | null = null
}

/** Extracts the final assistant text from either a JSON Responses payload or an SSE stream. */
export class ResponsesTextProtocol {
  static extract(body: string, eventStream: boolean): string {
    if (body.length === 0 || body.length > MAX_RESPONSES_TEXT_BODY_CHARS) {
      throw new Error('Responses provider response size is invalid')
    }
    const text: string = eventStream
      ? ResponsesTextProtocol.extractEventStreamText(body)
      : ResponsesTextProtocol.extractJsonResponseText(body)
    const normalized: string = text.trim()
    if (normalized.length === 0) {
      throw new Error('Responses provider returned empty output')
    }
    return normalized
  }

  private static extractJsonResponseText(body: string): string {
    const envelope: RawResponsesEnvelope = JSON.parse(body) as RawResponsesEnvelope
    if (!Array.isArray(envelope.output)) {
      throw new Error('Responses provider returned no output items')
    }
    return ResponsesTextProtocol.lastFinalMessageText(envelope.output)
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
        throw new Error('Responses stream failed (' + code + ')')
      }
      if (event.type === 'response.output_text.delta' && typeof event.delta === 'string') {
        deltas.push(event.delta)
      }
      if (event.type === 'response.output_item.done' && event.item !== null) {
        const candidate: string = ResponsesTextProtocol.outputItemText(event.item)
        const phase: string = typeof event.item.phase === 'string' ? event.item.phase.toLowerCase() : ''
        if (candidate.length > 0 && phase !== 'analysis' && phase !== 'commentary') {
          completedMessage = candidate
        }
      }
    }
    if (completedMessage.length > 0) {
      return completedMessage
    }
    return deltas.join('')
  }

  private static lastFinalMessageText(items: RawResponsesOutputItem[]): string {
    let result: string = ''
    for (let index: number = 0; index < items.length; index++) {
      const item: RawResponsesOutputItem = items[index]
      const phase: string = typeof item.phase === 'string' ? item.phase.toLowerCase() : ''
      if (phase === 'analysis' || phase === 'commentary') {
        continue
      }
      const candidate: string = ResponsesTextProtocol.outputItemText(item)
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
}
