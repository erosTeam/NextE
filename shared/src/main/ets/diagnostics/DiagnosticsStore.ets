import { DiagnosticsLogFormatter } from './DiagnosticsLogFormatter'
import { DiagnosticLogEntry, DiagnosticsRedactor } from './DiagnosticsRedactor'

const DEFAULT_MAX_ENTRIES: number = 500

export class DiagnosticsStore {
  private static entries: DiagnosticLogEntry[] = []
  private static maxEntries: number = DEFAULT_MAX_ENTRIES

  static append(entry: DiagnosticLogEntry): void {
    try {
      DiagnosticsStore.entries.push(DiagnosticsRedactor.sanitizeEvent(entry))
      if (DiagnosticsStore.entries.length > DiagnosticsStore.maxEntries) {
        DiagnosticsStore.entries = DiagnosticsStore.entries.slice(DiagnosticsStore.entries.length - DiagnosticsStore.maxEntries)
      }
    } catch (_error) {
    }
  }

  static snapshot(): DiagnosticLogEntry[] {
    try {
      return DiagnosticsStore.entries.slice()
    } catch (_error) {
      return []
    }
  }

  static clear(): void {
    DiagnosticsStore.entries = []
  }

  static exportText(): string {
    return DiagnosticsLogFormatter.formatEntries(DiagnosticsStore.snapshot())
  }

  static exportJsonlText(): string {
    return DiagnosticsLogFormatter.formatJsonlEntries(DiagnosticsStore.snapshot())
  }

  static count(): number {
    return DiagnosticsStore.entries.length
  }
}
