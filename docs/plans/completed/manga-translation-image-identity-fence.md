# Manga Translation Image Identity Fence

- **status**: completed
- **created**: 2026-07-21
- **last reviewed**: 2026-07-21
- **completed**: 2026-07-21

## Goal

Guarantee that the image bytes sent to a comic provider still match the request hash and declared MIME type used by
the cache identity.

## Grounding

- Reference implementation: Reader hashes the local file before orchestration; the Responses adapter later reopens it.
- Primary information: request SHA-256, declared image MIME, and the exact buffer encoded into the data URL.
- Primary action: verify SHA-256 and signature-derived MIME on that final buffer before transport.
- Current closure: reject changed or mislabeled files without provider quota consumption.
- Non-goals: no image decoding/resizing, dimension probing, provider call, cache ownership, or Reader UI change.

## Completion

- A mismatched image hash and mismatched MIME both fail after local read but before transport.
- A matching supported image still reaches the transport unchanged.
- Test build, full device suite on `237`, signed build, V2 inventory, and relevant static contracts pass.

## Result

- The Responses analyzer rehashes the exact final buffer and compares it with the request SHA-256 before encoding.
- JPEG, PNG, GIF, and WebP MIME are derived from file signatures and must match the declared preparation profile.
- Identity and MIME failures stop before the provider transport, so they cannot consume provider quota.

## Validation

- `entry@ohosTest` debug HAP build: passed in 10.100 s.
- Full suite on device `237`: 155/155 passed in 849 ms; the new image-identity test passed in 3 ms.
- Signed production HAP build: passed in 9.451 s.
- `git diff --check`, V2 decorator inventory, persistence inventory, secret safety, settings backup, sync design, and
  Huawei Cloud sync contracts: passed.
