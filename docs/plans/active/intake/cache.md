# Cache Architecture Intake

Status: domain intake ledger.

Purpose:

- Track NextE's app-wide cache design gaps separately from one-off Reader/download/history bugs.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- Cache work must define storage ownership, invalidation, size limits, and user-facing cache management before
  broad implementation.
- Durable user data and settings import/export are tracked in `persistence.md`; do not collapse those into a
  cache-clear implementation.

## Items

### App Cache Architecture And Cache Management Are Incomplete

Type: architecture gap / performance and storage UX

Priority suggestion: P1

Status: accepted / needs design and implementation

Source:

- User feedback, 2026-06-22: the app's cache design and cache management feel very incomplete, including
  image cache, HTML cache, possible gallery-detail cache, and other local data surfaces.
- User also observed history page entry can pause before content appears, raising concern that local history
  data is being restored/rendered as a whole blob rather than through a scalable storage model.

Current evidence:

- `shared/src/main/ets/services/ImageResolveService.ets` has in-memory maps for showKey, resolved full-image
  metadata, and in-flight image-page resolve promises. These are useful session caches, but they are not a
  managed disk image/HTML cache.
- Reader currently has `ReaderViewModel.sessionCache`, another process-local cache for preview metadata and
  resolved URLs. It is bounded by entry count, but it is not persistent and is tightly coupled to Reader state.
- Full-image bytes are left to ArkUI/Image/platform cache. There is no app-owned `ImageDiskCache` with size
  accounting, TTL, clear controls, or per-gallery management.
- HTML responses for list/detail/image pages are generally fetched and parsed through services/parsers; there
  is no shared HTML cache policy with freshness rules, auth/site partitioning, or invalidation after writes.
- Gallery detail data is fetched through view models/parsers. There is no explicit gallery-detail repository
  cache that can quickly reopen a gallery while refreshing in the background.
- Search history, viewed history, and reading progress are stored as Preferences JSON blobs:
  `SearchHistorySettings` caps search history at 100, `ViewedHistorySettings` caps viewed history at 200,
  and `GalleryReadProgressSettings` stores a JSON array with debounced writes. This is acceptable as a small
  early slice, but it is not a scalable history/cache repository model. The durable-data migration and
  settings backup concerns are tracked in `persistence.md`.
- The roadmap already names the missing target shape: `ImageDiskCache`, `ReaderResumeStore`,
  `GalleryCacheRepository`, and RDB-backed local data repositories. Current code only covers fragments.

Expected behavior:

- Define a cache taxonomy before adding more ad hoc caches:
  - image bytes / thumbnails / sprite thumbnails;
  - image-page HTML and resolved image metadata;
  - gallery list page HTML or parsed list results;
  - gallery detail parsed snapshot;
  - Reader preview metadata/session state;
  - viewed history, search history, reading progress, and future WebDAV-syncable records.
- Each cache type must state owner, key, storage backend, auth/site partitioning, invalidation trigger, size
  limit, TTL/freshness, and user clear behavior.
- Cache management UI should expose clear categories that users understand, such as image cache, page/HTML
  cache, history/progress, and downloaded/offline content. Do not mix destructive local downloads with
  disposable network cache under one button.
- Cache reads should be stale-while-refresh where useful: reopen gallery detail/history/reader quickly from
  local data, then refresh network data without flashing empty pages.
- Writes that mutate EH state, such as favorites, comments, ratings, and tags, must invalidate or patch the
  affected cached gallery/detail/list records.

Acceptance shape:

- Add a short cache architecture document or section naming the cache categories, backends, invalidation, and
  management UI.
- Implement the first bounded slice with a real storage backend where needed. Avoid a temporary in-memory-only
  layer for large datasets or long-lived caches.
- Add deterministic contracts for the chosen slice, including cache key partitioning by site/account where
  relevant, invalidation after refresh/write, and clear-cache behavior.
- Add an installed-device smoke path when the slice affects launch/open performance or cache management UI.

Non-goals for the first slice:

- Do not build the full download/offline reader system inside cache architecture.
- Do not rewrite every existing Preferences-backed small setting/history store at once.
- Do not add a custom cache framework if the native RDB/filesystem/platform image cache can cover a slice.
