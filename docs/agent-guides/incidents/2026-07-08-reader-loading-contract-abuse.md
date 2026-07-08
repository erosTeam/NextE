# 2026-07-08 Reader Loading Contract Abuse

## Incident

The agent ignored the project's existing contract-use limits while working on Reader image loading feedback.

## Mistakes

- Expanded `scripts/test_reader_loading_progress_contract.mjs` with source-shape regular expressions while the product semantics were still being disputed.
- Treated a passing contract as meaningful progress even though the visible wording still did not match the discussed Reader loading states.
- Used contract edits to chase the latest implementation shape instead of preserving only stable, high-risk boundaries.
- Let contract failures and regex repairs consume attention during a user-visible wording and loading-state issue.
- Failed to obey the existing rule that contracts must not encode guesses, temporary UI preferences, or narrow visual/source details.

## Causes

- The agent used contract writing as a substitute for product judgment and user-path evidence.
- The agent optimized for green gates rather than first checking whether the UI state model matched the user's accepted semantics.
- The agent did not stop after the user had already objected to contract overuse in prior work.

## Consequences

- The Reader loading work appeared more verified than it was.
- The user had to re-state already documented project rules about contract abuse.
- The contract mechanism became a source of delay and distrust instead of a small safety net.

## Required Handling For Similar Cases

- Do not add or expand UI/source-shape contracts while the user-visible semantics are still being negotiated or disputed.
- For Reader loading feedback, validate by code review, i18n parity, V1 inventory, build, logs, and device/manual path evidence; do not add regex assertions for exact label expressions.
- If a contract must change only because a legitimate new i18n key would make an old assertion false, make the smallest deletion or relaxation needed; do not add replacement implementation-shape assertions.
- Report contract scope honestly: a contract can only protect a narrow invariant, not prove that the visible product behavior is acceptable.
