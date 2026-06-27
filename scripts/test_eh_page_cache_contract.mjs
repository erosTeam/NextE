#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function fail(message) {
  console.error(`eh page cache contract failed: ${message}`);
  process.exit(1);
}

function assertIncludes(source, needle, message) {
  if (!source.includes(needle)) {
    fail(message);
  }
}

function assertNotIncludes(source, needle, message) {
  if (source.includes(needle)) {
    fail(message);
  }
}

function assertOrder(source, first, second, message) {
  const firstIndex = source.indexOf(first);
  const secondIndex = source.indexOf(second);
  if (firstIndex < 0 || secondIndex < 0 || firstIndex >= secondIndex) {
    fail(message);
  }
}

const localDataStore = read('shared/src/main/ets/storage/LocalDataStore.ets');
assertIncludes(localDataStore, 'CREATE TABLE IF NOT EXISTS eh_page_cache', 'page cache must be an RDB table, not Preferences');
assertIncludes(localDataStore, 'PRIMARY KEY(kind, cache_key)', 'page cache must key by cache kind + scoped cache key');
assertIncludes(localDataStore, 'idx_eh_page_cache_expires', 'page cache must have an expiry index');
assertIncludes(localDataStore, 'idx_eh_page_cache_access', 'page cache must have an access/prune index');

const service = read('shared/src/main/ets/services/EhPageCacheService.ets');
assertIncludes(service, "const CACHE_KIND_GALLERY_LIST: string = 'gallery_list'", 'service must separate gallery-list cache entries');
assertIncludes(service, "const CACHE_KIND_GALLERY_DETAIL: string = 'gallery_detail'", 'service must separate gallery-detail cache entries');
assertIncludes(service, 'EhConstants.COOKIE_MEMBER_ID', 'cache key must include the logged-in account scope');
assertIncludes(service, 'const site: string = isEx ?', 'cache key must include EH/EX site scope');
assertIncludes(service, 'LocalDataStore.open(context)', 'cache service must use the shared RDB store');
assertNotIncludes(service, 'Preferences', 'page cache must not store large payloads in Preferences');
assertIncludes(service, 'expires_at > ?', 'cache reads must ignore expired rows');
assertIncludes(service, 'SQL_DELETE_EXPIRED_CACHE', 'cache writes must clean expired rows');
assertIncludes(service, 'SQL_PRUNE_KIND_CACHE', 'cache writes must prune old entries');
assertIncludes(service, "'load_miss'", 'cache reads must log miss diagnostics for device verification');
assertIncludes(service, "'load_hit'", 'cache reads must log hit diagnostics for device verification');
assertIncludes(service, "'save_ok'", 'cache writes must log success diagnostics for device verification');
assertIncludes(service, "'save_failed'", 'cache writes must log failure diagnostics for device verification');
assertIncludes(service, 'MAX_LIST_ROWS_PER_CACHE', 'gallery-list snapshots must cap row count');
assertIncludes(service, 'reviveGalleryList(raw)', 'JSON cache must revive GalleryList class instances');
assertIncludes(service, 'reviveGallery(raw.gallery)', 'JSON cache must revive GalleryDetail gallery instances');
assertIncludes(service, 'new GalleryDetailResult', 'detail cache must restore the network result wrapper');
assertIncludes(service, 'new EhGallery(', 'gallery cache must revive EhGallery methods such as copy()/merge()');
assertIncludes(service, 'new SimpleTag(', 'tag cache must revive SimpleTag methods such as copy()/display()');
assertIncludes(service, 'tag.siteLabel = siteLabel', 'tag cache must preserve EH list visible labels for selective namespace prefixes');
assertIncludes(service, 'stripLegacyGeneratedPrefix(namespace', 'tag cache must strip old generated all-namespace prefixes when siteLabel is absent');
assertIncludes(service, 'new TagGroup(', 'tag-group cache must revive TagGroup methods');
assertIncludes(service, 'new EhGalleryImage(', 'image cache must revive EhGalleryImage methods');
assertIncludes(service, 'new EhGalleryComment()', 'comment cache must revive comment objects');

const index = read('shared/src/main/ets/Index.ets');
assertIncludes(index, "export { EhPageCacheService }", 'shared barrel must export EhPageCacheService');

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets');
assertIncludes(bootstrap, 'preloadPageCaches(context)', 'settings bootstrap must preload page caches before first content mount');
assertIncludes(bootstrap, 'const profiles: CustomProfile[] = connectCustomProfiles().profiles', 'startup preload must cover custom Gallery profile subtabs');
assertIncludes(bootstrap, 'p.listType !== PROFILE_TYPE_FAVORITE', 'startup preload must skip favorite-type custom profiles because favorites use favcat cache keys');
assertIncludes(bootstrap, 'EhPageCacheService.homeProfileKey(isEx, p.uuid)', 'startup preload must use uuid-scoped custom profile cache keys');
assertIncludes(bootstrap, 'const toplistTls: number[] = [11, 12, 13, 15]', 'startup preload must cover every Toplist period subtab');
assertIncludes(bootstrap, "const favcats: string[] = ['a', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']", 'startup preload must cover every remote Favorites subtab');
assertIncludes(bootstrap, 'await Promise.all(jobs)', 'startup cache preload must run subtabs in parallel instead of serially delaying startup');
assertIncludes(bootstrap, "'preload_done'", 'startup cache preload must log completion for device verification');

const httpClient = read('shared/src/main/ets/network/EhHttpClient.ets');
assertNotIncludes(httpClient, 'usingCache: true', 'EH HTTP client must not enable transparent global cache');

const homeVm = read('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets');
assertIncludes(homeVm, 'EhPageCacheService.homeListKey', 'home VM must build a scoped page-cache key');
assertIncludes(homeVm, 'applyCachedFirstPageIfEmpty()', 'home VM must prime first screen from cache');
assertIncludes(homeVm, 'takePreloadedGalleryList(this.cacheKey())', 'home VM must consume startup-preloaded cache before opening RDB');
assertIncludes(homeVm, 'private cacheRenderVersion: number = 0', 'home VM must guard async cached-row translation against network replacement');
assertIncludes(homeVm, 'this.dataSource.setData(rows)', 'home cache hit must render cached rows immediately');
assertIncludes(homeVm, 'this.translateCachedRowsLater(rows, renderVersion, cached)', 'home cache hit must translate cached rows asynchronously after immediate render and refresh translated cache');
assertOrder(homeVm, 'this.dataSource.setData(rows)', 'this.translateCachedRowsLater(rows, renderVersion, cached)', 'home cache hit must not await tag translation before rendering rows');
assertIncludes(homeVm, 'private async renderFirstPageRows(list: GalleryList, deferTranslation: boolean): Promise<void>', 'home network first-page rows must share one render/translation/cache path');
assertIncludes(homeVm, 'if (connectTagTranslationSettings().enabled && !deferTranslation)', 'home refresh/reload with existing content must translate before replacing visible rows');
if (!/renderFirstPageRows\(list: GalleryList, deferTranslation: boolean\): Promise<void>[\s\S]*const translated: EhGallery\[] = await this\.translateRows\(displayRows\)[\s\S]*this\.dataSource\.setData\(translated\)/.test(homeVm)) {
  fail('home refresh/reload must not flash untranslated rows when content is already visible');
}
assertOrder(homeVm, 'this.dataSource.setData(displayRows)', 'this.translateCachedRowsLater(displayRows, renderVersion, list)', 'home cold/no-content path may render immediately before async tag translation');
assertOrder(homeVm, 'await this.applyCachedFirstPageIfEmpty()', 'const list: GalleryList = await this.fetchFirstPageList()', 'home first load must read cache before network fetch');
assertIncludes(homeVm, 'await this.saveFirstPageCache(list)', 'home VM must save successful first-page network loads');
assertIncludes(homeVm, 'snapshot.gallerys = translated', 'home VM must refresh list cache with translated rows after async translation');
assertIncludes(homeVm, 'this.itemCount > 0', 'home cache must only apply to an empty first screen');

const favVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets');
assertIncludes(favVm, 'EhPageCacheService.favoritesListKey', 'favorites VM must build a scoped page-cache key');
assertIncludes(favVm, 'this.isLocalFavcat()', 'favorites cache must skip the local-favorites pseudo tab');
assertIncludes(favVm, 'takePreloadedGalleryList(this.cacheKey())', 'favorites VM must consume startup-preloaded cache before opening RDB');
assertIncludes(favVm, 'private cacheRenderVersion: number = 0', 'favorites VM must guard async cached-row translation against network replacement');
assertIncludes(favVm, 'this.translateCachedRowsLater(rows, renderVersion, cached)', 'favorites cache hit must translate cached rows asynchronously after immediate render and refresh translated cache');
assertOrder(favVm, 'this.dataSource.setData(rows)', 'this.translateCachedRowsLater(rows, renderVersion, cached)', 'favorites cache hit must not await tag translation before rendering rows');
assertIncludes(favVm, 'private async renderFirstPageRows(list: GalleryList, deferTranslation: boolean): Promise<void>', 'favorites network first-page rows must share one render/translation/cache path');
assertIncludes(favVm, 'if (connectTagTranslationSettings().enabled && !deferTranslation)', 'favorites refresh/reload with existing content must translate before replacing visible rows');
if (!/renderFirstPageRows\(list: GalleryList, deferTranslation: boolean\): Promise<void>[\s\S]*const translated: EhGallery\[] = await this\.translateRows\(displayRows\)[\s\S]*this\.dataSource\.setData\(translated\)/.test(favVm)) {
  fail('favorites refresh/reload must not flash untranslated rows when content is already visible');
}
assertOrder(favVm, 'this.dataSource.setData(displayRows)', 'this.translateCachedRowsLater(displayRows, renderVersion, list)', 'favorites cold/no-content path may render immediately before async tag translation');
assertOrder(favVm, 'await this.applyCachedFirstPageIfEmpty()', 'const list: GalleryList = await this.fetchPage', 'favorites first load must read cache before network fetch');
assertIncludes(favVm, 'snapshot.favList = this.favList', 'favorites cache must preserve favcat selector metadata');
assertIncludes(favVm, 'await this.saveFirstPageCache(list)', 'favorites VM must save successful first-page network loads');

const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets');
assertIncludes(detailVm, 'EhPageCacheService.galleryDetailKey', 'detail VM must build a scoped detail-cache key');
assertOrder(detailVm, 'await this.applyCachedDetailIfAvailable(gid, token)', 'await this.fetchAndApply(gid, token, false)', 'detail load must render cache before fresh network detail');
assertIncludes(detailVm, '@Trace cachedDetailApplied: boolean = false', 'detail VM must expose whether cached detail content is already applied');
assertIncludes(detailVm, 'this.cachedDetailApplied = true', 'detail VM must mark cache-applied state after a detail cache hit');
assertIncludes(detailVm, 'private detailRenderVersion: number = 0', 'detail VM must guard async cached-detail translation against network replacement');
assertIncludes(detailVm, 'this.translateCachedGalleryLater(this.gallery, renderVersion)', 'detail cache hit must translate cached gallery asynchronously after immediate render');
assertOrder(detailVm, 'this.gallery = connectTagTranslationSettings().enabled', 'this.translateCachedGalleryLater(this.gallery, renderVersion)', 'detail cache hit must not await tag translation before rendering cached detail');
assertNotIncludes(detailVm, 'this.gallery = await this.translateGallery(this.gallery.merge(res.gallery))', 'detail network result must not await tag translation before rendering gallery content');
assertIncludes(detailVm, 'const translated: EhGallery = await this.translateGallery(merged)', 'detail network result must translate tags before replacing visible detail tags');
assertOrder(detailVm, 'this.gallery = translated', 'this.saveCurrentDetailCache()', 'detail VM must refresh detail cache after async tag translation fills translat fields');
assertIncludes(detailVm, 'await this.saveCurrentDetailCache()', 'detail VM must save successful detail network loads');
assertIncludes(detailVm, 'this.saveCurrentDetailCache()', 'detail VM must refresh cache after known favorite/rating/tag mutations');
assertIncludes(detailVm, 'TagTranslationService.clearGalleryTranslations(gallery)', 'detail cache must not leak stale localized tag text when translation is disabled');

const detailPage = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets');
assertIncludes(detailPage, 'this.vm.loading && !this.vm.cachedDetailApplied', 'detail page must not keep showing first-load spinner after cached detail content is applied');

console.log('eh page cache contract passed');
