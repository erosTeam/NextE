# Huawei Cloud Image Block Sync Debug Ledger

Updated: 2026-07-02

This document records the actual routes already tried for `image_block_user_rules` Huawei Cloud sync. Use it as the first stop before making another sync change. Do not repeat a route here unless new evidence contradicts the recorded result.

## Current State

- Device under active validation: `192.168.50.200:12345`.
- Installed build verified by `bm dump`: `versionCode=22`, `appProvisionType=debug`, `cloudStructuredDataSyncEnabled=true`.
- The app is signed with a development/debug profile. Treat observed cloud records as records visible to the current development-signed app path, not as a production-app data source.
- Current client cloud schema:
  - `cloud_schema.json` top/database version: `17`.
  - `image_block_user_rules` local table alias: `ImageBlockUserRules`.
  - AGC development config shows `ImageBlockUserRules` local table name `image_block_user_rules`
    and device duplicate key `rule_id,scope_key`.
- Current 200-device failure after the field-order rollback and versionCode 22 install:
  - `SyncProtocol-fetchRecordsWithQuery recordType: ImageBlockUserRules schemaVersion: 17`.
  - CloudDrive fetches `/kinds/ImageBlockUserRules/record`.
  - CloudDrive returns `size: 26`.
  - App table detail: `image_block_user_rules,up=0/0,down=0/26,fail=26`.
  - Other selected tables report `fail=0`.
- The earlier AGC data-record query that showed `无数据` was checked in the wrong environment and is not valid evidence for the debug-signed device path.
- The relevant AGC data-record view shows 26 `ImageBlockUserRules` records, matching the device CloudDrive `size: 26` fetch. The current failure is that all 26 visible development-environment records fail to import on device.
- Browser inspection of the relevant development data-record table found only 14 unique `rule_id` values
  across those 26 records. Twelve rule IDs appear twice, and test records such as `local:qa-duplicate`
  and `local:qa-missing-source` are present. The current failure is therefore a duplicate/dirty
  cloud-record set for the same app-level keys, not missing data.
- Direct sqlite inspection on 200 confirms the local physical table is `PRIMARY KEY(rule_id, scope_key)`.
  The generated `naturalbase_rdb_image_block_user_rules_*` triggers also hash `RULE_ID + SCOPE_KEY`.
- AGC data-record delete removed the visible 26 normal records from the development table, and the AGC
  data-record page now shows `无数据`. This did not clear the sync change feed: the next 200-device sync
  fetched `normal: 0, deleted: 26` tombstones and still failed `down=0/26,fail=26`.
- Code cleanup now treats this as a design failure in the app-managed image-block sync path. The app-side
  `cleanDirtyData`, whole-table `updated_at` touch, native-first image upload, in-process image-table
  suspension, and mutating image-block QA seed routes are retired. Ordinary Huawei Cloud sync must use the
  same system-owned RDB cloud path as the other durable tables.

## Routes Already Tried

### 1. Enable Huawei Cloud Sync In App Settings

Evidence:

- Earlier manual sync failed while the app-level Huawei Cloud setting was not enabled.
- After enabling it, other tables started participating in RDB cloud sync and logs showed scheduled/startup sync.

Conclusion:

- Required baseline, but not sufficient. Do not diagnose `image_block_user_rules` failure as simply "app switch off" again unless logs show `huaweiCloud=false`.

### 2. Startup Prepare Order

Change tried:

- Removed the direct startup `SyncLocalDataAdapter.prepareHuaweiCloudTables(...)` call from `EntryAbility`.
- Startup now relies on `HuaweiCloudSyncService.tryEnableStartup(...)` so distributed tables are marked first.

Evidence from 200 after this change:

- `huawei_cloud_tables_marked | tables=...image_block_user_rules...`
- `huawei_cloud_image_block_clean_dirty | image_block_user_rules`
- `image_block_cloud_touch | userRules=12`
- `image_block_cloud_prepare | legacyMainUser=0,subscriptionDisabled=0,userRules=12`
- Failure still occurred afterward.

Conclusion:

- Startup order was a real cleanup, but it is not the root cause of the current `down=0/26,fail=26` failure.

### 3. HAP Packaging / Cloud Schema Missing

Check performed:

- Inspected the signed HAP and confirmed `resources/rawfile/arkdata/cloud/cloud_schema.json` is present.

Conclusion:

- Do not repeat "HAP did not include cloud_schema" as the primary explanation unless a future build artifact check proves otherwise.

### 4. Device Did Not Install Latest Build

Check performed:

- Installed signed HAP to 200 with `hdc install -r`.
- Verified by `bm dump` that the installed bundle is `versionCode=22`.

Conclusion:

- Current 200 evidence is from the latest installed debug build. Do not treat the current logs as stale-install evidence.

### 5. Cloud Schema Version 20

Change tried:

- Bumped local cloud schema version to `20` while CloudDrive logs still fetched `ImageBlockUserRules` with `schemaVersion: 17`.

Evidence:

- Device logs still showed `schemaVersion: 17`.
- The mismatch produced or preserved `can not find schema record type:ImageBlockUserRules`.

Conclusion:

- Local cloud schema version must match the effective CloudDrive schema version seen in device logs. Current effective version is `17`.

### 6. Cloud Schema Version 17

Change tried:

- Set local cloud schema top/database version back to `17`.

Evidence:

- Device logs fetch `ImageBlockUserRules` with `schemaVersion: 17`.
- Current 200 logs show `ImageBlockUserRules schemaVersion: 17`.
- The table still failed as `down=0/26,fail=26`.

Conclusion:

- Version alignment is necessary, but it did not make the dirty cloud records importable.

### 7. `rule_id, scope_key` Primary-Key Order

Change tried:

- Changed `image_block_user_rules` cloud schema, local RDB physical table, and SQL conflict targets to start with `rule_id, scope_key`.

Evidence:

- This diverged from the original stable table/schema order.
- It also created a migration path where devices that already had schema version `20` could retain old physical state unless the local RDB schema version moved again.
- The current AGC development config uses device duplicate key `rule_id,scope_key`; local RDB/cloud schema
  must stay aligned with that order.

Conclusion:

- Keep local RDB, cloud schema, and AGC device duplicate key aligned as `rule_id,scope_key`.
  Rule IDs may be canonicalized to values like `local:<hash>` and `allow:<hash>`, but that is row
  identity content, not a reason to create versioned data types.

### 8. Removing `image_block_subscriptions` From Huawei Cloud Table Set

Change tried:

- Removed `image_block_subscriptions` from current Huawei Cloud sync table selection and cloud schema.

Evidence:

- Current logs show the active failure is on `ImageBlockUserRules`; `ImageBlockSubscriptions` is not part of the current selected run.

Conclusion:

- This does not explain the current `ImageBlockUserRules down=0/26,fail=26` failure. Do not keep looping on subscription metadata when logs identify user rules.

### 9. AGC Record Debug Query

Check performed:

- Opened AGC cloud sync service, data-record debug page.
- Selected `ImageBlockUserRules`.
- Fields displayed: `deleted_at`, `enabled`, `feed_id`, `hash`, `label`, `preview_path`, `rule_id`, `scope`, `scope_key`, `source_page`, `source_type`, `source_url`, `threshold`, `updated_at`.
- Queried the relevant development/debug environment.

Evidence:

- The relevant AGC data-record view contains 26 `ImageBlockUserRules` records.
- Device CloudDrive also fetched 26 `ImageBlockUserRules` records and failed all 26 downloads.
- The earlier `无数据` observation came from the wrong environment and must not be used as a diagnosis.
- DOM extraction from the AGC data-record table found 26 `local:` / `allow:` rule-id cells but only 14
  unique values. `allow:ce9e181d354a3cd5`, `local:0123456789abcdef`,
  `local:80727a49371e3fd4`, `local:809a7bcb39d7831a`, `local:80d16c0cd5fa9779`,
  `local:b9ab429d2792e193`, `local:bc692e182367cdc6`, `local:c456a93bd5a95dc0`,
  `local:ce9e181d354a3cd5`, `local:e411afc85a25bace`, `local:ebf6489721b09b94`,
  and `local:fd0194e1cde47cb0` each appear twice.

Conclusion:

- AGC-visible development records and the device fetch count now agree. Diagnose the current problem as an import/record-shape failure for those 26 records, not as "no records exist" or "wrong data surface".
- Do not use the production-environment data-record page as evidence for debug-signed device sync.
- The immediate cloud-data problem is duplicate records for the same `(rule_id, scope_key)` app key.
  Cleaning must preserve at most one record per key or delete the whole dirty development table before a
  device re-uploads clean local rows.

### 10. Deleting AGC Records / Resetting Data

Status:

- Visible `ImageBlockUserRules` records were deleted from AGC development data-record debug.
- AGC now shows no visible data for `ImageBlockUserRules`.
- Current 200 sync still fetches 26 deleted tombstones from CloudDrive and fails all 26 downloads.
- The failure after deletion is explicit in system logs:
  `returns size: 26 normal: 0 recycle: 0 deleted: 26`,
  `ParseFromJsonValue parse record failed, can not find schema record type:ImageBlockUserRules`,
  and `Cloud data do not contain expected primary field value`.

Conclusion:

- Do not propose ordinary AGC data-record deletion again. It only hides normal records and leaves deleted
  tombstones in the sync change feed, which this RDB cloud path still cannot consume.
- The only visible AGC operation that claims to clear the remaining development test data is
  "重置开发环境", whose confirmation states it clears all test data and resets development data-type config
  to production. Do not click "实施变更到生产环境".

### 11. Versioned Data Types (`ImageBlockUserRulesV2`, Future V3)

Status:

- V2 existed as a previous reset attempt and caused more confusion.
- The client should use canonical `ImageBlockUserRules`.

Conclusion:

- Do not create V3 or another versioned type as a routine repair. That is table churn, not a diagnosis.

### 12. Narrow First-Upload Native-First Attempt

Change tried and retired:

- If local image-block user rules were touched for upload, sync `image_block_user_rules` alone once with `SYNC_MODE_NATIVE_FIRST` before the normal selected-table `SYNC_MODE_TIME_FIRST` run.

Reason:

- The current failure happens during a full cloud download before clean local rules can upload.
- A table-scoped native-first upload may establish local rows/cursor without broad rebuilding or new AGC data types.

Boundary:

- This is not a broad native-first repair.
- It must not create V2/V3 data types.
- It must not delete cloud records.
- If it fails, the app should isolate `image_block_user_rules` and let the rest of the selected tables sync.

Conclusion:

- Removed from product code. It was another special cloud path for one table and kept the investigation
  away from the simpler model/AGC-data issue. Do not reintroduce it without new device and AGC evidence.

### 13. Mutating Image-Block QA Seed Routes

Evidence:

- AGC development data contains `local:qa-duplicate` and `local:qa-missing-source`.
- Those IDs came from internal `nexte://qa/image-block-*` seed routes that wrote sample rules into the same
  `image_block_user_rules` table used for real sync.

Conclusion:

- Mutating image-block QA routes and the seeded-reader QA script are removed. Keep only no-write QA routes
  that open Reader or settings. Future QA helpers must not write sample image rules into the real user-rule
  sync table.

## Do Not Repeat Without New Evidence

- Do not say the current issue is caused by production data. The app under test is development/debug signed.
- Do not click AGC "实施变更到生产环境".
- Do not create a new versioned data type.
- Do not delete AGC records as the first response.
- Do not re-run schema version 20 against CloudDrive schema 17.
- Do not let AGC device duplicate key order drift away from local RDB/cloud schema order again.
- Do not diagnose startup order as root cause unless fresh logs contradict the recorded startup-order evidence.
- Do not reintroduce image-rule whole-table `updated_at` touch, `cleanDirtyData`, native-first upload, or
  mutating image-block QA seed routes.
- Do not claim "fixed" from static tests alone; require signed build plus 200-device logs.

## Required Evidence For A Real Fix

A fix is not verified until all of these are true on a signed build installed to 200:

- `bm dump` shows the expected new `versionCode`.
- App logs show `huawei_cloud_tables_marked` with the intended table set.
- App logs show `image_block_cloud_prepare` with the local user-rule count.
- CloudDrive logs do not show `can not find schema record type:ImageBlockUserRules`.
- `image_block_user_rules` table detail does not report `fail>0`.
- AGC development data has at most one record per `(rule_id, scope_key)` and contains no `qa-*` sample rows.
