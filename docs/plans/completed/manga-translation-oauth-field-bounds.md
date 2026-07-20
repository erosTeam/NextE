# Manga Translation OAuth Field Bounds

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Keep a body-size-valid experimental Codex OAuth response or corrupted local token record from creating oversized
request headers, Preferences values, reactive account state, or invalid polling behavior.

## Grounding

- OAuth response bodies are capped at 512 KiB, but individual fields were previously only checked for non-emptiness.
- Device sessions are public model objects, so manually assembled intervals and identifiers can reach polling.
- Local token JSON was parsed before any record or token-field size check.
- A very large polling interval can overflow platform timer behavior instead of simply waiting longer.

## Completion

- Bound user code, device authorization ID, authorization code, verifier, token, and account ID fields.
- Clamp provider polling intervals to 3–60 seconds and reject invalid public session objects.
- Bound local token JSON before parsing and validate token sets before persistence or reuse.
- Cover normal and oversized fields with fake-transport and pure token-record tests.
- Pass the full 237 device suite, signed build, V2 inventory, and static checks.

## Validation

- The first test build exposed one nullable raw interval access; an explicit null-safe local fixed it without changing
  the protocol boundary.
- Final `entry@ohosTest` HAP build: successful in 8.411 s.
- Full Hypium suite on `192.168.50.237:12345`: 165 passed, 0 failures/errors/ignored, 894 ms.
- Signed application build: successful in 14.226 s.
- V1 decorator inventory: 0 files across 459 ArkTS files.
- Version/module consistency, locale parity/duplicate scan, and `git diff --check`: passed.
