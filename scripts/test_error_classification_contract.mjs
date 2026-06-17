#!/usr/bin/env node
/**
 * Contract for the EH failure taxonomy in
 *   shared/src/main/ets/network/EhErrorClassifier.ets (classifyResponse) + EhError.ets (EhErrorKind)
 *
 * The classify() below is copy-equal to EhErrorClassifier.classifyResponse (status-first, then
 * marker-first body inspection). Synthetic bodies are the HARD gate (deterministic everywhere);
 * the gitignored real fixtures (scripts/fixtures/*) add a smoke check when present. It locks the
 * P0 #2 invariants:
 *   • ONLY a captured HTTP 404 may map to NotFound (the 404/not-found UI text);
 *   • a non-200 splits into RateLimited(429/509) / ServerError(5xx) / Cloudflare / LoginRequired /
 *     HttpError — never NotFound;
 *   • a 200 is NOT trusted: empty→SadPanda(ex)/EmptyBody, marker present→OK, else
 *     Cloudflare / LoginRequired / RateLimited(banned) / SadPanda(ex)/ParseFailure;
 *   • a real (marker-bearing) logged-out page is NEVER misread as LoginRequired by the top-bar
 *     "act=Login" link (marker-first).
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_error_classification_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = (rel) => readFileSync(join(ROOT, rel), 'utf8')

const KIND = {
  NotFound: 'notFound',
  MaybeHidden: 'maybeHidden',
  SadPanda: 'sadPanda',
  LoginRequired: 'loginRequired',
  Cloudflare: 'cloudflare',
  RateLimited: 'rateLimited',
  ServerError: 'serverError',
  ParseFailure: 'parseFailure',
  EmptyBody: 'emptyBody',
  HttpError: 'httpError',
  Network: 'network',
}

const looksCloudflare = (body) => {
  const b = body.toLowerCase()
  return (
    b.includes('just a moment') ||
    b.includes('attention required') ||
    b.includes('cf-browser-verification') ||
    b.includes('__cf_chl') ||
    b.includes('cf_chl_opt')
  )
}
const looksLogin = (body) => {
  const b = body.toLowerCase()
  return (
    b.includes('bounce_login.php') ||
    b.includes('act=login') ||
    (b.includes('name="username"') && b.includes('name="password"')) ||
    b.includes('you are currently not logged in')
  )
}
const looksBanned = (body) => {
  const b = body.toLowerCase()
  return (
    b.includes('your ip address has been temporarily banned') ||
    b.includes('you have exceeded your image viewing limits') ||
    (b.length < 512 && b.includes('banned'))
  )
}
const hasMarker = (body, page) => {
  if (page === 'generic') return true
  if (page === 'list') return body.includes('class="itg')
  return body.includes('<h1 id="gn"') || body.includes('<h1 id="gj"') || body.includes('id="gdt"')
}
// EH's ambiguous "removed or is unavailable" page (ExHentai-only-via-e-hentai / donor-gated /
// incomplete-cookie / expunged) — auth/visibility-sensitive, NOT a verified hard not-found.
const looksRemovedOrUnavailable = (body) => body.toLowerCase().includes('removed or is unavailable')

// Mirror of EhErrorClassifier.classifyResponse — returns a kind string, or null when usable.
function classify(reqUrl, isEx, resp, page) {
  const status = resp.statusCode
  const body = resp.body
  if (status === 404) {
    // "removed or is unavailable" is auth/visibility-sensitive → MaybeHidden; a true "Gallery not found."
    // (or any other 404 body) is the hard NotFound.
    if (looksRemovedOrUnavailable(body)) return KIND.MaybeHidden
    return KIND.NotFound
  }
  if (status === 429 || status === 509) return KIND.RateLimited
  if (status >= 500) return KIND.ServerError
  if (status !== 200) {
    if (looksCloudflare(body)) return KIND.Cloudflare
    if (looksLogin(body)) return KIND.LoginRequired
    return KIND.HttpError
  }
  const trimmed = body.trim()
  if (trimmed.length === 0) return isEx ? KIND.SadPanda : KIND.EmptyBody
  if (hasMarker(body, page)) return null
  if (looksCloudflare(body)) return KIND.Cloudflare
  if (looksLogin(body)) return KIND.LoginRequired
  if (looksBanned(body)) return KIND.RateLimited
  if (looksRemovedOrUnavailable(body)) return KIND.MaybeHidden
  return isEx ? KIND.SadPanda : KIND.ParseFailure
}

const resp = (statusCode, body) => ({ statusCode, body })
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (name, got, want) => {
  assert.strictEqual(got, want, `${name}: got ${got} want ${want}`)
  passed++
}

// --- Synthetic bodies (HARD gate; representative of each EH failure mode) ---
const SYN = {
  validDetail: '<html><h1 id="gn">A Title</h1><div id="gdt">...</div></html>',
  validList: '<html><table class="itg gltc"><tr></tr></table>'
    + '<a href="https://forums.e-hentai.org/index.php?act=Login">Login</a></html>', // top-bar login link MUST NOT trip LoginRequired
  // EH's AMBIGUOUS wording (expunged/private OR ExHentai-only-via-e-hentai OR donor-gated/
  // incomplete-cookie) — auth/visibility-sensitive, classifies as MaybeHidden, never hard NotFound.
  removedOrUnavailable: '<html><div class="d"><p>This gallery has been removed or is unavailable.</p></div></html>',
  // EH's UNAMBIGUOUS hard not-found (invalid gid/token) — the only 404 body that is true NotFound.
  hardNotFound: '<html><div class="d"><p>Gallery not found.</p></div></html>',
  empty: '',
  login: '<html><form><input name="UserName"><input name="PassWord"></form>'
    + '<a href="https://e-hentai.org/bounce_login.php">x</a></html>',
  cloudflare: '<html><head><title>Just a moment...</title></head><body class="cf-browser-verification"></body></html>',
  banned: '<html><p>Your IP address has been temporarily banned for excessive pageloads.</p></html>',
  parsefail: '<html><div class="unexpected">markup changed, no gallery container</div></html>',
}

// 1. Valid pages → usable (null); logged-out list with a top-bar act=Login link is NOT LoginRequired.
eq('valid detail 200 → usable', classify('https://e-hentai.org/g/1/a/', false, resp(200, SYN.validDetail), 'detail'), null)
eq('valid ex detail 200 → usable', classify('https://exhentai.org/g/1/a/', true, resp(200, SYN.validDetail), 'detail'), null)
eq('valid list 200 (with top-bar login link) → usable, NOT LoginRequired', classify('https://e-hentai.org/', false, resp(200, SYN.validList), 'list'), null)

// 2. Core invariant: ONLY a captured HTTP 404 with the HARD "Gallery not found." body is NotFound.
// EH's ambiguous "removed or is unavailable" — even on a 404 — is auth/visibility-sensitive MaybeHidden
// (donor/ExHentai-only/incomplete-cookie may be the real cause), so it must NEVER read as hard-deleted.
eq('HTTP 404 hard "Gallery not found." → NotFound', classify('https://e-hentai.org/g/1/a/', false, resp(404, SYN.hardNotFound), 'detail'), KIND.NotFound)
eq('HTTP 404 "removed or is unavailable" → MaybeHidden (NOT NotFound)', classify('https://e-hentai.org/g/1/a/', false, resp(404, SYN.removedOrUnavailable), 'detail'), KIND.MaybeHidden)
ok(
  'NotFound is produced for NO non-404 status',
  [200, 403, 429, 500, 502, 503, 509, 0].every(
    (s) => classify('https://e-hentai.org/g/1/a/', false, resp(s, SYN.hardNotFound), 'detail') !== KIND.NotFound,
  ),
)
ok(
  'MaybeHidden is produced for NO status other than the removed-or-unavailable 404/200 bodies',
  [403, 429, 500, 502, 503, 509, 0].every(
    (s) => classify('https://e-hentai.org/g/1/a/', false, resp(s, SYN.removedOrUnavailable), 'detail') !== KIND.MaybeHidden,
  ),
)
eq(
  '200 with removed-notice body → MaybeHidden (NOT NotFound, NOT ParseFailure)',
  classify('https://e-hentai.org/g/1/a/', false, resp(200, SYN.removedOrUnavailable), 'detail'),
  KIND.MaybeHidden,
)

// 3. Status taxonomy.
eq('429 → RateLimited', classify('u', false, resp(429, ''), 'detail'), KIND.RateLimited)
eq('509 → RateLimited', classify('u', false, resp(509, ''), 'detail'), KIND.RateLimited)
eq('503 → ServerError', classify('u', false, resp(503, SYN.banned), 'detail'), KIND.ServerError)
eq('500 → ServerError', classify('u', false, resp(500, ''), 'detail'), KIND.ServerError)
eq('403 plain → HttpError', classify('u', false, resp(403, '<html>forbidden</html>'), 'detail'), KIND.HttpError)
eq('403 + cloudflare body → Cloudflare', classify('u', false, resp(403, SYN.cloudflare), 'detail'), KIND.Cloudflare)

// 4. 200 body sentinels (reached only when the positive marker is absent).
eq('empty 200 on ex → SadPanda', classify('https://exhentai.org/g/1/a/', true, resp(200, SYN.empty), 'detail'), KIND.SadPanda)
eq('empty 200 on table → EmptyBody', classify('https://e-hentai.org/g/1/a/', false, resp(200, SYN.empty), 'detail'), KIND.EmptyBody)
eq('200 login page → LoginRequired', classify('https://e-hentai.org/favorites.php', false, resp(200, SYN.login), 'list'), KIND.LoginRequired)
eq('200 cloudflare → Cloudflare', classify('u', false, resp(200, SYN.cloudflare), 'detail'), KIND.Cloudflare)
eq('200 banned page → RateLimited', classify('u', false, resp(200, SYN.banned), 'detail'), KIND.RateLimited)
eq('200 no-marker on table → ParseFailure', classify('https://e-hentai.org/g/1/a/', false, resp(200, SYN.parsefail), 'detail'), KIND.ParseFailure)
eq('200 no-marker on ex → SadPanda', classify('https://exhentai.org/g/1/a/', true, resp(200, SYN.parsefail), 'detail'), KIND.SadPanda)

// 5. 'generic' page (image /s/ pages, api.php callers) skips the marker requirement.
eq('generic 200 arbitrary body → usable', classify('u', false, resp(200, SYN.parsefail), 'generic'), null)
eq('generic 404 → NotFound', classify('u', false, resp(404, ''), 'generic'), KIND.NotFound)

// 6. Real fixtures (gitignored) — smoke check when present.
for (const [name, isEx, page] of [
  ['gdetail_real.html', false, 'detail'],
  ['gdetail_ex_real.html', true, 'detail'],
  ['gallery_list.html', false, 'list'],
]) {
  const p = join(ROOT, 'scripts/fixtures', name)
  if (existsSync(p)) {
    eq(`real fixture ${name} (200) → usable`, classify('https://e-hentai.org/', isEx, resp(200, readFileSync(p, 'utf8')), page), null)
  }
}

// 7. Structural: the .ets taxonomy + classifier carry the required kinds and decision tokens.
{
  const errSrc = src('shared/src/main/ets/network/EhError.ets')
  for (const k of ['NotFound', 'MaybeHidden', 'SadPanda', 'LoginRequired', 'Cloudflare', 'RateLimited', 'ServerError', 'ParseFailure', 'EmptyBody', 'HttpError', 'Network']) {
    ok(`EhError declares kind ${k}`, new RegExp(`${k}\\s*=`).test(errSrc))
  }
  ok('EhError extends Error', /class EhError extends Error/.test(errSrc))
  ok('EhError.kindOf helper present', /static kindOf\(/.test(errSrc))

  const clsSrc = src('shared/src/main/ets/network/EhErrorClassifier.ets')
  ok('classifier: only 404 → NotFound', /status === 404[\s\S]*?EhErrorKind\.NotFound/.test(clsSrc))
  // The ambiguous "removed or is unavailable" body (404 or 200) must route to MaybeHidden, never a hard
  // NotFound — this is the auth/visibility-completeness gate (donor / ExHentai-only / incomplete-cookie).
  ok('classifier: removed-or-unavailable → MaybeHidden', /looksRemovedOrUnavailable\(body\)[\s\S]*?EhErrorKind\.MaybeHidden/.test(clsSrc))
  ok('classifier: marker-first on 200', /hasMarker\(body, page\)\s*\)\s*\{\s*return null/.test(clsSrc))
  ok('classifier: 429/509 → RateLimited', /status === 429 \|\| status === 509/.test(clsSrc))
  ok('classifier: transport wrapper', /static network\(/.test(clsSrc))
}

// 8. Wiring: the gallery web-page service routes every failure through the classifier (no raw
//    `... HTTP <code>` string can reach the UI), and each surfacing ViewModel maps the kind to a
//    localized EhErrorText message instead of storing the raw Error.message.
{
  const api = src('shared/src/main/ets/network/EhApiService.ets')
  ok('EhApiService routes through classifyResponse', /EhErrorClassifier\.classifyResponse\(/.test(api))
  ok('EhApiService wraps transport throws as network', /EhErrorClassifier\.network\(/.test(api))
  ok('EhApiService throws NO raw `... HTTP ${...}`', !/throw new Error\(`[^`]*HTTP \$\{/.test(api))

  for (const vm of [
    'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets',
    'feature/search/src/main/ets/viewmodel/SearchViewModel.ets',
    'feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets',
    'feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets',
    'feature/gallery/src/main/ets/viewmodel/AllThumbnailsViewModel.ets',
    'feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets',
  ]) {
    const s = src(vm)
    const name = vm.split('/').pop()
    ok(`${name}: surfaces localized EhErrorText.forUser`, /EhErrorText\.forUser\(err\)/.test(s))
    ok(
      `${name}: never assigns raw Error.message to the user-facing field`,
      !/this\.(error|errorMessage)\s*=\s*\(?(?:e|err)\b[^\n]*\.message/.test(s),
    )
  }
}

// 9. User-facing copy is OFFICIAL-TONE: MaybeHidden maps to error_gallery_maybe_hidden, and that visible
//    string (every locale) must NOT leak the internal classification guess — no ExHentai / 里站 / donor /
//    permission / cookie / login wording. The internal kind stays MaybeHidden; only the copy is neutral.
{
  const etx = src('shared/src/main/ets/i18n/EhErrorText.ets')
  ok(
    'EhErrorText maps MaybeHidden → error_gallery_maybe_hidden',
    /MaybeHidden:\s*\n?\s*return 'error_gallery_maybe_hidden'/.test(etx),
  )
  ok('EhErrorText maps NotFound → error_gallery_unavailable', /NotFound:\s*\n?\s*return 'error_gallery_unavailable'/.test(etx))

  // Implementation-leak tokens forbidden in the PRIMARY visible error copy (case-insensitive for ASCII).
  const FORBIDDEN = ['exhentai', 'e-hentai', '里站', '表站', 'donor', '捐赠', 'cookie', 'login', '登录', 'permission', '权限', 'igneous']
  for (const loc of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
    const json = JSON.parse(src(`entry/src/main/resources/${loc}/element/string.json`))
    const entry = json.string.find((e) => e.name === 'error_gallery_maybe_hidden')
    ok(`${loc}: error_gallery_maybe_hidden present and non-empty`, entry && entry.value.trim().length > 0)
    const low = (entry ? entry.value : '').toLowerCase()
    for (const tok of FORBIDDEN) {
      ok(`${loc}: MaybeHidden copy omits implementation hint "${tok}"`, !low.includes(tok.toLowerCase()))
    }
  }
}

console.log(`✓ error classification contract: ${passed} assertions passed`)
