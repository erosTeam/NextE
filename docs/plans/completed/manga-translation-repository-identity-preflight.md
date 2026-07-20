# Manga Translation Repository Identity Preflight

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Reject manually constructed invalid comic translation request identities before cache-key generation, memory
mutation, document encoding, or RDB access.

## Grounding

- `ComicTranslationRequestIdentity.from` validates normal orchestrator requests.
- The identity class and repository implementations are exported, while tests and future callers can construct
  identities directly.
- Repository methods currently rely on the factory invariant and do not assert it at their own public boundary.
- The existing exact, previous-page, and persistent-cache semantics remain unchanged.

## Completion

- Cache and scope keys cannot be produced from an invalid identity.
- Memory and RDB repository entrypoints reject invalid identities before work.
- Direct identity tests, full device suite on 237, signed build, V2 inventory, and relevant static checks pass.

## Result

- `ComicTranslationRequestIdentity.assertValid` is now public and guards both cache/scope-key generation and
  every exported in-memory/RDB repository identity entrypoint.
- Cache-key construction uses a private unchecked scope serializer only after the full identity has passed.
- Test HAP build: successful in 14.320 seconds.
- Full `entry_test` suite on `237`: 160 tests, 0 failures, 0 errors, 160 passes in 837 ms.
- `scripts/build_hvigor_signed.sh`: successful in 15.374 seconds.
- V2 inventory: 0 live V1 files across 459 ETS files; version consistency, i18n parity, and `git diff --check`
  also passed.
