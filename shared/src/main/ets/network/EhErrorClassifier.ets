import { EhTextResponse } from './EhHttpClient'
import { EhError, EhErrorKind } from './EhError'

/**
 * Turns a raw EH response (or a transport throw) into a TRUTHFUL typed failure. The transport layer
 * only hands us { statusCode, body }, so classification is status-first then body-sentinel:
 *
 *   - captured HTTP 404 → NotFound (and ONLY 404 may become not-found/404 UI text), scraping EH's
 *     own `<p>` sentence ("This gallery has been removed or is unavailable." / "Gallery not found.");
 *   - 429/509/IP-ban/quota → RateLimited; 5xx → ServerError; other non-200 → Cloudflare/Login/HttpError;
 *   - HTTP 200 is NOT trusted: an empty/blank ex body is the Sad Panda igneous gate, a login page is
 *     LoginRequired, a Cloudflare interstitial is Cloudflare, and a 200 lacking the page's required
 *     markup is SadPanda (ex) / ParseFailure (table) — never a silent blank "success".
 *
 * `page` selects the positive marker a real 200 must contain: 'detail' (a /g/ page), 'list' (a gltc
 * table), or 'generic' (skip the marker check — for /s/ image pages and api.php callers).
 * Mirror any change here in scripts/test_error_classification_contract.mjs.
 */
export class EhErrorClassifier {
  /** Classify a completed HTTP response. Returns null when the body is a usable page for `page`. */
  static classifyResponse(
    reqUrl: string,
    isEx: boolean,
    resp: EhTextResponse,
    page: string,
  ): EhError | null {
    const status: number = resp.statusCode
    const body: string = resp.body
    const host: string = EhErrorClassifier.hostOf(reqUrl)

    // --- Status-driven (non-200) ---
    if (status === 404) {
      const notice: string = EhErrorClassifier.scrapeNotice(body)
      // EH's "removed or is unavailable" wording is ambiguous (ExHentai-only-via-e-hentai / donor-gated /
      // incomplete-cookie / expunged) — surface it as auth/visibility-sensitive, NOT verified hard-deleted.
      // Only a true "Gallery not found." (or any other 404 body) is the hard not-found (invalid gid/token).
      if (EhErrorClassifier.looksRemovedOrUnavailable(body)) {
        return new EhError(
          EhErrorKind.MaybeHidden,
          EhErrorClassifier.dev('maybe-hidden', page, status, host),
          notice,
        )
      }
      return new EhError(
        EhErrorKind.NotFound,
        EhErrorClassifier.dev('not-found', page, status, host),
        notice,
      )
    }
    if (status === 429 || status === 509) {
      return new EhError(
        EhErrorKind.RateLimited,
        EhErrorClassifier.dev('rate-limited', page, status, host),
      )
    }
    if (status >= 500) {
      return new EhError(
        EhErrorKind.ServerError,
        EhErrorClassifier.dev('server-error', page, status, host),
      )
    }
    if (status !== 200) {
      if (EhErrorClassifier.looksCloudflare(body)) {
        return new EhError(
          EhErrorKind.Cloudflare,
          EhErrorClassifier.dev('cloudflare', page, status, host),
        )
      }
      if (EhErrorClassifier.looksLogin(body)) {
        return new EhError(
          EhErrorKind.LoginRequired,
          EhErrorClassifier.dev('login', page, status, host),
        )
      }
      return new EhError(
        EhErrorKind.HttpError,
        EhErrorClassifier.dev('http-error', page, status, host),
      )
    }

    // --- HTTP 200 body inspection (200 is NOT trusted) ---
    const trimmed: string = body.trim()
    if (trimmed.length === 0) {
      // An empty 200 on ex is the Sad Panda / igneous gate; on the table site it is a dropped body.
      return new EhError(
        isEx ? EhErrorKind.SadPanda : EhErrorKind.EmptyBody,
        EhErrorClassifier.dev(isEx ? 'sad-panda-empty' : 'empty-body', page, status, host),
      )
    }
    // `generic` pages intentionally skip the positive-marker check (image pages, api.php, archiver),
    // but a dedicated login form is still a hard auth failure. Keep this stricter than looksLogin():
    // real logged-out list/detail pages contain a top-bar act=Login link, while archiver.php can return
    // a full "This page requires you to log on" form with HTTP 200.
    if (EhErrorClassifier.looksDedicatedLoginPage(body)) {
      return new EhError(
        EhErrorKind.LoginRequired,
        EhErrorClassifier.dev('login', page, status, host),
      )
    }
    // A real page carries its positive marker (a /g/ header or a gltc table) — trust it and SKIP the
    // sentinel sniff. This is marker-first on purpose: every logged-out EH page has a top-bar
    // "act=Login" link, so running the login sniff before the marker check would misread a valid
    // logged-out list/detail as LoginRequired. Sentinels only run on a body that lacks the marker.
    if (EhErrorClassifier.hasMarker(body, page)) {
      return null
    }
    // A valid EH search with zero matches may render no `class="itg"` result table at all. Treat that
    // as a usable empty list before the logged-out top-bar `act=Login` link can be misread as auth failure.
    if (page === 'list' && EhErrorClassifier.looksListNoResults(body)) {
      return null
    }
    if (EhErrorClassifier.looksCloudflare(body)) {
      return new EhError(
        EhErrorKind.Cloudflare,
        EhErrorClassifier.dev('cloudflare', page, status, host),
      )
    }
    if (EhErrorClassifier.looksLogin(body)) {
      return new EhError(
        EhErrorKind.LoginRequired,
        EhErrorClassifier.dev('login', page, status, host),
      )
    }
    if (EhErrorClassifier.looksBanned(body)) {
      return new EhError(
        EhErrorKind.RateLimited,
        EhErrorClassifier.dev('banned-200', page, status, host),
      )
    }
    // Some EH variants serve the "removed or is unavailable" notice with HTTP 200 (no /g/ marker). Same
    // auth/visibility ambiguity as the 404 form — surface MaybeHidden, never a hard not-found/deleted.
    if (EhErrorClassifier.looksRemovedOrUnavailable(body)) {
      return new EhError(
        EhErrorKind.MaybeHidden,
        EhErrorClassifier.dev('maybe-hidden-200', page, status, host),
        EhErrorClassifier.scrapeNotice(body),
      )
    }
    // A 200 with no gallery/list markup and no known interstitial: on ex this is the blank Sad Panda
    // gate; on the table site it is an unparseable page (markup changed / unexpected variant).
    return new EhError(
      isEx ? EhErrorKind.SadPanda : EhErrorKind.ParseFailure,
      EhErrorClassifier.dev(isEx ? 'sad-panda-nomarker' : 'parse-failure', page, status, host),
    )
  }

  /** Wrap a transport-layer throw (no HTTP response: DNS/TLS/timeout/connection) as a Network error. */
  static network(err: Error, reqUrl: string): EhError {
    const host: string = EhErrorClassifier.hostOf(reqUrl)
    const detail: string =
      err !== null && err !== undefined && err.message !== undefined
        ? err.message
        : 'request failed'
    return new EhError(EhErrorKind.Network, `network host=${host} ${detail}`)
  }

  // --- helpers (all cookie-free; only host + status + sentinels are logged, never headers/cookies) ---

  private static dev(label: string, page: string, status: number, host: string): string {
    return `${page} ${label} status=${status} host=${host}`
  }

  private static hostOf(url: string): string {
    if (url.indexOf('exhentai.org') >= 0) {
      return 'exhentai'
    }
    if (url.indexOf('e-hentai.org') >= 0) {
      return 'e-hentai'
    }
    return ''
  }

  private static looksCloudflare(body: string): boolean {
    const b: string = body.toLowerCase()
    return (
      b.indexOf('just a moment') >= 0 ||
      b.indexOf('attention required') >= 0 ||
      b.indexOf('cf-browser-verification') >= 0 ||
      b.indexOf('__cf_chl') >= 0 ||
      b.indexOf('cf_chl_opt') >= 0
    )
  }

  private static looksLogin(body: string): boolean {
    const b: string = body.toLowerCase()
    return (
      b.indexOf('bounce_login.php') >= 0 ||
      b.indexOf('act=login') >= 0 ||
      (b.indexOf('name="username"') >= 0 && b.indexOf('name="password"') >= 0) ||
      b.indexOf('you are currently not logged in') >= 0
    )
  }

  private static looksDedicatedLoginPage(body: string): boolean {
    const b: string = body.toLowerCase()
    return (
      b.indexOf('this page requires you to log on') >= 0 ||
      b.indexOf('you are currently not logged in') >= 0 ||
      b.indexOf('bounce_login.php') >= 0 ||
      (b.indexOf('name="username"') >= 0 && b.indexOf('name="password"') >= 0) ||
      (b.indexOf('name="username"') >= 0 && b.indexOf('name="passwd"') >= 0)
    )
  }

  private static looksListNoResults(body: string): boolean {
    const b: string = body.toLowerCase()
    return (
      b.indexOf('no hits found') >= 0 ||
      b.indexOf('no matching galleries') >= 0 ||
      b.indexOf('no results found') >= 0 ||
      b.indexOf('did not match any') >= 0
    )
  }

  // EH's ambiguous "This gallery has been removed or is unavailable." page (expunged/private OR
  // ExHentai-only-via-e-hentai OR donor-gated/incomplete-cookie) — NOT a verified hard not-found.
  private static looksRemovedOrUnavailable(body: string): boolean {
    return body.toLowerCase().indexOf('removed or is unavailable') >= 0
  }

  private static looksBanned(body: string): boolean {
    const b: string = body.toLowerCase()
    return (
      b.indexOf('your ip address has been temporarily banned') >= 0 ||
      b.indexOf('you have exceeded your image viewing limits') >= 0 ||
      (b.length < 512 && b.indexOf('banned') >= 0)
    )
  }

  // Positive markers a real 200 page must carry. ex Sad Panda / login / cloudflare pages have none.
  private static hasMarker(body: string, page: string): boolean {
    if (page === 'generic') {
      return true
    }
    if (page === 'list') {
      return body.indexOf('class="itg') >= 0
    }
    // 'detail' (a /g/{gid}/{token} page, incl. ?p= preview pages)
    return (
      body.indexOf('<h1 id="gn"') >= 0 ||
      body.indexOf('<h1 id="gj"') >= 0 ||
      body.indexOf('id="gdt"') >= 0
    )
  }

  // EH's removed/not-found pages carry a one-sentence `<p>` explanation; surface it verbatim on a 404.
  private static scrapeNotice(body: string): string {
    const m: RegExpMatchArray | null = body.match(/<p>([^<]{4,200})<\/p>/)
    if (m !== null && m[1] !== undefined) {
      return m[1].trim()
    }
    return ''
  }
}
