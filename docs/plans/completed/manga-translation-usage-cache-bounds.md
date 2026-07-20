# Manga Translation Usage Cache Bounds

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Keep a corrupted local Codex usage snapshot from causing an oversized JSON parse or carrying unsafe text and numeric
values into the compact quota row.

## Grounding

- Remote usage responses are capped at 512 KiB, but the persisted cache was parsed without a local record bound.
- A valid cache contains one account, one short plan name, four small windows, and is normally below 1 KiB.
- Cached timestamps and window values accepted any finite number, including values outside JavaScript's safe integer
  range.

## Completion

- Limit serialized and restored usage cache records to 16 KiB before JSON parsing.
- Limit account IDs to 160 characters and plan names to 64 characters with no control characters.
- Normalize cached windows and reject unsafe timestamps before persistence and display.
- Cover oversized records and unsafe numeric values with pure cache tests.
- Pass the full 237 device suite, signed build, V2 inventory, and static checks.

## Validation

- `entry@ohosTest` HAP build: successful in 13.279 s.
- Full Hypium suite on `192.168.50.237:12345`: 166 passed, 0 failures/errors/ignored, 907 ms.
- Signed application build: successful in 15.692 s.
- V1 decorator inventory: 0 files across 459 ArkTS files.
- Version/module consistency, locale parity/duplicate scan, and `git diff --check`: passed.
