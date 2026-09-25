# Reader entry: online loading and selected-part landing

## Current scope and baseline

The user requested the installed version be committed before repair. Baseline **c94b43fa** includes the preserved host changes and pins reader-kit **4e50b79**. No push. The prepared-fullscreen-target approach in **28f5b92c / 4e50b79** is rejected by the user's spread counterexample; its earlier portrait-only timing observation is not acceptance of spread or online loading.

## Cause and repair

- `ReaderRootEntryHandoff.sync` could depart without a measured selected-part target. Its fallback was the host's fullscreen thumbnail rectangle. This replaced the correct left/right endpoint with a whole-screen endpoint. Require the reader's actual selected-part geometry again. Retain parser-attested preview geometry from detail seeds when a local source replaces the online source, so original decode need not precede layout.
- `ReaderThumbnailTransitionState.rootProxyVisible` kept the root image above the whole reader until original readiness. The inner preview also had `zIndex(1)`, above cell feedback. Retire the root after the one-frame handoff; keep the inner preview below images, loading, errors and chrome. While entry owns the preview, use the ReaderSurface canvas below it instead of a second opaque pager canvas above it.
- `ReaderSurface.pageTap` rejected all pending entry phases, including waiting for the original. `ReaderEntryTransition.blocksInput` now covers layout/motion only. A later page turn cancels entry and releases its placeholder independently of image-ready reports; stale decode callbacks remain rejected.

Reader-kit **126fc08** owns the geometry/input changes. The host changes are limited to the adapter, Lab handoff and thumbnail transition state. The cached-page allocation fix remains. No second spread calculator, decode-readiness fabrication, new loading component, default-navigation rewrite, or close-target change.

## Pre-edit rationale and verification boundary

User feedback reopened this entry/loading parent tree. The faulty assumption was that fullscreen proxy geometry could substitute for a selected spread part. Local portrait QA ignored network waiting and spread placement. The affected tree is root flight → ReaderSurface preview/canvas → paged or continuous content → per-cell image/loading/error and chrome. Existing default no-thumbnail navigation and current close-target measurement have separate owners.

The repair requires physical evidence for online waiting/input and both spread endpoints. Source tests and a signed build do not establish that evidence. Future changes must not use local loaded content as acceptance for an online waiting path.

## Observed on device 197, 2026-09-25

Candidate: baseline c94b43fa plus frozen `host.patch`, reader-kit126fc08. Signed HAP SHA256 `af79a069493e719b61c0ab6f31084a7e3c3c9263a019bdc42a17b11eab38cfa6`. Installed without clearing data. Device ALN-AL80, portrait1260x2720, fold state unknown; no cross-fold geometry claim. Evidence root `.hvigor/outputs/reader-entry-loading-spread-20260925/`; identity.txt, host.patch, manifests, command ledgers, recordings, PTS and contact sheets bind this run.

- `online-loading-input`: ordinary gallery4210308 (95 pages), explicitly logged `kind=online`. Flight ended waiting04:05:03.404; page tap04.228 cancelled that waiting entry through `pager-command`. Actual selection progressed1→2→3→2 using tap and6000px/s swipes. Continuous frames show a white loading indicator over the first thumbnail (frame95 retained as `loading-visible-at-tap.png`), then retirement of that thumbnail on navigation. Page2's loading indicator and subsequent original are visible. No slow drag was used.
- `online-wait-original`: ordinary detail thumbnail8, remained selected. Flight ended waiting04:07:06.622; actual original reveal08.560, entry finished08.612. Continuous frames preserve the preview and loading feedback during the approximately1.94s wait, then display the original without an empty frame. Normal thumbnail return is visible.
- `spread-left-right`: joined spread enabled through the actual reading sheet. Detail thumbnail1 lands on the left part; thumbnail2 lands on the right part. Logged proxy rectangles are x0 andx193.8, each193.8vp wide within387.7vp root. All recorded frames were reviewed: neither entry first expands fullscreen before becoming a spread. Spread was restored off afterward; the subsequent online recordings independently show single-page rendering.
- `single-entry`: actual geometry precedes original decode; scale entry is retained. Local original dimensions refine rounded preview dimensions and cancel the optional core entry on a mismatch; the host flight remains intact. This is not evidence that all aspect-ratio combinations are accepted.

105 related actual state/geometry/session tests pass; V1 inventory0; NextE signed build succeeds. No product source changed after this candidate was installed.

## Open boundaries

The second spread return used the system POP rather than thumbnail return; it remains **OPEN** and is not included in entry acceptance. Physical Back during flight, rotation/split variants and complete three-host replacement remain unaccepted. The two requested repairs are accepted only for the named ordinary online waiting/input and left/right joined-spread entry paths above. No Koma or device200 operation; no push. The temporary screen timeout is restored to120000ms after this session.


## 2026-09-25 final audit disposition

Historical second-spread return OPEN is closed for current NextE/device197 EX Machi thumbnail3 route: hoste5625bd0/corea433017, HAPbd4f95be, second-spread-default-final all592 frames reviewed, both index2 thumbnail returns prepared/finished and visible; left-part entry/companion fade preserved. See reader-settings-runtime-audit.md final regression. Other untested boundaries above remain unclaimed.
