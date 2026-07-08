#!/usr/bin/env node
/**
 * Contract for gallery detail pull-to-refresh.
 *
 * Detail pages are a high-frequency route and should not require backing out and reopening just to retry
 * stale/auth-sensitive data. Refresh must reuse the existing PullRefresh scaffold, reload the current
 * gid/token through the same detail fetch path, and keep already-rendered content visible while refreshing.
 *
 * Run: node scripts/test_gallery_detail_refresh_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const page = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok('detail page imports PullRefreshListScaffold', /PullRefreshListScaffold/.test(page))
ok('detail page imports PullRefreshController', /PullRefreshController/.test(page))
ok('detail page keeps a refresh controller', /private refreshController:\s*PullRefreshController\s*=\s*new PullRefreshController\(\)/.test(page))
ok(
  'detail page uses PullRefreshListScaffold instead of importing SecondaryListScaffold',
  /PullRefreshListScaffold\(\{/.test(page) && !/^\s*SecondaryListScaffold,/m.test(page),
)
ok('detail refresh uses existing scroller', /PullRefreshListScaffold\(\{[\s\S]*scroller:\s*this\.scroller/.test(page))
ok('detail refresh preserves list spacing and FAB-aware bottom padding', /listSpace:\s*ThemeConstants\.SPACE_MD/.test(page) && /bottomPadding:\s*ThemeConstants\.SPACE_XXL\s*\+\s*ThemeConstants\.BUTTON_HEIGHT/.test(page))
ok('detail page wires onRefresh to GalleryDetailViewModel.refresh', /onRefresh:\s*async \(\) => \{[\s\S]*await this\.vm\.refresh\(\)/.test(page))
ok('detail page wires bottom pull-up to the existing all-thumbnails entry',
  /private detailBottomPreviewInitialPage\(\): number \{[\s\S]*this\.thumbMode\.hideGalleryThumbnails[\s\S]*this\.thumbMode\.horizontalThumbnails[\s\S]*return this\.vm\.images\[this\.vm\.images\.length - 1\]\.page/.test(page) &&
  /onBottomRefresh:\s*async \(\) => \{[\s\S]*this\.openThumbnails\(this\.detailBottomPreviewInitialPage\(\)\)/.test(page) &&
  /canStartBottomRefresh:\s*\(\) => this\.vm\.images\.length > 0/.test(page))
ok('detail title menu includes a non-destructive refresh action',
  /const refreshInner: Record<string, Object> = \{[\s\S]*'label': \$r\('app\.string\.common_refresh'\)[\s\S]*'icon': \$r\('sys\.symbol\.arrow_clockwise'\)[\s\S]*this\.refreshFromTitle\(\)/.test(page))
ok('detail title refresh reuses the same ViewModel refresh path and guards double taps',
  /@Local detailRefreshInFlight: boolean = false/.test(page) &&
  /private async refreshFromTitle\(\): Promise<void> \{[\s\S]*if \(this\.detailRefreshInFlight\)[\s\S]*await this\.vm\.refresh\(\)[\s\S]*this\.detailRefreshInFlight = false/.test(page))
ok('detail title refresh reports failure without clearing current content',
  /refreshFromTitle[\s\S]*openToast\(\{[\s\S]*message: \$r\('app\.string\.common_refresh_failed'\)/.test(page) &&
  !/refreshFromTitle[\s\S]*this\.vm\.images\s*=\s*\[\]/.test(page))
ok('detail title menu keeps favorite/share inline priority and refresh in the HDS overflow set',
  /const items: Record<string, Object>\[\] = \[\s*\{ 'content': favoriteInner \},\s*\{ 'content': shareInner \},\s*\{ 'content': commentsInner \},\s*\{ 'content': refreshInner \},/.test(page) &&
  /return \{ 'value': items, 'maxCount': 3 \}/.test(page) &&
  !/tagGallery|setusertag|addTag\(/.test(page))
ok('detail title reveal still uses onDidScroll', /onDidScroll:\s*\(offset: number\)/.test(page) && /this\.showNavTitle = past/.test(page))

const vm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
ok('detail VM exposes refresh', /async refresh\(\): Promise<void>/.test(vm))
ok('detail refresh is guarded by current loading state and current gid', /if \(this\.loading \|\| this\.gid\.length === 0\)/.test(vm))
ok('detail refresh does not clear gallery/images/comments before fetch', !/refresh\(\)[\s\S]*this\.images\s*=\s*\[\][\s\S]*fetchAndApply/.test(vm))
ok('detail refresh reuses the same fetch-and-apply path as initial load', /await this\.fetchAndApply\(this\.gid, this\.token, true\)/.test(vm))
ok('initial load reuses fetch-and-apply path', /async load\([\s\S]*await this\.fetchAndApply\(gid, token, false\)/.test(vm))
ok('fetch-and-apply still performs sparse gdata enrich before detail fetch', /private async fetchAndApply[\s\S]*this\.gallery\.fileCount\.length === 0[\s\S]*await this\.enrichFromApi/.test(vm))
ok('fetch-and-apply still fetches gallery detail through EhApiService', /getGalleryDetail\([\s\S]*connectSiteMode\(\)\.isEx/.test(vm))
ok('fetch-and-apply replaces images/comments/preview count from fresh result', /this\.images = res\.images/.test(vm) && /this\.comments = res\.comments/.test(vm) && /this\.previewPageCount = res\.previewPageCount/.test(vm))
ok('refresh success emits a bounded diagnostic for device evidence', /detail_refresh_ok[\s\S]*images=\$\{this\.images\.length\}/.test(vm))
ok('refresh failure records a refresh-specific diagnostic', /detail_refresh_failed/.test(vm))
ok('refresh rethrows an Error so PullRefresh can show failed-refresh feedback', /catch \(err\)[\s\S]*throw new Error\(this\.error\)/.test(vm))

for (const locale of [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]) {
  ok(`${locale} defines common_refresh`, /"name": "common_refresh"/.test(read(locale)))
}

console.log(`✓ gallery detail refresh contract: ${passed} assertions passed`)
