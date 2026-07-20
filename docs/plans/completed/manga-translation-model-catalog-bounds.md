# Manga Translation Model Catalog Bounds

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Keep a body-size-valid provider model catalog from creating an unbounded settings menu or carrying malformed model
identifiers into persisted provider selection and translation request identity.

## Grounding

- Model catalog response bodies are capped at 2 MiB, but a compact JSON array can still contain many thousands of
  entries.
- The settings page retains every parsed unique entry and builds one menu item per model.
- Catalog parsers access entry fields directly, so a JSON `null` entry can fail before normal filtering.
- Translation request identities already cap model identifiers at 160 characters.

## Completion

- Reject provider catalogs containing more than 512 source entries.
- Ignore null, empty, control-character, or over-160-character model identifiers while preserving valid entries.
- Cover public API and Codex catalog behavior with parser tests.
- Pass the full 237 device suite, signed build, V2 inventory, and static checks.

## Validation

- `entry@ohosTest` HAP build: successful in 12.745 s.
- Full Hypium suite on `192.168.50.237:12345`: 163 passed, 0 failures/errors/ignored, 904 ms.
- Signed application build: successful in 13.984 s.
- V1 decorator inventory: 0 files across 459 ArkTS files.
- Version/module consistency, locale parity/duplicate scan, and `git diff --check`: passed.
