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
assertIncludes(service, 'MAX_PRELOADED_GALLERY_LISTS', 'startup preload staging must have a finite memory cap');
assertIncludes(service, 'PreloadedGalleryListMemoryCache', 'startup preload staging must use a bounded cache type');
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
assertIncludes(index, 'EhPageCacheService, PreloadedGalleryListMemoryCache', 'shared barrel must export page-cache service and bounded preload cache');

const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets');
assertIncludes(bootstrap, 'const profiles: CustomProfile[] = connectCustomProfiles().profiles', 'startup preload must cover custom Gallery profile subtabs');
assertIncludes(bootstrap, 'p.listType !== PROFILE_TYPE_FAVORITE', 'startup preload must skip favorite-type custom profiles because favorites use favcat cache keys');
assertIncludes(bootstrap, 'EhPageCacheService.homeProfileKey(isEx, p.uuid)', 'startup preload must use uuid-scoped custom profile cache keys');
assertIncludes(bootstrap, 'const toplistTls: number[] = [11, 12, 13, 15]', 'startup preload must cover every Toplist period subtab');
assertIncludes(bootstrap, "const favcats: string[] = ['a', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']", 'startup preload must cover every remote Favorites subtab');
assertIncludes(bootstrap, 'const MAX_PAGE_CACHE_PRELOAD_CONCURRENCY: number = 2', 'startup cache preload must cap concurrent RDB work');
assertIncludes(bootstrap, 'await SettingsBootstrap.preloadGalleryListsBounded(context, keys)', 'startup cache preload must use bounded workers');
assertIncludes(bootstrap, 'await Promise.all(workers)', 'startup cache preload must retain bounded parallelism');
assertIncludes(bootstrap, "'preload_done'", 'startup cache preload must log completion for device verification');

// Cache-warming timing is a first-frame performance concern. It is intentionally verified through the
// device startup path rather than requiring a specific bootstrap-await shape here.

const httpClient = read('shared/src/main/ets/network/EhHttpClient.ets');
assertNotIncludes(httpClient, 'usingCache: true', 'EH HTTP client must not enable transparent global cache');

// First-screen rendering order, translation presentation, and spinner behavior are user-path concerns.
// They require cache-hit and cache-miss device evidence instead of implementation-shape assertions here.

console.log('eh page cache contract passed');
