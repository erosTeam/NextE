import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { CacheStat } from './CacheStat'

const TORII_CONTEXT_RECORD_VERSION: number = 1
const TORII_CONTEXT_CACHE_DIR: string = 'comic-torii-context'
const MAX_TORII_CONTEXT_CHARS: number = 10000
const MAX_TORII_CONTEXT_RECORD_CHARS: number = 16 * 1024
const MAX_TORII_CONTEXT_RECORDS: number = 128

export class ToriiWholePageContextScope {
  projectId: string = ''
  pageIndex: number = -1
  targetLanguage: string = ''
  sourceProfileId: string = ''
  sourceRevision: number = 0
  modelId: string = ''
  promptVersion: string = ''

  copy(): ToriiWholePageContextScope {
    const value: ToriiWholePageContextScope = new ToriiWholePageContextScope()
    value.projectId = this.projectId
    value.pageIndex = this.pageIndex
    value.targetLanguage = this.targetLanguage
    value.sourceProfileId = this.sourceProfileId
    value.sourceRevision = this.sourceRevision
    value.modelId = this.modelId
    value.promptVersion = this.promptVersion
    return value
  }

  assertValid(): void {
    if (!ToriiWholePageContextStore.identifier(this.projectId) ||
      !ToriiWholePageContextStore.nonNegativeInteger(this.pageIndex) ||
      !ToriiWholePageContextStore.identifier(this.targetLanguage) ||
      !ToriiWholePageContextStore.identifier(this.sourceProfileId) ||
      !ToriiWholePageContextStore.positiveInteger(this.sourceRevision) ||
      !ToriiWholePageContextStore.identifier(this.modelId) ||
      !ToriiWholePageContextStore.identifier(this.promptVersion)) {
      throw new Error('Torii context scope is invalid')
    }
  }

  chainKey(): string {
    this.assertValid()
    return JSON.stringify([
      this.projectId,
      this.targetLanguage,
      this.sourceProfileId,
      `${this.sourceRevision}`,
      this.modelId,
      this.promptVersion,
    ])
  }
}

class ToriiWholePageContextRecord {
  version: number = TORII_CONTEXT_RECORD_VERSION
  chainKey: string = ''
  scope: ToriiWholePageContextScope = new ToriiWholePageContextScope()
  context: string = ''
  createdAt: number = 0
}

/** Regenerable, device-local continuation context returned by Torii after each page. */
export class ToriiWholePageContextStore {
  private readonly context: common.UIAbilityContext

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  async loadPrevious(scope: ToriiWholePageContextScope): Promise<string> {
    scope.assertValid()
    const chainKey: string = scope.chainKey()
    const records: ToriiWholePageContextRecord[] = this.records()
    let previous: ToriiWholePageContextRecord | null = null
    for (let index: number = 0; index < records.length; index++) {
      const record: ToriiWholePageContextRecord = records[index]
      if (record.chainKey === chainKey && record.scope.pageIndex < scope.pageIndex &&
        (previous === null || record.scope.pageIndex > previous.scope.pageIndex)) {
        previous = record
      }
    }
    return previous?.context ?? ''
  }

  async save(scope: ToriiWholePageContextScope, providerContext: string): Promise<void> {
    scope.assertValid()
    const normalized: string = providerContext.trim()
    if (normalized.length === 0) {
      return
    }
    ToriiWholePageContextStore.validateContext(normalized)
    const record: ToriiWholePageContextRecord = new ToriiWholePageContextRecord()
    record.chainKey = scope.chainKey()
    record.scope = scope.copy()
    record.context = normalized
    record.createdAt = Date.now()
    const text: string = JSON.stringify(record)
    if (text.length <= 0 || text.length > MAX_TORII_CONTEXT_RECORD_CHARS) {
      throw new Error('Torii context record size is invalid')
    }
    const dir: string = this.cacheDir()
    ToriiWholePageContextStore.ensureDir(dir)
    const path: string = `${dir}/${ToriiWholePageContextStore.recordHash(scope)}.json`
    const partial: string = `${path}.part-${util.generateRandomUUID(true)}`
    try {
      ToriiWholePageContextStore.writeText(partial, text)
      fileIo.renameSync(partial, path)
      this.prune(path)
    } catch (error) {
      ToriiWholePageContextStore.removeFile(partial)
      throw error as Error
    }
  }

  async stat(): Promise<CacheStat> {
    const stat: CacheStat = new CacheStat()
    const dir: string = this.cacheDir()
    if (!fileIo.accessSync(dir)) {
      return stat
    }
    const names: string[] = fileIo.listFileSync(dir)
    for (let index: number = 0; index < names.length; index++) {
      if (!/^[a-f0-9]{64}\.json$/.test(names[index])) {
        continue
      }
      try {
        const fileStat: fileIo.Stat = fileIo.statSync(`${dir}/${names[index]}`)
        if (fileStat.isFile() && fileStat.size > 0 &&
          fileStat.size <= MAX_TORII_CONTEXT_RECORD_CHARS) {
          stat.count++
          stat.bytes += Math.floor(fileStat.size)
        }
      } catch (_error) {}
    }
    return stat
  }

  async clear(): Promise<void> {
    const dir: string = this.cacheDir()
    if (!fileIo.accessSync(dir)) {
      return
    }
    const names: string[] = fileIo.listFileSync(dir)
    for (let index: number = 0; index < names.length; index++) {
      if (/^[a-f0-9]{64}\.json$/.test(names[index]) || names[index].includes('.part-')) {
        ToriiWholePageContextStore.removeFile(`${dir}/${names[index]}`)
      }
    }
  }

  private records(): ToriiWholePageContextRecord[] {
    const output: ToriiWholePageContextRecord[] = []
    const dir: string = this.cacheDir()
    if (!fileIo.accessSync(dir)) {
      return output
    }
    const names: string[] = fileIo.listFileSync(dir)
    for (let index: number = 0; index < names.length; index++) {
      if (!/^[a-f0-9]{64}\.json$/.test(names[index])) {
        continue
      }
      const path: string = `${dir}/${names[index]}`
      try {
        const raw: string = ToriiWholePageContextStore.readText(path)
        const parsed: ToriiWholePageContextRecord =
          JSON.parse(raw) as ToriiWholePageContextRecord
        const record: ToriiWholePageContextRecord = this.copyRecord(parsed)
        if (record.version !== TORII_CONTEXT_RECORD_VERSION ||
          ToriiWholePageContextStore.recordHash(record.scope) + '.json' !== names[index] ||
          record.chainKey !== record.scope.chainKey()) {
          throw new Error('Torii context record identity is invalid')
        }
        output.push(record)
      } catch (_error) {
        ToriiWholePageContextStore.removeFile(path)
      }
    }
    return output
  }

  private copyRecord(raw: ToriiWholePageContextRecord): ToriiWholePageContextRecord {
    if (raw === null || typeof raw !== 'object' || raw.scope === null ||
      typeof raw.scope !== 'object' || typeof raw.chainKey !== 'string' ||
      typeof raw.context !== 'string') {
      throw new Error('Torii context record is invalid')
    }
    const record: ToriiWholePageContextRecord = new ToriiWholePageContextRecord()
    record.version = raw.version
    record.chainKey = raw.chainKey
    record.scope.projectId = raw.scope.projectId
    record.scope.pageIndex = raw.scope.pageIndex
    record.scope.targetLanguage = raw.scope.targetLanguage
    record.scope.sourceProfileId = raw.scope.sourceProfileId
    record.scope.sourceRevision = raw.scope.sourceRevision
    record.scope.modelId = raw.scope.modelId
    record.scope.promptVersion = raw.scope.promptVersion
    record.scope.assertValid()
    record.context = raw.context
    ToriiWholePageContextStore.validateContext(record.context)
    record.createdAt = raw.createdAt
    if (!ToriiWholePageContextStore.nonNegativeInteger(record.createdAt)) {
      throw new Error('Torii context record timestamp is invalid')
    }
    return record
  }

  private prune(protectedPath: string): void {
    const records: ToriiWholePageContextRecord[] = this.records()
    if (records.length <= MAX_TORII_CONTEXT_RECORDS) {
      return
    }
    records.sort(
      (left: ToriiWholePageContextRecord, right: ToriiWholePageContextRecord): number =>
        left.createdAt - right.createdAt,
    )
    let remaining: number = records.length
    for (let index: number = 0; index < records.length &&
      remaining > MAX_TORII_CONTEXT_RECORDS; index++) {
      const path: string = `${this.cacheDir()}/${ToriiWholePageContextStore.recordHash(
        records[index].scope,
      )}.json`
      if (path === protectedPath) {
        continue
      }
      ToriiWholePageContextStore.removeFile(path)
      remaining--
    }
  }

  private cacheDir(): string {
    return `${this.context.cacheDir}/${TORII_CONTEXT_CACHE_DIR}`
  }

  private static recordHash(scope: ToriiWholePageContextScope): string {
    return ToriiWholePageContextStore.sha256Text(
      JSON.stringify([scope.chainKey(), `${scope.pageIndex}`]),
    )
  }

  private static validateContext(value: string): void {
    if (value.length <= 0 || value.length > MAX_TORII_CONTEXT_CHARS ||
      value !== value.trim() || value.includes('\u0000')) {
      throw new Error('Torii provider context is invalid')
    }
  }

  private static readText(path: string): string {
    const stat: fileIo.Stat = fileIo.statSync(path)
    const length: number = Math.floor(stat.size)
    if (!stat.isFile() || length <= 0 || length > MAX_TORII_CONTEXT_RECORD_CHARS) {
      throw new Error('Torii context file size is invalid')
    }
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(length)
      const read: number = fileIo.readSync(file.fd, buffer, { length: length })
      if (read !== length) {
        throw new Error('Torii context file read is incomplete')
      }
      return new util.TextDecoder().decodeToString(new Uint8Array(buffer))
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static writeText(path: string, text: string): void {
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(text)
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      const written: number = fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.length })
      if (written !== bytes.length) {
        throw new Error('Torii context file write is incomplete')
      }
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true)
    } catch (error) {
      if (!fileIo.accessSync(path)) {
        throw error as Error
      }
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  static identifier(value: string): boolean {
    return typeof value === 'string' && value.length > 0 && value.length <= 160 &&
      value === value.trim()
  }

  static nonNegativeInteger(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value &&
      value <= Number.MAX_SAFE_INTEGER
  }

  static positiveInteger(value: number): boolean {
    return value > 0 && ToriiWholePageContextStore.nonNegativeInteger(value)
  }

  private static sha256Text(value: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) })
    const bytes: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}
