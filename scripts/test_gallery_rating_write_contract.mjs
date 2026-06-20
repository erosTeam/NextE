#!/usr/bin/env node
/**
 * Contract for protected EH gallery rating writes.
 *
 * Locks the product/data contract:
 * - /api.php method=rategallery uses detail-scraped apiuid/apikey and EH half-star integer rating.
 * - Detail no longer routes Rate to the old readonly web-only dialog.
 * - Rating UI is an AppModalScaffold sheet with half-star choices and title confirm action.
 * - Success writes server-returned rating_usr/rating_avg/rating_cnt/rating_cls into detail + retained lists.
 *
 * Run: node scripts/test_gallery_rating_write_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

const api = read('shared/src/main/ets/network/EhApiPhpService.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
const mutation = read('shared/src/main/ets/state/GalleryRatingMutationState.ets')
const homeVm = read('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets')
const searchVm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const favVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const homeBody = read('feature/home/src/main/ets/components/GalleryListBody.ets')
const searchPage = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const favPage = read('feature/user/src/main/ets/components/FavcatPage.ets')
const barrel = read('shared/src/main/ets/Index.ets')

ok('API exposes rategallery request body with EH fields',
  /class RateGalleryRequest[\s\S]*method: string = 'rategallery'[\s\S]*apikey: string[\s\S]*apiuid: number[\s\S]*gid: number[\s\S]*token: string[\s\S]*rating: number/.test(api))
ok('API posts rategallery to /api.php as JSON',
  /static async rateGallery\([\s\S]*Promise<GalleryRatingResult>/.test(api) &&
  api.includes('`${base}/api.php`') &&
  /postJson\([\s\S]*JSON\.stringify\(req\)/.test(api))
ok('API parses server rating response fields',
  /rating_usr/.test(api) &&
  /rating_avg/.test(api) &&
  /rating_cnt/.test(api) &&
  /rating_cls/.test(api) &&
  /result\.userRating = EhApiPhpService\.numberFrom\(obj\.rating_usr\)/.test(api) &&
  /result\.averageRating = EhApiPhpService\.numberFrom\(obj\.rating_avg\)/.test(api) &&
  /result\.ratingCount = EhApiPhpService\.intFrom\(obj\.rating_cnt\)\.toString\(\)/.test(api) &&
  /result\.colorRating = typeof obj\.rating_cls === 'string' \? obj\.rating_cls : ''/.test(api))
ok('API rejects missing apikey/apiuid/gid before destructive write',
  /apikey\.length === 0[\s\S]*Number\.isNaN\(apiuidNum\)[\s\S]*Number\.isNaN\(gidNum\)[\s\S]*throw new Error\('rateGallery: missing API key'\)/.test(api))

ok('detail VM converts stars to EH half-star integer and calls API',
  /async rateGallery\(stars: number\): Promise<GalleryRatingResult> \{[\s\S]*const ratingValue: number = Math\.round\(stars \* 2\)[\s\S]*EhApiPhpService\.rateGallery\([\s\S]*this\.gallery\.apikey[\s\S]*this\.gallery\.apiuid[\s\S]*ratingValue/.test(detailVm))
ok('detail VM applies server-returned rating fields like eros_fe afterRating',
  /applyRatingResult\(result: GalleryRatingResult\): void \{[\s\S]*next\.ratingFallBack = result\.userRating[\s\S]*next\.rating = result\.averageRating[\s\S]*next\.ratingCount = result\.ratingCount[\s\S]*next\.colorRating = result\.colorRating[\s\S]*next\.isRated = true/.test(detailVm))

ok('rating mutation is V2 app-wide signal and exported',
  /@ObservedV2[\s\S]*export class GalleryRatingMutationState[\s\S]*@Trace version/.test(mutation) &&
  /publish\([\s\S]*userRating: number[\s\S]*averageRating: number[\s\S]*ratingCount: string[\s\S]*colorRating: string[\s\S]*this\.version = this\.version \+ 1/.test(mutation) &&
  /connectGalleryRatingMutation/.test(barrel) &&
  /GalleryRatingResult/.test(barrel))

ok('detail page opens rating sheet rather than readonly web dialog',
  /private openRatingSheet\(\): void \{[\s\S]*this\.ratingSheetShown = true/.test(detail) &&
  /Text\(\$r\('app\.string\.detail_rate'\)\)[\s\S]*this\.openRatingSheet\(\)/.test(detail) &&
  !/openRatingSafety/.test(detail))
ok('rating sheet uses AppModalScaffold and title confirm action',
  /private RatingSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*title: \$r\('app\.string\.detail_rate'\)[\s\S]*confirmText: \$r\('app\.string\.detail_rate_submit'\)[\s\S]*confirmEnabled: this\.canSubmitRating\(\)[\s\S]*confirmAction: \(\) => \{[\s\S]*this\.submitRating\(\)/.test(detail))
ok('rating sheet offers half-star choices, not a web fallback',
  /private ratingOptions: number\[] = \[0\.5, 1, 1\.5, 2, 2\.5, 3, 3\.5, 4, 4\.5, 5\]/.test(detail) &&
  /RatingStars\(\{[\s\S]*rating: value/.test(detail) &&
  /this\.ratingSelected = value/.test(detail))
ok('rating submit publishes mutation after server success',
  /const result: GalleryRatingResult = await this\.vm\.rateGallery\(this\.ratingSelected\)[\s\S]*this\.ratingMutation\.publish\([\s\S]*result\.userRating[\s\S]*result\.averageRating[\s\S]*result\.ratingCount[\s\S]*result\.colorRating/.test(detail))
ok('rating submit reports failures without closing sheet first',
  /catch \(err\) \{[\s\S]*this\.ratingError = EhErrorText\.forUser\(err\)[\s\S]*detail_rate_failed/.test(detail))
ok('detail page hosts rating sheet separately from favorite sheet',
  /bindSheet\(\$\$this\.remoteFavoriteSheetShown/.test(detail) &&
  /bindSheet\(\$\$this\.ratingSheetShown, this\.RatingSheet\(\)/.test(detail))

for (const [name, src] of [
  ['home', homeVm],
  ['search', searchVm],
  ['favorites', favVm],
]) {
  ok(`${name} VM applies rating mutation to retained rows`,
    /applyRatingMutation\([\s\S]*userRating: number[\s\S]*averageRating: number[\s\S]*ratingCount: string[\s\S]*colorRating: string[\s\S]*next\.ratingFallBack = userRating[\s\S]*next\.rating = averageRating[\s\S]*next\.ratingCount = ratingCount[\s\S]*next\.colorRating = colorRating[\s\S]*next\.isRated = true[\s\S]*this\.dataSource\.setData\(nextRows\)/.test(src))
}
for (const [name, src] of [
  ['home body', homeBody],
  ['search page', searchPage],
  ['favcat page', favPage],
]) {
  ok(`${name} monitors GalleryRatingMutationState`,
    /GalleryRatingMutationState/.test(src) &&
    /connectGalleryRatingMutation/.test(src) &&
    /@Monitor\('ratingMutation\.version'\)[\s\S]*applyRatingMutation\([\s\S]*this\.ratingMutation\.gid[\s\S]*this\.ratingMutation\.userRating/.test(src))
}

console.log(`✓ gallery rating write contract: ${passed} assertions passed`)
