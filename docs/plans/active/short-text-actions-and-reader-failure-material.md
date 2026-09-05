# Short text actions and Reader failure material

Status: device-verified for double-page Reader failure/retry and shared page-error actions; remaining variants need QA (2026-09-05).

## Grounding

1. Reference: current NextE ReaderLoadingStage neutral thin-blur panel; current NextN real failed-image overlay.
2. Main information: image failure title, category-specific hint and page number, readable over the retained preview.
3. Main action: native capsule Retry; secondary context and existing Reader controls remain unchanged.
4. Path: thumbnail -> real original-image failure -> visible recovery card -> restore connectivity -> Retry -> image.
   Non-goals: Reader extraction, error classification changes, proxy lifecycle, account or image-block policy changes.
5. HarmonyOS expression: existing Column and native Button; BACKGROUND_THIN, existing neutral tint/card radius;
   explicit body font, 40vp action height, 120vp minimum width, 24vp horizontal padding.

## User authority and audit

The user rejected NextN's 64.3x48vp short Retry inside a large recovery card, requested app-wide review, explicitly
included matching NextE problems and asked to port the failure backdrop. Current NextE ReaderFailureOverlay has
no material; loading already has one. Reader's initial failure, shared PageErrorState and SecurityLockOverlay's
Unlock are also auto-width short text actions. Preserve their parent trees and action ownership; share dimensions,
not a new control. One-character labels retain a horizontal footprint; longer translations can grow naturally.

Excluded: full-width login/import forms, padded icon+label detail chips/FABs, longer image-unblock actions, circle
icons, +/- steppers, transparent Clear suffixes, metadata/tag chips and the developer-only gesture probe Reset.
These are not the standalone short-label/large-height pattern. A source classification is not visual acceptance.

## Verification

- Signed build succeeded in 20 s 36 ms. V1 inventory: 0 files (559 scanned).
- Actual 237 before-state: native NextE Gallery root [0,117][1320,2120], VDE-AL00, portrait; fold state unknown.
- Final-candidate double-page failure, restored-connectivity retry and page-error observations are recorded below.
  Single/continuous and initial Reader failure, language/font-scale variants and security-lock runtime remain
  unverified until separately observed.
- Current evidence is under NextN's local .hvigor/outputs/device-237__VDE-AL00/unknown/portrait-1320x2120/
  short-text-actions-20260905/. No raw screenshot is committed.

## Device counterexample and correction

`nexte-reader-failure/` is failed QA: actual native Reader1/24 is double-page, but ReaderSpreadImageLayer does not
pass the existing compact flag. Both failure Columns stay 280vp in 220vp halves; newly visible material extends
across the neighbor and clips the first hint. Never accept only the button while ignoring its parent/background.
Use compact=true for the spread failure leaf, and constrain ReaderFailureOverlay to its parent with width100%
and maxWidth(contentWidth), retaining normal280/compact196 caps. No image, gesture, proxy or pagination ownership
changes. Rebuild/install and repeat the same actual double-page failure before acceptance.

## Observed final-candidate paths

- Rebuild:14 s909 ms; V1 inventory0; installed in place. Actual native double-page Reader1/24 in
  `nexte-compact-settled/`: cards [36,751][624,1370] and [696,751][1284,1370], each196vp wide with120x40vp Retry.
  Whole raw frame reviewed: cards no longer intersect, hints wrap within their own card, every button is fully
  visible, retained cover remains around the translucent material, page indicator remains visible below.
- `nexte-restored-retry/`: mobile and WLAN restored ON with readbacks. Page1 and page2 each retried once; actual
  cover and originally blank second-page bitmap displayed, with both failure/loading overlays removed.
- Shared PageErrorState: unavailable-gallery real request exercised in `nexte-page-error-visible/`, native root
  [0,117][1320,2120]; Retry[480,1448][840,1568]=120x40vp, centered and unclipped beneath its error message.
  Initial `nexte-page-error/` was rejected because Reader still covered that route; no acceptance from hidden layout.
- These are bounded runtime observations, not blanket acceptance of every page, locale, font scale or lock screen.
  Single/continuous Reader and security Unlock are source-reviewed candidates without separate device captures.
  No security setting was enabled merely to obtain a screenshot; image-block actions and account semantics unchanged.
- Cleanup: original Hot subtab restored after leaving invalid-gallery test; final device foreground is NextN's
  Download root. No NextE cache/account/history/download deletion occurred. Both original network permissions ON.
