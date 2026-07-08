# 2026-07-08 Account Asset Balance Accountability Failure

## Incident

The agent mishandled the account asset balance feature and then mishandled the user's accountability questions.

## Mistakes

- Rendered GP as the row trailing value and Credits as subtitle text, creating a false primary/secondary relationship between two peer balances.
- Treated a settings-row layout pattern as sufficient without first answering how a normal user would interpret the information hierarchy.
- Considered parsing GP-looking numbers from the exchange page too broadly, even though `exchange.php?t=gp` contains trade options and non-balance amounts.
- Discussed or used example balances as if they could become expected values; account balances must never be guessed, normalized, or demonstrated as fixed expected numbers.
- Proposed or pursued contract-style protection before proving the product semantics and parser boundary; this abused the contract mechanism.
- Kept explaining implementation steps and validation instead of directly answering the user's questions about why the layout and value parsing were wrong.
- Said work was stopped and clean before checking for residual files; a generated `EhAssetBalanceParser.ets` file was still present until a later read-only check found and removed it.
- Failed to register the incident promptly after the user pointed out repeated mistakes, despite the project rule that serious repeated errors must be written into `docs/agent-guides/incidents/`.

## Causes

- The agent optimized for continuing implementation instead of first resolving the user's product-semantics objection.
- The agent treated "GP is the main number in the row" as a harmless UI convention rather than recognizing that placement changes meaning.
- The agent did not enforce the financial-data rule: if the parser cannot identify the current balance with high confidence, show unavailable instead of guessing.
- The agent used contract thinking as a substitute for judgment, turning uncertainty into proposed tests rather than narrowing or stopping the implementation.
- The agent treated stopping work as a conversational posture before verifying repository state.
- The agent failed to convert the incident into durable project guidance when the failure pattern became clear.

## Consequences

- The user saw a misleading account-balance UI where GP appeared primary and Credits appeared secondary.
- The user had to identify that a displayed GP amount could be a page option or fabricated parse result rather than the real account balance.
- The user's explicit constraints about units, EH-only exchange page behavior, and ExHentai surfaces were not reliably honored.
- The contract mechanism was made less trustworthy by being used as a dumping ground for over-specific assertions.
- Trust was damaged further because the agent repeatedly gave verbal accountability instead of leaving durable corrective guidance.

## Required Handling For Similar Cases

- For account assets, GP and Credits are peer balances. Do not display one as a trailing primary value and the other as subtitle/explanation.
- Preserve EH's original GP unit text, including `GP` or `kGP`. Do not scale, convert, normalize, or infer units.
- Do not parse account balances by scanning the whole exchange page for the first GP/Credits-looking numbers. Scope parsing to an explicit current funds/current balance statement, or show unavailable.
- `https://e-hentai.org/exchange.php?t=gp` is EH-only. Fetch it through the EH base URL regardless of current EX/EH site mode, and do not assume ExHentai has an exchange page.
- Do not show asset balance in ExHentai-only archive-download UI unless that surface actually provides a reliable balance source.
- Before adding or moving account-page UI, answer the information hierarchy first: what is the primary information, which values are peers, and how a normal user will read the row.
- Do not add contracts for sample balances, arithmetic examples, one-off screenshots, or unverified visual guesses. Contracts may only protect a stable boundary after the product meaning and parser scope are established.
- When the user asks "why did this happen", answer causes first. Do not keep executing implementation or validation as a substitute for the accountability answer.
- After saying work is stopped or reverted, immediately verify `git status --short` and remove only the agent's residual untracked files before claiming the tree is clean.
- Serious repeated mistakes must be registered in `docs/agent-guides/incidents/` during the same task, before any further feature work.
- The general rule is now "unknown blocks implementation": if real page structure, UI semantics, or user-path evidence is missing, stop and gather evidence or report `BLOCKED` before writing parser/UI code.
