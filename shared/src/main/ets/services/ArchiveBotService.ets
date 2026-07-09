import { DownloadSettingsState } from '../state/DownloadSettingsState'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'

const CONNECT_TIMEOUT_MS: number = 10000
const READ_TIMEOUT_MS: number = 30000
const ARCHIVE_AT_HOME_BASE_URL: string = 'https://api.archive-at-home.org'
const ARCHIVE_AT_HOME_CLIENT: string = 'app/jhentai'

class ArchiveBotResponseJson {
  code?: number
  msg?: string
  message?: string
  data?: ArchiveBotDataJson
  error?: string
}

class ArchiveBotDataJson {
  archive_url?: string
  balance?: Object
}

export class ArchiveBotBalanceResult {
  gp: number = 0
  message: string = ''
  hasBalance: boolean = false
}

export class ArchiveBotResolveResult {
  url: string = ''
  message: string = ''
}

export class ArchiveBotService {
  static async requestBalance(settings: DownloadSettingsState): Promise<ArchiveBotBalanceResult> {
    const resp: ArchiveBotResponseJson = await ArchiveBotService.requestBot(settings, 'balance', '', '', false)
    ArchiveBotService.assertSuccess(resp)
    const data: ArchiveBotDataJson = resp.data !== undefined ? resp.data : new ArchiveBotDataJson()
    const out: ArchiveBotBalanceResult = new ArchiveBotBalanceResult()
    out.hasBalance = data.balance !== undefined
    out.gp = ArchiveBotService.safeNumber(data.balance)
    out.message = ArchiveBotService.message(resp)
    return out
  }

  static async requestResolve(
    settings: DownloadSettingsState,
    gid: string,
    token: string,
    reParse: boolean,
  ): Promise<ArchiveBotResolveResult> {
    const resp: ArchiveBotResponseJson = await ArchiveBotService.requestBot(settings, 'resolve', gid, token, reParse)
    ArchiveBotService.assertSuccess(resp)
    const data: ArchiveBotDataJson = resp.data !== undefined ? resp.data : new ArchiveBotDataJson()
    const out: ArchiveBotResolveResult = new ArchiveBotResolveResult()
    out.url = typeof data.archive_url === 'string' ? data.archive_url : ''
    out.message = ArchiveBotService.message(resp)
    if (out.url.length === 0) {
      throw new Error('archive bot returned empty archive url')
    }
    return out
  }

  private static async requestBot(
    settings: DownloadSettingsState,
    action: string,
    gid: string,
    token: string,
    reParse: boolean,
  ): Promise<ArchiveBotResponseJson> {
    const url: string = ArchiveBotService.endpoint(action)
    const body: string = ArchiveBotService.body(action, gid, token, reParse)
    DiagnosticLogger.info(
      'download',
      'archive_bot_request_start',
      `${settings.archiveBotType} action=${action} gidHash=${DiagnosticLogger.ownerHash(gid)}`,
    )
    try {
      const requestHeaders: Record<string, string> = body.length > 0
        ? ArchiveBotService.headers(settings, true)
        : ArchiveBotService.headers(settings, false)
      const resp: AxiosTextResponse = await AxiosHttpClient.requestText(
        url,
        ArchiveBotService.method(action),
        requestHeaders,
        body,
        CONNECT_TIMEOUT_MS,
        READ_TIMEOUT_MS,
      )
      const code: number = resp.statusCode
      const text: string = resp.body
      DiagnosticLogger.info(
        'download',
        'archive_bot_response_summary',
        `${settings.archiveBotType} action=${action} http=${code} ${ArchiveBotService.responseSummary(text)}`,
      )
      if (code >= 400) {
        const errResp: ArchiveBotResponseJson = ArchiveBotService.parseResponse(text)
        DiagnosticLogger.warn(
          'download',
          'archive_bot_http_error',
          `${settings.archiveBotType} action=${action} http=${code} message=${ArchiveBotService.message(errResp)}`,
        )
        throw new Error(ArchiveBotService.message(errResp))
      }
      const parsed: ArchiveBotResponseJson = ArchiveBotService.parseResponse(text)
      DiagnosticLogger.info(
        'download',
        'archive_bot_request_done',
        `${settings.archiveBotType} action=${action} code=${parsed.code}`,
      )
      return parsed
    } catch (error) {
      DiagnosticLogger.warn('download', 'archive_bot_request_failed', `${action}: ${(error as Error).message}`)
      throw error as Error
    }
  }

  private static endpoint(action: string): string {
    if (action === 'balance') {
      return `${ARCHIVE_AT_HOME_BASE_URL}/api/v1/me/balance`
    }
    return `${ARCHIVE_AT_HOME_BASE_URL}/api/v1/parse`
  }

  private static method(action: string): string {
    if (action === 'balance') {
      return 'GET'
    }
    return 'POST'
  }

  private static headers(settings: DownloadSettingsState, hasBody: boolean): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': EhConstants.USER_AGENT,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
    }
    if (hasBody) {
      headers['Content-Type'] = 'application/json'
    }
    headers.Authorization = `Bearer ${settings.archiveBotApiKey}`
    headers['X-Client'] = ARCHIVE_AT_HOME_CLIENT
    return headers
  }

  private static body(
    action: string,
    gid: string,
    token: string,
    reParse: boolean,
  ): string {
    if (action === 'balance') {
      return ''
    }
    return JSON.stringify({
      gallery_id: gid,
      gallery_key: token,
      force: reParse,
    })
  }

  private static parseResponse(body: string): ArchiveBotResponseJson {
    const rec = JSON.parse(body) as ArchiveBotResponseJson
    const out: ArchiveBotResponseJson = new ArchiveBotResponseJson()
    out.code = typeof rec.code === 'number' ? rec.code : 0
    out.msg = typeof rec.msg === 'string' ? rec.msg : ''
    out.message = typeof rec.message === 'string' ? rec.message : ''
    const raw: ArchiveBotDataJson = rec.data !== undefined ? rec.data : (rec as ArchiveBotDataJson)
    const rawAny = raw as Record<string, Object>
    const data: ArchiveBotDataJson = new ArchiveBotDataJson()
    data.archive_url = typeof raw.archive_url === 'string' ? raw.archive_url : ''
    if (raw.balance !== undefined) {
      data.balance = ArchiveBotService.safeNumber(raw.balance)
    }
    out.data = data
    out.error = typeof rec.error === 'string' ? rec.error : ''
    if (rec.data !== undefined) {
      return out
    }
    const hasBusinessData: boolean = rawAny.archive_url !== undefined || rawAny.balance !== undefined
    if (!hasBusinessData && typeof rec.code !== 'number') {
      out.code = 99
    }
    return out
  }

  private static assertSuccess(resp: ArchiveBotResponseJson): void {
    if (resp.code !== 0) {
      throw new Error(ArchiveBotService.message(resp))
    }
  }

  private static message(resp: ArchiveBotResponseJson): string {
    if (typeof resp.msg === 'string' && resp.msg.length > 0) {
      return resp.msg
    }
    if (typeof resp.message === 'string' && resp.message.length > 0) {
      return resp.message
    }
    if (typeof resp.error === 'string' && resp.error.length > 0) {
      return resp.error
    }
    return ArchiveBotService.errorName(resp.code)
  }

  private static errorName(code?: number): string {
    if (code === 1) {
      return 'Invalid parameter'
    }
    if (code === 2) {
      return 'Invalid API key'
    }
    if (code === 3) {
      return 'Banned'
    }
    if (code === 4) {
      return 'Failed to fetch gallery info'
    }
    if (code === 5) {
      return 'Insufficient GP'
    }
    if (code === 6) {
      return 'Parse failed'
    }
    return 'Archive bot error'
  }

  private static responseSummary(body: string): string {
    try {
      const rec = JSON.parse(body) as Record<string, Object>
      const data = rec.data as Record<string, Object> | undefined
      const keys: string = Object.keys(rec).join(',')
      const dataKeys: string = data !== undefined && typeof data === 'object' ? Object.keys(data).join(',') : ''
      const message: string = typeof rec.message === 'string' ? rec.message as string :
        typeof rec.msg === 'string' ? rec.msg as string : ''
      const balance: Object | undefined = data !== undefined && data.balance !== undefined ? data.balance : rec.balance
      return `keys=${keys} dataKeys=${dataKeys} balance=${balance ?? ''} message=${message}`
    } catch (_error) {
      return 'unparseable'
    }
  }

  private static safeNumber(value?: Object): number {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.floor(value)
    }
    if (typeof value === 'string') {
      const parsed: number = Number.parseFloat(value)
      return Number.isFinite(parsed) ? Math.floor(parsed) : 0
    }
    return 0
  }

}
