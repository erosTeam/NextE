import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { DiagnosticLogEntry, DiagnosticsRedactor } from './DiagnosticsRedactor'
import { DiagnosticsLogFileSink } from './DiagnosticsLogFileSink'
import { DiagnosticsStore } from './DiagnosticsStore'

const DOMAIN: number = 0xE001
const TAG: string = 'NextE'
export type DiagnosticLogLevel = 'debug' | 'info' | 'warn' | 'error'

/**
 * Structured diagnostics over native hilog plus a redacted local retention sink.
 * Existing call sites keep using category + event + message; the logger owns
 * redaction and export safety so user feedback is not limited to live hilog capture.
 */
export class DiagnosticLogger {
  private static enabled: boolean = true
  private static minLevel: DiagnosticLogLevel = 'info'

  static configure(enabled: boolean, minLevel: string = 'info'): void {
    try {
      DiagnosticLogger.enabled = enabled
      DiagnosticLogger.minLevel = DiagnosticLogger.normalizeLevel(minLevel)
    } catch (_error) {
    }
  }

  static initializePersistentSink(context: common.UIAbilityContext): void {
    try {
      DiagnosticsLogFileSink.initialize(context)
    } catch (_error) {
    }
  }

  static closePersistentSink(): void {
    try {
      DiagnosticsLogFileSink.close()
    } catch (_error) {
    }
  }

  static debug(category: string, event: string, message: string): void {
    DiagnosticLogger.log('debug', category, event, message)
  }

  static info(category: string, event: string, message: string): void {
    DiagnosticLogger.log('info', category, event, message)
  }

  static warn(category: string, event: string, message: string): void {
    DiagnosticLogger.log('warn', category, event, message)
  }

  static error(category: string, event: string, message: string): void {
    DiagnosticLogger.log('error', category, event, message)
  }

  static exception(category: string, event: string, err: Error): void {
    DiagnosticLogger.log('error', category, event, err.message)
  }

  static exportText(): string {
    try {
      const latestFileText = DiagnosticsLogFileSink.exportLatestText()
      if (latestFileText.length > 0) {
        return latestFileText
      }
      return DiagnosticsStore.exportText()
    } catch (_error) {
      return ''
    }
  }

  static exportBufferedText(): string {
    try {
      return DiagnosticsStore.exportText()
    } catch (_error) {
      return ''
    }
  }

  static clear(): void {
    try {
      DiagnosticsStore.clear()
    } catch (_error) {
    }
  }

  static count(): number {
    try {
      return DiagnosticsStore.count()
    } catch (_error) {
      return 0
    }
  }

  static ownerHash(value: string): string {
    try {
      return DiagnosticsRedactor.ownerHash(value)
    } catch (_error) {
      return ''
    }
  }

  private static log(level: DiagnosticLogLevel, category: string, event: string, message: string): void {
    try {
      if (!DiagnosticLogger.enabled || !DiagnosticLogger.shouldLog(level)) {
        return
      }
      const entry: DiagnosticLogEntry = DiagnosticsRedactor.sanitizeEvent({
        ts: Date.now(),
        level: level,
        category: category,
        event: event,
        message: message,
      })
      DiagnosticsStore.append(entry)
      DiagnosticsLogFileSink.append(entry)
      DiagnosticLogger.hilogSink(entry)
    } catch (_error) {
      // Diagnostics must never affect app behavior.
    }
  }

  private static hilogSink(entry: DiagnosticLogEntry): void {
    if (entry.level === 'debug') {
      hilog.debug(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', entry.category, entry.event, entry.message)
      return
    }
    if (entry.level === 'warn') {
      hilog.warn(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', entry.category, entry.event, entry.message)
      return
    }
    if (entry.level === 'error') {
      hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', entry.category, entry.event, entry.message)
      return
    }
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', entry.category, entry.event, entry.message)
  }

  private static shouldLog(level: DiagnosticLogLevel): boolean {
    return DiagnosticLogger.levelRank(level) >= DiagnosticLogger.levelRank(DiagnosticLogger.minLevel)
  }

  private static levelRank(level: string): number {
    if (level === 'debug') {
      return 10
    }
    if (level === 'warn') {
      return 30
    }
    if (level === 'error') {
      return 40
    }
    return 20
  }

  private static normalizeLevel(level: string): DiagnosticLogLevel {
    if (level === 'debug' || level === 'info' || level === 'warn' || level === 'error') {
      return level
    }
    return 'info'
  }
}
