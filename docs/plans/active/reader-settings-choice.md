# Reader settings single-choice ownership

User evidence: the reader settings sheet displayed Legacy in the row while checking Shared in the menu. The user explicitly requested correction at the shared component boundary, not only two caller expressions.

## Cause and boundary

`a9b16cc8` moved ReaderSettingsPage's label to persisted ReadModeState.readerImplementation but left menu checks reading process-local NextEReaderBackendSelectionState.current(). ConciseListRow accepted independent trailingText and dropdownMenuBuilder; SettingsCheckedMenuItem accepted an unrelated selected boolean. Those primitives did not own a single-choice invariant.

SettingsChoiceRow now accepts title, options, value and onSelect. Both the label and native menu checks derive from value. ReaderImplementationGroup supplies the persisted observed field and retains its original selection/persistence handler. Native Menu/MenuItem, ConciseListRow geometry and deferred click dispatch remain unchanged. Empty/unmatched values do not fabricate a selection. This migrates the reader implementation option only; other arbitrary menus are not claimed migrated.

## Validation

V2 inventory: 615 files scanned, no V1 decorators. Exact diff reviewed; signed build passed.

Installed HAP SHA256: `1b0048a5da76a63086c63a91472703c7955e204b08fcbfb665e287d2723bd93e` (core c76b2b3, host 5d93966a plus preserved unrelated WIP and this change).

On authorized device197 / ALN-AL80 / portrait 1260x2720, ordinary Settings → Reading and ordinary archive reader → settings sheet were exercised. Full-screen captures reviewed: Shared label/check, selection to Legacy, Legacy label/check after ordinary cold start, return to Shared; sheet Shared and Legacy label/check. Evidence: `.hvigor/outputs/reader-settings-choice-20260925/choice-new-menu`, `choice-legacy-cold`, `choice-restored-new`, `choice-sheet-new-menu`, `choice-sheet-legacy-menu`, `choice-sheet-restored`. Fold state unknown; no cross-device geometry equivalence claimed.

The initial fast select/reopen chain did not reach its declared terminal state and remains rejected. The subsequent continuous diagnostic recording establishes that selecting Legacy changed the row to Legacy; it does not establish the cause of the earlier route failure.

## Remaining work

Reader-settings opening latency, missing tap-zone preview, entry animation and adjacent preload/blur remain OPEN. This commit does not change loading, entry ownership, model validation or tap-zone behavior, and is not reader-wide acceptance.
