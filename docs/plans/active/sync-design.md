# NextE Sync Design

Status: active implementation note.

## Scope

This lane implements the provider-neutral sync spine plus a manual WebDAV provider. Huawei cloud sync is
intentionally excluded until the syncable RDB schema and write semantics are stable enough to mirror in AGC.

## Syncable Data

Sync only durable user-local records with stable keys and timestamps:

- `gallery_read_progress`
- `viewed_history`
- `local_favorites`
- `search_history`
- `local_block_settings`
- `local_block_rules`
- `custom_profiles`
- `custom_profile_selection`

Do not sync disposable cache, generated/downloadable databases, device-local download state, diagnostics,
or plaintext secrets/provider credentials:

- `tag_translations`, `tag_translation_meta`
- `eh_page_cache`, `comment_translation_cache`
- `download_gallery_tasks`, `download_gallery_seeds`
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
- Huawei cloud sync, when enabled later by a private build/profile, marks the same syncable tables

Conflict resolution belongs to the sync dataset adapter, not providers.

WebDAV settings are Preferences-backed local settings. The URL and username are configuration; the password is
a local-only credential and must not appear in backup export, sync envelopes, or logs.

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
- custom profiles: `scope_key + uuid` for profiles and `scope_key` for selection

The current WebDAV provider uses 64 buckets (`00` through `3f`). A single record update or tombstone
therefore changes only its stable bucket shard, not every later record.

Each shard file is a normal partial sync envelope containing only records from one dataset/bucket. The
provider compares each shard's `sha256` with the manifest and PUTs only changed shards. `manifest.json`
is small and may be PUT after sync.
Shard metadata must be stable too: per-shard `generatedAt` is derived from the newest record timestamp
inside that shard, not from wall-clock sync time, so unchanged user data does not upload again on every
manual sync.

The WebDAV provider must not write a single all-data `nexte-sync-v1.json` as the product format. That
file is legacy/transition input only: if it exists and the manifest is empty, import it once and then
write the sharded layout. Do not delete the legacy file during sync; leave cleanup to a later explicit
migration action.

## Dataset Selection

Manual WebDAV sync exposes user-facing switches for the durable data groups:

- reading progress (`gallery_read_progress`)
- browsing history (`viewed_history`)
- local favorites (`local_favorites`)
- search history (`search_history`)
- local hidden-tag/comment-filter settings (`local_block_settings`, `local_block_rules`)
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
- Custom profiles: newer `last_edit_time` or tombstone wins per `(scope_key, uuid)`.
- Custom profile selection: newer `updated_at` or tombstone wins per `scope_key`.

Search and profile order are carried by `position_index` from the winning record.
