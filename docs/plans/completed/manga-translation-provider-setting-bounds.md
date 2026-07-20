# Manga Translation Provider Setting Bounds

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Keep user-editable comic provider URL, credential, and model fields bounded consistently across ArkUI input,
reactive state, Preferences, catalog requests, and translation request identity.

## Grounding

- The settings input fields previously had no `maxLength`.
- Save and restore only trimmed strings; corrupted Preferences or programmatic snapshots could still populate very
  large state and request-header values.
- Translation request identity already rejects model IDs over 160 characters, but settings allowed them until request
  time.

## Completion

- Limit API base URLs to 2048 characters, API keys to 16 KiB, and API/Codex model IDs to 160 characters.
- Apply the same constants to all four settings text inputs and service normalization.
- Drop non-string, over-limit, or control-character fields before reactive state and persistence.
- Cover valid trimming and invalid-field fallback with a pure settings test.
- Pass the full 237 device suite, signed build, V2 inventory, and static checks.

## Validation

- Offline OpenHarmony SDK declaration confirmed `TextInputAttribute.maxLength(number)` for the UI boundary.
- `entry@ohosTest` HAP build: successful in 13.105 s.
- Full Hypium suite on `192.168.50.237:12345`: 167 passed, 0 failures/errors/ignored, 900 ms.
- Signed application build: successful in 14.627 s.
- V1 decorator inventory: 0 files across 459 ArkTS files.
- Version/module consistency, locale parity/duplicate scan, and `git diff --check`: passed.
