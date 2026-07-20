# NextE Sync Design

Status: active implementation note.

## Scope

This lane implements the provider-neutral sync spine plus WebDAV and Huawei Cloud providers. WebDAV is a
user-configured file sync provider. Huawei Cloud sync is compiled into the app and defaults to visible for
local/private development builds.

## Syncable Data

Sync only durable user-local records with stable keys and timestamps:

- `gallery_read_progress`
- `viewed_history`
- `local_favorites`
- `search_history`
- `local_block_settings`
- `local_block_rules`
- `image_block_user_rules` for user-authored image rules (`local` / `allow`) and per-rule subscription
  overrides such as enabled state and threshold.
- `image_block_rules` stores subscription rule bodies only. Subscription bodies are regenerated from
  synced subscription feed metadata and are not exported as user data.
  Huawei Cloud syncs `image_block_user_rules` directly; it is the user-rule source table, not a mirror.
  A legacy prepare step may copy old non-subscription rows out of `image_block_rules`, but normal reads
  and writes must use `image_block_user_rules`. Huawei Cloud prepare must not clean, dedupe, delete, or
  bulk-touch image-rule rows to force upload; ordinary row writes already carry `updated_at`, and the
  system cloud provider must own dirty tracking.
- `image_block_subscriptions` stores community subscription feed metadata. WebDAV/export may carry it
  with the image-block dataset, but Huawei Cloud does not mark or download this table; a stale AGC
  `ImageBlockSubscriptions` record can otherwise fail the entire RDB cloud sync before user rules upload.
- `custom_profiles`
- `custom_profile_selection`

Do not sync disposable cache, generated/downloadable databases, device-local download state, diagnostics,
or plaintext secrets/provider credentials:

- `tag_translations`, `tag_translation_meta`
- `eh_page_cache`, `comment_translation_cache`
- `image_block_hash_cache`
- `download_gallery_tasks`, `download_gallery_seeds`, `download_archiver_tasks`
- cookie jars, account secrets, LLM API keys, WebDAV passwords

## Write Semantics

Syncable tables use real upsert (`INSERT ... ON CONFLICT DO UPDATE`) instead of `INSERT OR REPLACE`.
Deletes are represented by `deleted_at` tombstones so a later sync does not resurrect deleted rows from
another device.

Backup restore may still replace the visible set, but it should do so by tombstoning rows missing from
the restored snapshot and upserting restored rows.

## Provider Model

Providers do transport only:

- local file/import-export style sync reads and writes one `nexte-sync-v1.json` envelope
- manual WebDAV uses a directory layout: a small manifest plus one JSON file per enabled dataset group
- Huawei Cloud sync marks the selected RDB cloud table subset with `DISTRIBUTED_CLOUD` and syncs it
  directly through HarmonyOS RDB cloud sync
- manual Huawei Cloud sync must expose the last progress code and table-level upload/download/failure
  counts in diagnostics, the failure toast, and the persisted provider status, so AGC/schema mismatches
  are not reduced to a generic "sync failed" message after the page or process is recreated

Conflict resolution belongs to the sync dataset adapter, not providers.

WebDAV settings are Preferences-backed local settings. URL, username, enable switch, and password form one
credential group: they are excluded from plaintext backup, may travel only inside an encrypted backup, and
must restore atomically. The group never appears in sync envelopes or logs.

## Huawei Cloud Provider

Huawei Cloud sync reuses the same dataset switches as WebDAV:

- read progress -> `gallery_read_progress`
- browsing history -> `viewed_history`
- local favorites -> `local_favorites`
- search history -> `search_history`
- local hidden-tag/comment-filter settings -> `local_block_settings`, `local_block_rules`
- image block user rules -> `image_block_user_rules`
- custom list tabs -> `custom_profiles`, `custom_profile_selection`

`HUAWEI_CLOUD_SYNC_BUILD_ENABLED` defaults to true so local development can actually see and test the
provider. Public release builds that do not configure the matching AGC/HGC cloud schema can run
`NEXTE_HUAWEI_CLOUD_SYNC=0 scripts/build_hvigor_signed.sh`; the build script temporarily flips the flag for
that build and restores the source file afterward.

The cloud schema must include only syncable durable user tables. Cache tables, generated tag-translation data,
download queues, diagnostics, cookie jars, API keys, and WebDAV credentials stay local-only. Every synced table
column is nullable because RDB cloud sync rejects NOT NULL cloud fields.

Historical image-block Huawei Cloud debugging evidence is archived in
[huawei-cloud-image-block-sync-debug-ledger.md](../archive/huawei-cloud-image-block-sync-debug-ledger.md).
Treat it as past evidence only; current AGC schema and device behavior must be verified live before changing
`image_block_user_rules` sync behavior.

Earlier Huawei Cloud schema/data state was not accepted. Verification on 2026-07-01 showed:

- `tables[].name = snake_case local table` is required for `setDistributedTables`; changing table names to
  AGC record types such as `GalleryReadProgress` makes local distributed-table creation fail with
  `Analysis sql and trigger failed -1003` because those PascalCase local RDB tables do not exist.
- `tables[].alias = PascalCase AGC data type` can route CloudKit requests to the PascalCase record type,
  but it does not make dirty or hand-created cloud records safe. After the AGC data type was handled and
  the record debugging page was queried again, `ImageBlockUserRules` still had 13 current records. The
  197 device fetched `normal: 13, deleted: 39` and failed with
  `Invalid data from cloud, no version[0], lost primary key[1]`,
  `Cloud data do not contain expected primary field value`, and
  `image_block_user_rules:up=0/0,down=0/52,fail=52`.
- The visible fields were `deleted_at`, `enabled`, `feed_id`, `hash`, `label`, `preview_path`, `rule_id`,
  `scope`, `scope_key`, `source_page`, `source_type`, `source_url`, `threshold`, and `updated_at`.

Current image-block user-rule target: `image_block_user_rules` keeps its local RDB table name and points its
cloud schema alias to the current AGC development data type `ImageBlockUserRules`. The temporary
`ImageBlockUserRulesV2` development reset is retired. AGC reports it as production-effective and refuses
deletion, so it must stay unused; the client must not reference it again. Do not rename the client to another
versioned image-block data type.
The `ImageBlockUserRules` AGC development config currently sets the device duplicate key to
`rule_id,scope_key`; the local `image_block_user_rules` physical RDB table, cloud schema, and every
`ON CONFLICT` target for that table must use the same order. The app can still canonicalize user-created
rule IDs to `local:<hash>` or `allow:<hash>`; that identity choice must not be confused with the RDB/cloud
primary-key column order. The source metadata fields `source_url`,
`source_page`, and `preview_path` still stay before `enabled`, `updated_at`, and `deleted_at`.
The AGC record-debug table may display fields alphabetically, but the device cloud mapper and RDB insert
path are sensitive to the deployed order. Moving the numeric state fields before the source fields corrupts
rows, for example `source_url=1`, `enabled=https://...`, and `deleted_at=/data/storage/...`, then the next
upload fails with `Code:400 reason:Param is invalid`.
If AGC already contains such shifted rows, another device fails before app-level merge with
`image_block_user_rules:up=0/0,down=0/13,fail=13`; those cloud records must be deleted or repaired in AGC
before a device can upload clean rows again. Do not hide that condition behind app-side prepare repair.

Do not add a new `CustomProfilesV2`, `ImageBlockUserRulesV3`, or other versioned AGC data type as a routine
repair for local/cloud metadata drift. Versioned AGC data types are a last-resort development reset tactic,
not a normal app feature. If a device already has local RDB cloud metadata pointing at records that were
deleted directly in AGC, fix that as an explicit maintenance/reset case and keep ordinary sync on the
current AGC data type.
The local `cloud_schema.json` top-level `version` and database `version` must match the AGC/CloudDrive
effective schema version seen in device logs. Version 18 adds the complete viewed-history list snapshot;
it must not be device-tested against an AGC environment that still reports version 17. The earlier attempt
to set the local cloud schema to 20 while CloudDrive still fetched schema 17 produced
`can not find schema record type:ImageBlockUserRules`. Local RDB schema version is separate and is 24.
Earlier 17/V2 and 18/V2 builds could leave devices in a state where other tables synced but image-block user
rule downloads failed against the versioned data type; the canonical `ImageBlockUserRules` schema keeps the
AGC device duplicate-key order and keeps client rule identity canonicalization inside the row values.
Manual Huawei Cloud sync waits 240 seconds
because the first clean development-environment upload can include hundreds of durable rows;
197 needed about 126 seconds before CloudDrive returned the table-level finish callback, so the old 120-second
guard hid the real table details behind a premature timeout.

Image-block cloud touch markers are retired. The app no longer stores
`image_block_user_rules_cloud_touch_*`, no longer bulk-updates `updated_at` to manufacture dirty rows, and
no longer marks a separate image-rule upload completion state. That app-managed touch layer created a second
dirty-state system beside HarmonyOS RDB cloud sync and made duplicate cloud records harder to reason about.

Earlier 197 QA evidence on 2026-07-02: after enabling Huawei Cloud sync in app settings,
`image_block_user_rules` ran but reported `up=2/13,down=0/0,fail=11`; native logs showed
`modifyNormalRecords ImageBlockUserRulesV2 count: 13 success:2,fail:11` followed by
`Code:400 reason:Param is invalid`. Pulling the device DB showed rows corrupted by the field-order mismatch
above, while AGC data-record debugging for `ImageBlockUserRulesV2` showed the cloud records themselves still
had the correct named fields. A later attempt that moved local/cloud order to `enabled`, `updated_at`,
`deleted_at` before source fields reproduced the same local corruption before upload: CloudDrive then logged
`saveRecordsExPrepare ImageBlockUserRulesV2 count: 11 normal:11,recycle:0,new:0,modify:11,dbType:1` and
`modifyNormalRecords ImageBlockUserRulesV2 count: 11 success:0,fail:11` without downloading cloud changes.
The fix is to keep `cloud_schema.json`, the local RDB physical table, and all user-rule conflict targets on
the AGC device duplicate-key order. Affected development-device or AGC rows still need restoring or explicit
out-of-band repair before re-testing because already-corrupted row values are not fully reversible after the
cloud-touch update.

Normal Huawei Cloud sync uses the same two roles for every selected table. The provider-neutral app
scheduler coalesces durable local writes and foreground events into a `SYNC_MODE_TIME_FIRST` run, which
reliably uploads local RDB mutations. The RDB `autoSync: true` setting on the same selected subset receives
system cloud deliveries, while `SUBSCRIBE_TYPE_CLOUD_DETAILS` refreshes selected application state after the
system applies a cloud change. The service retains the listener-owning `RdbStore` handle for the process
lifetime; a function-local handle can stop delivering callbacks after startup. Deselected tables use
`autoSync: false`, and manual sync passes the same
selected table subset to the same sync mode. History has no separate provider path, mode, timer, snapshot,
or correction loop. Disabling Huawei Cloud disables native automatic sync and stops scheduled provider runs.
Backup restore pauses both the app scheduler and native automatic sync before durable rows are replaced,
then restores both from the current provider and dataset selection after the transaction.

No dataset may add a cloud-first snapshot, shadow table, second dirty-state tracker, or app-managed repair
loop to override HarmonyOS cloud ownership. No image-block first-upload exception remains.
The app must not run cleanDirtyData for `image_block_user_rules`, must not run native-first for that table, and must not hide
AGC-development-environment repair behind ordinary sync. If AGC contains duplicate or malformed development
records, fix the development data directly or through a separately reviewed maintenance tool.

Do not set both `name` and `alias` to snake_case: device logs showed CloudKit then requesting
`/kinds/custom_profile_selection/record`, which does not match the existing AGC data type and returns
`kind is Invalid`.

Manual and scheduled Huawei Cloud runs call `cloudSync(mode, tables, progress)` with the current selected
table subset after `setDistributedTables`. Native automatic sync is configured by first applying
`autoSync: false` to the complete durable cloud-table set and then applying `autoSync: true` to the selected
subset. `setDistributedTables` does not provide an API to unmark tables that older builds already marked;
constraining explicit runs and the automatic subset keeps stale historical distributed-table metadata, such as the removed
`image_block_subscriptions` cloud mapping, out of current work.

## WebDAV File Layout

WebDAV sync stores files under the configured directory:

```text
nexte-sync-v1/
  manifest.json
  datasets/
    read-progress/00.json ... 3f.json
    viewed-history/00.json ... 3f.json
    local-favorites/00.json ... 3f.json
    search-history/00.json ... 3f.json
    local-block/00.json ... 3f.json
    image-block/00.json ... 3f.json
    custom-profiles/00.json ... 3f.json
```

`manifest.json` is metadata only. It records `magic`, `appId`, `schemaVersion`,
`minSupportedSchemaVersion`, `generatedAt`, and one entry per dataset. Each dataset entry lists shard
metadata: `id`, `path`, `updatedAt`, `recordCount`, and `sha256`. It must not contain the full user data
arrays.

Shards are stable hash buckets, not position slices. The bucket key is the dataset primary key:

- read progress: `scope_key + gid`
- viewed history: `scope_key + gid`
- local favorites: `scope_key + gid`
- search history: `scope_key + query_text`
- local block: `scope_key` for settings and `scope_key + rule_id` for rules
- image block: `scope_key + feed_id` for subscriptions and `scope_key + rule_id` for rules
- custom profiles: `scope_key + uuid` for profile records and `scope_key` for selection.
  The app/export model keeps the semantic field name `uuid`, but the local RDB and AGC cloud table
  store it as `profile_uuid` because `uuid` is an AGC reserved field name.

The current WebDAV provider uses 64 buckets (`00` through `3f`). A single record update or tombstone
therefore changes only its stable bucket shard, not every later record.

Each shard file is a normal partial sync envelope containing only records from one dataset/bucket. The
provider compares each local shard's `sha256` and metadata with the manifest before downloading data:
matching shards stay local and are not GET again, while missing or changed shards are downloaded and
merged. The provider then PUTs only changed shards from the merged result. `manifest.json` is small and may be PUT after
sync.
Shard metadata must be stable too: per-shard `generatedAt` is derived from the newest record timestamp
inside that shard, not from wall-clock sync time, so unchanged user data does not upload again on every
manual sync. Read-progress records are also rebuilt in a fixed field order before hashing, so older
shards created before the optional `columnMode` field do not remain permanent false-positive changes.

Manual and scheduled WebDAV entry points share one process-wide single-flight keyed by normalized sync
root plus username. A second request for the same account/root joins the active promise instead of starting
another manifest/shard lane. Directory setup accepts WebDAV `405 Method Not Allowed` as the normal
"collection already exists" result and does not retry it.

When the WebDAV server returns an `ETag` for `manifest.json`, the provider replaces that manifest with
`If-Match`; a first manifest uses `If-None-Match: *`. A `409`/`412` precondition conflict re-reads,
merges, and retries the sync round up to three times, preventing one concurrent writer from silently
replacing another writer's manifest entry. Servers that do not return an `ETag` keep the compatible
unconditional replacement path and emit a diagnostic warning; they cannot provide this optimistic
concurrency guarantee.

The WebDAV provider must not write a single all-data `nexte-sync-v1.json` as the product format. That
file is legacy/transition input only: request it only when `manifest.json` is missing, import it once when
present, and then write the sharded layout. Once a manifest exists, it is authoritative and normal sync
does not probe the legacy path. Do not delete the legacy file during sync; leave cleanup to a later explicit
migration action.

## Dataset Selection

Manual WebDAV sync supports selection for the durable data groups:

- reading progress (`gallery_read_progress`)
- browsing history (`viewed_history`)
- local favorites (`local_favorites`)
- search history (`search_history`)
- block rules (`local_block_settings`, `local_block_rules`, `image_block_subscriptions`, `image_block_user_rules`)
- custom list tabs (`custom_profiles`, `custom_profile_selection`)

All groups default to enabled. A disabled group must not be exported from the current device, must not be
applied to the current device, and must not be erased from WebDAV. The provider simply skips MKCOL/GET/
merge/PUT for disabled dataset files and leaves the manifest entry untouched.

## Merge Rules

- Read progress: newer `updated_at` or tombstone wins per `(scope_key, gid)`.
- Viewed history: newer `viewed_at` or tombstone wins per `(scope_key, gid)`.
- Local favorites: newer `last_view_time` or tombstone wins per `(scope_key, gid)`.
- Search history: newer `updated_at` or tombstone wins per `(scope_key, query_text)`.
- Local block settings: newer `updated_at` or tombstone wins per `scope_key`.
- Local block rules: newer `updated_at` or tombstone wins per `(scope_key, rule_id)`.
- Image block subscriptions: newer `updated_at` or tombstone wins per `(scope_key, feed_id)`.
- Image block rules: newer `updated_at` or tombstone wins per `(rule_id, scope_key)` for non-subscription
  rules. Subscription feeds sync as feed metadata; their rule bodies are downloaded from the feed.
- Custom profiles: newer `last_edit_time` or tombstone wins per semantic `(scope_key, uuid)`;
  the physical RDB/AGC key column is `(scope_key, profile_uuid)`.
- Custom profile selection: newer `updated_at` or tombstone wins per `scope_key`.

Search and profile order are carried by `position_index` from the winning record.
