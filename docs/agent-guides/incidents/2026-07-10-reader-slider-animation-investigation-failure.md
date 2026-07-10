# 2026-07-10 Reader Slider Animation Investigation Failure

## Incident

The agent repeatedly proposed unsupported or unnecessary Reader progress-slider implementations after the user twice identified `AppColorPicker` as an existing working native-Slider animation reference.

## Mistakes

- Treated an early platform-capability theory as stronger evidence than the user's reproducible in-app counterexample.
- Inspected the three `Slider` builders in `AppColorPicker` but initially failed to follow the complete nested path: `selectFavoriteColor()` → `UIContext.animateTo()` → `selectColor()` → `syncDraftFromHex()` → the three Slider-bound values.
- After an attempted Reader change had no visible effect, generalized the failure into “Slider does not support programmatic animation” instead of comparing the complete value-write chains.
- Continued editing the full Reader after the state chain remained ambiguous instead of first reproducing the working and failing paths in a minimal native-Slider fixture.
- Proposed replacing the native Slider with a hand-built track and gesture control before exhausting the existing native-component reference supplied by the user.
- Repeated implementation attempts before establishing the exact static difference, forcing the user to restate the same evidence multiple times.

## Causes

- Investigation was organized around proving or disproving a platform API assumption, rather than starting from the known-working project implementation.
- Source inspection stopped at component declarations and builders instead of tracing every state mutation and callback across component and ViewModel boundaries.
- The agent shifted into solution generation after each failed result instead of returning to a side-by-side source-to-state comparison.
- Build and installation activity displaced the more important isolation step: proving which execution boundary made the same native Slider animate or jump.

## Consequences

- The user repeatedly tested changes that did not alter the reported behavior.
- Time was spent on platform-source speculation and a proposed custom control that were outside the smallest correct fix.
- The user's explicit working reference was dismissed or reinterpreted, damaging trust and delaying identification of the Reader double-write.

## Required Handling For Similar Cases

- When the user names a working in-project component as a reference, trace its full event-to-state-to-render chain before consulting broader platform theories or proposing replacement controls.
- Treat a user-confirmed working counterexample as evidence that invalidates a conflicting capability claim until the behavioral difference is proven.
- Compare all writes to the bound value on both paths, including ViewModel mutations, monitors, promise continuations, and callbacks; do not compare only component declarations.
- After the first real-device failure, stop implementation attempts and produce a concrete side-by-side difference before editing again.
- When the full page contains multiple reactive boundaries, create a minimal fixture that changes one boundary at a time and capture intermediate device frames before returning to product code.
- Do not propose a custom or overlaid replacement while the existing native component demonstrates the requested behavior.
- Never create or propose a hand-drawn component, native-control imitation, or custom replacement layer in any scenario unless the user explicitly authorizes self-drawing for that specific request; inability to make the native path work is a blocker, not permission.
- For Reader slider animation, do not start the Slider transaction directly inside the `vm.currentIndex` Monitor. The Monitor runs after the observed write has invalidated the Reader subtree; retain the old Slider value, start `animateTo()` in the next task, and reject stale callbacks when a newer page change or user drag wins.
