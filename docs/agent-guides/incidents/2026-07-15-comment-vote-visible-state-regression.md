# 2026-07-15 Comment Vote Visible-State Regression

## Incident

After a user voted on a gallery comment, the full-comments row did not reliably repaint its score and the score-details dialog continued to show the pre-vote breakdown without the user's record. The same score-refresh behavior had previously been marked implemented pending real-submit acceptance.

## Causes

- The vote path updated `GalleryCommentRenderState.score` and `vote`, then relied on nested observed-state repaint plus a full `BasicDataSource` reload. It did not explicitly notify the changed virtualized row.
- `scoreDetails` was excluded from `GalleryCommentRenderState` and `CommentVoteMutationState`; the dialog read the initial route comment snapshot even after the vote result changed the row state.
- The `votecomment` response contains aggregate score and current vote state but no authoritative score-detail breakdown. The implementation treated those response fields as if they completed every visible vote surface.
- Source-shape checks asserted that score/vote fields were assigned, but no authorized real-submit evidence proved the badge, selected thumb, and detail dialog converged after the write.

## Consequences

- Successful vote state could be split across three truths: updated API result fields, a stale virtualized card, and stale server-parsed score details.
- Returning to the gallery detail page could preserve the new score/vote while retaining old score details in its cached comments.

## Required Handling For Similar Cases

- A write result is not complete until every visible consumer of that result is identified and refreshed.
- For a virtualized list, explicitly notify the changed row when a nested state mutation is reported not to repaint; do not rely on a broad reload as evidence.
- Keep aggregate score, current-user vote state, and score details in the same per-row presentation state and cross-page mutation payload.
- Do not synthesize server score-detail text. When the write response omits details, perform a bounded read-back and apply the server-parsed breakdown.
- A read-back failure after a successful write must not roll back or report the write as failed; retain the authoritative write response and report only the detail-refresh failure in diagnostics.
- Do not mark this path accepted without an explicitly authorized real-account submit covering badge score, selected thumb, detail breakdown, withdrawal, and failure rollback.
