import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { http } from '@kit.NetworkKit'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectLanguageState } from '../state/AppearanceState'
import { CommentTranslationSettings } from '../settings/CommentTranslationSettings'
import { LocalDataStore } from '../storage/LocalDataStore'

const COMMENT_TRANSLATION_TTL_MS: number = 7 * 24 * 60 * 60 * 1000
const TRANSLATION_CONNECT_TIMEOUT_MS: number = 12000
const TRANSLATION_READ_TIMEOUT_MS: number = 30000
const DEFAULT_LLM_BASE_URL: string = 'https://api.openai.com'
const DEFAULT_LLM_MODEL: string = 'gpt-4o-mini'
const SQL_SELECT_COMMENT_TRANSLATION: string =
  'SELECT translated FROM comment_translation_cache WHERE text_hash = ? AND target_lang = ? AND expires_at > ? LIMIT 1'
const SQL_UPSERT_COMMENT_TRANSLATION: string =
  'INSERT OR REPLACE INTO comment_translation_cache (text_hash, target_lang, translated, cached_at, expires_at) ' +
  'VALUES (?, ?, ?, ?, ?)'
const SQL_DELETE_EXPIRED_COMMENT_TRANSLATIONS: string =
  'DELETE FROM comment_translation_cache WHERE expires_at <= ?'
const SQL_DELETE_COMMENT_TRANSLATIONS: string = 'DELETE FROM comment_translation_cache'
const SQL_COUNT_COMMENT_TRANSLATIONS: string =
  'SELECT COUNT(*) AS c FROM comment_translation_cache WHERE expires_at > ?'

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

export class CommentTranslationService {
  private static memory: Map<string, MemoryTranslationEntry> = new Map()
  private static inflight: Map<string, Promise<string>> = new Map()

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

  // Local, network-free language pre-check: a comment "needs translation" only when its dominant script
  // differs from the current UI language's. Cheap heuristic — it cannot tell apart latin-script languages
  // (en/fr/de all read as "latin") or kana-less Japanese, so it errs toward translating when unsure. Used
  // to skip AUTO-translating comments the user can already read; the manual translate button is unaffected.
  static needsTranslation(text: string): boolean {
    const t: string = text.trim()
    if (t.length === 0) {
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

  // Dominant-script classifier over the BMP: kana ⇒ Japanese, Hangul ⇒ Korean, Han (no kana) ⇒ Chinese,
  // else Latin letters ⇒ latin. Returns 'unknown' when none are present (digits/punctuation/emoji only).
  private static detectScript(text: string): string {
    let han: number = 0
    let kana: number = 0
    let hangul: number = 0
    let latin: number = 0
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
    return 'unknown'
  }

  static async getCached(
    context: common.UIAbilityContext,
    text: string,
    targetLang: string,
  ): Promise<string> {
    const key: string = CommentTranslationService.cacheKey(text, targetLang)
    const now: number = Date.now()
    const mem: MemoryTranslationEntry | undefined = CommentTranslationService.memory.get(key)
    if (mem !== undefined) {
      if (mem.expiresAt > now) {
        return mem.translated
      }
      CommentTranslationService.memory.delete(key)
    }

    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(
      SQL_SELECT_COMMENT_TRANSLATION,
      [CommentTranslationService.textHash(text), targetLang, now],
    )
    try {
      if (resultSet.goToFirstRow()) {
        const translated: string = resultSet.getString(resultSet.getColumnIndex('translated'))
        CommentTranslationService.putMemory(key, translated, now + COMMENT_TRANSLATION_TTL_MS)
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
  ): Promise<string> {
    const source: string = text.trim()
    if (source.length === 0) {
      return ''
    }
    const targetLang: string = CommentTranslationService.targetLanguage()
    const key: string = CommentTranslationService.cacheKey(source, targetLang)
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
    const inFlight: Promise<string> | undefined = CommentTranslationService.inflight.get(key)
    if (inFlight !== undefined) {
      DiagnosticLogger.info(
        'translation',
        'comment_join_inflight',
        `target=${targetLang} len=${source.length} textHash=${DiagnosticLogger.ownerHash(source)}`,
      )
      return inFlight
    }
    const task: Promise<string> = CommentTranslationService.translateAndCache(
      context,
      source,
      targetLang,
    )
    CommentTranslationService.inflight.set(key, task)
    try {
      return await task
    } finally {
      CommentTranslationService.inflight.delete(key)
    }
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    CommentTranslationService.memory.clear()
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

  static async validateConfiguredLlm(): Promise<void> {
    const settings = CommentTranslationSettings.current()
    if (settings.apiKey.length === 0) {
      throw new Error('missing_api_key')
    }
    await CommentTranslationService.callLlm(
      'Hello',
      CommentTranslationService.targetLanguage(),
      settings.apiUrl.length > 0 ? settings.apiUrl : DEFAULT_LLM_BASE_URL,
      settings.apiKey,
      settings.model.length > 0 ? settings.model : DEFAULT_LLM_MODEL,
    )
  }

  static async fetchConfiguredLlmModels(): Promise<string[]> {
    const settings = CommentTranslationSettings.current()
    if (settings.apiKey.length === 0) {
      throw new Error('missing_api_key')
    }
    return CommentTranslationService.fetchLlmModels(
      settings.apiUrl.length > 0 ? settings.apiUrl : DEFAULT_LLM_BASE_URL,
      settings.apiKey,
    )
  }

  private static async translateAndCache(
    context: common.UIAbilityContext,
    text: string,
    targetLang: string,
  ): Promise<string> {
    const startedAt: number = Date.now()
    DiagnosticLogger.info(
      'translation',
      'comment_translate_start',
      `target=${targetLang} len=${text.length} textHash=${DiagnosticLogger.ownerHash(text)}`,
    )
    const rawResult: string = await CommentTranslationService.callTranslation(text, targetLang)
    const result: string = CommentTranslationService.restoreMentionTokens(rawResult)
    await CommentTranslationService.save(context, text, targetLang, result)
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
    targetLang: string,
    translated: string,
  ): Promise<void> {
    const now: number = Date.now()
    const expiresAt: number = now + COMMENT_TRANSLATION_TTL_MS
    CommentTranslationService.putMemory(
      CommentTranslationService.cacheKey(text, targetLang),
      translated,
      expiresAt,
    )
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    await store.executeSql(SQL_DELETE_EXPIRED_COMMENT_TRANSLATIONS, [now])
    await store.executeSql(SQL_UPSERT_COMMENT_TRANSLATION, [
      CommentTranslationService.textHash(text),
      targetLang,
      translated,
      now,
      expiresAt,
    ])
  }

  private static async callTranslation(text: string, targetLang: string): Promise<string> {
    const settings = CommentTranslationSettings.current()
    if (!settings.useGoogleOnly && settings.apiKey.length > 0) {
      try {
        const llmStartedAt: number = Date.now()
        DiagnosticLogger.info(
          'translation',
          'comment_llm_start',
          `target=${targetLang} len=${text.length} model=${settings.model.length > 0 ? settings.model : DEFAULT_LLM_MODEL} baseHash=${DiagnosticLogger.ownerHash(settings.apiUrl.length > 0 ? settings.apiUrl : DEFAULT_LLM_BASE_URL)}`,
        )
        const llmResult: string = await CommentTranslationService.callLlm(
          text,
          targetLang,
          settings.apiUrl.length > 0 ? settings.apiUrl : DEFAULT_LLM_BASE_URL,
          settings.apiKey,
          settings.model.length > 0 ? settings.model : DEFAULT_LLM_MODEL,
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

    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(
        `${CommentTranslationService.stripV1(baseUrl)}/v1/chat/completions`,
        {
          method: http.RequestMethod.POST,
          header: {
            'User-Agent': EhConstants.USER_AGENT,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
          },
          extraData: JSON.stringify(reqBody),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: TRANSLATION_CONNECT_TIMEOUT_MS,
          readTimeout: TRANSLATION_READ_TIMEOUT_MS,
          usingCache: false,
        },
      )
      const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
      if ((resp.responseCode as number) !== 200) {
        throw new Error(`LLM HTTP ${resp.responseCode as number}`)
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
    } finally {
      req.destroy()
    }
  }

  private static async fetchLlmModels(baseUrl: string, apiKey: string): Promise<string[]> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(
        `${CommentTranslationService.stripV1(baseUrl)}/v1/models`,
        {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': EhConstants.USER_AGENT,
            'Accept': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
          },
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: TRANSLATION_CONNECT_TIMEOUT_MS,
          readTimeout: TRANSLATION_READ_TIMEOUT_MS,
          usingCache: false,
        },
      )
      const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
      if ((resp.responseCode as number) !== 200) {
        throw new Error(`LLM models HTTP ${resp.responseCode as number}`)
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
    } finally {
      req.destroy()
    }
  }

  private static async callGoogle(text: string, targetLang: string): Promise<string> {
    const to: string =
      targetLang === 'zh-CN' ? 'zh-cn' : targetLang === 'zh-TW' ? 'zh-tw' : targetLang
    const url: string =
      `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=${encodeURIComponent(to)}` +
      `&dt=t&q=${encodeURIComponent(text)}`
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': 'application/json,text/plain,*/*',
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TRANSLATION_CONNECT_TIMEOUT_MS,
        readTimeout: TRANSLATION_READ_TIMEOUT_MS,
        usingCache: false,
      })
      const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
      if ((resp.responseCode as number) !== 200) {
        throw new Error(`Google Translate HTTP ${resp.responseCode as number}`)
      }
      const translated: string = CommentTranslationService.parseGoogleBody(body)
      if (translated.length === 0) {
        throw new Error('Google Translate returned empty response')
      }
      return translated
    } finally {
      req.destroy()
    }
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
    const entry = new MemoryTranslationEntry()
    entry.translated = translated
    entry.expiresAt = expiresAt
    CommentTranslationService.memory.set(key, entry)
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

  private static cacheKey(text: string, targetLang: string): string {
    return `${CommentTranslationService.textHash(text)}:${targetLang}`
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
