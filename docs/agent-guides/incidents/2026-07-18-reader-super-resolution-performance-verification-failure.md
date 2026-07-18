# 2026-07-18 Reader Super-Resolution Performance Verification Failure

## Incident

The initial local-model verification established that waifu2x and Real-ESRGAN could produce correctly
sized output from a 64 x 48 synthetic input, but that evidence was treated as progress toward Reader
usability without first measuring a representative full Reader page. Device 103 later showed that the
implemented ncnn paths were far outside an interactive loading budget.

## Mistakes

- Used a 64 x 48 integration fixture to compare CPU and Vulkan without stating that its backend ranking
  could not be extrapolated to an 800 x 1132 Reader page.
- Proved model loading, output dimensions, and backend reporting before proving first-processing latency
  on the user path.
- Allowed multiple Reader pages to enter the global serial processing chain without first validating
  current-page latency, queue priority, or cancellation behavior.
- Treated the existence of a true local model backend as meaningful Reader progress even though neither
  model had passed a representative end-to-end latency gate.

## Evidence

- Target: device selector `103`, resolved live to `192.168.50.103:12345` for the diagnostic run.
- Real-ESRGAN: 800 x 1132 to 1600 x 2264, Vulkan, 108.357 seconds.
- waifu2x photo noise0 2x: 800 x 1132 to 1600 x 2264, CPU, 62.272 seconds.
- The waifu2x log recorded `process_start` for another 800 x 1132 page immediately after the first
  `process_success`, demonstrating that adjacent work can continue occupying the serial inference queue.
- The first waifu2x page reported `model_inference_done` only 101 ms before `process_success`; output
  packing was not the dominant part of the 62.272-second total.

## Consequences

- Both model choices were unusable for first-time interactive Reader display on the measured device.
- Small-fixture results gave an incorrect impression of practical performance and backend preference.
- Background or adjacent-page work could extend heat, battery use, and wait time after the visible page
  had already incurred a long inference.

## Required Handling For Similar Cases

- A super-resolution backend is only a functional candidate after it passes the exact model, backend,
  source dimensions, output dimensions, first-run/warm-run, and end-to-end latency matrix on the selected
  device. A synthetic fixture proves integration only.
- Do not choose an automatic backend from small-input timing. Compare CPU and accelerator backends on the
  same representative Reader page and record the actual backend returned by the runtime.
- Record native inference time separately from decode, pixel conversion, output packing, and cache I/O.
- Benchmark tile size, precision, and backend one variable at a time, with output-difference and memory
  checks; do not present a faster candidate without proving image correctness.
- Current-page work must have priority. Do not enqueue adjacent-page model inference until current-page
  latency is acceptable and cancellation or stale-work suppression is proven.
- Until a representative page meets the agreed latency budget, label the path experimental and do not
  enable it by default or describe it as Reader-ready.
