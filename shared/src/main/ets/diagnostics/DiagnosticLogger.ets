import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0xE001
const TAG: string = 'NextE'

/**
 * Structured diagnostics over native hilog (NOT a file-log hack — hilog is fully
 * visible via `hdc shell hilog | grep NextE`). Every line is category + event + message
 * so logs grep cleanly by subsystem. Sensitive values (cookies, pass_hash, igneous)
 * MUST be redacted by the caller before reaching here.
 */
export class DiagnosticLogger {
  static info(category: string, event: string, message: string): void {
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', category, event, message)
  }

  static warn(category: string, event: string, message: string): void {
    hilog.warn(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', category, event, message)
  }

  static error(category: string, event: string, message: string): void {
    hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', category, event, message)
  }

  static exception(category: string, event: string, err: Error): void {
    hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s | %{public}s', category, event, err.message)
  }
}
