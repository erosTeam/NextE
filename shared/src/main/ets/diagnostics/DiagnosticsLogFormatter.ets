import { DiagnosticLogEntry, DiagnosticsRedactor } from './DiagnosticsRedactor'

export class DiagnosticsLogFormatter {
  static formatEntry(entry: DiagnosticLogEntry): string {
    try {
      const safeEntry = DiagnosticsRedactor.sanitizeEvent(entry)
      const pieces: string[] = []
      pieces.push(DiagnosticsLogFormatter.formatTimestamp(safeEntry.ts))
      pieces.push('[' + DiagnosticsLogFormatter.levelLabel(safeEntry.level) + ']')
      pieces.push(DiagnosticsLogFormatter.safeName(safeEntry.category) + '.' + DiagnosticsLogFormatter.safeName(safeEntry.event))
      const message = DiagnosticsLogFormatter.cleanText(safeEntry.message)
      if (message.length > 0) {
        pieces.push(message)
      }
      return pieces.join(' ')
    } catch (_error) {
      return DiagnosticsLogFormatter.formatTimestamp(Date.now()) + ' [ERROR] diagnostics.format_error Diagnostic log format failed'
    }
  }

  static formatEntries(entries: DiagnosticLogEntry[]): string {
    try {
      return entries.map((entry: DiagnosticLogEntry) => DiagnosticsLogFormatter.formatEntry(entry)).join('\n')
    } catch (_error) {
      return ''
    }
  }

  static formatJsonlEntries(entries: DiagnosticLogEntry[]): string {
    try {
      return entries.map((entry: DiagnosticLogEntry) => JSON.stringify(DiagnosticsRedactor.sanitizeEvent(entry))).join('\n')
    } catch (_error) {
      return ''
    }
  }

  private static cleanText(value: string): string {
    return (value || '')
      .replace(/\r/g, ' ')
      .replace(/\n/g, ' ')
      .replace(/\t/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
  }

  private static levelLabel(level: string): string {
    const clean = (level || 'info').toUpperCase()
    if (clean === 'DEBUG' || clean === 'INFO' || clean === 'WARN' || clean === 'ERROR') {
      return clean
    }
    return 'INFO'
  }

  private static safeName(value: string): string {
    return DiagnosticsRedactor.safeToken(value || 'unknown')
  }

  private static formatTimestamp(ts: number): string {
    const date = new Date(ts > 0 ? ts : Date.now())
    const year = date.getFullYear().toString().padStart(4, '0')
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hour = date.getHours().toString().padStart(2, '0')
    const minute = date.getMinutes().toString().padStart(2, '0')
    const second = date.getSeconds().toString().padStart(2, '0')
    const millis = date.getMilliseconds().toString().padStart(3, '0')
    return `${year}-${month}-${day} ${hour}:${minute}:${second}.${millis}`
  }
}
