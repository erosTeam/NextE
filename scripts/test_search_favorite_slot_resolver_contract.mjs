#!/usr/bin/env node
/**
 * Contract: Search visible favorite hearts must re-resolve favTitle -> favcat when real favcat
 * metadata arrives. This mirrors the Favorites page path and excludes seed placeholders.
 *
 * Run: node scripts/test_search_favorite_slot_resolver_contract.mjs
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

const resolver = read('shared/src/main/ets/utils/FavcatSlotResolver.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const searchVm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const searchPage = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const favVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')

ok('shared resolver exists and only maps real favcat titles',
  /export class FavcatSlotResolver/.test(resolver) &&
  /static realTitleMap\(favcats: Favcat\[\]\): Map<string, string>/.test(resolver) &&
  /!FavSelectionState\.isPlaceholderFavcat\(f\)/.test(resolver) &&
  /byTitle\.set\(f\.favTitle, f\.favId\)/.test(resolver))

ok('shared resolver applies title -> slot only to rows missing favcat',
  /static applyInPlace\(gallerys: EhGallery\[\], favcats: Favcat\[\]\): void/.test(resolver) &&
  /g\.favcat\.length === 0 && g\.favTitle\.length > 0/.test(resolver) &&
  /g\.favcat = hit/.test(resolver))

ok('shared resolver can replace visible datasource rows with resolved copies',
  /static resolvedCopies\(rows: EhGallery\[\], favcats: Favcat\[\]\): FavcatSlotResolveResult/.test(resolver) &&
  /const next: EhGallery = g\.copy\(\)/.test(resolver) &&
  /next\.favcat = hit/.test(resolver) &&
  /result\.changed = true/.test(resolver))

ok('shared barrel exports the resolver for Search and Favorites',
  /export \{ FavcatSlotResolver, FavcatSlotResolveResult \} from '\.\/utils\/FavcatSlotResolver'/.test(sharedIndex))

ok('FavoritesViewModel uses the shared resolver instead of a private title map',
  /FavcatSlotResolver/.test(favVm) &&
  /FavcatSlotResolver\.applyInPlace\(gallerys, favcats\)/.test(favVm) &&
  /FavcatSlotResolver\.resolvedCopies\(this\.dataSource\.getAll\(\), favcats\)/.test(favVm) &&
  !/realFavcatTitleMap/.test(favVm))

ok('SearchViewModel resolves fetched pages before rendering or appending them',
  /private resolveFavoriteSlots\(gallerys: EhGallery\[\], favcats: Favcat\[\]\): void \{[\s\S]*FavcatSlotResolver\.applyInPlace\(gallerys, favcats\)/.test(searchVm) &&
  /const list: GalleryList = await this\.fetchPage\(''\)[\s\S]*this\.resolveFavoriteSlots\(list\.gallerys, list\.favList\)[\s\S]*this\.dataSource\.setData\(list\.gallerys\)/.test(searchVm) &&
  /async refresh\(\): Promise<void> \{[\s\S]*const list: GalleryList = await this\.fetchPage\(''\)[\s\S]*this\.resolveFavoriteSlots\(list\.gallerys, list\.favList\)[\s\S]*this\.dataSource\.setData\(list\.gallerys\)/.test(searchVm) &&
  /const fresh: EhGallery\[\] = this\.dedupeNew\(list\.gallerys\)[\s\S]*this\.resolveFavoriteSlots\(fresh, list\.favList\)[\s\S]*this\.dataSource\.appendData\(fresh\)/.test(searchVm))

ok('SearchViewModel can re-resolve already-visible rows when metadata arrives later',
  /resolveVisibleFavoriteSlotsFrom\(favcats: Favcat\[\]\): boolean \{[\s\S]*FavcatSlotResolver\.resolvedCopies\(this\.dataSource\.getAll\(\), favcats\)[\s\S]*this\.dataSource\.setData\(result\.rows\)/.test(searchVm))

ok('GallerySearchPage listens to account-level favcat metadata and re-resolves Search rows',
  /@Local favSel: FavSelectionState = connectFavSelection\(\)/.test(searchPage) &&
  /@Monitor\('favSel\.favList'\)[\s\S]*onFavListChange\(\): void \{[\s\S]*this\.vm\.resolveVisibleFavoriteSlotsFrom\(this\.favSel\.favList\)/.test(searchPage))

console.log(`✓ search favorite slot resolver contract: ${passed} assertions passed`)
