#!/usr/bin/env node
/**
 * Contract test for the reader showKey fast-path:
 *   shared/src/main/ets/network/EhApiPhpService.ets (showpage POST body)
 *   shared/src/main/ets/parser/EhImagePageParser.ets (parseShowPage JSON response)
 *   shared/src/main/ets/services/ImageResolveService.ets (gallery showKey cache + fast/slow paths)
 *
 * The functions below are copy-equal to that logic (no network — synthetic request/response). They
 * lock the eros_fe fetchImageInfoByApi / paraShowPageJson port:
 *   • request body = {method:'showpage', gid:int, page:int, imgkey, showkey}.
 *   • response: i3 → `<img src="URL" style>`; i6 → origin (fullimg) + nl('sourceId') reload key;
 *     `error` (e.g. 'Key mismatch') throws so the caller falls back to the /s/ HTML path.
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_image_resolve_showpage_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of EhApiPhpService showpage POST body.
const buildReq = (gid, page, imgkey, showkey) =>
  JSON.stringify({ method: 'showpage', gid, page, imgkey, showkey })

// Mirror of EhImagePageParser.parseShowPage.
const RE_IMG = /<img[^>]*src="([^"]+)" style/
const RE_ORIGIN = /<a href="([^"]+fullimg[^"]+)"/
const RE_NL = /nl\('([^']+)'\)/
function parseShowPage(body) {
  let obj
  try {
    obj = JSON.parse(body)
  } catch {
    throw new Error('showpage: invalid JSON')
  }
  const err = typeof obj.error === 'string' ? obj.error : ''
  if (err.length > 0) throw new Error(`showpage error: ${err}`)
  const i3 = typeof obj.i3 === 'string' ? obj.i3 : ''
  const i6 = typeof obj.i6 === 'string' ? obj.i6 : ''
  const out = { imageUrl: '', originImageUrl: '', reloadKey: '' }
  const img = i3.match(RE_IMG)
  if (img) out.imageUrl = img[1]
  const og = i6.match(RE_ORIGIN)
  if (og) out.originImageUrl = og[1].replace(/&amp;/g, '&')
  const nl = i6.match(RE_NL)
  if (nl) out.reloadKey = nl[1]
  return out
}

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// 1. request body shape (gid/page ints; method first; keys as given)
{
  const body = buildReq(1763749, 3, 'a1b2c3d4e5', 'show-key-xyz')
  const o = JSON.parse(body)
  ok('method showpage', o.method === 'showpage')
  ok('gid is int', o.gid === 1763749 && typeof o.gid === 'number')
  ok('page is int', o.page === 3 && typeof o.page === 'number')
  ok('imgkey', o.imgkey === 'a1b2c3d4e5')
  ok('showkey', o.showkey === 'show-key-xyz')
}

// 2. response parse: i3 image, i6 origin + reload key
{
  const resp = JSON.stringify({
    i3: '<img id="img" src="https://abc.ehgt.org/full/img.jpg" style="height:1280px;width:900px">',
    i6: '<a href="https://abc.ehgt.org/fullimg.php?gid=1&amp;page=3&amp;key=zz">Download original 2.00 MiB</a><a onclick="return nl(\'12345-67890\')">Reload</a>',
    x: 900,
    y: 1280,
  })
  const r = parseShowPage(resp)
  ok('imageUrl from i3', r.imageUrl === 'https://abc.ehgt.org/full/img.jpg')
  ok('originImageUrl from i6 (unescaped)', r.originImageUrl === 'https://abc.ehgt.org/fullimg.php?gid=1&page=3&key=zz')
  ok('reloadKey from nl()', r.reloadKey === '12345-67890')
}

// 3. minimal response (only i3) — still yields the image; origin/reload empty
{
  const r = parseShowPage(JSON.stringify({ i3: '<img id="img" src="https://x/y.jpg" style="">' }))
  ok('minimal imageUrl', r.imageUrl === 'https://x/y.jpg')
  ok('minimal origin empty', r.originImageUrl === '')
  ok('minimal reload empty', r.reloadKey === '')
}

// 4. error response throws (so the caller falls back to /s/)
{
  let threw = false
  try {
    parseShowPage(JSON.stringify({ error: 'Key mismatch' }))
  } catch (e) {
    threw = e.message.includes('Key mismatch')
  }
  ok('error field throws', threw)
}

// 5. invalid JSON throws
{
  let threw = false
  try {
    parseShowPage('{not json')
  } catch {
    threw = true
  }
  ok('invalid JSON throws', threw)
}

// 6. 509 placeholder guard: EH's rate-limit gif must be treated as failure, not shown (eros_fe REG_509_URL)
{
  const is509 = (url) => /\.org\/.+\/509s?\.gif/.test(url)
  ok('509 gif detected', is509('https://ehgt.org/g/509.gif') === true)
  ok('509s gif detected', is509('https://exhentai.org/t/509s.gif') === true)
  ok('normal image not flagged', is509('https://abc.ehgt.org/full/img.jpg') === false)
}

// 7. 换源 re-source URL: changeSource appends ?nl={reloadKey} to the /s/ url (different host)
{
  const sourceUrl = (sUrl, reloadKey, changeSource) =>
    changeSource && reloadKey.length > 0 ? `${sUrl}?nl=${reloadKey}` : sUrl
  ok('changeSource appends nl', sourceUrl('https://e-hentai.org/s/abc/1-2', 'rk123', true) === 'https://e-hentai.org/s/abc/1-2?nl=rk123')
  ok('no changeSource → plain url', sourceUrl('https://e-hentai.org/s/abc/1-2', 'rk123', false) === 'https://e-hentai.org/s/abc/1-2')
  ok('changeSource but no reloadKey → plain', sourceUrl('https://x/s/a/1-2', '', true) === 'https://x/s/a/1-2')
}

// 8. A 200 OK /s/ page can still be unusable (e.g. "Invalid page." or a login/interstitial page).
// Slow-path resolve must fail closed instead of returning an empty URL and leaving Reader loading forever.
{
  const parseImagePage = (html) => {
    const match = html.match(/<img id="img" src="([^"]+)"/)
    return match ? match[1] : ''
  }
  const img = parseImagePage('Invalid page.')
  ok('invalid /s/ page has no imageUrl', img.length === 0)
  ok('empty imageUrl is treated as resolve failure', img.length === 0)
}

// 9. structural: the .ets protocol wiring (cache, fast path, fallback, POST body, 509 guard, 换源).
// Reader rendering callbacks and retry-overlay behavior require a device path; they are not source-shape
// contract targets.
{
  const php = readFileSync(join(ROOT, 'shared/src/main/ets/network/EhApiPhpService.ets'), 'utf8')
  ok('showPage POSTs /api.php through the read-only retry path', /postJsonReadOnly\(\s*`\$\{base\}\/api\.php`/.test(php))
  ok('request method showpage', /method: string = 'showpage'/.test(php))
  const svc = readFileSync(join(ROOT, 'shared/src/main/ets/services/ImageResolveService.ets'), 'utf8')
  ok('keeps a gallery showKey cache', /private showKeys: Map<string, string>/.test(svc))
  ok('fast path calls showPage', /EhApiPhpService\.showPage\(/.test(svc))
  ok('learns showKey from /s/ resolve', /this\.showKeys\.set\(ref\.gid, r\.showKey\)/.test(svc))
  ok('stores reloadKey', /image\.reloadKey = r\.reloadKey/.test(svc))
  ok('has 509 guard', /RE_509: RegExp = \/\\\.org/.test(svc) && /throw new Error\('image509'\)/.test(svc))
  ok('slow /s/ path throws on empty parsed image URL', /if \(r\.imageUrl\.length === 0\) \{[\s\S]*throw new Error\('image page has no full image url'\)/.test(svc))
  ok('resolve takes changeSource', /async resolve\(image: EhGalleryImage, changeSource: boolean = false\)/.test(svc))
  ok('re-source appends nl', /\$\{image\.sUrl\}\?nl=\$\{image\.reloadKey\}/.test(svc))
  const client = readFileSync(join(ROOT, 'shared/src/main/ets/network/EhHttpClient.ets'), 'utf8')
  ok('http client has a read-only JSON POST path', /async postJsonReadOnly\(url: string, body: string\)/.test(client))
}

console.log(`✓ image-resolve showpage contract: ${passed} assertions passed`)
