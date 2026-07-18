# 2026-07-18 Reader Super-Resolution Height Limit Contract Failure

## Incident

Reader settings described the super-resolution limit as a maximum source-image height and defaulted it
to 2000, but the processing service also imposed smaller hidden output-edge, pixel-count, and RGBA-byte
caps. With a 2x model, the 3200 output-edge cap made any source taller than 1600 ineligible. The menu
still offered 2000, 2500, 3000, and 4000, and the height comparison also rejected an image exactly at
the selected limit.

## Consequences

- A 1280 x 1837 source was rejected even though its height was below the displayed 2000 limit.
- The 2000 setting did not mean what the UI said, while 2500, 3000, and 4000 were unreachable promises.
- Users could not distinguish the configured height rule from an undisclosed implementation guard.

## Required Handling For Similar Cases

- A user-facing eligibility limit must remain truthful end to end. Hidden guards may protect abnormal
  inputs, but they must not reject ordinary inputs that satisfy the displayed rule.
- Derive internal output and memory bounds from the same supported source limit, or expose a separately
  named constraint. Do not maintain unrelated magic caps below the advertised range.
- Offer only values the current decode, inference, full-output-buffer, PixelMap, and packing pipeline can
  actually complete. Remove unsupported choices instead of leaving placeholders in a live menu.
- Treat a maximum as inclusive unless the product explicitly says otherwise, and verify both the exact
  boundary and a representative near-boundary Reader image on the selected device.

## Correction Evidence

- The supported source-height maximum is now one shared constant: 2000. Internal 2x output guards are
  derived from it, and sources with `height <= 2000` are eligible.
- Device selector `103` resolved live to `192.168.50.103:12345`. The exact 1280 x 1837 integration case
  produced a 2560 x 3674 waifu2x Vulkan result in 21,405 ms; the targeted test reported 1 pass, 0
  failures, and 0 errors.
