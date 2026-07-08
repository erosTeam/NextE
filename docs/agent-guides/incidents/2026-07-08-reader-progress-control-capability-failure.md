# 2026-07-08 Reader Progress Control Capability Failure

## Incident

The agent gave an incorrect capability answer about the Reader loading progress control, then used that incorrect answer to drive a UI implementation choice.

## Mistakes

- Claimed or implied that the system linear progress control could provide a no-percent dynamic loading state for Reader image loading.
- Treated documentation-level expectation as enough instead of compiling the exact ArkUI `Progress` API shape before advising the user.
- Converted the user's "use the system linear progress bar" direction into an always-rendered `ProgressType.Linear` branch, even though unknown-total downloads render as an empty 0% track in the current SDK.
- Tried a hidden/empty linear-progress compromise after the user objected to the blank track, instead of returning to the actual old interaction model.
- Made the user choose between UI options based on a false premise about platform control support.

## Causes

- The agent optimized for aligning with the requested system component before proving the component supports the requested state.
- The agent conflated "system progress component" with "linear progress bar can express indeterminate loading".
- The agent did not stop after the SDK rejected `ProgressStatus.LOADING` for linear progress and re-state the product choice from the new evidence.
- The agent tried to preserve layout stability through invisible placeholders after the core visual state was already wrong.

## Consequences

- The Reader loading UI briefly moved toward a worse state: an empty linear progress track during unknown-total image waits.
- The user had to identify that the proposed "unified progress bar" was based on an incorrect control-capability claim.
- Trust in the agent's ArkUI API judgment and UI decision framing was damaged.

## Required Handling For Similar Cases

- For uncertain ArkUI/HDS component states, verify the exact API by SDK source, official docs, or a build before advising the user.
- If build evidence disproves an assumed API, stop and restate the available product choices from that evidence before editing further.
- Do not render a determinate progress bar when the code has no determinate value to show. Unknown-total waits should use a native busy indicator or a separately approved custom indeterminate component.
- Do not use invisible placeholders to justify a control that communicates the wrong loading state.
- When the user chooses a UI direction based on an agent-supplied capability claim, treat that claim as part of the implementation contract and re-check it before coding.
