import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGalleryCommentTextSpan } from '../model/EhGalleryComment'
import {
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LlmConsumerBinding,
  LlmSourceResolution,
} from '../model/LlmSourceProfile'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { connectLanguageState } from '../state/AppearanceState'
import { CommentTranslationSettings } from '../settings/CommentTranslationSettings'
import { LlmSourceProfileRepository } from '../settings/LlmSourceProfileRepository'
import { LocalDataStore } from '../storage/LocalDataStore'
import { CacheStat } from './CacheStat'
import { LlmSourceRuntimeConfig, LlmSourceRuntimeResolver } from './LlmSourceRuntimeResolver'

const COMMENT_TRANSLATION_TTL_MS: number = 7 * 24 * 60 * 60 * 1000
const TRANSLATION_CONNECT_TIMEOUT_MS: number = 12000
const TRANSLATION_READ_TIMEOUT_MS: number = 30000
const MAX_CONCURRENT_COMMENT_TRANSLATIONS: number = 2
export const MAX_PENDING_COMMENT_TRANSLATIONS: number = 32
const MAX_COMMENT_TRANSLATION_MEMORY_ENTRIES: number = 256
const MAX_PERSISTED_COMMENT_TRANSLATION_ENTRIES: number = 512
// The durable cap is maintained in batches, so ordinary bursts may temporarily hold one interval extra rows.
const COMMENT_TRANSLATION_MAINTENANCE_INTERVAL: number = 32
export const COMMENT_TRANSLATION_PRIORITY_INTERACTIVE: number = 0
export const COMMENT_TRANSLATION_PRIORITY_AUTO: number = 1
const COMMENT_TRANSLATION_QUEUE_EVICTED_ERROR: string = 'comment_translation_queue_evicted'
const COMMENT_TRANSLATION_QUEUE_FULL_ERROR: string = 'comment_translation_queue_full'
const SQL_SELECT_COMMENT_TRANSLATION: string =
  'SELECT translated FROM comment_translation_cache WHERE text_hash = ? AND target_lang = ? AND expires_at > ? LIMIT 1'
const SQL_UPSERT_COMMENT_TRANSLATION: string =
  'INSERT OR REPLACE INTO comment_translation_cache (text_hash, target_lang, translated, cached_at, expires_at) ' +
  'VALUES (?, ?, ?, ?, ?)'
const SQL_DELETE_EXPIRED_COMMENT_TRANSLATIONS: string =
  'DELETE FROM comment_translation_cache WHERE expires_at <= ?'
const SQL_PRUNE_COMMENT_TRANSLATIONS: string =
  'DELETE FROM comment_translation_cache WHERE rowid NOT IN (' +
  'SELECT rowid FROM comment_translation_cache WHERE expires_at > ? ORDER BY cached_at DESC LIMIT ?' +
  ')'
const SQL_DELETE_COMMENT_TRANSLATIONS: string = 'DELETE FROM comment_translation_cache'
const SQL_COUNT_COMMENT_TRANSLATIONS: string =
  'SELECT COUNT(*) AS c FROM comment_translation_cache WHERE expires_at > ?'
const COMMENT_LANGUAGE_URL_RE: RegExp = /https?:\/\/[^\s<>"']+/g
const COMMENT_LANGUAGE_DOMAIN_RE: RegExp =
  /\b(?:www\.)?[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+(?:\/[^\s<>"']*)?/g
const COMMENT_LANGUAGE_TOKEN_RE: RegExp = /NEXTEATHEX[0-9a-fA-F]+TOKEN/g

class ChatMessage {
  role: string = ''
  content: string = ''
}

class ChatCompletionRequest {
  model: string = ''
  messages: ChatMessage[] = []
  temperature: number = 0.3
  max_tokens: number = 2048
}

class ChatCompletionMessage {
  content: string = ''
}

class ChatCompletionChoice {
  message: ChatCompletionMessage = new ChatCompletionMessage()
}

class ChatCompletionResponse {
  choices: ChatCompletionChoice[] = []
}

class LlmModelItem {
  id: string = ''
}

class LlmModelsResponse {
  data: LlmModelItem[] = []
}

class MemoryTranslationEntry {
  translated: string = ''
  expiresAt: number = 0
}

/**
 * A tiny LRU cache for the active process. The durable seven-day RDB cache remains the source of truth;
 * this layer only prevents repeated reads from keeping every translation ever seen in a long session.
 */
export class CommentTranslationMemoryCache {
  private readonly maxEntries: number
  private entries: Map<string, MemoryTranslationEntry> = new Map()

  constructor(maxEntries: number = MAX_COMMENT_TRANSLATION_MEMORY_ENTRIES) {
    this.maxEntries = maxEntries > 0 ? maxEntries : 1
  }

  get(key: string, now: number = Date.now()): string {
    const entry: MemoryTranslationEntry | undefined = this.entries.get(key)
    if (entry === undefined) {
      return ''
    }
    if (entry.expiresAt <= now) {
      this.entries.delete(key)
      return ''
    }
    // Map insertion order gives us an inexpensive LRU policy: a hit moves the entry to the newest end.
    this.entries.delete(key)
    this.entries.set(key, entry)
    return entry.translated
  }

  put(key: string, translated: string, expiresAt: number, now: number = Date.now()): void {
    this.removeExpired(now)
    if (expiresAt <= now || translated.length === 0) {
      return
    }
    this.entries.delete(key)
    while (this.entries.size >= this.maxEntries) {
      this.removeOldest()
    }
    const entry: MemoryTranslationEntry = new MemoryTranslationEntry()
    entry.translated = translated
    entry.expiresAt = expiresAt
    this.entries.set(key, entry)
  }

  clear(): void {
    this.entries.clear()
  }

  size(now: number = Date.now()): number {
    this.removeExpired(now)
    return this.entries.size
  }

  private removeExpired(now: number): void {
    const expired: string[] = []
    this.entries.forEach((entry: MemoryTranslationEntry, key: string): void => {
      if (entry.expiresAt <= now) {
        expired.push(key)
      }
    })
    for (let i: number = 0; i < expired.length; i++) {
      this.entries.delete(expired[i])
    }
  }

  private removeOldest(): void {
    let found: boolean = false
    let oldest: string = ''
    this.entries.forEach((_entry: MemoryTranslationEntry, key: string): void => {
      if (!found) {
        found = true
        oldest = key
      }
    })
    if (found) {
      this.entries.delete(oldest)
    }
  }
}

/** Monotonic generation used to ensure an explicit clear wins over older in-flight translations. */
export class CommentTranslationCacheEpoch {
  private value: number = 0

  snapshot(): number {
    return this.value
  }

  advance(): number {
    this.value++
    return this.value
  }

  isCurrent(snapshot: number): boolean {
    return snapshot === this.value
  }
}

/** A small FIFO scheduler that bounds both concurrent and waiting remote comment translations. */
export class CommentTranslationQueueTask {
  key: string = ''
  priority: number = COMMENT_TRANSLATION_PRIORITY_AUTO
  started: boolean = false
  active: boolean = false
  discarded: boolean = false
  private startAction: () => void = () => {}
  private discardAction: (error: Error) => void = (_error: Error): void => {}

  constructor(
    key: string,
    priority: number,
    startAction: () => void,
    discardAction: (error: Error) => void = (_error: Error): void => {},
  ) {
    this.key = key
    this.priority = priority
    this.startAction = startAction
    this.discardAction = discardAction
  }

  start(): void {
    this.startAction()
  }

  discard(error: Error): void {
    if (this.started || this.discarded) {
      return
    }
    this.discarded = true
    this.discardAction(error)
  }
}

/**
 * Bounds distinct remote translations while preserving priority/FIFO order. Cache reads and same-key joins
 * stay outside this scheduler; only the eventual provider call occupies a slot. When the waiting budget is
 * full, stale automatic work yields to the newest visible automatic request or to an interactive request;
 * running work is never cancelled.
 */
export class CommentTranslationQueueScheduler {
  private queue: CommentTranslationQueueTask[] = []
  private running: number = 0

  schedule(task: CommentTranslationQueueTask): void {
    if (task.started || task.discarded) {
      return
    }
    if (!this.makeRoom(task)) {
      return
    }
    this.enqueue(task)
    this.drain()
  }

  /** A user-visible request can move an already-queued auto translation ahead of background work. */
  promote(task: CommentTranslationQueueTask, priority: number): void {
    if (task.discarded || priority >= task.priority) {
      return
    }
    task.priority = priority
    if (task.started || !this.removeQueued(task)) {
      return
    }
    this.enqueue(task)
    this.drain()
  }

  complete(task: CommentTranslationQueueTask): void {
    if (!task.active) {
      return
    }
    task.active = false
    if (this.running > 0) {
      this.running--
    }
    this.drain()
  }

  pendingCount(): number {
    return this.queue.length
  }

  private drain(): void {
    while (this.running < MAX_CONCURRENT_COMMENT_TRANSLATIONS && this.queue.length > 0) {
      const next: CommentTranslationQueueTask | undefined = this.queue.shift()
      if (next === undefined || next.started || next.discarded) {
        continue
      }
      next.started = true
      next.active = true
      this.running++
      next.start()
    }
  }

  private enqueue(task: CommentTranslationQueueTask): void {
    for (let i: number = 0; i < this.queue.length; i++) {
      if (task.priority < this.queue[i].priority) {
        this.queue.splice(i, 0, task)
        return
      }
    }
    this.queue.push(task)
  }

  private makeRoom(task: CommentTranslationQueueTask): boolean {
    if (this.queue.length < MAX_PENDING_COMMENT_TRANSLATIONS) {
      return true
    }
    const discarded: CommentTranslationQueueTask | undefined = this.discardOldestAuto()
    if (discarded !== undefined) {
      discarded.discard(new Error(COMMENT_TRANSLATION_QUEUE_EVICTED_ERROR))
      return true
    }
    task.discard(new Error(COMMENT_TRANSLATION_QUEUE_FULL_ERROR))
    return false
  }

  private discardOldestAuto(): CommentTranslationQueueTask | undefined {
    for (let i: number = 0; i < this.queue.length; i++) {
      if (this.queue[i].priority === COMMENT_TRANSLATION_PRIORITY_AUTO) {
        return this.queue.splice(i, 1)[0]
      }
    }
    return undefined
  }

  private removeQueued(task: CommentTranslationQueueTask): boolean {
    for (let i: number = 0; i < this.queue.length; i++) {
      if (this.queue[i] === task) {
        this.queue.splice(i, 1)
        return true
      }
    }
    return false
  }
}

class CommentTranslationNetworkTask {
  queueTask: CommentTranslationQueueTask
  private readonly work: () => Promise<string>
  private readonly scheduler: CommentTranslationQueueScheduler
  private completion: Promise<string> = Promise.resolve('')
  private resolveCompletion: (result: string) => void = (_result: string): void => {}
  private rejectCompletion: (error: Error) => void = (_error: Error): void => {}
  private settled: boolean = false
  private discardCleanup: () => void = () => {}

  constructor(
    key: string,
    priority: number,
    work: () => Promise<string>,
    scheduler: CommentTranslationQueueScheduler,
  ) {
    this.work = work
    this.scheduler = scheduler
    this.queueTask = new CommentTranslationQueueTask(
      key,
      priority,
      (): void => this.start(),
      (error: Error): void => this.rejectBeforeStart(error),
    )
    this.completion = new Promise<string>((resolve: (result: string) => void, reject: (error: Error) => void): void => {
      this.resolveCompletion = resolve
      this.rejectCompletion = reject
    })
  }

  wait(): Promise<string> {
    return this.completion
  }

  isSettled(): boolean {
    return this.settled
  }

  setDiscardCleanup(cleanup: () => void): void {
    this.discardCleanup = cleanup
  }

  private start(): void {
    try {
      this.work().then(
        (result: string): void => {
          this.resolve(result)
          this.scheduler.complete(this.queueTask)
        },
        (error: Error): void => {
          this.reject(error)
          this.scheduler.complete(this.queueTask)
        },
      )
    } catch (error) {
      this.reject(error as Error)
      this.scheduler.complete(this.queueTask)
    }
  }

  private rejectBeforeStart(error: Error): void {
    this.discardCleanup()
    this.reject(error)
  }

  private resolve(result: string): void {
    if (this.settled) {
      return
    }
    this.settled = true
    this.resolveCompletion(result)
  }

  private reject(error: Error): void {
    if (this.settled) {
      return
    }
    this.settled = true
    this.rejectCompletion(error)
  }
}

export class CommentStructuredTranslation {
  text: string = ''
  spans: EhGalleryCommentTextSpan[] = []
}

export class CommentTranslationService {
  private static memory: CommentTranslationMemoryCache = new CommentTranslationMemoryCache()
  private static inflight: Map<string, CommentTranslationNetworkTask> = new Map()
  private static readonly scheduler: CommentTranslationQueueScheduler = new CommentTranslationQueueScheduler()
  private static readonly cacheEpoch: CommentTranslationCacheEpoch = new CommentTranslationCacheEpoch()
  private static persistedCacheWritesSinceMaintenance: number = -1
  private static persistedCacheMaintenanceInFlight: boolean = false
  private static persistedCacheMaintenanceFollowUp: boolean = false

  static targetLanguage(): string {
    const locale: string = connectLanguageState().effectiveLocale
    if (locale.startsWith('zh-Hant') || locale.startsWith('zh-TW')) {
      return 'zh-TW'
    }
    if (locale.startsWith('zh')) {
      return 'zh-CN'
    }
    if (locale.length >= 2) {
      return locale.substring(0, 2)
    }
    return 'zh-CN'
  }

  static isQueueCapacityError(error: Error): boolean {
    return error.message === COMMENT_TRANSLATION_QUEUE_EVICTED_ERROR ||
      error.message === COMMENT_TRANSLATION_QUEUE_FULL_ERROR
  }

  // Local, network-free language pre-check: a comment "needs translation" only when its dominant script
  // differs from the current UI language's. Cheap heuristic — it cannot tell apart latin-script languages
  // (en/fr/de all read as "latin") or kana-less Japanese, so it errs toward translating when unsure. Used
  // to skip AUTO-translating comments the user can already read; the manual translate button is unaffected.
  static needsTranslation(text: string): boolean {
    const t: string = CommentTranslationService.languageSample(text.trim())
    if (t.length === 0) {
      return false
    }
    if (!CommentTranslationService.hasLanguageSignal(t)) {
      return false
    }
    const script: string = CommentTranslationService.detectScript(t)
    if (script === 'unknown') {
      return true
    }
    return script !== CommentTranslationService.targetScriptFamily()
  }

  private static targetScriptFamily(): string {
    const target: string = CommentTranslationService.targetLanguage()
    if (target.startsWith('zh')) {
      // Simplified and Traditional are the same spoken language: a Chinese reader can read either, so a
      // Chinese comment never auto-translates regardless of the zh-CN/zh-TW variant.
      return 'zh'
    }
    if (target === 'ja') {
      return 'ja'
    }
    if (target === 'ko') {
      return 'ko'
    }
    return 'latin'
  }

  private static languageSample(text: string): string {
    return text
      .replace(COMMENT_LANGUAGE_URL_RE, ' ')
      .replace(COMMENT_LANGUAGE_DOMAIN_RE, ' ')
      .replace(COMMENT_LANGUAGE_TOKEN_RE, ' ')
      .trim()
  }

  private static hasLanguageSignal(text: string): boolean {
    let cjk: number = 0
    let other: number = 0
    let latinRun: number = 0
    let latinWordCount: number = 0
    let latinHasVowel: boolean = false
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i)
      if (CommentTranslationService.isLatinLetter(code)) {
        latinRun++
        const ch: string = text.charAt(i).toLowerCase()
        if (ch === 'a' || ch === 'e' || ch === 'i' || ch === 'o' || ch === 'u') {
          latinHasVowel = true
        }
        continue
      }
      if (latinRun >= 4 && latinHasVowel) {
        latinWordCount++
      }
      latinRun = 0
      latinHasVowel = false
      if (
        (code >= 0x3040 && code <= 0x30ff) ||
        (code >= 0x3400 && code <= 0x9fff) ||
        (code >= 0xac00 && code <= 0xd7a3)
      ) {
        cjk++
      } else if (CommentTranslationService.isOtherLetter(code)) {
        other++
      }
    }
    if (latinRun >= 4 && latinHasVowel) {
      latinWordCount++
    }
    return cjk >= 2 || other >= 2 || latinWordCount > 0
  }

  private static isLatinLetter(code: number): boolean {
    return (
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      (code >= 0xc0 && code <= 0x24f)
    )
  }

  private static isOtherLetter(code: number): boolean {
    return (
      (code >= 0x0370 && code <= 0x03ff) ||
      (code >= 0x0400 && code <= 0x052f) ||
      (code >= 0x0590 && code <= 0x05ff) ||
      (code >= 0x0600 && code <= 0x06ff) ||
      (code >= 0x0900 && code <= 0x097f) ||
      (code >= 0x0e00 && code <= 0x0e7f)
    )
  }

  // Dominant-script classifier over the BMP: kana ⇒ Japanese, Hangul ⇒ Korean, Han (no kana) ⇒ Chinese,
  // else Latin letters ⇒ latin. Returns 'unknown' when none are present (digits/punctuation/emoji only).
  private static detectScript(text: string): string {
    let han: number = 0
    let kana: number = 0
    let hangul: number = 0
    let latin: number = 0
    let other: number = 0
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i)
      if ((code >= 0x3040 && code <= 0x309f) || (code >= 0x30a0 && code <= 0x30ff)) {
        kana++
      } else if (
        (code >= 0xac00 && code <= 0xd7a3) ||
        (code >= 0x1100 && code <= 0x11ff) ||
        (code >= 0x3130 && code <= 0x318f)
      ) {
        hangul++
      } else if (
        (code >= 0x4e00 && code <= 0x9fff) ||
        (code >= 0x3400 && code <= 0x4dbf) ||
        (code >= 0xf900 && code <= 0xfaff)
      ) {
        han++
      } else if (
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a) ||
        (code >= 0xc0 && code <= 0x24f)
      ) {
        latin++
      } else if (CommentTranslationService.isOtherLetter(code)) {
        other++
      }
    }
    if (kana > 0) {
      return 'ja'
    }
    if (hangul > 0) {
      return 'ko'
    }
    if (han > 0) {
      return 'zh'
    }
    if (latin > 0) {
      return 'latin'
    }
    if (other > 0) {
      return 'other'
    }
    return 'unknown'
  }

  static async getCached(
    context: common.UIAbilityContext,
    text: string,
    targetLang: string,
  ): Promise<string> {
    const cacheEpoch: number = CommentTranslationService.cacheEpoch.snapshot()
    const cacheScope: string = CommentTranslationService.cacheScope(targetLang)
    const key: string = CommentTranslationService.cacheKey(text, cacheScope)
    const now: number = Date.now()
    const memoryHit: string = CommentTranslationService.memory.get(key, now)
    if (memoryHit.length > 0) {
      return memoryHit
    }

    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(
      SQL_SELECT_COMMENT_TRANSLATION,
      [CommentTranslationService.textHash(text), cacheScope, now],
    )
    try {
      if (resultSet.goToFirstRow()) {
        const translated: string = resultSet.getString(resultSet.getColumnIndex('translated'))
        if (CommentTranslationService.cacheEpoch.isCurrent(cacheEpoch)) {
          CommentTranslationService.putMemory(key, translated, now + COMMENT_TRANSLATION_TTL_MS)
        }
        return translated
      }
    } finally {
      resultSet.close()
    }
    return ''
  }

  static async translate(
    context: common.UIAbilityContext,
    text: string,
    force: boolean = false,
    priority: number = COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  ): Promise<string> {
    const source: string = text.trim()
    if (source.length === 0) {
      return ''
    }
    const targetLang: string = CommentTranslationService.targetLanguage()
    const cacheScope: string = CommentTranslationService.cacheScope(targetLang)
    const key: string = CommentTranslationService.cacheKey(source, cacheScope)
    if (!force) {
      const cached: string = await CommentTranslationService.getCached(context, source, targetLang)
      if (cached.length > 0) {
        DiagnosticLogger.info(
          'translation',
          'comment_cache_hit',
          `target=${targetLang} len=${source.length} textHash=${DiagnosticLogger.ownerHash(source)}`,
        )
        return cached
      }
    }
    const inFlight: CommentTranslationNetworkTask | undefined = CommentTranslationService.inflight.get(key)
    if (inFlight !== undefined && !inFlight.isSettled()) {
      CommentTranslationService.scheduler.promote(inFlight.queueTask, priority)
      DiagnosticLogger.info(
        'translation',
        'comment_join_inflight',
        `target=${targetLang} len=${source.length} textHash=${DiagnosticLogger.ownerHash(source)}`,
      )
      return inFlight.wait()
    }
    if (inFlight !== undefined) {
      CommentTranslationService.inflight.delete(key)
    }
    const cacheEpoch: number = CommentTranslationService.cacheEpoch.snapshot()
    const queuedTask: CommentTranslationNetworkTask = new CommentTranslationNetworkTask(
      key,
      priority,
      (): Promise<string> => CommentTranslationService.translateAndCache(
        context,
        source,
        targetLang,
        cacheScope,
        cacheEpoch,
      ),
      CommentTranslationService.scheduler,
    )
    const task: Promise<string> = queuedTask.wait()
    queuedTask.setDiscardCleanup((): void => {
      const active: CommentTranslationNetworkTask | undefined = CommentTranslationService.inflight.get(key)
      if (active === queuedTask) {
        CommentTranslationService.inflight.delete(key)
      }
    })
    CommentTranslationService.inflight.set(key, queuedTask)
    CommentTranslationService.scheduler.schedule(queuedTask.queueTask)
    try {
      return await task
    } finally {
      const active: CommentTranslationNetworkTask | undefined = CommentTranslationService.inflight.get(key)
      if (active === queuedTask) {
        CommentTranslationService.inflight.delete(key)
      }
    }
  }

  static async translateStructured(
    context: common.UIAbilityContext,
    sourceText: string,
    sourceSpans: EhGalleryCommentTextSpan[],
    force: boolean = false,
    priority: number = COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  ): Promise<CommentStructuredTranslation> {
    const result: CommentStructuredTranslation = new CommentStructuredTranslation()
    if (sourceText.trim().length === 0) {
      return result
    }
    if (sourceSpans.length === 0) {
      result.text = await CommentTranslationService.translate(context, sourceText, force, priority)
      return result
    }
    let cursor: number = 0
    const spans: EhGalleryCommentTextSpan[] = sourceSpans.slice()
    spans.sort((a: EhGalleryCommentTextSpan, b: EhGalleryCommentTextSpan) => a.start - b.start)
    for (let i = 0; i < spans.length; i++) {
      const sourceSpan: EhGalleryCommentTextSpan = spans[i]
      if (
        sourceSpan.start < cursor ||
        sourceSpan.end <= 0 ||
        sourceSpan.start >= sourceText.length ||
        sourceSpan.end > sourceText.length
      ) {
        continue
      }
      if (sourceSpan.start > cursor) {
        result.text += await CommentTranslationService.translateChunk(
          context,
          sourceText.substring(cursor, sourceSpan.start),
          force,
          priority,
        )
      }
      const translatedStart: number = result.text.length
      const translatedChunk: string = await CommentTranslationService.translateChunk(
        context,
        sourceText.substring(sourceSpan.start, sourceSpan.end),
        force,
        priority,
      )
      result.text += translatedChunk
      const translatedEnd: number = result.text.length
      if (translatedEnd > translatedStart) {
        const span: EhGalleryCommentTextSpan = new EhGalleryCommentTextSpan()
        span.start = translatedStart
        span.end = translatedEnd
        span.url = sourceSpan.url
        span.bold = sourceSpan.bold
        span.italic = sourceSpan.italic
        span.underline = sourceSpan.underline
        span.strike = sourceSpan.strike
        span.color = sourceSpan.color
        result.spans.push(span)
      }
      cursor = sourceSpan.end
    }
    if (cursor < sourceText.length) {
      result.text += await CommentTranslationService.translateChunk(
        context,
        sourceText.substring(cursor),
        force,
        priority,
      )
    }
    return result
  }

  private static async translateChunk(
    context: common.UIAbilityContext,
    raw: string,
    force: boolean,
    priority: number,
  ): Promise<string> {
    if (raw.trim().length === 0) {
      return raw
    }
    const startTrim: number = CommentTranslationService.leadingWhitespace(raw)
    const endTrim: number = CommentTranslationService.trailingWhitespace(raw)
    const end: number = raw.length - endTrim
    const lead: string = raw.substring(0, startTrim)
    const tail: string = raw.substring(end)
    const body: string = raw.substring(startTrim, end)
    if (!CommentTranslationService.hasTranslatableText(body)) {
      return raw
    }
    return `${lead}${await CommentTranslationService.translate(context, body, force, priority)}${tail}`
  }

  private static hasTranslatableText(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i)
      if (
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a) ||
        (code >= 0x3040 && code <= 0x30ff) ||
        (code >= 0x3400 && code <= 0x9fff) ||
        (code >= 0xac00 && code <= 0xd7a3)
      ) {
        return true
      }
    }
    return false
  }

  private static leadingWhitespace(text: string): number {
    let count: number = 0
    while (count < text.length && text.charAt(count).trim().length === 0) {
      count++
    }
    return count
  }

  private static trailingWhitespace(text: string): number {
    let count: number = 0
    while (count < text.length && text.charAt(text.length - count - 1).trim().length === 0) {
      count++
    }
    return count
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    CommentTranslationService.cacheEpoch.advance()
    CommentTranslationService.memory.clear()
    CommentTranslationService.resetPersistedCacheMaintenance()
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_DELETE_COMMENT_TRANSLATIONS)
  }

  static async count(context: common.UIAbilityContext): Promise<number> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(
      SQL_COUNT_COMMENT_TRANSLATIONS,
      [Date.now()],
    )
    try {
      if (resultSet.goToFirstRow()) {
        return resultSet.getDouble(resultSet.getColumnIndex('c'))
      }
    } finally {
      resultSet.close()
    }
    return 0
  }

  // Count + translated-text bytes of the unexpired comment-translation cache, for the cache page.
  static async stat(context: common.UIAbilityContext): Promise<CacheStat> {
    const out: CacheStat = new CacheStat()
    try {
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT COUNT(*) AS c, COALESCE(SUM(LENGTH(translated)), 0) AS b FROM comment_translation_cache WHERE expires_at > ?',
        [Date.now()],
      )
      try {
        if (rs.goToFirstRow()) {
          out.count = rs.getDouble(rs.getColumnIndex('c'))
          out.bytes = rs.getDouble(rs.getColumnIndex('b'))
        }
      } finally {
        rs.close()
      }
    } catch (error) {
      DiagnosticLogger.warn('translation', 'comment_cache_stat_failed', (error as Error).message)
    }
    return out
  }

  static async validateConfiguredLlm(context: common.UIAbilityContext): Promise<void> {
    const runtime: LlmSourceRuntimeConfig = await LlmSourceRuntimeResolver.resolveComment(context)
    await CommentTranslationService.callLlm(
      'Hello',
      CommentTranslationService.targetLanguage(),
      runtime.baseUrl,
      runtime.apiKey,
      runtime.modelId,
    )
  }

  static async fetchConfiguredLlmModels(context: common.UIAbilityContext): Promise<string[]> {
    const runtime: LlmSourceRuntimeConfig = await LlmSourceRuntimeResolver.resolveComment(context)
    return CommentTranslationService.fetchLlmModels(
      runtime.baseUrl,
      runtime.apiKey,
    )
  }

  private static async translateAndCache(
    context: common.UIAbilityContext,
    text: string,
    targetLang: string,
    cacheScope: string,
    cacheEpoch: number,
  ): Promise<string> {
    const startedAt: number = Date.now()
    DiagnosticLogger.info(
      'translation',
      'comment_translate_start',
      `target=${targetLang} len=${text.length} textHash=${DiagnosticLogger.ownerHash(text)}`,
    )
    const rawResult: string = await CommentTranslationService.callTranslation(
      context,
      text,
      targetLang,
    )
    const result: string = CommentTranslationService.restoreMentionTokens(rawResult)
    await CommentTranslationService.save(context, text, cacheScope, result, cacheEpoch)
    DiagnosticLogger.info(
      'translation',
      'comment_translate_done',
      `target=${targetLang} len=${text.length} resultLen=${result.length} elapsedMs=${Date.now() - startedAt} textHash=${DiagnosticLogger.ownerHash(text)}`,
    )
    return result
  }

  private static async save(
    context: common.UIAbilityContext,
    text: string,
    cacheScope: string,
    translated: string,
    cacheEpoch: number,
  ): Promise<void> {
    const now: number = Date.now()
    const expiresAt: number = now + COMMENT_TRANSLATION_TTL_MS
    if (!CommentTranslationService.cacheEpoch.isCurrent(cacheEpoch)) {
      return
    }
    CommentTranslationService.putMemory(
      CommentTranslationService.cacheKey(text, cacheScope),
      translated,
      expiresAt,
    )
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    if (!CommentTranslationService.cacheEpoch.isCurrent(cacheEpoch)) {
      return
    }
    await store.executeSql(SQL_UPSERT_COMMENT_TRANSLATION, [
      CommentTranslationService.textHash(text),
      cacheScope,
      translated,
      now,
      expiresAt,
    ])
    if (!CommentTranslationService.cacheEpoch.isCurrent(cacheEpoch)) {
      return
    }
    if (!CommentTranslationService.shouldRunPersistedCacheMaintenance()) {
      return
    }
    let maintenanceSucceeded: boolean = false
    try {
      // After the target row is safely upserted, maintenance only deletes stale/excess rows. It is
      // intentionally best-effort so a prune failure does not turn a successful translation into UI failure.
      await store.executeSql(SQL_DELETE_EXPIRED_COMMENT_TRANSLATIONS, [now])
      await store.executeSql(SQL_PRUNE_COMMENT_TRANSLATIONS, [
        now,
        MAX_PERSISTED_COMMENT_TRANSLATION_ENTRIES,
      ])
      maintenanceSucceeded = true
    } catch (error) {
      DiagnosticLogger.warn('translation', 'comment_cache_maintenance_failed', (error as Error).message)
    } finally {
      CommentTranslationService.finishPersistedCacheMaintenance(maintenanceSucceeded)
    }
  }

  /** First durable save and every later interval clean expiry + restore the eventual retention cap. */
  private static shouldRunPersistedCacheMaintenance(): boolean {
    if (CommentTranslationService.persistedCacheMaintenanceInFlight) {
      CommentTranslationService.persistedCacheMaintenanceFollowUp = true
      return false
    }
    if (
      CommentTranslationService.persistedCacheWritesSinceMaintenance < 0 ||
      CommentTranslationService.persistedCacheWritesSinceMaintenance >= COMMENT_TRANSLATION_MAINTENANCE_INTERVAL - 1
    ) {
      CommentTranslationService.persistedCacheMaintenanceInFlight = true
      return true
    }
    CommentTranslationService.persistedCacheWritesSinceMaintenance =
      CommentTranslationService.persistedCacheWritesSinceMaintenance + 1
    return false
  }

  /** A failed or overlapped prune stays due, so the next successful save retries immediately. */
  private static finishPersistedCacheMaintenance(succeeded: boolean): void {
    CommentTranslationService.persistedCacheMaintenanceInFlight = false
    const hasFollowUp: boolean = CommentTranslationService.persistedCacheMaintenanceFollowUp
    CommentTranslationService.persistedCacheMaintenanceFollowUp = false
    CommentTranslationService.persistedCacheWritesSinceMaintenance = succeeded && !hasFollowUp
      ? 0
      : COMMENT_TRANSLATION_MAINTENANCE_INTERVAL - 1
  }

  private static resetPersistedCacheMaintenance(): void {
    CommentTranslationService.persistedCacheWritesSinceMaintenance = -1
    CommentTranslationService.persistedCacheMaintenanceFollowUp = false
  }

  private static async callTranslation(
    context: common.UIAbilityContext,
    text: string,
    targetLang: string,
  ): Promise<string> {
    const settings = CommentTranslationSettings.current()
    if (!settings.useGoogleOnly) {
      try {
        const runtime: LlmSourceRuntimeConfig =
          await LlmSourceRuntimeResolver.resolveComment(context)
        const llmStartedAt: number = Date.now()
        DiagnosticLogger.info(
          'translation',
          'comment_llm_start',
          `target=${targetLang} len=${text.length} source=${runtime.sourceProfileId} revision=${runtime.sourceRevision} model=${runtime.modelId}`,
        )
        const llmResult: string = await CommentTranslationService.callLlm(
          text,
          targetLang,
          runtime.baseUrl,
          runtime.apiKey,
          runtime.modelId,
        )
        DiagnosticLogger.info(
          'translation',
          'comment_llm_done',
          `target=${targetLang} resultLen=${llmResult.length} elapsedMs=${Date.now() - llmStartedAt}`,
        )
        return llmResult
      } catch (error) {
        DiagnosticLogger.warn('translation', 'llm_failed_google_fallback', (error as Error).message)
      }
    }
    const googleStartedAt: number = Date.now()
    DiagnosticLogger.info(
      'translation',
      'comment_google_start',
      `target=${targetLang} len=${text.length} textHash=${DiagnosticLogger.ownerHash(text)}`,
    )
    const googleResult: string = await CommentTranslationService.callGoogle(text, targetLang)
    DiagnosticLogger.info(
      'translation',
      'comment_google_done',
      `target=${targetLang} resultLen=${googleResult.length} elapsedMs=${Date.now() - googleStartedAt}`,
    )
    return googleResult
  }

  private static async callLlm(
    text: string,
    targetLang: string,
    baseUrl: string,
    apiKey: string,
    model: string,
  ): Promise<string> {
    const reqBody = new ChatCompletionRequest()
    reqBody.model = model
    const system = new ChatMessage()
    system.role = 'system'
    system.content =
      `You are a translator. Translate the following text to ${CommentTranslationService.langName(targetLang)}. ` +
      'Keep NEXTEATHEX...TOKEN placeholders unchanged. Output ONLY the translated text, no explanations.'
    const user = new ChatMessage()
    user.role = 'user'
    user.content = text
    reqBody.messages = [system, user]

    try {
      const resp: AxiosTextResponse = await AxiosHttpClient.requestText(
        `${CommentTranslationService.stripV1(baseUrl)}/v1/chat/completions`,
        'POST',
        {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
        },
        JSON.stringify(reqBody),
        TRANSLATION_CONNECT_TIMEOUT_MS,
        TRANSLATION_READ_TIMEOUT_MS,
      )
      const body: string = resp.body
      if (resp.statusCode !== 200) {
        throw new Error(`LLM HTTP ${resp.statusCode}`)
      }
      const raw: Object = JSON.parse(body) as Object
      const parsed: ChatCompletionResponse = raw as ChatCompletionResponse
      if (Array.isArray(parsed.choices) && parsed.choices.length > 0) {
        const result: string = parsed.choices[0].message.content.trim()
        if (result.length > 0) {
          return result
        }
      }
      throw new Error('LLM returned empty response')
    } catch (error) {
      throw error as Error
    }
  }

  private static async fetchLlmModels(baseUrl: string, apiKey: string): Promise<string[]> {
    const resp: AxiosTextResponse = await AxiosHttpClient.requestText(
      `${CommentTranslationService.stripV1(baseUrl)}/v1/models`,
      'GET',
      {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      '',
      TRANSLATION_CONNECT_TIMEOUT_MS,
      TRANSLATION_READ_TIMEOUT_MS,
    )
    const body: string = resp.body
    if (resp.statusCode !== 200) {
      throw new Error(`LLM models HTTP ${resp.statusCode}`)
    }
    const raw: Object = JSON.parse(body) as Object
    const parsed: LlmModelsResponse = raw as LlmModelsResponse
    const out: string[] = []
    if (Array.isArray(parsed.data)) {
      for (let i = 0; i < parsed.data.length; i++) {
        const item: LlmModelItem = parsed.data[i]
        if (item.id.length > 0) {
          out.push(item.id)
        }
      }
    }
    out.sort()
    return out
  }

  private static async callGoogle(text: string, targetLang: string): Promise<string> {
    const to: string =
      targetLang === 'zh-CN' ? 'zh-cn' : targetLang === 'zh-TW' ? 'zh-tw' : targetLang
    const url: string =
      `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=${encodeURIComponent(to)}` +
      `&dt=t&q=${encodeURIComponent(text)}`
    const resp: AxiosTextResponse = await AxiosHttpClient.requestText(
      url,
      'GET',
      {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/json,text/plain,*/*',
        'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
      },
      '',
      TRANSLATION_CONNECT_TIMEOUT_MS,
      TRANSLATION_READ_TIMEOUT_MS,
    )
    const body: string = resp.body
    if (resp.statusCode !== 200) {
      throw new Error(`Google Translate HTTP ${resp.statusCode}`)
    }
    const translated: string = CommentTranslationService.parseGoogleBody(body)
    if (translated.length === 0) {
      throw new Error('Google Translate returned empty response')
    }
    return translated
  }

  private static parseGoogleBody(body: string): string {
    let root: Object
    try {
      root = JSON.parse(body) as Object
    } catch (_error) {
      return ''
    }
    if (!Array.isArray(root)) {
      return ''
    }
    const top: Object[] = root as Object[]
    if (top.length === 0 || !Array.isArray(top[0])) {
      return ''
    }
    const lines: Object[] = top[0] as Object[]
    let out: string = ''
    for (let i = 0; i < lines.length; i++) {
      const lineObj: Object = lines[i]
      if (Array.isArray(lineObj)) {
        const line: Object[] = lineObj as Object[]
        if (line.length > 0 && typeof line[0] === 'string') {
          out += line[0] as string
        }
      }
    }
    return out.trim()
  }

  private static putMemory(key: string, translated: string, expiresAt: number): void {
    CommentTranslationService.memory.put(key, translated, expiresAt)
  }

  static protectMentionText(mention: string): string {
    let hex: string = ''
    for (let i = 0; i < mention.length; i++) {
      hex += mention.charCodeAt(i).toString(16).padStart(4, '0')
    }
    return `NEXTEATHEX${hex}TOKEN`
  }

  private static restoreMentionTokens(text: string): string {
    let out: string = ''
    let cursor: number = 0
    while (cursor < text.length) {
      const start: number = text.indexOf('NEXTEATHEX', cursor)
      if (start < 0) {
        out += text.substring(cursor)
        break
      }
      const end: number = text.indexOf('TOKEN', start + 10)
      if (end < 0) {
        out += text.substring(cursor)
        break
      }
      out += text.substring(cursor, start)
      const hex: string = text.substring(start + 10, end)
      out += CommentTranslationService.decodeMentionHex(hex)
      cursor = end + 5
    }
    return out
  }

  private static decodeMentionHex(hex: string): string {
    if (hex.length === 0 || hex.length % 4 !== 0) {
      return ''
    }
    let out: string = ''
    for (let i = 0; i < hex.length; i += 4) {
      const code: number = Number.parseInt(hex.substring(i, i + 4), 16)
      if (Number.isNaN(code)) {
        return ''
      }
      out += String.fromCharCode(code)
    }
    return out
  }

  /** Keeps cached output attached to the selected route, source revision and model. */
  private static cacheScope(targetLang: string): string {
    if (CommentTranslationSettings.current().useGoogleOnly) {
      return `${targetLang}|google-v1`
    }
    try {
      const binding: LlmConsumerBinding = LlmSourceProfileRepository.currentBinding(
        LLM_CONSUMER_COMMENT_TRANSLATION,
      )
      const resolution: LlmSourceResolution | null = LlmSourceProfileRepository.resolve(
        LlmSourceProfileRepository.currentProfiles(),
        binding,
      )
      if (resolution !== null) {
        return `${targetLang}|${resolution.profile.sourceProfileId}|r${resolution.profile.sourceRevision}|${resolution.modelId}`
      }
    } catch (_error) {
      // Missing or damaged source selection follows the same explicit Google fallback as the request path.
    }
    return `${targetLang}|google-fallback-v1`
  }

  private static cacheKey(text: string, cacheScope: string): string {
    return `${CommentTranslationService.textHash(text)}:${cacheScope}`
  }

  private static textHash(text: string): string {
    let hash: number = 2166136261
    for (let i = 0; i < text.length; i++) {
      hash = (hash ^ text.charCodeAt(i)) * 16777619
      hash = hash >>> 0
    }
    return `${text.length.toString(36)}_${hash.toString(36)}`
  }

  private static stripV1(url: string): string {
    let out: string = url.trim()
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1)
    }
    return out.endsWith('/v1') ? out.substring(0, out.length - 3) : out
  }

  private static langName(lang: string): string {
    if (lang === 'zh-CN') {
      return 'Simplified Chinese'
    }
    if (lang === 'zh-TW') {
      return 'Traditional Chinese'
    }
    return lang
  }
}
