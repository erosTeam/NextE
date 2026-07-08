# Download Management Search And Sorting

Status: implemented candidate; gallery-side X7 smoke passed, archive row metadata still needs a device sample with at least one archive task.

Purpose: guide the Downloads tab cleanup for search, status grouping, sorting, and richer archive rows. Keep this file updated when scope changes so follow-up work does not depend on conversation memory.

## Grounding

Reference behavior:

- `../eros_n_ohos/lib/pages/nav/downloads/downloads_page.dart`: search by title/GID, status groups, sort by added time/title.
- `../eros_n_ohos/lib/store/db/entity/download_task.dart`: durable task `createdAt` field.
- `../eros_fe/lib/pages/item/download_gallery_item.dart`: task rows show title, cover, progress/count, and added time.
- `../eros_fe/lib/pages/item/download_archiver_item.dart`: archive rows show title, cover, resolution, progress, and created time.
- NextE current surface: `feature/download/src/main/ets/pages/DownloadQueuePage.ets` plus title-bottom selector in `entry/src/main/ets/components/DownloadTypeBar.ets`.

## Current Data Facts

- Gallery tasks already have `queuedAt`, `pageCount`, `category`, `preferOriginal`, and live progress fields.
- Archiver tasks already have `queuedAt`, `dltype`, `resolution`, `bytesWritten`, `bytesTotal`, `progress`, `thumbUrl`, and status.
- The repository already reads both queues by `queued_at DESC`.
- Archiver tasks do not currently persist `pageCount` or `category`; displaying those requires a model/RDB/metadata migration.

## Implementation Order

1. Page-only work first:
   - add search state and sort mode to `DownloadViewState`;
   - let the title-bottom download bar switch between the existing Gallery/Archiver segmented control and a search field;
   - add title-bar menu actions for search and sort modes;
   - keep search and one sort-cycle action inline in the title bar; detailed sort choices stay in the overflow menu so the current sort checkmark is not exposed as an unlabeled top action;
   - render filtered tasks grouped by status;
   - sort inside each status group by added time or title;
   - show added time on both Gallery and Archiver task rows;
   - enrich Archiver metadata with resolution/type and byte size when available.
2. Only if required later:
   - add `pageCount` and `category` to `DownloadArchiverTask`;
   - pass them from gallery detail / archive sheet;
   - migrate RDB and metadata.

## Status Groups

Display only non-empty groups:

- Active: queued, preparing, ready, downloading, partial.
- Paused: paused.
- Failed: error.
- Completed: complete.

Completed stays after active/paused/failed regardless of selected sort mode.

## Non-Scope

- No download executor rewrite.
- No RDB schema change in the first slice.
- No bulk destructive actions.
- No full-text database search.
- No new caching/sync behavior.

## Verification

- `node scripts/test_v1_decorator_inventory_contract.mjs`
- UI grounding ledger review
- `python3 scripts/check_i18n_duplicates.py`
- signed HarmonyOS build
- X7 emulator first: open Downloads, switch Gallery/Archiver, search hit/miss, switch sort modes, confirm grouped rows and archive metadata do not break card layout.

## 2026-07-01 Implementation Notes

- Added `DownloadViewState.searchActive`, `searchText`, and `sortMode`.
- Reused the Downloads title-bottom selector; it switches to `AppSearchField` only while search is active.
- Downloads title actions now show search, one sort-cycle action, and overflow. Detailed sort choices stay in overflow.
- Gallery and Archiver queues derive visible rows by search filter, status group, and selected sort mode without mutating queue order.
- Gallery rows show queued time; Archiver rows can show resolution/type, byte size, and queued time from existing task fields.
- X7 evidence:
  - `/private/tmp/nexte_download_initial.jpeg`: grouped Gallery list with search/sort/overflow actions.
  - `/private/tmp/nexte_download_search_fixed.jpeg`: `Minecraft` search hit shows one row and `已完成 1`.
  - `/private/tmp/nexte_download_search_empty.jpeg`: miss search shows `没有匹配的下载`.
  - `/private/tmp/nexte_download_sort_cycle.jpeg`: sort-cycle action changes completed-task order.
  - `/private/tmp/nexte_download_archiver.jpeg`: Archiver tab empty state remains intact; archive metadata row still needs a real archive task sample.
