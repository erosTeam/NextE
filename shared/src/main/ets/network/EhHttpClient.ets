import { http } from '@kit.NetworkKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EhConstants } from '../constants/EhConstants'
import { EhCookieStore } from './EhCookieStore'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export interface EhTextResponse {
  statusCode: number
  body: string
  // Server Set-Cookie response (HttpResponse.cookies). Used to capture igneous/identity cookies that EH
  // sets on a response (igneous from exhentai.org/uconfig.php, ipb_* from a forums password login).
  cookies?: string
  // Full response headers as a JSON string. HttpResponse.cookies is LOSSY (it drops the igneous
  // Set-Cookie from exhentai.org/uconfig.php), so Set-Cookie capture reads auth cookies from here.
  rawHeader?: string
}

const MAX_RETRIES: number = 3
const CONNECT_TIMEOUT_MS: number = 10000
const READ_TIMEOUT_MS: number = 20000
const BACKOFF_BASE_MS: number = 800
const MAX_BINARY_BYTES: number = 100 * 1024 * 1024
const IMAGE_ACCEPT: string = 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'

/**
 * EH HTTP transport over @ohos.net.http. Singleton. Sets the desktop Chrome UA + Accept
 * headers EH expects, injects the cookie jar (forced nw=1), auto-gzip, exponential-backoff
 * retry on transport errors / 5xx, and destroys each request to avoid leaks.
 *
 * Anti-block (per the dropped-domain-fronting decision): standard requests + DoH/fallback-IP
 * resolution + user proxy/VPN are layered in later via a pluggable resolver; M1 connects
 * directly (the table site is reachable on the test network).
 */
export class EhHttpClient {
  private static instance: EhHttpClient

  static getInstance(): EhHttpClient {
    if (!EhHttpClient.instance) {
      EhHttpClient.instance = new EhHttpClient()
    }
    return EhHttpClient.instance
  }

  async getText(url: string): Promise<EhTextResponse> {
    let attempt: number = 0
    let lastError: Error | null = null
    while (attempt < MAX_RETRIES) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': EhConstants.ACCEPT,
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
          'Accept-Encoding': 'gzip',
          'Cookie': EhCookieStore.getInstance().header(),
        }
        const resp: http.HttpResponse = await req.request(url, {
          method: http.RequestMethod.GET,
          header: header,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
          usingCache: false,
        })
        const code: number = resp.responseCode as number
        const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
        const cookies: string = typeof resp.cookies === 'string' ? resp.cookies : ''
        const rawHeader: string = JSON.stringify(resp.header)
        req.destroy()
        if (code >= 500 && attempt < MAX_RETRIES - 1) {
          lastError = new Error(`HTTP ${code}`)
        } else {
          return { statusCode: code, body: body, cookies: cookies, rawHeader: rawHeader }
        }
      } catch (error) {
        const e = error as Error
        lastError = e
        DiagnosticLogger.warn('network', 'http_get_retry', `attempt ${attempt}: ${e.message}`)
        req.destroy()
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('request failed')
  }

  async getTextWithReferer(url: string, referer: string): Promise<EhTextResponse> {
    let attempt: number = 0
    let lastError: Error | null = null
    while (attempt < MAX_RETRIES) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': EhConstants.ACCEPT,
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
          'Accept-Encoding': 'gzip',
          'Referer': referer,
          'Cookie': EhCookieStore.getInstance().header(),
        }
        const resp: http.HttpResponse = await req.request(url, {
          method: http.RequestMethod.GET,
          header: header,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
          usingCache: false,
        })
        const code: number = resp.responseCode as number
        const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
        const cookies: string = typeof resp.cookies === 'string' ? resp.cookies : ''
        const rawHeader: string = JSON.stringify(resp.header)
        req.destroy()
        if (code >= 500 && attempt < MAX_RETRIES - 1) {
          lastError = new Error(`HTTP ${code}`)
        } else {
          return { statusCode: code, body: body, cookies: cookies, rawHeader: rawHeader }
        }
      } catch (error) {
        const e = error as Error
        lastError = e
        DiagnosticLogger.warn('network', 'http_get_referer_retry', `attempt ${attempt}: ${e.message}`)
        req.destroy()
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('request failed')
  }

  /** POST a JSON body (EH /api.php). Same headers/cookies/retry as getText, plus Content-Type. */
  async postJson(url: string, body: string): Promise<EhTextResponse> {
    let attempt: number = 0
    let lastError: Error | null = null
    while (attempt < MAX_RETRIES) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': EhConstants.ACCEPT,
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
          'Accept-Encoding': 'gzip',
          'Content-Type': 'application/json',
          'Cookie': EhCookieStore.getInstance().header(),
        }
        const resp: http.HttpResponse = await req.request(url, {
          method: http.RequestMethod.POST,
          header: header,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
          usingCache: false,
        })
        const code: number = resp.responseCode as number
        const respBody: string = typeof resp.result === 'string' ? (resp.result as string) : ''
        req.destroy()
        if (code >= 500 && attempt < MAX_RETRIES - 1) {
          lastError = new Error(`HTTP ${code}`)
        } else {
          return { statusCode: code, body: respBody }
        }
      } catch (error) {
        const e = error as Error
        lastError = e
        DiagnosticLogger.warn('network', 'http_post_retry', `attempt ${attempt}: ${e.message}`)
        req.destroy()
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('request failed')
  }

  /** POST a classic PHP form body. Used by protected EH write endpoints after explicit user confirmation. */
  async postFormUrlEncoded(url: string, body: string): Promise<EhTextResponse> {
    let attempt: number = 0
    let lastError: Error | null = null
    while (attempt < MAX_RETRIES) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': EhConstants.ACCEPT,
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
          'Accept-Encoding': 'gzip',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': EhCookieStore.getInstance().header(),
        }
        const resp: http.HttpResponse = await req.request(url, {
          method: http.RequestMethod.POST,
          header: header,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
          usingCache: false,
        })
        const code: number = resp.responseCode as number
        const respBody: string = typeof resp.result === 'string' ? (resp.result as string) : ''
        req.destroy()
        if (code >= 500 && attempt < MAX_RETRIES - 1) {
          lastError = new Error(`HTTP ${code}`)
        } else {
          return { statusCode: code, body: respBody }
        }
      } catch (error) {
        const e = error as Error
        lastError = e
        DiagnosticLogger.warn('network', 'http_form_retry', `attempt ${attempt}: ${e.message}`)
        req.destroy()
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('request failed')
  }

  /**
   * POST the forums password-login form (single attempt). Sends a Referer + urlencoded body and returns
   * the FULL response header (rawHeader) so the caller can capture the Set-Cookie identity cookies — the
   * login succeeds iff that header carries ipb_member_id + ipb_pass_hash.
   */
  async postLogin(url: string, body: string, referer: string): Promise<EhTextResponse> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': EhConstants.ACCEPT,
        'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
        'Accept-Encoding': 'gzip',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': referer,
        'Cookie': EhCookieStore.getInstance().header(),
      }
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      const respBody: string = typeof resp.result === 'string' ? (resp.result as string) : ''
      const rawHeader: string = JSON.stringify(resp.header)
      req.destroy()
      return { statusCode: code, body: respBody, rawHeader: rawHeader }
    } catch (error) {
      req.destroy()
      throw error as Error
    }
  }

  async downloadBinaryToFile(url: string, filePath: string): Promise<number> {
    let attempt: number = 0
    let lastError: Error | null = null
    while (attempt < MAX_RETRIES) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': IMAGE_ACCEPT,
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
          'Cookie': EhCookieStore.getInstance().header(),
        }
        const resp: http.HttpResponse = await req.request(url, {
          method: http.RequestMethod.GET,
          header: header,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          maxLimit: MAX_BINARY_BYTES,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
          usingCache: false,
        })
        const code: number = resp.responseCode as number
        if (code >= 500 && attempt < MAX_RETRIES - 1) {
          req.destroy()
          lastError = new Error(`HTTP ${code}`)
        } else if (code !== 200) {
          req.destroy()
          throw new Error(`image HTTP ${code}`)
        } else if (typeof resp.result === 'string') {
          req.destroy()
          throw new Error('image response is not binary')
        } else {
          const bytes: ArrayBuffer = resp.result as ArrayBuffer
          const written: number = await EhHttpClient.writeArrayBuffer(filePath, bytes)
          req.destroy()
          return written
        }
      } catch (error) {
        const e = error as Error
        lastError = e
        DiagnosticLogger.warn('network', 'http_binary_retry', `attempt ${attempt}: ${e.message}`)
        req.destroy()
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('binary request failed')
  }

  async downloadBinaryToFileInStream(
    url: string,
    filePath: string,
    progress: (loaded: number, total: number) => void,
    accept: string = IMAGE_ACCEPT,
    maxAttempts: number = MAX_RETRIES,
  ): Promise<number> {
    let attempt: number = 0
    let lastError: Error | null = null
    const attempts: number = Math.max(1, Math.round(maxAttempts))
    while (attempt < attempts) {
      const req: http.HttpRequest = http.createHttp()
      let file: fs.File | null = null
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': accept,
          'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
          'Cookie': EhCookieStore.getInstance().header(),
        }
        file = fs.openSync(
          filePath,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
        )
        let written: number = 0
        let progressTotal: number = 0
        req.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
          progressTotal = info.totalSize
          progress(info.receiveSize, progressTotal)
        })
        req.on('dataReceive', (data: ArrayBuffer) => {
          const offset: number = written
          const len: number = fs.writeSync((file as fs.File).fd, data, { offset: offset })
          written += len
          progress(written, progressTotal)
        })
        const code: number = await req.requestInStream(url, {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
          usingCache: false,
        })
        req.destroy()
        fs.closeSync(file)
        file = null
        if (code >= 500 && attempt < attempts - 1) {
          lastError = new Error(`HTTP ${code}`)
        } else if (code !== 200) {
          throw new Error(`binary HTTP ${code}`)
        } else {
          progress(written, progressTotal > 0 ? progressTotal : written)
          return written
        }
      } catch (error) {
        const e = error as Error
        lastError = e
        DiagnosticLogger.warn(
          'network',
          'http_binary_stream_retry',
          `attempt ${attempt}: ${e.message}`,
        )
        req.destroy()
      } finally {
        if (file !== null) {
          fs.closeSync(file)
        }
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('binary stream request failed')
  }

  private static async writeArrayBuffer(filePath: string, bytes: ArrayBuffer): Promise<number> {
    let file: fs.File | null = null
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      const written: number = await fs.write(file.fd, bytes)
      return written
    } finally {
      if (file !== null) {
        fs.closeSync(file)
      }
    }
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }
}
