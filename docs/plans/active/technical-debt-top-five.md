# Technical-Debt Top Five

Status: active. This is the fixed scope for the current cleanup pass.

Rule: do not start another debt item until these five are complete or the user reprioritizes them.

| # | Priority | Item | Status | Commit / boundary |
| --- | --- | --- | --- | --- |
| 1 | P0 | A plaintext backup must not combine restored WebDAV URL, account, or enabled state with an old local password. | complete | `910fd461` |
| 2 | P1 | A backup missing `localData` must not clear history, progress, favorites, or search data. | complete | `6102126f` |
| 3 | P1 | Restoring viewed history and reading progress must preserve logical sync clocks so future records and tombstones do not resurrect. | complete | `0ac44b68`, `da50c3f7` |
| 4 | P1 | Custom-home profile content must converge across devices; reorder, visibility, and display-mode changes must not lose to stale state. | in progress | `bd6f57f8` fixes only profile selection, not profile content. |
| 5 | P2 | Download-queue startup must not issue one SQL query per recovered task. | complete | `7e1c79ff` |

## Current work

Only item 4 remains. Keep its sync timestamp separate from the UI/cache reload version, migrate existing
records safely, and validate the affected custom-home flows on Mate X7 before calling it complete.

## Explicit non-scope

Reader stale-session handling, image-block sync, schema DDL, WebDAV concurrent-write protocol, and
multi-table backup atomicity are not part of this five-item pass. They require a separately approved priority.
