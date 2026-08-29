# Rejected approaches registry

This registry contains only implementation approaches that current user evidence
or accepted history has explicitly invalidated. It is not a backlog, a test
matrix, or a general architecture guide.

Before editing an existing behavior, identify the affected file and symbols,
then query this file with those names. Do not read the whole registry by
default. A matching `REJECTED` entry forbids that approach unless the current
user explicitly reopens the entry after reviewing its failure evidence.

## REJ-READER-001 — Require a post-status-bar target-layout change

- **Status:** `REJECTED`
- **Lookup keys:** `ReaderThumbnailTransitionCoordinator`,
  `requireTargetLayoutChange`, `ReaderPage`, `GalleryDetail`,
  all-thumbnails, fullscreen, status bar, return target.
- **Rejected approach:** record the retained thumbnail rectangle before
  restoring the status bar and require its rectangle/layout key to change
  before allowing the custom Reader return.
- **Why rejected:** the retained thumbnail is not required to move. Waiting for
  movement can exhaust the close gate and replace the custom return with the
  system POP.
- **Evidence:** `git show b5ffd012`;
  `docs/plans/active/gallery-reader-transition-acceptance.md`.

## REJ-READER-002 — Restore the status bar after the return flight

- **Status:** `REJECTED`
- **Lookup keys:** `ReaderPage`, `statusBarRestore`,
  `setSpecificSystemBarEnabled`, close handoff, overlay POP, fullscreen.
- **Rejected approach:** defer status-bar restoration until after the custom
  return flight, ownership handoff, or overlay POP.
- **Why rejected:** it visibly toggles fullscreen after the transition and
  revives a repeatedly fixed timing regression.
- **Evidence:** failed 2026-08-30 candidate recorded in
  `docs/plans/active/gallery-reader-transition-acceptance.md`.

## REJ-READER-003 — Reuse Reader-entry geometry as the close target

- **Status:** `REJECTED`
- **Lookup keys:** entry geometry, cached rectangle, source snapshot,
  `ReaderThumbnailTransitionState`, rotation, fold, window resize.
- **Rejected approach:** cache geometry when entering Reader and reuse it as the
  return endpoint instead of measuring the current retained target.
- **Why rejected:** rotation, folding, resizing, and other window changes make
  entry geometry stale even when the same thumbnail remains the target.
- **Evidence:** rotation objection and live-target boundary recorded in
  `docs/plans/active/gallery-reader-transition-acceptance.md`.

## REJ-READER-004 — Change unrelated transition ownership to fix status-bar timing

- **Status:** `REJECTED`
- **Lookup keys:** target eligibility, proxy root, root size, visibility gate,
  radius ownership, `proxyRadius`, `ReaderThumbnailTransitionCoordinator`.
- **Rejected approach:** solve status-bar timing by changing target eligibility,
  overwriting proxy/root dimensions, adding unrelated visibility gates, or
  changing radius ownership.
- **Why rejected:** these speculative changes caused system-animation fallback
  and discontinuous corner-radius morphs without proving the landing defect.
- **Evidence:** failed 2026-08-30 candidate sequence recorded in
  `docs/plans/active/gallery-reader-transition-acceptance.md`.
