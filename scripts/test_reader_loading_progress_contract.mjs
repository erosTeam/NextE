#!/usr/bin/env node
/**
 * Contract: Reader loading-stage UI stays lightweight and cannot regress core Reader interaction.
 *
 * Reader image loading uses an isolated pending surface:
 * - HTML/image-page resolving stage can show the resolving placeholder.
 * - Image-byte download stage can show a progress bar while no renderable file exists.
 * - Once a local cached image path exists, the Image branch must not be hidden behind opacity or covered
 *   by a loading overlay.
 *
 * Run: node scripts/test_reader_loading_progress_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const vm = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
const cacheService = read('shared/src/main/ets/services/CachedImageFileService.ets')
const httpClient = read('shared/src/main/ets/network/EhHttpClient.ets')
const settings = read('shared/src/main/ets/settings/ReadModeSettings.ets')
const state = read('shared/src/main/ets/state/ReadModeState.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets')
const zh = read('entry/src/main/resources/zh_CN/element/string.json')
const streamMethod = httpClient.substring(
  httpClient.indexOf('async downloadBinaryToFileInStream('),
  httpClient.indexOf('async downloadBinaryToFileInStreamResumable('),
)
const loadResolvedMethods = [
  ...reader.matchAll(/private async loadResolvedImage\(resolved: string\): Promise<void> \{[\s\S]*?^  private async applyImageBlockDecision/mg),
].map((match) => match[0])
const loadingStage = reader.substring(
  reader.indexOf('struct ReaderLoadingStage'),
  reader.indexOf('struct ReaderFailureOverlay'),
)
const decodeLoadingBlocks = [
  ...reader.matchAll(/ReaderLoadingStage\(\{\s*label: \$r\('app\.string\.reader_loading_decoding'\),?\s*(?:compact: true,\s*)?\}\)/g),
].map((match) => match[0])

ok('Reader root uses the pre-overlay bottom stack baseline',
  /Stack\(\{ alignContent: Alignment\.Bottom \}\)/.test(reader))
ok('root empty loading shows resolving stage and jump loading does not cover readable content',
  /else \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader) &&
  /if \(this\.vm\.jumping && !this\.readerContentReady\(\)\) \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader))
ok('horizontal image resolving shows resolving stage',
  /struct ReaderImagePage[\s\S]*else \{[\s\S]*ReaderLoadingStage\(\{ label: \$r\('app\.string\.reader_loading_resolving'\) \}\)/.test(reader))
ok('vertical image resolving shows compact resolving stage',
  /struct ReaderVerticalImage[\s\S]*else \{[\s\S]*ReaderLoadingStage\(\{[\s\S]*reader_loading_resolving[\s\S]*compact: true/.test(reader))
ok('ReaderLoadingOverlay is not present in ReaderPage',
  !/ReaderLoadingOverlay|ReaderLoadingLine/.test(reader))
ok('Reader uses the shared cached image file service for full image bytes',
  /CachedImageFileService/.test(reader) &&
  /CachedImageFileService\.load\(/.test(reader))
ok('cached image service separates disk path from ArkUI display URI',
  /interface CachedImageFileResult[\s\S]*filePath: string[\s\S]*displayUri: string/.test(cacheService) &&
  /static displayUri\(path: string\): string/.test(cacheService))
ok('image presentation is not hidden behind imageLoaded opacity gates',
  !/\.opacity\(this\.imageLoaded \? 1 : 0\)/.test(reader))
ok('image download progress appears only before a cached render path exists',
  (reader.match(/else if \(this\.sourceImageUrl\.length > 0\) \{[\s\S]*?reader_loading_image/g) || []).length >= 3)
ok('local Image decode wait uses a separate preparing label without download progress',
  /reader_loading_decoding/.test(zh) &&
  decodeLoadingBlocks.length >= 3 &&
  decodeLoadingBlocks.every((block) => !/loaded: this\.imageProgressLoaded|total: this\.imageProgressTotal/.test(block)))
ok('Reader download progress uses the system linear Progress component instead of a scaled custom bar',
  /Progress\(\{ value: this\.loaded, total: this\.total, type: ProgressType\.Linear \}\)/.test(loadingStage) &&
  /\.style\(\{ strokeWidth: 4, strokeRadius: 2 \}\)/.test(loadingStage) &&
  !/\.scale\(\{ x: this\.progressRatio\(\)/.test(loadingStage))
ok('unknown-total image downloads still expose byte progress',
  /reader_loading_downloaded/.test(zh) &&
  /private hasLoadedBytes\(\): boolean \{[\s\S]*!this\.hasProgress\(\) && this\.loaded > 0/.test(loadingStage) &&
  /private loadedSizeText\(\): string \{[\s\S]*toFixed\(1\)[\s\S]*KB/.test(loadingStage) &&
  /else if \(this\.hasLoadedBytes\(\)\) \{[\s\S]*reader_loading_downloaded[\s\S]*this\.loadedSizeText\(\)/.test(loadingStage))
ok('resolved remote URLs are converted into cached display URIs before presentation',
  (reader.match(/await this\.loadResolvedImage\(resolved\)/g) || []).length >= 3 &&
  (reader.match(/this\.imageUrl = result\.displayUri/g) || []).length >= 3)
ok('Reader does not keep a remote-URL Image warmer beside the cache pipeline',
  !/ReaderImageWarmers|warmImageIndexes|READER_IMAGE_WARM_AHEAD|warm_image_complete|warm_image_failed/.test(reader) &&
  !/Image\(this\.vm\.imageAt\(index\)\.imageUrl\)/.test(reader))
ok('Reader keeps preload warmers inside the cached image file pipeline',
  /ReaderCacheWarmers\(\)/.test(reader) &&
  /struct ReaderCacheWarmImage[\s\S]*CachedImageFileService\.cached[\s\S]*CachedImageFileService\.load[\s\S]*reader_warm_complete/.test(reader) &&
  /private cacheWarmImageIndexes\(\): number\[\] \{[\s\S]*const preloadPages: number = this\.readerPreloadPages\(\)[\s\S]*this\.vm\.currentIndex \+ preloadPages/.test(reader))
ok('streamed image downloads do not reuse the short HTML read timeout',
  /const BINARY_STREAM_READ_TIMEOUT_MS: number = 120000/.test(httpClient) &&
  /readTimeoutMs: number = BINARY_STREAM_READ_TIMEOUT_MS/.test(streamMethod) &&
  !/readTimeoutMs: number = READ_TIMEOUT_MS/.test(streamMethod))
ok('automatic image retry count is not reset at the start of each resolved download attempt',
  loadResolvedMethods.length === 3 &&
  loadResolvedMethods.every((method) => {
    const beforeContext = method.slice(0, method.indexOf('const context: common.UIAbilityContext'))
    return !/this\.autoRetryCount = 0/.test(beforeContext)
  }))
ok('Reader preload page count is persisted with a 0..5 bounded default',
  /@Trace preloadPages: number = 2/.test(state) &&
  /READING_PRELOAD_PAGES: string = 'reading\.preloadPages'/.test(keys) &&
  /private static normalizePreloadPages\(value: number\): number \{[\s\S]*return 2[\s\S]*if \(value < 0\)[\s\S]*return 0[\s\S]*if \(value > 5\)[\s\S]*return 5/.test(settings) &&
  /StorageKeys\.READING_PRELOAD_PAGES[\s\S]*connectReadMode\(\)\.preloadPages/.test(settings) &&
  /static async setPreloadPages[\s\S]*store\.putSync\(StorageKeys\.READING_PRELOAD_PAGES, normalized\)/.test(settings))
ok('Reader settings exposes preload page count choices from 0 to 5',
  /settings_reader_preload_pages/.test(settingsPage) &&
  /PreloadPageMenu\(\)/.test(settingsPage) &&
  /ReadModeSettings\.setPreloadPages/.test(settingsPage) &&
  /content: '0'[\s\S]*content: '1'[\s\S]*content: '2'[\s\S]*content: '3'[\s\S]*content: '4'[\s\S]*content: '5'/.test(settingsPage) &&
  /"settings_reader_preload_pages"[\s\S]*"预载页数"/.test(zh))
ok('Reader preload count drives URL pre-resolve and component cache windows',
  !/PRECACHE_AHEAD/.test(vm) &&
  /private preloadPages\(\): number \{[\s\S]*connectReadMode\(\)\.preloadPages[\s\S]*MAX_PRELOAD_PAGES/.test(vm) &&
  /if \(preloadPages <= 0\) \{[\s\S]*return[\s\S]*const to: number = Math\.min\(start \+ preloadPages - 1/.test(vm) &&
  (reader.match(/\.cachedCount\(this\.readerPreloadPages\(\)\)/g) || []).length === 3 &&
  !/\.cachedCount\(2\)/.test(reader))
ok('Image.onComplete still records page loaded state for visible pages and auto-read',
  /\.onComplete\(\(event\?: ReaderImageLoadEvent\) => \{[\s\S]*this\.imageLoaded = true/.test(reader) &&
  /\.onComplete\(\(e\) => \{[\s\S]*this\.imageLoaded = true/.test(reader))
ok('bottom chrome is not re-anchored against a centered root',
  !/ReaderBottomBar\(\)[\s\S]*\.align\(Alignment\.Bottom\)/.test(reader))

console.log(`✓ reader loading recovery contract: ${passed} assertions passed`)
