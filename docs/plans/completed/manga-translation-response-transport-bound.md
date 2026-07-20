# Manga Translation Response Transport Bound

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21

## Goal

Enforce the existing 8 MiB comic Responses body limit while Axios is receiving the response, before the
complete body is retained and handed to protocol parsing.

## Grounding

- `ComicResponsesProtocol.extractAssistantJson` already rejects empty or over-8-MiB response strings.
- The default transport currently calls generic `AxiosHttpClient.requestText` without `maxContentLength`, so
  an oversized remote response is fully allocated before the protocol guard runs.
- The bundled HarmonyOS Axios adapter maps `maxContentLength` to the platform HTTP `maxLimit` and also checks
  the completed response length.
- Other text-call sites must retain their current default behavior; only the comic Responses transport opts in.

## Completion

- Generic text requests accept an optional response-byte limit without changing existing callers.
- The default comic Responses transport supplies 8 MiB as that limit.
- The protocol retains its independent size guard for custom transports.
- Test build, full device suite on 237, signed build, V2 inventory, and relevant static checks pass.

## Result

- `AxiosHttpClient.requestText` now accepts an optional `maxResponseBytes`; its default remains unlimited to
  preserve all existing text callers.
- `DefaultComicResponsesHttpTransport` opts into an 8 MiB Axios `maxContentLength`, matching the existing
  `ComicResponsesProtocol` character guard.
- Test HAP build: successful in 14.086 seconds.
- Full `entry_test` suite on `237`: 161 tests, 0 failures, 0 errors, 161 passes in 877 ms.
- `scripts/build_hvigor_signed.sh`: successful in 14.704 seconds.
- V2 inventory: 0 live V1 files across 459 ETS files; version consistency, i18n parity, and `git diff --check`
  also passed.
