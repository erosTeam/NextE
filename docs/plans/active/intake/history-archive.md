# General Archive Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- Do not use this file directly as the scheduling source of truth; start from `../current-dispatch-state.md`.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Last Selected Sub-Tabs Are Not Persisted

Type: UX optimization / preference persistence

Priority suggestion: P3

Status: parked

Source:

- User feedback, 2026-06-20: after exiting and reopening the app, several high-level sub-tab selections
  reset to their defaults. This affects at least the gallery/home source tab, Favorites favcat selection,
  and Toplist/ranking period.

Observed behavior:

- Retained sub-tab state preserves in-process navigation reasonably well, but app restart returns users
  to default sub-tabs.
- This makes repeated usage feel less personal: users who mostly browse a non-default source/favcat/
  ranking period must reselect it after each restart.

Expected behavior:

- Persist the last user-selected sub-tab per surface:
  - Home/Gallery source selection.
  - Favorites favcat selection, including local/all/remote slot where applicable.
  - Toplist/ranking period selection.
- Restore the persisted value on app startup only when it is still valid for the current account/data.
- If a saved favcat no longer exists, fall back gracefully to all/local/default without showing an error.
- Do not confuse this with retained in-memory tab state; this is cross-launch preference persistence.

Implementation direction:

- Add small settings holders under `shared/settings` or the existing relevant settings modules.
- Persist only stable identifiers (`source`, `favcat`, `toplistPeriod`), not full lists or gallery data.
- Restore after bootstrap/account state is available; for favcat, validate against known slots when the
  remote list arrives and fall back if invalid.
- Keep the scope narrow: no tabbar customization, custom profiles, WebDAV sync, or account migration in
  this lane.

Acceptance shape:

- Select a non-default Home/Gallery source, restart app, and verify the same source is active.
- Select a non-default Favorites favcat, restart app, and verify it is restored when valid.
- Select a non-default Toplist/ranking period, restart app, and verify it is restored.
- If the saved favorite slot is unavailable, the app falls back to a safe default without blanking or
  crashing.
- Deterministic contract covers persistence keys, restore/fallback behavior, and avoids storing gallery
  list payloads as preference state.
