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
const STREAM_PROGRESS_INTERVAL_MS: number = 500

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
          if (written <= 0) {
            EhHttpClient.deleteFileQuietly(filePath)
            throw new Error('binary response is empty')
          }
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
    readTimeoutMs: number = READ_TIMEOUT_MS,
  ): Promise<number> {
    let attempt: number = 0
    let lastError: Error | null = null
    const attempts: number = Math.max(1, Math.round(maxAttempts))
    while (attempt < attempts) {
      const req: http.HttpRequest = http.createHttp()
      let file: fs.File | null = null
      let openedTarget: boolean = false
      let shouldDeleteFile: boolean = false
      try {
        const header: Record<string, string> = EhHttpClient.binaryHeader(accept)
        file = fs.openSync(
          filePath,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
        )
        openedTarget = true
        let written: number = 0
        let progressTotal: number = 0
        let progressLoaded: number = 0
        let lastProgressAt: number = 0
        let lastProgressLoaded: number = -1
        let lastProgressTotal: number = -1
        const emitProgress = (loaded: number, total: number, force: boolean = false): void => {
          if (loaded <= 0) {
            return
          }
          const now: number = force ? 0 : Date.now()
          if (!force && now - lastProgressAt < STREAM_PROGRESS_INTERVAL_MS) {
            return
          }
          if (!force && loaded === lastProgressLoaded && total === lastProgressTotal) {
            return
          }
          lastProgressAt = force ? Date.now() : now
          lastProgressLoaded = loaded
          lastProgressTotal = total
          progress(loaded, total)
        }
        req.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
          if (info.totalSize > progressTotal) {
            progressTotal = info.totalSize
          }
          if (info.receiveSize > progressLoaded) {
            progressLoaded = info.receiveSize
          }
          emitProgress(progressLoaded, progressTotal)
        })
        req.on('dataReceive', (data: ArrayBuffer) => {
          const offset: number = written
          const len: number = fs.writeSync((file as fs.File).fd, data, { offset: offset })
          written += len
          if (written > progressLoaded) {
            progressLoaded = written
          }
          emitProgress(progressLoaded, progressTotal)
        })
        const code: number = await req.requestInStream(url, {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: readTimeoutMs,
          usingCache: false,
        })
        req.destroy()
        fs.closeSync(file)
        file = null
        if (code >= 500 && attempt < attempts - 1) {
          shouldDeleteFile = true
          lastError = new Error(`HTTP ${code}`)
        } else if (code !== 200) {
          throw new Error(`binary HTTP ${code}`)
        } else if (written <= 0) {
          shouldDeleteFile = true
          throw new Error('binary response is empty')
        } else {
          emitProgress(written, progressTotal > 0 ? progressTotal : written, true)
          return written
        }
      } catch (error) {
        const e = error as Error
        shouldDeleteFile = openedTarget
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
        if (shouldDeleteFile) {
          EhHttpClient.deleteFileQuietly(filePath)
        }
      }
      attempt++
      await EhHttpClient.delay(BACKOFF_BASE_MS * attempt)
    }
    throw lastError !== null ? lastError : new Error('binary stream request failed')
  }

  async downloadBinaryToFileInStreamResumable(
    url: string,
    partialPath: string,
    progress: (loaded: number, total: number) => void,
    shouldCancel: () => boolean,
    knownTotal: number = 0,
    accept: string = IMAGE_ACCEPT,
    maxAttempts: number = MAX_RETRIES,
    readTimeoutMs: number = READ_TIMEOUT_MS,
  ): Promise<number> {
    let attempt: number = 0
    let lastError: Error | null = null
    const attempts: number = Math.max(1, Math.round(maxAttempts))
    while (attempt < attempts) {
      const req: http.HttpRequest = http.createHttp()
      let file: fs.File | null = null
      let openedTarget: boolean = false
      let attemptStart: number = EhHttpClient.fileSizeQuietly(partialPath)
      let written: number = attemptStart
      let responseTotal: number = knownTotal
      let lastProgressAt: number = 0
      let lastProgressLoaded: number = -1
      let lastProgressTotal: number = -1
      let headersSeen: boolean = attemptStart <= 0
      let resumeAccepted: boolean = attemptStart <= 0
      let resumeDecisionLogged: boolean = attemptStart <= 0
      let prepared: boolean = false
      let cancelled: boolean = false
      let streamError: string = ''
      const emitProgress = (loaded: number, total: number, force: boolean = false): void => {
        if (loaded <= 0) {
          return
        }
        const now: number = force ? 0 : Date.now()
        if (!force && now - lastProgressAt < STREAM_PROGRESS_INTERVAL_MS) {
          return
        }
        if (!force && loaded === lastProgressLoaded && total === lastProgressTotal) {
          return
        }
        lastProgressAt = force ? Date.now() : now
        lastProgressLoaded = loaded
        lastProgressTotal = total
        progress(loaded, total)
      }
      try {
        if (attemptStart > 0) {
          emitProgress(attemptStart, knownTotal, true)
        }
        const header: Record<string, string> = EhHttpClient.binaryHeader(accept)
        if (attemptStart > 0) {
          header['Range'] = `bytes=${attemptStart}-`
        }
        req.on('headersReceive', (respHeader: Object) => {
          headersSeen = true
          const contentRange: string = EhHttpClient.headerValue(respHeader, 'content-range')
          const rangeStart: number = EhHttpClient.contentRangeStart(contentRange)
          const rangeTotal: number = EhHttpClient.contentRangeTotal(contentRange)
          resumeAccepted = attemptStart <= 0 || rangeStart === attemptStart
          if (attemptStart > 0 && !resumeDecisionLogged) {
            DiagnosticLogger.info(
              'network',
              resumeAccepted ? 'http_binary_resume_accepted' : 'http_binary_resume_ignored',
              `start=${attemptStart}`,
            )
            resumeDecisionLogged = true
          }
          if (rangeTotal > 0) {
            responseTotal = rangeTotal
            return
          }
          const contentLength: number = EhHttpClient.positiveIntHeader(respHeader, 'content-length')
          if (contentLength > 0) {
            responseTotal = resumeAccepted ? attemptStart + contentLength : contentLength
          }
        })
        req.on('dataReceive', (data: ArrayBuffer) => {
          if (cancelled || streamError.length > 0) {
            return
          }
          if (shouldCancel()) {
            cancelled = true
            req.destroy()
            return
          }
          if (!headersSeen && attemptStart > 0) {
            streamError = 'resume response headers missing'
            req.destroy()
            return
          }
          if (attemptStart > 0 && !resumeAccepted) {
            streamError = 'binary resume unsupported'
            req.destroy()
            return
          }
          if (!prepared) {
            const mode: number = fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE
            file = fs.openSync(partialPath, mode)
            openedTarget = true
            prepared = true
          }
          const len: number = fs.writeSync((file as fs.File).fd, data, { offset: written })
          written += len
          emitProgress(written, responseTotal)
        })
        const code: number = await req.requestInStream(url, {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: readTimeoutMs,
          usingCache: false,
        })
        req.destroy()
        if (file !== null) {
          fs.closeSync(file)
          file = null
        }
        if (cancelled || shouldCancel()) {
          throw new Error('binary download cancelled')
        }
        if (streamError.length > 0) {
          throw new Error(streamError)
        }
        if (code === 416 && knownTotal > 0 && attemptStart >= knownTotal) {
          emitProgress(attemptStart, knownTotal, true)
          return attemptStart
        }
        if (code !== 200 && code !== 206) {
          EhHttpClient.truncateQuietly(partialPath, attemptStart)
          throw new Error(`binary HTTP ${code}`)
        }
        if (attemptStart > 0 && !resumeAccepted) {
          throw new Error(code === 206 ? 'invalid content range' : 'binary resume unsupported')
        }
        if (written <= 0) {
          throw new Error('binary response is empty')
        }
        emitProgress(written, responseTotal > 0 ? responseTotal : written, true)
        return written
      } catch (error) {
        const e = error as Error
        lastError = streamError.length > 0 ? new Error(streamError) : e
        if (!cancelled && streamError.length === 0 && e.message !== 'binary download cancelled') {
          DiagnosticLogger.warn(
            'network',
            'http_binary_resumable_retry',
            `attempt ${attempt}: start=${attemptStart} written=${written} error=${e.message}`,
          )
        }
        req.destroy()
      } finally {
        if (file !== null) {
          fs.closeSync(file)
        }
        if (openedTarget && !cancelled && lastError !== null && written < attemptStart) {
          EhHttpClient.truncateQuietly(partialPath, attemptStart)
        }
      }
      if (streamError.length > 0) {
        throw lastError !== null ? lastError : new Error(streamError)
      }
      if (cancelled || lastError?.message === 'binary download cancelled') {
        throw lastError !== null ? lastError : new Error('binary download cancelled')
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

  private static deleteFileQuietly(filePath: string): void {
    try {
      if (filePath.length > 0 && fs.accessSync(filePath)) {
        fs.unlinkSync(filePath)
      }
    } catch (error) {
      DiagnosticLogger.warn('network', 'http_empty_file_delete_failed', (error as Error).message)
    }
  }

  private static fileSizeQuietly(filePath: string): number {
    try {
      if (!fs.accessSync(filePath)) {
        return 0
      }
      const stat: fs.Stat = fs.statSync(filePath)
      return stat.isFile() && stat.size > 0 ? stat.size : 0
    } catch (_error) {
      return 0
    }
  }

  private static binaryHeader(accept: string): Record<string, string> {
    return {
      'User-Agent': EhConstants.USER_AGENT,
      'Accept': accept,
      'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
      'Cookie': EhCookieStore.getInstance().header(),
    }
  }

  private static truncateQuietly(filePath: string, len: number): void {
    try {
      if (fs.accessSync(filePath)) {
        fs.truncateSync(filePath, Math.max(0, len))
      }
    } catch (error) {
      DiagnosticLogger.warn('network', 'http_partial_truncate_failed', (error as Error).message)
    }
  }

  private static headerValue(header: Object, name: string): string {
    const record: Record<string, Object> = header as Record<string, Object>
    const keys: string[] = Object.keys(record)
    const expected: string = name.toLowerCase()
    for (let i: number = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === expected) {
        const value: Object = record[keys[i]]
        return typeof value === 'string' ? value as string : JSON.stringify(value)
      }
    }
    return ''
  }

  private static positiveIntHeader(header: Object, name: string): number {
    const value: string = EhHttpClient.headerValue(header, name)
    if (value.length === 0) {
      return 0
    }
    const n: number = Number.parseInt(value, 10)
    return Number.isFinite(n) && n > 0 ? n : 0
  }

  private static contentRangeStart(value: string): number {
    const match: RegExpMatchArray | null = value.match(/^bytes\s+(\d+)-\d+\/(\d+|\*)$/i)
    return match === null ? -1 : Number.parseInt(match[1], 10)
  }

  private static contentRangeTotal(value: string): number {
    const match: RegExpMatchArray | null = value.match(/^bytes\s+\d+-\d+\/(\d+)$/i)
    return match === null ? 0 : Number.parseInt(match[1], 10)
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }
}
