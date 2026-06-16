/**
 * Typed EH failure taxonomy (mirrors eros_fe EhErrorType in lib/component/exception/error.dart).
 * The whole point: a user-facing failure must reflect the REAL cause. Only a captured HTTP 404
 * may become `NotFound` ("not available" / 404 wording) — every other failure (auth gate, login
 * redirect, Cloudflare, rate-limit/ban, parse miss, empty/200 sentinel, other non-200, transport)
 * gets its own kind so the UI never mislabels them as 404.
 *
 * The kind drives a localized message (see i18n/EhErrorText); the `message` carried here is a
 * NON-localized, cookie-free developer string for hilog only, and `ehText` is EH's own sentence
 * scraped from a 404 body (e.g. "This gallery has been removed or is unavailable.").
 */
export enum EhErrorKind {
  NotFound = 'notFound', // captured HTTP 404 ONLY
  SadPanda = 'sadPanda', // ExHentai auth gate: missing/invalid igneous → empty/blank 200 on ex
  LoginRequired = 'loginRequired', // redirected to / served the EH login page
  Cloudflare = 'cloudflare', // Cloudflare challenge / interstitial
  RateLimited = 'rateLimited', // 429 / 509 / IP-ban / image-quota
  ServerError = 'serverError', // 5xx after retries
  ParseFailure = 'parseFailure', // 200 with a real page but expected markers absent
  EmptyBody = 'emptyBody', // 200 with an empty/too-short body (non-ex)
  HttpError = 'httpError', // any other non-200 (e.g. 403) not otherwise classified
  Network = 'network', // transport/DNS/TLS/timeout — no HTTP response at all
  Unknown = 'unknown', // unexpected throw (e.g. parser bug) — generic load-failed
}

/**
 * Carrier for a classified EH failure. Extends Error so existing `catch (e) { e.message }` sites
 * keep working; ViewModels read `kind` via EhError.kindOf() (no instanceof reliance — a sentinel
 * field guards against a plain Error leaking through).
 */
export class EhError extends Error {
  readonly isEhError: boolean = true
  kind: EhErrorKind
  // EH's own explanatory sentence (404 body `<p>`), shown verbatim when present; '' otherwise.
  ehText: string

  constructor(kind: EhErrorKind, message: string, ehText: string = '') {
    super(message)
    this.kind = kind
    this.ehText = ehText
  }

  /** Read the kind off a caught value; anything that is not an EhError maps to Unknown. */
  static kindOf(err: Object): EhErrorKind {
    const e = err as EhError
    return e !== null && e !== undefined && e.isEhError === true ? e.kind : EhErrorKind.Unknown
  }

  /** Read EH's scraped sentence off a caught value ('' when absent / not an EhError). */
  static ehTextOf(err: Object): string {
    const e = err as EhError
    return e !== null && e !== undefined && e.isEhError === true ? e.ehText : ''
  }
}
