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

## Authorized follow-up: settings scan execution (OPEN)

Device197 ordinary Settings → Reading diagnostic measured two scans (6ms and 5ms); touch-up to native push was 90ms versus 80ms for Download settings. This does not establish the user's earlier visible delay cause. Remove the proven duplicate scan, defer hidden model-page scanning until active without changing its mounted transition tree, and move size/SHA256 verification to a thin TaskPool worker. Share only pending identical checks, not completed results. Worker infrastructure errors must retain settings rather than treating the model as absent. Preserve model validation rules and navigation. Next acceptance: signed candidate on197, ordinary settings/model page and tap preview route; original reader regressions remain OPEN.

### Follow-up implementation and device result

Size and SHA-256 checks now run in `ReaderModelFileValidationTask` through TaskPool; identical pending file checks share a promise that is removed on completion. No completed-result cache. Existing synchronous installation/runtime validation remains intact. Normal Reading uses onWillShow, sheet Reading uses aboutToAppear, and the offscreen model pane refreshes when active without changing its mounted transition tree. TaskPool rejection is caught at the settings refresh boundary before selection replacement.

Signed build passed. Candidate SHA256 `8117423b3a9a5218dc19f531e6d7b6413526efa3cf4e1cb0d6ce48704dcd3329`, host993ac08f plus preserved WIP and this follow-up/tap-preview changes, corec76b2b3. Device197 ordinary Settings → Reading → Model management shows system model ready, installed waifu2x photo removable, absent models downloadable; selected system model retained. Evidence under `.hvigor/outputs/reader-settings-optimize-20260925`. This verifies the existing installed/missing model paths, not injected corruption or TaskPool failure, and does not establish a quantitative latency improvement.

Tap preview: NextEReaderLabPage previously supplied only the resolver to ReaderTapPolicy, leaving preview regions empty and revision zero. It now passes resolver-derived regions and increments revision on the same four setting changes monitored by legacy, only when session ready. Candidate recording `tap-preview/tap-preview.mp4` shows the overlay after changing paged layout Right/Left → L-shaped and dismissing settings; first left tap hides it while remaining on page7, second advances to page8. Initial ordinary entry showed no preview. Right/Left and page7 were restored and the resulting three-column preview was observed; the preview was then dismissed. Entry animation and adjacent blur/preload remain OPEN and are outside this settings fix.

Normal Settings → Reading final recording: `settings-opening/settings-opening.mp4`; device log touch-up02:26:34.225, native push start34.287 (62ms), end34.881. Frames show the ordinary navigation transition and final settings page. This single sample is not a controlled performance benchmark or proof of the historical delay cause.

Reading-sheet hidden model pane was additionally opened on final allocation HAP09c73, device197. `reader-allocation-final-20260925/hidden-model-pane-confirm/view.png` shows system ready, installed photo model removable and absent models downloadable after activation. No model download/removal or value change. The first route tapped the height-menu row after scrolling; it was dismissed without selection and is rejected as a model-opening result. The corrected terminal route confirms on-demand activation.
