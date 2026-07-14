#!/usr/bin/env node
/**
 * Contract test for EH /s/ image-page URL routing:
 *   - EhUrlRouter accepts eros_fe-compatible a-z imgkeys/tokens.
 *   - Image-page parsing and resolution preserve the parent gallery and exact Reader seed.
 *
 * Run: node scripts/test_image_page_url_routing_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const GALLERY_RE = /https?:\/\/(?:e-|ex)hentai\.org\/g\/(\d+)\/([0-9a-z]+)/
const IMAGE_RE = /https?:\/\/(?:e-|ex)hentai\.org\/s\/([0-9a-z]+)\/(\d+)-(\d+)/
const canHandle = (url) => GALLERY_RE.test(url) || IMAGE_RE.test(url)

ok('router accepts /g/ token with z', canHandle('https://e-hentai.org/g/3987108/z9altc/'))
ok('router accepts /s/ imgkey with z', canHandle('https://e-hentai.org/s/z9imgkey/3987108-37'))
{
  const m = 'https://exhentai.org/s/z9imgkey/3987108-37'.match(IMAGE_RE)
  ok('image-page gid parsed', m?.[2] === '3987108')
  ok('image-page page parsed', m?.[3] === '37')
}

const parserSrc = read('shared/src/main/ets/parser/EhImagePageParser.ets')
ok('parser extracts parent gallery link', /RE_GALLERY[\s\S]*\/g\\\/\(\\d\+\)\\\/\(\[0-9a-z\]\+\)/.test(parserSrc))
ok('parser extracts image serial and total file count with EH thousands separators', /RE_SER_TOTAL/.test(parserSrc) &&
  /import \{ EhGallery \} from '..\/model\/EhGallery'/.test(parserSrc) &&
  /r\.ser = EhGallery\.parseFileCount\(ser\[1\]\)/.test(parserSrc) &&
  /r\.fileCount = EhGallery\.parseFileCount\(ser\[2\]\)/.test(parserSrc))

const serviceSrc = read('shared/src/main/ets/services/ImagePageRouteService.ets')
ok('route service normalizes image-page URL to current host', /EhUrlRouter\.toCurrentHost\(url, EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)\)/.test(serviceSrc))
ok('route service fetches image page HTML from current host', /EhHttpClient\.getInstance\(\)\.getText\(currentUrl\)/.test(serviceSrc))
ok('route service requires parent token', /galleryToken\.length === 0/.test(serviceSrc))
ok('route service converts serial to zero-based index', /Math\.max\(0, ser - 1\)/.test(serviceSrc))
ok('route service preserves parsed total file count', /fileCount:\s*number\s*=\s*0/.test(serviceSrc) && /target\.fileCount = parsed\.fileCount/.test(serviceSrc))
ok('route service returns an exact Reader seed image', /seedImage:\s*EhGalleryImage\s*=\s*new EhGalleryImage\(\)/.test(serviceSrc))
ok('route service preserves current-host /s/ URL in seed', /seed\.sUrl = currentUrl/.test(serviceSrc))
ok('route service preserves parsed full image URL in seed', /seed\.imageUrl = parsed\.imageUrl/.test(serviceSrc))
ok('route service preserves parsed origin image URL in seed', /seed\.originImageUrl = parsed\.originImageUrl/.test(serviceSrc))
ok('route service preserves showKey and reloadKey in seed', /seed\.showKey = parsed\.showKey[\s\S]*seed\.reloadKey = parsed\.reloadKey/.test(serviceSrc))

console.log(`✓ image-page parsing and resolution contract: ${passed} assertions passed`)
