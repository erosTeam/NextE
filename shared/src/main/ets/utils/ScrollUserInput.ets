/**
 * Returns whether an ArkUI scroll callback originated from direct user input.
 * Programmatic Scroller calls and their animations must not steal the native
 * status-bar back-to-top target from the pane the user last operated.
 */
export function isUserScrollSource(source: ScrollSource): boolean {
  return source === ScrollSource.DRAG ||
    source === ScrollSource.FLING ||
    source === ScrollSource.OTHER_USER_INPUT ||
    source === ScrollSource.SCROLL_BAR ||
    source === ScrollSource.SCROLL_BAR_FLING
}
