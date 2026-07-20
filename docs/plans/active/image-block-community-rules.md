# Image Block Community Rules

Status: active protocol and follow-up note.
Last reviewed: 2026-07-20.

The full implementation/device ledger is archived at
[`docs/plans/archive/image-block-community-rules-full-ledger.md`](../archive/image-block-community-rules-full-ledger.md).
It is evidence only. This file contains the current client boundary and unresolved product work.

## Current Boundary

- Community rules are maintained outside the app repository. The client subscribes to the generated manifest at
  `https://raw.githubusercontent.com/erosTeam/nexte-image-block-rules/main/dist/manifest.json`.
- Client schema: `schema=1`, manifest kind `nexte-image-block-manifest`, feed kind
  `nexte-image-block-feed`, algorithm `dct64-v1`, 16-character lowercase hex hashes, threshold `0..12`,
  first-version scope `whole`, maximum 10,000 items per feed.
- Feed update failure keeps the last valid local feed. The local allowlist wins over subscription rules.
- Reviewer-only source URL/page/note fields remain in the rules repository; generated client feeds contain only
  safe matching fields.
- Runtime decisions use local files and pHash cache. No image bytes, cookies, temporary image URLs, tokens or
  session data are uploaded by this feature.

## Landed Product Surface

- RDB-backed subscriptions, local rules, allowlist and pHash cache.
- SHA-256 verified manifest/feed refresh with last-valid fallback.
- Reader-side block decision, blurred blocked presentation, local manual block action and false-positive allowlist.
- EH settings page for subscriptions, local rules, allowlist and sanitized contribution-draft copy.
- Non-mutating QA routes only. Test helpers must not seed/delete real user rules or replace subscription feeds.
- WebDAV/Huawei Cloud sync classification is governed by
  [Persistence Dataset Inventory](persistence-dataset-inventory.md) and [Sync Design](sync-design.md), not by
  this document.

## Open Follow-Ups

- Validate representative real gallery samples when image-block matching changes.
- Decide whether contribution remains copy-assisted or gains an explicitly authorized GitHub flow.
- Consider privacy/bandwidth No Image Mode as a separate product lane.

## Deferred

- QR-code auto blocking, region/crop matching, signed feed metadata, hash indexes, backend voting/moderation and
  one-tap PR submission.
- Super-resolution, Archive Bot and download-heavy ideas are separate features and do not belong to this plan.

These items are not a scheduling queue. Work starts only from a current user request.
