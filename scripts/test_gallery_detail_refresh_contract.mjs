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
ok('detail refresh preserves list spacing and bottom padding', /listSpace:\s*ThemeConstants\.SPACE_MD/.test(page) && /bottomPadding:\s*ThemeConstants\.SPACE_XL/.test(page))
ok('detail page wires onRefresh to GalleryDetailViewModel.refresh', /onRefresh:\s*async \(\) => \{[\s\S]*await this\.vm\.refresh\(\)/.test(page))
ok('detail title reveal still uses onDidScroll', /onDidScroll:\s*\(offset: number\)/.test(page) && /this\.showNavTitle = past/.test(page))

const vm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
ok('detail VM exposes refresh', /async refresh\(\): Promise<void>/.test(vm))
ok('detail refresh is guarded by current loading state and current gid', /if \(this\.loading \|\| this\.gid\.length === 0\)/.test(vm))
ok('detail refresh does not clear gallery/images/comments before fetch', !/refresh\(\)[\s\S]*this\.images\s*=\s*\[\][\s\S]*fetchAndApply/.test(vm))
ok('detail refresh reuses the same fetch-and-apply path as initial load', /await this\.fetchAndApply\(this\.gid, this\.token\)/.test(vm))
ok('initial load reuses fetch-and-apply path', /async load\([\s\S]*await this\.fetchAndApply\(gid, token\)/.test(vm))
ok('fetch-and-apply still performs sparse gdata enrich before detail fetch', /private async fetchAndApply[\s\S]*this\.gallery\.fileCount\.length === 0[\s\S]*await this\.enrichFromApi/.test(vm))
ok('fetch-and-apply still fetches gallery detail through EhApiService', /getGalleryDetail\([\s\S]*connectSiteMode\(\)\.isEx/.test(vm))
ok('fetch-and-apply replaces images/comments/preview count from fresh result', /this\.images = res\.images/.test(vm) && /this\.comments = res\.comments/.test(vm) && /this\.previewPageCount = res\.previewPageCount/.test(vm))
ok('refresh success emits a bounded diagnostic for device evidence', /detail_refresh_ok[\s\S]*images=\$\{this\.images\.length\}/.test(vm))
ok('refresh failure records a refresh-specific diagnostic', /detail_refresh_failed/.test(vm))
ok('refresh rethrows an Error so PullRefresh can show failed-refresh feedback', /catch \(err\)[\s\S]*throw new Error\(this\.error\)/.test(vm))

console.log(`✓ gallery detail refresh contract: ${passed} assertions passed`)
