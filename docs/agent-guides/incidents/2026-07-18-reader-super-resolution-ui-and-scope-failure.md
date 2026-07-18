# 2026-07-18 Reader Super-Resolution UI And Scope Failure

## Incident

The first Reader super-resolution management UI was implemented as an isolated feature screen instead
of being grounded in NextE's settings, modal-navigation, download-action, and state-ownership patterns.
It also reduced the previously accepted candidate set to two hard-coded models without preserving an
explicit feasibility boundary for the omitted candidates.

## Mistakes

- Combined enable/disable, active-model selection, and local-file management into one ambiguous flow.
- Added a `none` model choice even though the independent enhancement switch already owns disabled
  semantics.
- Used selected-row tint and selection affordances on a page whose job is only downloading and deleting
  local files.
- Used text actions and plain status copy instead of the project's existing circular symbol buttons and
  persistent `LoadingProgress` action state.
- Dismissed the Reader settings sheet before pushing model management into the full-screen Reader
  overlay stack, then over-corrected by embedding a separate `HdsNavigation` inside the sheet content.
- Hard-coded two install booleans and two branches across settings, management, and runtime services;
  previously evaluated candidates disappeared instead of being represented by one auditable registry.
- Localized model identifiers with full-width punctuation even though model names and parameter tokens
  are technical identifiers.

## Consequences

- The management page read like a model picker rather than local download management.
- The independent switch lost a single, understandable meaning.
- A user opening model management from the Reader sheet was moved into a different presentation and
  back-stack context.
- Model breadth, download state, and runtime support could drift independently in multiple files.

## Required Handling For Similar Cases

- Before adding a settings subflow, record the exact existing page, modal, navigation, row, icon-action,
  and loading-state references used by the implementation.
- A boolean switch owns enable/disable. A model picker contains installed runnable models only and must
  not add a second disabled state.
- A model-management page manages local files only: neutral rows, file size, download/delete symbol
  action, and an in-place loading indicator. It does not visually select the active model.
- `bindSheet` is not a route container. For a same-panel secondary page, follow the Huawei component UX
  example: keep both complete pages in one clipped `Stack`, measure the panel width, and animate their
  horizontal `translate` values. Do not embed a `NavPathStack` inside the sheet or dismiss it to push a
  global/full-screen route. Use a second `bindSheet` only when the product actually calls for multiple
  panels.
- Downloadable models, native configuration, checksums, paths, UI enumeration, and runtime lookup must
  come from one typed registry. Do not add per-model booleans or branches to UI pages.
- Keep the full evaluated candidate list in the intake record. Integrate candidates only when their
  model assets, runtime operators, output contract, and license/source can be audited; record an explicit
  blocker instead of silently dropping them.
- Preserve ASCII punctuation in model names and parameter tokens across every locale.
