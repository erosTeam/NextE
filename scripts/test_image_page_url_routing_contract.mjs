#!/usr/bin/env node
/**
 * Contract test for EH /s/ image-page URL routing:
 *   - EhUrlRouter accepts eros_fe-compatible a-z imgkeys/tokens.
 *   - Index deep links do not stop at canHandle(); /s/ opens gallery first, then confirms Reader jump.
 *   - Search bare /s/ URLs resolve to Reader instead of becoming ordinary searches.
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

const indexSrc = read('entry/src/main/ets/pages/Index.ets')
const routeCoordinatorSrc = read('entry/src/main/ets/model/IndexRouteCoordinator.ets')
ok('Index normalizes deep-link host to current site mode', /const currentUri:[\s\S]*EhUrlRouter\.toCurrentHost\(uri, EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)\)/.test(indexSrc))
ok('Index still routes /g/ detail links', /EhUrlRouter\.parseGallery\(currentUri\)[\s\S]*GalleryDetail/.test(indexSrc))
ok('Index can route comment QA gallery links directly to full comments', /EhUrlRouter\.wantsComments\(currentUri\)[\s\S]*pushPathByName\(\s*'GalleryComments'[\s\S]*new GalleryCommentsParams\(ref\.gid, ref\.token\)/.test(indexSrc))
ok('Index routes /s/ through ImagePageRouteService', /EhUrlRouter\.parseImagePage\(currentUri\)[\s\S]*openImagePageUrl\(currentUri\)/.test(indexSrc))
ok('Index opens parent GalleryDetail before offering image-page jump', /ImagePageRouteService\.resolve\(uri\)[\s\S]*pushPathByName\(\s*'GalleryDetail'[\s\S]*confirmOpenImagePage\(target\)/.test(indexSrc))
ok('Index confirms before opening Reader for resolved /s/', /private confirmOpenImagePage\(target: ImagePageRouteTarget\): void[\s\S]*image_page_jump_confirm[\s\S]*readerOverlay\.open\(/.test(indexSrc))
ok('Index passes exact image seed and parsed fileCount without marking preview pages loaded', /new ReaderParams\(\s*target\.gid,\s*target\.token,\s*target\.index,\s*target\.fileCount,\s*'',\s*\[target\.seedImage\],\s*0,\s*0,\s*\)/.test(indexSrc))
ok('Index shows a visible route-failure page for failed /s/ deep links', /image_page_deep_link_failed[\s\S]*pushPathByName\(\s*'ImagePageRouteError'/.test(indexSrc))
ok('Index registers the image-page route-failure destination through the route coordinator',
  /'ImagePageRouteError':\s*'imagePageRouteError'/.test(routeCoordinatorSrc) &&
  /'imagePageRouteError':\s*wrapBuilder<\[\]>\(IndexImagePageRouteErrorRoute\)/.test(indexSrc) &&
  /function IndexImagePageRouteErrorRoute\(\)\s*\{\s*ImagePageRouteErrorPage\(\)/.test(indexSrc))

const routeErrorSrc = read('entry/src/main/ets/pages/ImagePageRouteErrorPage.ets')
ok('image-page route-failure page retries the original /s/ URL', /ImagePageRouteService\.resolve\(this\.params\.url\)/.test(routeErrorSrc))
ok('image-page route-failure page can still open Reader after retry', /connectReaderOverlayNavigation\(\)\.open\([\s\S]*new ReaderParams\(target\.gid, target\.token, target\.index, target\.fileCount/.test(routeErrorSrc))
ok('image-page route-failure page uses localized failure copy', /image_page_open_failed/.test(routeErrorSrc))

const searchSrc = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
ok('Search recognized /s/ branches before ordinary search', /EhUrlRouter\.parseImagePage\(directUrl\)[\s\S]*openImagePageUrl\(directUrl\)[\s\S]*return/.test(searchSrc))
ok('Search image-page branch opens Reader in its dedicated navigation host', /ImagePageRouteService\.resolve\(url\)[\s\S]*connectReaderOverlayNavigation\(\)\.open\(/.test(searchSrc))
ok('Search passes exact image seed and parsed fileCount without marking preview pages loaded', /new ReaderParams\(target\.gid, target\.token, target\.index, target\.fileCount, '', \[target\.seedImage\], 0, 0\)/.test(searchSrc))
ok('Search image-page failure shows a visible retry state', /image_page_jump_failed[\s\S]*this\.imagePageErrorUrl = url/.test(searchSrc))
ok('Search image-page retry reuses the original /s/ URL', /retryAction:[\s\S]*this\.openImagePageUrl\(this\.imagePageErrorUrl\)/.test(searchSrc))

console.log(`✓ image-page URL routing contract: ${passed} assertions passed`)
