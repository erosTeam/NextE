# Comment list virtualization + per-comment reactive translation

Status: in progress. Fixes auto-translate scroll jank on comment-heavy galleries.

## Problem (root cause)

The full comments page (`GalleryCommentsPage`) renders the comment list with `List` + **`ForEach`**
(`PullRefreshListScaffold` is a `List`; the page's content slot is a plain `ForEach`). `ForEach` is eager —
every comment card mounts up front, so:

1. **All comments auto-translate at once** — each card's `aboutToAppear` → `autoTranslateVisibleComments`
   fires for its comment, and all cards exist immediately. Not "translate what's on screen".
2. **Every translation completion re-renders the WHOLE list.** `applyCommentTranslationState` does
   `this.comments = slice()` (reactive `referenceComments` to every card) **and** `commentRenderVersion++`
   (a global `@Param` every card `@Monitor`s), all wrapped in `animateTo`. N completions × N cards = O(N²)
   reactive churn on the UI thread while results stream in — the felt jank.
3. **Each card re-render re-sorts the whole comment array.** `replyReferences → candidateComments →
   sortedComments()` does `slice()+sort()` of all reference comments on every build, plus the same again
   inside `commentTextSegments`. With (2) that's O(N² log N) per wave.

Translation requests themselves are already async/off-thread; the cost is the synchronous completion
cascade, not the network.

## Fix (full virtualization — user chose 彻底虚拟化)

- **P1 LazyForEach.** Page switches `ForEach` → `LazyForEach(commentSource, builder, c => c.commentId)`
  over a stable `BasicDataSource<EhGalleryComment>` (the canonical NextE source, kept out of `@Trace`).
  Only visible cards mount → only visible comments auto-translate (as you scroll) and only visible cards
  re-render. The data source is reloaded ONLY on refresh / uploader-only toggle / block change — never on
  a translation completion (stable keys → no reload).
- **P2 per-comment reactivity.** Each comment already has an `@ObservedV2 GalleryCommentRenderState` with
  `@Trace` fields. The card READS its `renderState.translation*/vote/score` directly (reactive `@Trace`),
  and the page mutates one render state per completion via a `Map<id, renderState>` — re-rendering exactly
  one card. Drops the global `commentRenderVersion` `@Param`/`@Monitor`, the `comments.slice()` churn, and
  the card's `localTranslation*`/`localVote*` mirrors. O(N²) → O(visible).
- **P3 memoize the full-list work.** Card caches `sortedComments()` (once per instance) + `replyReferences`
  / `displayContentText` per comment id, reset on `referenceComments` identity change. A translation
  re-render no longer re-sorts all comments.
- **P4 no per-completion list animation.** Page mutations are plain synchronous `@Trace` writes (no global
  `animateTo`). The manual single-tap height-grow animation stays (local to one card).

## Files

- `feature/gallery/.../pages/GalleryCommentsPage.ets` — data source + render-state Map + LazyForEach;
  translation/vote handlers mutate render state (not the array / version).
- `feature/gallery/.../components/GalleryCommentsCard.ets` — parentManaged path reads `renderState`
  `@Trace` directly; remove locals/`renderVersion`; memoize sort/reply/display.
- `feature/gallery/.../model/GalleryCommentRenderState.ets` — unchanged (already carries all fields).

Peek path (`GalleryDetailPage`, `parentManagedActions:false`, `max>0`, translation disabled) is untouched.

## Validation

V1-decorator gate 0; signed build; device test on a comment-heavy gallery with auto-translate ON —
scroll stays smooth while translations stream in; manual translate still animates; vote still works.

## Adversarial review follow-ups (fixed)

A 3-lens adversarial review (reactivity / parity / arkts-lifecycle) confirmed 5 findings. Fixed the 3 real
regressions; the 2 lows are a pre-existing cosmetic gap left as-is:

- **[fixed] uploaderOnly toggle dropped off-filter state.** `rebuildCommentList` keyed the render-state map
  off the *visible* subset, so toggling the filter discarded non-uploader render states; since comment
  objects are no longer written back, a vote / manual translation was lost on a filter ON→OFF cycle. Fix:
  key the preserved map off `this.comments` (all comments), not just the visible subset. Device-verified.
- **[fixed] blocked-comment expand lost on recycle.** The expand flag was a card `@Local`, reset when
  LazyForEach recycles a card. Fix: in the parentManaged (page) path it lives on the render state as
  `@Trace blockedExpanded`; the peek path keeps the local array (one card renders several comments).
- **[fixed] block-setting changes didn't update a mounted page.** List + count became snapshots written only
  on refresh/filter; an external block-rule/mode change no longer re-filtered live (HIDE mode). Fix:
  `@Monitor('localBlock.version')` → `rebuildCommentList()` (mirrors GallerySourcePage).
- **[won't fix, low] reply-quote excerpt shows the referenced comment's original text, not its translation.**
  `quoteExcerptText` reads `c.translation*` off the comment object, which the page no longer writes. A real
  fix needs comment-object dual-writes (against the single-source-of-truth design) for a ≤3-line excerpt;
  not worth it. (Two of the five findings were this same issue.)
