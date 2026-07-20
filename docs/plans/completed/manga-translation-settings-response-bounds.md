# Manga Translation Settings Response Bounds

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Bound model-catalog, Codex-usage, and experimental OAuth responses while the default Axios transport receives
them, with service-level guards retained for custom transports.

## Grounding

- Model catalogs already reject parsed bodies over 2 MiB.
- Codex usage already rejects parsed bodies over 512 KiB.
- Experimental OAuth responses are small JSON documents but currently have no explicit body bound.
- All three default transports use generic text requests without `maxContentLength`.

## Completion

- Default model-catalog responses are capped at 2 MiB.
- Default Codex-usage and OAuth responses are capped at 512 KiB.
- OAuth checks every returned body before status handling or JSON parsing.
- Parser/custom-transport tests, full device suite on 237, signed build, V2 inventory, and static checks pass.

## Validation

- `entry@ohosTest` HAP build: successful in 13.116 s.
- Full Hypium suite on `192.168.50.237:12345`: 162 passed, 0 failures/errors/ignored, 906 ms.
- Signed application build: successful in 13.854 s.
- V1 decorator inventory: 0 files across 459 ArkTS files.
- Version/module consistency, locale parity/duplicate scan, and `git diff --check`: passed.
