# Technical-Debt Top Five

Status: active. This is the fixed scope for the current cleanup pass.

Rule: do not start another debt item until these five are complete or the user reprioritizes them.

| # | Priority | Item | Status | Commit / boundary |
| --- | --- | --- | --- | --- |
| 1 | P0 | A plaintext backup must not combine restored WebDAV URL, account, or enabled state with an old local password. | complete | `910fd461` |
| 2 | P1 | A backup missing `localData` must not clear history, progress, favorites, or search data. | complete | `6102126f` |
| 3 | P1 | Restoring viewed history and reading progress must preserve logical sync clocks so future records and tombstones do not resurrect. | complete | `0ac44b68`, `da50c3f7` |
| 4 | P1 | Custom-home profile content must converge across devices; reorder, visibility, and display-mode changes must not lose to stale state. | code complete / pending two-device acceptance | `bd6f57f8` selection; `621e5150` profile-row LWW and request revision separation. |
| 5 | P2 | Download-queue startup must not issue one SQL query per recovered task. | complete | `7e1c79ff` |

## Current work

All five implementation items are committed. Item 4 keeps `last_edit_time` as the existing profile-row
LWW clock and derives a separate request revision for UI/cache behavior, so it does not require an AGC
schema change. The Mate X7 Hypium suite passed 78/78; a future real two-device or configured WebDAV round
trip is acceptance evidence, not authorization to start a sixth debt item.

## Explicit non-scope

Reader stale-session handling, image-block sync, schema DDL, WebDAV concurrent-write protocol, and
multi-table backup atomicity are not part of this five-item pass. They require a separately approved priority.
