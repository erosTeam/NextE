import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { preferences } from '@kit.ArkData'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { StorageKeys } from '../constants/StorageKeys'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'

export const TORII_CREDITS_ENDPOINT: string =
  'https://api.toriitranslate.com/api/credits'

const TORII_CREDITS_CONNECT_TIMEOUT_MS: number = 15000
const TORII_CREDITS_READ_TIMEOUT_MS: number = 20000
const TORII_CREDITS_MAX_BODY_CHARS: number = 16 * 1024
const TORII_CREDITS_CACHE_MAX_CHARS: number = 1024
const TORII_CREDITS_CACHE_MAX_AGE_MS: number = 24 * 60 * 60 * 1000
const TORII_CREDITS_MAX_VALUE: number = 1000000000000

class RawToriiCreditsResponse {
  credits: number | null = null
}

class RawToriiCreditsCache {
  keyFingerprint: string = ''
  credits: number = 0
  fetchedAtMs: number = 0
}

export class ToriiCreditsSnapshot {
  credits: number = 0
  fetchedAtMs: number = 0

  copy(): ToriiCreditsSnapshot {
    const value: ToriiCreditsSnapshot = new ToriiCreditsSnapshot()
    value.credits = this.credits
    value.fetchedAtMs = this.fetchedAtMs
    return value
  }
}

export interface ToriiCreditsHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultToriiCreditsHttpTransport implements ToriiCreditsHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    return AxiosHttpClient.requestText(
      url,
      method,
      headers,
      body,
      connectTimeoutMs,
      readTimeoutMs,
      TORII_CREDITS_MAX_BODY_CHARS,
    )
  }
}

/** Free Torii balance query with a device-local stale-while-revalidate cache. */
export class ToriiCreditsService {
  static async fetch(
    apiKey: string,
    transport: ToriiCreditsHttpTransport = new DefaultToriiCreditsHttpTransport(),
  ): Promise<ToriiCreditsSnapshot> {
    ToriiCreditsService.validateApiKey(apiKey)
    const response: AxiosTextResponse = await transport.requestText(
      TORII_CREDITS_ENDPOINT,
      'GET',
      {
        'Authorization': `Bearer ${apiKey}`,
        'Accept': 'application/json',
      },
      '',
      TORII_CREDITS_CONNECT_TIMEOUT_MS,
      TORII_CREDITS_READ_TIMEOUT_MS,
    )
    if (response.statusCode !== 200) {
      throw new Error(`Torii credits query failed (HTTP ${response.statusCode})`)
    }
    return ToriiCreditsService.parse(response.body)
  }

  static async cached(
    context: common.UIAbilityContext,
    apiKey: string,
  ): Promise<ToriiCreditsSnapshot | null> {
    if (apiKey.length === 0) {
      return null
    }
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    return ToriiCreditsService.parseCached(
      store.getSync(StorageKeys.COMIC_TRANSLATION_TORII_CREDITS_CACHE, '') as string,
      apiKey,
    )
  }

  static async saveCached(
    context: common.UIAbilityContext,
    apiKey: string,
    snapshot: ToriiCreditsSnapshot,
  ): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(
      context,
      StorageKeys.STORE_SETTINGS,
    )
    store.putSync(
      StorageKeys.COMIC_TRANSLATION_TORII_CREDITS_CACHE,
      ToriiCreditsService.serializeCached(apiKey, snapshot),
    )
    store.flushSync()
  }

  static serializeCached(apiKey: string, snapshot: ToriiCreditsSnapshot): string {
    ToriiCreditsService.validateApiKey(apiKey)
    ToriiCreditsService.validateSnapshot(snapshot)
    const raw: RawToriiCreditsCache = new RawToriiCreditsCache()
    raw.keyFingerprint = ToriiCreditsService.keyFingerprint(apiKey)
    raw.credits = snapshot.credits
    raw.fetchedAtMs = snapshot.fetchedAtMs
    const text: string = JSON.stringify(raw)
    if (text.length <= 0 || text.length > TORII_CREDITS_CACHE_MAX_CHARS) {
      throw new Error('Torii credits cache is invalid')
    }
    return text
  }

  static parseCached(rawText: string, apiKey: string): ToriiCreditsSnapshot | null {
    if (rawText.length <= 0 || rawText.length > TORII_CREDITS_CACHE_MAX_CHARS ||
      apiKey.length === 0) {
      return null
    }
    try {
      ToriiCreditsService.validateApiKey(apiKey)
      const raw: RawToriiCreditsCache | null = JSON.parse(rawText) as RawToriiCreditsCache | null
      if (raw === null || typeof raw !== 'object' ||
        typeof raw.keyFingerprint !== 'string' ||
        raw.keyFingerprint !== ToriiCreditsService.keyFingerprint(apiKey) ||
        typeof raw.credits !== 'number' || typeof raw.fetchedAtMs !== 'number') {
        return null
      }
      const snapshot: ToriiCreditsSnapshot = new ToriiCreditsSnapshot()
      snapshot.credits = raw.credits
      snapshot.fetchedAtMs = raw.fetchedAtMs
      ToriiCreditsService.validateSnapshot(snapshot)
      if (Date.now() - snapshot.fetchedAtMs > TORII_CREDITS_CACHE_MAX_AGE_MS) {
        return null
      }
      return snapshot
    } catch (_error) {
      return null
    }
  }

  static parse(rawText: string): ToriiCreditsSnapshot {
    if (rawText.length <= 0 || rawText.length > TORII_CREDITS_MAX_BODY_CHARS) {
      throw new Error('Torii credits response size is invalid')
    }
    let raw: RawToriiCreditsResponse | null
    try {
      raw = JSON.parse(rawText) as RawToriiCreditsResponse | null
    } catch (_error) {
      throw new Error('Torii credits response is invalid')
    }
    if (raw === null || typeof raw !== 'object' || typeof raw.credits !== 'number') {
      throw new Error('Torii credits response has no balance')
    }
    const snapshot: ToriiCreditsSnapshot = new ToriiCreditsSnapshot()
    snapshot.credits = raw.credits
    snapshot.fetchedAtMs = Date.now()
    ToriiCreditsService.validateSnapshot(snapshot)
    return snapshot
  }

  private static validateApiKey(value: string): void {
    if (value.length <= 0 || value.length > 8192 || value !== value.trim() ||
      /[\r\n\t]/.test(value) || value.includes('\u0000')) {
      throw new Error('Torii API credential is invalid')
    }
  }

  private static validateSnapshot(snapshot: ToriiCreditsSnapshot): void {
    if (!Number.isFinite(snapshot.credits) || snapshot.credits < 0 ||
      snapshot.credits > TORII_CREDITS_MAX_VALUE ||
      !Number.isFinite(snapshot.fetchedAtMs) || snapshot.fetchedAtMs <= 0 ||
      Math.floor(snapshot.fetchedAtMs) !== snapshot.fetchedAtMs ||
      snapshot.fetchedAtMs > Number.MAX_SAFE_INTEGER) {
      throw new Error('Torii credits snapshot is invalid')
    }
  }

  private static keyFingerprint(apiKey: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new util.TextEncoder().encodeInto(apiKey) })
    const bytes: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let index: number = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}
