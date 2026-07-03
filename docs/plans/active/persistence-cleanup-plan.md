# Persistence Cleanup Plan

Status: active plan.

Goal: make NextE persistence boring and predictable. Each datum should have one owner, one storage class,
one backup rule, and one sync rule. Import/export, WebDAV sync, Huawei Cloud sync, and app startup restore
must stop re-classifying the same data differently.

## Target Model

### Preferences

Small durable user choices only.

Examples:

- Theme, language, layout, gallery title mode, reader settings, download settings.
- Sync configuration switches and endpoint/user names.
- Feature switches such as tag translation, comment translation, and image block enablement.

Backup rule: plaintext backup if non-secret; encrypted backup if the key is secret.

Sync rule: do not cloud-sync Preferences as a blob. Sync only explicit durable datasets.

### Secrets

Credential-like values that are user configuration but not safe in plaintext.

Examples:

- EH cookie jar and saved account bundles.
- WebDAV password.
- Comment translation API key.
- Archiver bot API key.

Backup rule: encrypted backup only.

Sync rule: never WebDAV/Huawei Cloud sync through durable datasets.

### RDB Durable Data

Growing or record-shaped user data.

Current durable datasets:

- `gallery_read_progress`
- `viewed_history`
- `local_favorites`
- `search_history`
- `local_block_settings`
- `local_block_rules`
- `image_block_user_rules`
- `custom_profiles`
- `custom_profile_selection`

Backup rule: `localData` section only, with explicit typed records.

Sync rule: dataset-level WebDAV/Huawei Cloud sync only.

### Runtime State

Transient status derived from recent app activity.

Examples:

- Sync last run time/status/detail.
- Huawei Cloud last run time/status/detail and cloud-disabled marker.
- Last background timestamp.
- Safe-mode unlocked marker.
- Cached archiver bot balance and balance update time.

Backup rule: never export; ignore if present in old backups.

Sync rule: never sync.

### Cache And Files

Disposable or large payloads.

Examples:

- Page cache, image cache, thumbnail crops, comment translation cache, tag translation cache.
- Downloaded galleries and exported backup files.
- Image-block preview images.

Backup rule: never export in app-data backup.

Sync rule: never sync as durable user data.

## Migration Phases

### Phase 0: Backup Boundary Cleanup

Status: complete.

Scope:

- Exclude runtime state from Preferences backup and restore.
- Keep WebDAV password as encrypted-backup-only, not syncable.
- Document the current boundary in `docs/plans/active/intake/persistence.md`.

Acceptance:

- `node scripts/test_settings_backup_contract.mjs`
- `node scripts/test_v1_decorator_inventory_contract.mjs`
- `git diff --check`
- Emulator validation is not required for this pure backup-boundary slice unless the Storage UI changes.

### Phase 1: Import Preview And Diagnostics

Status: main path implemented; source contract covers parse diagnostics; negative-file emulator cases remain.

Goal: importing a backup should be explainable before and after the user confirms.

Scope:

- Show backup created time, version, encrypted/plaintext status, and section counts in the restore confirm dialog.
- Surface parse failure reasons instead of collapsing everything to "invalid backup".
- Keep the UI on the existing Storage page; do not add a new backup page.

Acceptance:

- Contract covers `BackupService.preview()` being used by the import confirmation path.
- Emulator QA covered Storage order, plaintext export through system picker, importing that exported backup,
  restore-preview counts, cancel, and encrypted-export password fields.
- Emulator QA also covered encrypted import password prompt and disabled empty-password submit after the
  password input was changed to a state-bound field.
- Emulator QA covered encrypted import with the correct password and restore-preview counts, including
  encrypted type and sensitive-item count.
- Source contract covers parser code mapping for invalid JSON, oversized file, foreign backup,
  unsupported version, malformed envelope, and bad checksum.
- Remaining emulator QA: invalid JSON, bad checksum, and wrong-password feedback. The system file picker's
  "My phone" storage is not visible through ordinary `hdc shell` paths, so bad files were not injected
  through a test-only app path.

### Phase 2: Restore Safety

Status: service rollback implemented; runtime failure-injection QA remains.

Goal: restore should not leave a half-written app state when a section fails.

Scope:

- Add a minimal rollback snapshot around restore.
- Prefer existing export helpers for the snapshot; do not create a generic transaction framework.
- Report the section that failed.

Acceptance:

- Contract proves restore snapshots Preferences/localData/secrets and rolls them back on failure.
- Preferences rollback replaces the backup scope, including deleting keys introduced by a failed import.
- Emulator QA covers a failed import and a subsequent valid import.

### Phase 3: Dataset Inventory Contract

Status: inventory document and coverage contract implemented.

Goal: every durable dataset has an explicit owner and backup/sync decision.

Scope:

- Add a small inventory document or table covering `StorageKeys` and `LocalDataStore` tables.
- Check that new legacy Preferences blobs are not added for growing local data.
- Check that new RDB tables are classified as durable, cache, or excluded.

Acceptance:

- `node scripts/test_persistence_inventory_contract.mjs`
- A contract fails if a new `StorageKeys` key is not classified.
- A contract fails if a new RDB table is added without a backup/sync/cache classification.

### Phase 4: Remaining Data Moves

Status: legacy fallback audited; keep compatibility migrations, contract now guards backup exclusions.

Goal: remove old Preferences fallback paths only after their RDB owner is proven stable.

Scope:

- Audit legacy keys that are now RDB source of truth.
- Remove or narrow legacy migration code only when old backups and existing installs remain supported.
- Do not migrate downloads into app-data backup unless a separate product decision says downloaded tasks should be portable.

Acceptance:

- Startup restore still works on fresh install and upgraded install.
- Backup/restore round trip keeps the supported durable datasets.
- WebDAV/Huawei Cloud sync uses the same durable dataset set as backup unless explicitly excluded.
- Legacy Preferences blobs for RDB-owned data stay excluded from Preferences backup and migrate through
  `BackupLocalDataAdapter.restoreLegacyPreferences()` only for supported local-data sections.
- Download queue legacy data remains excluded from app-data backup.

## Non-Goals

- No broad rewrite of `LocalDataStore`.
- No generic persistence framework.
- No Preferences descriptor system unless repeated classification checks become painful.
- No syncing caches or downloaded image payloads.
- No backup of image-block preview images.

## Current Next Action

Run Phase 4 gates for the legacy-boundary contract slice.

## Emulator Validation

Use emulator validation for every user-visible import/export change.

Minimum emulator path:

1. Open Storage settings.
2. Export plaintext backup through the system picker.
3. Import that backup and confirm the preview counts match expected sections.
4. Import an encrypted backup and verify password prompt + wrong-password feedback.
5. Try an invalid file and verify the error reason is visible enough to diagnose.
6. After successful restore, revisit at least one restored setting and one restored local-data surface.

Static contracts can prove boundaries; emulator QA proves the user path.
