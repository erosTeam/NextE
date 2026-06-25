import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { DiagnosticLogEntry, DiagnosticsRedactor } from './DiagnosticsRedactor'
import { DiagnosticsLogFormatter } from './DiagnosticsLogFormatter'

export const DIAGNOSTICS_LOG_DIR: string = 'diagnostics_logs'
export const DIAGNOSTICS_LOG_PREFIX: string = 'nexte-log-'
export const DIAGNOSTICS_LOG_SUFFIX: string = '.txt'
export const DIAGNOSTICS_LOG_KEEP_COUNT: number = 12
export const DIAGNOSTICS_LOG_MAX_AGE_DAYS: number = 14
export const DIAGNOSTICS_LOG_MAX_TOTAL_BYTES: number = 8 * 1024 * 1024

export interface DiagnosticsLogFileInfo {
  fileName: string
  filePath: string
  directory: string
  uri: string
  sizeBytes: number
  createdAtMs: number
  isCurrent: boolean
}

export class DiagnosticsLogFileSink {
  private static directory: string = ''
  private static currentFileName: string = ''
  private static currentFilePath: string = ''
  private static disabled: boolean = false
  private static initialized: boolean = false

  static initialize(context: common.UIAbilityContext): void {
    try {
      const filesDir = DiagnosticsLogFileSink.nonEmptyDir(context.filesDir)
      if (filesDir.length <= 0) {
        DiagnosticsLogFileSink.disableMemoryOnly()
        return
      }
      DiagnosticsLogFileSink.directory = filesDir + '/' + DIAGNOSTICS_LOG_DIR
      DiagnosticsLogFileSink.ensureDirectory(DiagnosticsLogFileSink.directory)
      DiagnosticsLogFileSink.currentFileName = DiagnosticsLogFileSink.createUniqueFileName(DiagnosticsLogFileSink.directory, new Date())
      DiagnosticsLogFileSink.currentFilePath = DiagnosticsLogFileSink.directory + '/' + DiagnosticsLogFileSink.currentFileName
      DiagnosticsLogFileSink.writeTextFile(DiagnosticsLogFileSink.currentFilePath, '', true)
      DiagnosticsLogFileSink.initialized = true
      DiagnosticsLogFileSink.disabled = false
      DiagnosticsLogFileSink.pruneRetainedLogs()
    } catch (_error) {
      DiagnosticsLogFileSink.disableMemoryOnly()
    }
  }

  static append(entry: DiagnosticLogEntry): void {
    try {
      if (DiagnosticsLogFileSink.disabled || !DiagnosticsLogFileSink.initialized || DiagnosticsLogFileSink.currentFilePath.length <= 0) {
        return
      }
      const safeEntry = DiagnosticsRedactor.sanitizeEvent(entry)
      DiagnosticsLogFileSink.writeTextFile(
        DiagnosticsLogFileSink.currentFilePath,
        DiagnosticsLogFormatter.formatEntry(safeEntry) + '\n',
        false,
      )
    } catch (_error) {
      DiagnosticsLogFileSink.disabled = true
    }
  }

  static exportLatestText(): string {
    try {
      const path = DiagnosticsLogFileSink.latestLogPath()
      if (path.length <= 0) {
        return ''
      }
      return fileIo.readTextSync(path)
    } catch (_error) {
      return ''
    }
  }

  static currentInfo(): DiagnosticsLogFileInfo | null {
    try {
      if (!DiagnosticsLogFileSink.initialized || DiagnosticsLogFileSink.currentFileName.length <= 0) {
        return null
      }
      return DiagnosticsLogFileSink.infoForName(DiagnosticsLogFileSink.currentFileName)
    } catch (_error) {
      return null
    }
  }

  static listRetainedLogFiles(): DiagnosticsLogFileInfo[] {
    try {
      if (DiagnosticsLogFileSink.directory.length <= 0) {
        return []
      }
      return DiagnosticsLogFileSink.listSafeLogNames().sort().reverse().map((name: string): DiagnosticsLogFileInfo => {
        return DiagnosticsLogFileSink.infoForName(name)
      })
    } catch (_error) {
      return []
    }
  }

  static readLogFileText(fileName: string): string {
    try {
      if (DiagnosticsLogFileSink.directory.length <= 0 || !DiagnosticsLogFileSink.isDiagnosticsLogFileName(fileName)) {
        return ''
      }
      return fileIo.readTextSync(DiagnosticsLogFileSink.directory + '/' + fileName)
    } catch (_error) {
      return ''
    }
  }

  static close(): void {
    try {
      DiagnosticsLogFileSink.pruneRetainedLogs()
    } catch (_error) {
    }
  }

  static isDiagnosticsLogFileName(fileName: string): boolean {
    if (!fileName.startsWith(DIAGNOSTICS_LOG_PREFIX) || !fileName.endsWith(DIAGNOSTICS_LOG_SUFFIX)) {
      return false
    }
    if (fileName.includes('/') || fileName.includes('\\') || fileName.includes('..')) {
      return false
    }
    const middle = fileName.substring(DIAGNOSTICS_LOG_PREFIX.length, fileName.length - DIAGNOSTICS_LOG_SUFFIX.length)
    const baseLength = 'YYYYMMDD-HHMMSS'.length
    if (middle.length !== baseLength && (middle.length <= baseLength + 1 || middle.charAt(baseLength) !== '-')) {
      return false
    }
    if (middle.charAt(8) !== '-') {
      return false
    }
    const timestampDigits = middle.substring(0, 8) + middle.substring(9, 15)
    if (!DiagnosticsLogFileSink.allDigits(timestampDigits)) {
      return false
    }
    if (middle.length > baseLength) {
      const suffix = middle.substring(baseLength + 1)
      if (suffix.length <= 0 || !DiagnosticsLogFileSink.allDigits(suffix)) {
        return false
      }
    }
    return true
  }

  private static infoForName(name: string): DiagnosticsLogFileInfo {
    const path = DiagnosticsLogFileSink.directory + '/' + name
    return {
      fileName: name,
      filePath: path,
      directory: DiagnosticsLogFileSink.directory,
      uri: fileUri.getUriFromPath(path),
      sizeBytes: DiagnosticsLogFileSink.approxFileBytes(path),
      createdAtMs: DiagnosticsLogFileSink.createdAtMsFromFileName(name),
      isCurrent: name === DiagnosticsLogFileSink.currentFileName,
    }
  }

  private static latestLogPath(): string {
    if (DiagnosticsLogFileSink.currentFilePath.length > 0 && DiagnosticsLogFileSink.fileExists(DiagnosticsLogFileSink.currentFilePath)) {
      return DiagnosticsLogFileSink.currentFilePath
    }
    if (DiagnosticsLogFileSink.directory.length <= 0) {
      return ''
    }
    const names = DiagnosticsLogFileSink.listSafeLogNames().sort().reverse()
    if (names.length <= 0) {
      return ''
    }
    return DiagnosticsLogFileSink.directory + '/' + names[0]
  }

  private static pruneRetainedLogs(): void {
    if (DiagnosticsLogFileSink.directory.length <= 0) {
      return
    }
    const names = DiagnosticsLogFileSink.listSafeLogNames().sort().reverse()
    const now = Date.now()
    let totalBytes = 0
    names.forEach((name: string, index: number) => {
      const path = DiagnosticsLogFileSink.directory + '/' + name
      const protectedCurrent = name === DiagnosticsLogFileSink.currentFileName
      const ageExpired = DiagnosticsLogFileSink.fileAgeMs(name, now) > DIAGNOSTICS_LOG_MAX_AGE_DAYS * 24 * 60 * 60 * 1000
      const size = DiagnosticsLogFileSink.approxFileBytes(path)
      totalBytes += size
      if (protectedCurrent) {
        return
      }
      if (index >= DIAGNOSTICS_LOG_KEEP_COUNT || ageExpired || totalBytes > DIAGNOSTICS_LOG_MAX_TOTAL_BYTES) {
        DiagnosticsLogFileSink.unlinkBestEffort(path)
      }
    })
  }

  private static listSafeLogNames(): string[] {
    try {
      return fileIo.listFileSync(DiagnosticsLogFileSink.directory)
        .filter((name: string) => DiagnosticsLogFileSink.isDiagnosticsLogFileName(name))
    } catch (_error) {
      return []
    }
  }

  private static createUniqueFileName(directory: string, date: Date): string {
    const stem = DiagnosticsLogFileSink.timestampStem(date)
    for (let attempt = 0; attempt < 100; attempt += 1) {
      const suffix = attempt === 0 ? '' : '-' + attempt.toString().padStart(2, '0')
      const candidate = DIAGNOSTICS_LOG_PREFIX + stem + suffix + DIAGNOSTICS_LOG_SUFFIX
      if (!DiagnosticsLogFileSink.fileExists(directory + '/' + candidate)) {
        return candidate
      }
    }
    return DIAGNOSTICS_LOG_PREFIX + stem + '-' + Date.now().toString() + DIAGNOSTICS_LOG_SUFFIX
  }

  private static timestampStem(date: Date): string {
    const year = date.getFullYear().toString().padStart(4, '0')
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hour = date.getHours().toString().padStart(2, '0')
    const minute = date.getMinutes().toString().padStart(2, '0')
    const second = date.getSeconds().toString().padStart(2, '0')
    return `${year}${month}${day}-${hour}${minute}${second}`
  }

  private static fileAgeMs(fileName: string, now: number): number {
    const createdAtMs = DiagnosticsLogFileSink.createdAtMsFromFileName(fileName)
    if (createdAtMs <= 0) {
      return 0
    }
    return Math.max(0, now - createdAtMs)
  }

  private static createdAtMsFromFileName(fileName: string): number {
    try {
      const middle = fileName.substring(DIAGNOSTICS_LOG_PREFIX.length, DIAGNOSTICS_LOG_PREFIX.length + 'YYYYMMDD-HHMMSS'.length)
      const year = Number(middle.substring(0, 4))
      const month = Number(middle.substring(4, 6)) - 1
      const day = Number(middle.substring(6, 8))
      const hour = Number(middle.substring(9, 11))
      const minute = Number(middle.substring(11, 13))
      const second = Number(middle.substring(13, 15))
      return new Date(year, month, day, hour, minute, second).getTime()
    } catch (_error) {
      return 0
    }
  }

  private static approxFileBytes(path: string): number {
    try {
      return DiagnosticsLogFileSink.byteLength(fileIo.readTextSync(path))
    } catch (_error) {
      return 0
    }
  }

  private static byteLength(value: string): number {
    let bytes = 0
    for (let i = 0; i < value.length; i += 1) {
      const code = value.charCodeAt(i)
      if (code <= 0x7F) {
        bytes += 1
      } else if (code <= 0x7FF) {
        bytes += 2
      } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
        bytes += 4
        i += 1
      } else {
        bytes += 3
      }
    }
    return bytes
  }

  private static ensureDirectory(directory: string): void {
    try {
      fileIo.mkdirSync(directory, true)
    } catch (_error) {
      fileIo.listFileSync(directory)
    }
  }

  private static writeTextFile(path: string, text: string, truncate: boolean): void {
    let file: fileIo.File | null = null
    try {
      const mode = truncate ?
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC :
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND
      file = fileIo.openSync(path, mode)
      fileIo.writeSync(file.fd, text)
    } finally {
      DiagnosticsLogFileSink.closeFileBestEffort(file)
    }
  }

  private static closeFileBestEffort(file: fileIo.File | null): void {
    if (!file) {
      return
    }
    try {
      fileIo.closeSync(file)
    } catch (_error) {
    }
  }

  private static fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (_error) {
      return false
    }
  }

  private static unlinkBestEffort(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {
    }
  }

  private static disableMemoryOnly(): void {
    DiagnosticsLogFileSink.disabled = true
    DiagnosticsLogFileSink.initialized = false
    DiagnosticsLogFileSink.currentFileName = ''
    DiagnosticsLogFileSink.currentFilePath = ''
  }

  private static nonEmptyDir(value: string): string {
    let clean = (value || '').trim()
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1)
    }
    return clean
  }

  private static allDigits(value: string): boolean {
    if (value.length <= 0) {
      return false
    }
    for (let i = 0; i < value.length; i += 1) {
      const code = value.charCodeAt(i)
      if (code < 48 || code > 57) {
        return false
      }
    }
    return true
  }
}
