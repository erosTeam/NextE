# Persistence And Backup Intake

Status: domain intake ledger.

Purpose:

- Track NextE's durable local-data, settings-backup, and import/export design gaps separately from
  disposable cache work.
- Do not use this file directly as the scheduling source of truth; start from
  `../current-dispatch-state.md`.
- Persistence work must define which data is a small preference, which data belongs in RDB, which data is a
  file/cache payload, and which data is secret or account-scoped before implementation.

## Items

### Durable Local Data And Settings Import/Export Are Not Yet Designed

Type: architecture gap / FE parity gap / data safety

Priority suggestion: P1

Status: accepted / needs design and implementation

Source:

- User feedback, 2026-06-22: beyond cache, it is unclear whether NextE's persistence design is reasonable.
  Settings export/import is also a visible feature gap and should not keep disappearing behind small QA loops.
- Existing roadmap and architecture already name the intended target, but the code has not caught up:
  `docs/roadmap.md` lists `shared/storage: LocalDataStore RDB + HistoryRepository/ReadProgressRepository`,
  and `docs/architecture.md` separates `settings`, `cache`, and `storage`.

Current NextE evidence:

- Small scalar settings generally use `preferences.getPreferences(... StorageKeys.STORE_SETTINGS)` and mirror
  into AppStorageV2 through `SettingsBootstrap`.
- Search history is stored as a JSON array in Preferences by
  `shared/src/main/ets/settings/SearchHistorySettings.ets`, capped at 100.
- Viewed history is stored as a JSON list in Preferences by
  `shared/src/main/ets/settings/ViewedHistorySettings.ets`, capped at 200. Its code comment explicitly notes
  that `eros_fe` history is DB-backed and that the cap exists only because NextE currently uses a Preferences
  blob.
- Reader progress is stored as a Preferences JSON array by
  `shared/src/main/ets/settings/GalleryReadProgressSettings.ets`, with a 3s debounce and flush-on-close.
- Local favorites are stored as a Preferences JSON snapshot by
  `shared/src/main/ets/settings/LocalFavSettings.ets`.
- There is no user-visible settings backup/import/export workflow in NextE today, aside from the separate
  manual Cookie import flow. There is also no single backup envelope, schema version, category preview,
  rollback, or secret-denylist contract for general app data.

Reference evidence:

- `../V2Next/shared/src/main/ets/storage/LocalDataStore.ets` uses HarmonyOS `relationalStore` for durable
  local tables and schema migration. It separates search history, cache entries, collection/read state,
  overlays, user marks, and a synced key-value fallback table.
- `../V2Next/shared/src/main/ets/settings/SearchSettings.ets` stores search history in RDB, prunes by SQL,
  removes legacy Preferences history, and requests cloud sync after local writes.
- `../V2Next/shared/src/main/ets/settings/SettingsStorage.ets` and
  `../V2Next/shared/src/main/ets/settings/SettingsDescriptor.ets` keep small preferences as a separate,
  descriptor-driven path.
- `../V2Next/shared/src/main/ets/backup/BackupService.ets` builds a versioned backup envelope, previews and
  validates imports, snapshots rollback state before restore, and separates plaintext sections from encrypted
  user-info sections.
- `../V2Next/shared/src/main/ets/backup/BackupPreferencesAdapter.ets` exports the unified settings store while
  rehydrating live settings on restore, and `BackupSecretDenylist.ets` prevents credential-like keys from
  entering plaintext backups.
- `../eros_fe/lib/pages/setting/advanced_setting_page.dart` exposes Advanced maintenance rows for clear cache,
  WebDAV connection count, app data export, and app data import. `../eros_fe/lib/utils/import_export.dart`
  exports app profile data after replacing the user with `kDefUser`, and imports while preserving current
  user/download-location safety values. This is useful product grounding, but NextE should prefer the safer
  V2Next backup-envelope/denylist/rollback shape over a direct profile dump.

Expected direction:

- Define a persistence taxonomy before writing more stores:
  - Preferences: small scalar settings and simple UI choices only.
  - RDB: search history, viewed history, read progress, QuickSearch, local favorites, tag translation index,
    user tag/local overlay data, and future syncable records.
  - Files/cache: image bytes, HTML snapshots, resolved image metadata payloads, downloads, and exported files.
  - Secrets: cookies, `ipb_pass_hash`, `igneous`, tokens, proxy passwords, and account credentials. These must
    be excluded from plaintext export unless a separate explicit encrypted flow is designed.
- Add or design a `LocalDataStore` equivalent before moving more growing data into Preferences JSON blobs.
  The first slice can migrate one high-value table, but the schema should reserve account/site partitioning
  and future sync metadata where needed.
- Settings export/import should be a real backup workflow, not a raw Preferences dump:
  - versioned envelope with app/schema metadata;
  - category counts and preview before restore;
  - denylist/redaction for secret keys;
  - import validation and rollback snapshot;
  - merge/replace rules per section;
  - `SettingsBootstrap` or equivalent reapply path after restore.
- Cache management and persistence management are related but not identical. Clearing disposable cache must
  not delete history/progress/local favorites/downloads unless the UI explicitly names that destructive
  category and confirms it.
- This lane should also decide where the user-facing rows live: cache clearing and backup/import/export belong
  in a maintenance/advanced settings surface, while secret/account import remains under EH/account settings.

Acceptance shape:

- Produce a short architecture note or design section naming data categories, owners, backends, schema version,
  migration plan, and backup sections.
- Implement the first bounded persistence slice using the chosen backend. Good candidates are search history
  or viewed/read history because current Preferences JSON evidence is clear and the user can feel startup/open
  latency.
- Add deterministic contracts covering:
  - no growing history/progress/local-data table is newly stored as an unbounded Preferences JSON blob;
  - schema creation/migration is idempotent;
  - site/account partitioning is present where user data depends on EH identity;
  - plaintext export excludes cookie/token/password-like keys;
  - import validates schema and restores/reapplies settings without restart where possible.
- If export/import UI is implemented, capture emulator evidence for export category preview, import preview,
  cancel path, success path with non-secret sample data, and secret-denylist behavior.

Non-goals for the first slice:

- Do not build full WebDAV/cloud sync in the first persistence slice.
- Do not migrate every existing setting/history/favorite store in one patch.
- Do not include EH cookies or account credentials in plaintext app-data export.
- Do not treat a cache-clear button as completion of the persistence/backup lane.
