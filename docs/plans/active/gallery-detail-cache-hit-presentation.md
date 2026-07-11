# Gallery Detail Cache-Hit Presentation

Status: complete (2026-07-12). Scope was limited to the reported same-gallery re-entry flash.

## Goal

Within one app process, reopening a recently loaded gallery must apply a bounded in-memory detail snapshot
before the first loading frame, then retain the existing asynchronous network refresh.

## Completed work

1. Add a clone-on-read, account/site-keyed, bounded gallery-detail memory LRU above the existing RDB cache.
2. Apply that memory snapshot in `GalleryDetailViewModel` before setting the initial loading state; use RDB
   only as the memory-miss fallback.
3. Verify the same-gallery return-and-reopen path on Mate X7 with immediate UI-tree/screen evidence and
   the full on-device test suite.

## Result

The X7 same-item reopen rendered the complete cached detail immediately (metadata, tags, comments, and
preview controls) without a `LoadingProgress` node. The original network refresh remains asynchronous.
The separate header-image spinner did not reproduce on this route, so `EhThumbnail` remains unchanged.

## Conditional follow-up

Only if X7 still shows the header-cover's own spinner after item 1-3, add a narrow delayed native-spinner
gate to `EhThumbnail`. Do not change image-cache policy, route retention, or global loading behavior.
