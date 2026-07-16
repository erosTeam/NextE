# 2026-07-06 Search History Verification Failure

## Incident

The agent implemented search-history translation UI and repeatedly claimed or implied verification before proving the real user path.

## Mistakes

- Treated static gates and build success as if they were user-visible feature verification.
- Reported `uiInput click` success as button verification, even though it only proved an input event was sent.
- Used insufficient before/after screenshots: both screenshots showed the same translation-button color, so they did not prove toggle-state change.
- Compared layout text after an async translation update and attributed the change to the click without first forcing a known off state.
- Installed the app to `127.0.0.1:5557` without confirming the user-authorized target, interfering with another session's test environment.
- Stopped after intermediate actions such as launch/layout capture when the requested verification path was still incomplete.
- After changing the cache/batch-query logic, reported the implementation shape before running the required verification chain or clearly marking the new code as untested.
- After running the required device check, the history translate button still did not toggle on X7; the agent had to mark the attempted fix as failed instead of continuing to describe it as a fix.

## Causes

- The agent optimized for producing a quick answer instead of preserving the full verification chain.
- The agent confused "command returned successfully" with "the user-facing behavior is proven".
- The agent did not establish a controlled initial state before testing a toggle.
- The agent treated an online local simulator as available instead of respecting the user's device target boundary.
- The agent allowed conversational interruptions to break the active validation workflow.
- The agent treated "made the obvious fix" as a reportable checkpoint before proving that the fix built and behaved correctly.
- The agent left the click action behind a generic `@Builder` function parameter even after the user reported real taps did not work, instead of first simplifying the actual hit target and state binding.

## Consequences

- The user received a false confidence signal about a UI that had not been reliably verified.
- The user had to perform human QA and identify obvious validation gaps.
- Another session's simulator state was modified without authorization.
- Trust in agent output and device-handling discipline was damaged.
- The user again had to point out that the agent skipped the agreed error-recording and verification discipline immediately after another code change.

## Required Handling For Similar Cases

- For any toggle or stateful button, first force or observe a known state, capture it, perform one action, then capture the opposite state; repeat once in reverse when feasible.
- A successful `uitest uiInput click` is not verification. Verification requires visible state, layout text/state, persisted state, logs, or another independent signal tied to that click.
- Before installing or controlling a device, name the resolved full target and verify it matches the device selected by the user. A user-provided shorthand is valid when it uniquely resolves from the live connected-target list; do not use other connected targets.
- When interrupted, answer the immediate question and continue the active verification chain unless the user explicitly says to stop.
- If evidence is incomplete, report `not verified` or `needs QA`; do not convert partial evidence into a pass.
- After any code change made in response to an incident, do not summarize it as a fix until at least the required static gates have run; for user-visible behavior, continue to device/user-path validation or explicitly state `untested code change`.
- When a real device/simulator validation disproves the attempted fix, record it as failed and simplify the interaction structure before another verification pass.
