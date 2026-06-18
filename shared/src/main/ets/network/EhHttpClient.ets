import { http } from '@kit.NetworkKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EhConstants } from '../constants/EhConstants'
import { EhCookieStore } from './EhCookieStore'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export interface EhTextResponse {
  statusCode: number
  body: string
}

const MAX_RETRIES: number = 3
const CONNECT_TIMEOUT_MS: number = 10000
const READ_TIMEOUT_MS: number = 20000
const BACKOFF_BASE_MS: number = 800
const MAX_BINARY_BYTES: number = 100 * 1024 * 1024

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
        const body: string = typeof resp.result === 'string' ? resp.result as string : ''
        req.destroy()
        if (code >= 500 && attempt < MAX_RETRIES - 1) {
          lastError = new Error(`HTTP ${code}`)
        } else {
          return { statusCode: code, body: body }
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
    throw (lastError !== null ? lastError : new Error('request failed'))
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
    throw (lastError !== null ? lastError : new Error('request failed'))
  }

  async downloadBinaryToFile(url: string, filePath: string): Promise<number> {
    let attempt: number = 0
    let lastError: Error | null = null
    while (attempt < MAX_RETRIES) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const header: Record<string, string> = {
          'User-Agent': EhConstants.USER_AGENT,
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
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
    throw (lastError !== null ? lastError : new Error('binary request failed'))
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
