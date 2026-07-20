# Manga Translation Cache Identifier Preflight

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Reject non-canonical identity and code fields while decoding generated comic translation cache documents,
without rewriting user-visible text.

## Grounding

- The request/cache identity contract already requires exact project and image-profile identifiers.
- Provider parsing trims block, speaker, signal-code, and signal-target identifiers before persistence.
- The persisted codec currently checks only non-empty values and lengths, so a damaged payload can retain
  leading or trailing whitespace in those fields.
- Source text, translation text, summaries, style hints, and diagnostic messages are free text and may contain
  meaningful whitespace; this phase must preserve them exactly.

## Completion

- Exact project/profile/block/speaker/signal/error-code identifiers are required during cache decode.
- Free text retains its original spelling and whitespace.
- Codec tests, full device suite on 237, signed build, V2 inventory, and relevant static checks pass.

## Result

- Cache decoding now rejects leading or trailing whitespace in project, image-profile, block, speaker,
  quality-signal, signal-target, and diagnostic-code identifiers.
- Source/translation text, page summaries, and signal messages retain their original whitespace.
- Test HAP build: successful in 13.995 seconds.
- Full `entry_test` suite on `237`: 159 tests, 0 failures, 0 errors, 159 passes in 858 ms.
- `scripts/build_hvigor_signed.sh`: successful in 15.473 seconds.
- V2 inventory: 0 live V1 files across 459 ETS files; version consistency, i18n parity, and `git diff --check`
  also passed.
