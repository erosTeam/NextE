# 2026-07-15 Gallery Comment Preview Text Tap Regression

## Incident

The two comment previews on the gallery detail page opened the full comments page when their card surface was tapped, but tapping directly on ordinary body text did nothing. The user reported that this interaction had regressed repeatedly.

## Cause

- `GalleryCommentsCard.CommentRow()` already routed preview-card taps through `onMore`.
- Commit `0be130e2` changed every rich-text segment into a `Span` with its own `onClick` so HTML and detected links could remain interactive.
- Non-link spans entered that child handler but performed no action. The child text hit therefore never reached the preview card's `onClick`.
- Static source checks around the outer card route did not exercise the actual text hit target, so they could pass while the user path remained broken.

## Consequences

- The same visible comment card had inconsistent hit behavior depending on whether the user touched glyphs or surrounding padding.
- Later rich-text and translation work kept the child span handler in place, so the regression survived unrelated comment fixes.

## Required Handling For Similar Cases

- Treat the innermost interactive text/span as the event owner when it has an explicit click handler; do not assume an ancestor card handler will also run.
- In a detail-page comment preview, ordinary body segments must invoke the existing full-comments action directly. URL segments must preserve their link action.
- Do not add a transparent overlay or duplicate geometry to repair text hit testing.
- Verify the real hit targets separately: ordinary body text on each preview comment, a URL segment, author text, and ordinary body text on the full comments page.
- A source-shape contract around the outer `onMore` callback is not user-path acceptance for nested text interaction.
