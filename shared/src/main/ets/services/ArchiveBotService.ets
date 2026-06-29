import { http } from '@kit.NetworkKit'
import { ArchiveBotType, DownloadSettingsState } from '../state/DownloadSettingsState'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const CONNECT_TIMEOUT_MS: number = 10000
const READ_TIMEOUT_MS: number = 30000
const ARCHIVE_AT_HOME_CLIENT: string = 'app/jhentai'

class ArchiveBotResponseJson {
  code?: number
  msg?: string
  data?: ArchiveBotDataJson
  error?: string
}

class ArchiveBotDataJson {
  archive_url?: string
  current_GP?: Object
  get_GP?: Object
  balance?: Object
  reward?: Object
}

export class ArchiveBotBalanceResult {
  gp: number = 0
  message: string = ''
}

export class ArchiveBotCheckInResult {
  reward: number = 0
  gp: number = 0
  message: string = ''
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
    out.gp = settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME
      ? ArchiveBotService.safeNumber(data.balance)
      : ArchiveBotService.safeNumber(data.current_GP)
    out.message = ArchiveBotService.message(resp)
    return out
  }

  static async requestCheckIn(settings: DownloadSettingsState): Promise<ArchiveBotCheckInResult> {
    const resp: ArchiveBotResponseJson = await ArchiveBotService.requestBot(settings, 'checkin', '', '', false)
    ArchiveBotService.assertSuccess(resp)
    const data: ArchiveBotDataJson = resp.data !== undefined ? resp.data : new ArchiveBotDataJson()
    const out: ArchiveBotCheckInResult = new ArchiveBotCheckInResult()
    out.reward = settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME
      ? ArchiveBotService.safeNumber(data.reward)
      : ArchiveBotService.safeNumber(data.get_GP)
    out.gp = settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME
      ? ArchiveBotService.safeNumber(data.balance)
      : ArchiveBotService.safeNumber(data.current_GP)
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
    const url: string = ArchiveBotService.endpoint(settings, action)
    const body: string = ArchiveBotService.body(settings, action, gid, token, reParse)
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: ArchiveBotService.method(settings, action),
        header: ArchiveBotService.headers(settings),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      const text: string = typeof resp.result === 'string' ? resp.result as string : ''
      req.destroy()
      if (code >= 400) {
        const errResp: ArchiveBotResponseJson = ArchiveBotService.parseResponse(text)
        throw new Error(ArchiveBotService.message(errResp))
      }
      return ArchiveBotService.parseResponse(text)
    } catch (error) {
      req.destroy()
      DiagnosticLogger.warn('download', 'archive_bot_request_failed', `${action}: ${(error as Error).message}`)
      throw error as Error
    }
  }

  private static endpoint(settings: DownloadSettingsState, action: string): string {
    const base: string = ArchiveBotService.trimRightSlash(settings.archiveBotAddress)
    if (settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME) {
      if (action === 'balance') {
        return `${base}/api/v1/me/balance`
      }
      if (action === 'checkin') {
        return `${base}/api/v1/me/checkin`
      }
      return `${base}/api/v1/parse`
    }
    return `${base}/${action === 'resolve' ? 'resolve' : action}`
  }

  private static method(settings: DownloadSettingsState, action: string): http.RequestMethod {
    if (settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME && action === 'balance') {
      return http.RequestMethod.GET
    }
    return http.RequestMethod.POST
  }

  private static headers(settings: DownloadSettingsState): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': EhConstants.USER_AGENT,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
      'Content-Type': 'application/json',
    }
    if (settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME) {
      headers.Authorization = `Bearer ${settings.archiveBotApiKey}`
      headers['X-Client'] = ARCHIVE_AT_HOME_CLIENT
    }
    return headers
  }

  private static body(
    settings: DownloadSettingsState,
    action: string,
    gid: string,
    token: string,
    reParse: boolean,
  ): string {
    if (settings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME) {
      if (action === 'balance') {
        return ''
      }
      if (action === 'checkin') {
        return ''
      }
      return JSON.stringify({
        gallery_id: gid,
        gallery_key: token,
        force: reParse,
      })
    }
    if (action === 'resolve') {
      return JSON.stringify({
        apikey: settings.archiveBotApiKey,
        gid: Number.parseInt(gid, 10),
        token: token,
        force_resolve: reParse,
      })
    }
    return JSON.stringify({ apikey: settings.archiveBotApiKey })
  }

  private static parseResponse(body: string): ArchiveBotResponseJson {
    const rec = JSON.parse(body) as ArchiveBotResponseJson
    const out: ArchiveBotResponseJson = new ArchiveBotResponseJson()
    out.code = typeof rec.code === 'number' ? rec.code : 0
    out.msg = typeof rec.msg === 'string' ? rec.msg : ''
    const raw: ArchiveBotDataJson = rec.data !== undefined ? rec.data : (rec as ArchiveBotDataJson)
    const rawAny = raw as Record<string, Object>
    const data: ArchiveBotDataJson = new ArchiveBotDataJson()
    data.archive_url = typeof raw.archive_url === 'string' ? raw.archive_url : ''
    data.current_GP = ArchiveBotService.safeNumber(raw.current_GP)
    data.get_GP = ArchiveBotService.safeNumber(raw.get_GP)
    data.balance = ArchiveBotService.safeNumber(raw.balance)
    data.reward = ArchiveBotService.safeNumber(raw.reward)
    out.data = data
    out.error = typeof rec.error === 'string' ? rec.error : ''
    if (rec.data !== undefined) {
      return out
    }
    const hasBusinessData: boolean = rawAny.archive_url !== undefined || rawAny.current_GP !== undefined ||
      rawAny.get_GP !== undefined || rawAny.balance !== undefined || rawAny.reward !== undefined
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
    if (code === 7) {
      return 'Already checked in'
    }
    return 'Archive bot error'
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

  private static trimRightSlash(value: string): string {
    let out: string = value.trim()
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1)
    }
    return out
  }
}
