# 2026-07-16 Active Task Continuity Failure

## Incident

During download-status device QA, intermediate user corrections were repeatedly treated as standalone
requests that could end the task. The active deliverables—real archive-download state verification on
device `237`, visual inspection, and screenshots—were known but left unfinished when the agent returned
a final answer after correcting one inaccurate explanation.

## Mistakes

- Treated the latest correction as a replacement for the active task without an explicit cancellation
  or scope replacement from the user.
- Returned a final answer while required device evidence and screenshots were still missing.
- Replaced execution with repeated task restatement and planning after the user asked for concrete QA.
- Invented a remote-archive side-effect distinction that was not supported by the inspected code, then
  used that distinction to avoid the same real-task validation already performed for normal downloads.

## Causes

- Optimized each response around the latest sentence instead of checking the task's unresolved
  acceptance criteria before ending the turn.
- Had no hard completion gate tying final-answer eligibility to the requested deliverables.
- Failed to separate a constraint correction from an explicit cancel, replace, pause, or acceptance
  instruction.

## Consequences

- Device QA stopped without proving archive status on the relevant screens.
- The user had to repeatedly restore the original task context.
- Explanations and plans displaced the requested implementation evidence.
- Trust in status reports and task continuity was damaged.

## Required Handling For Similar Cases

- Keep one active objective with explicit unresolved deliverables. A user correction updates facts,
  constraints, or implementation direction; it does not terminate the objective.
- End or replace the objective only when the user explicitly cancels/replaces it, or when every requested
  deliverable has current evidence.
- Before any final answer, audit the active objective: list each unresolved deliverable internally and
  continue work when any required implementation, device path, log, screenshot, or validation remains.
- Do not substitute a restated plan, apology, source explanation, build result, or partial screenshot for
  missing user-visible QA.
- When a claim about side effects changes whether a real action will be performed, inspect the exact code
  path first. Unsupported side-effect assumptions cannot narrow the authorized validation path.
