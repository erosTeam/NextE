# 2026-07-12 Fixed-Scope Debt Cleanup Drift

## Fact

After agreeing on five fixed cleanup items, work opened unrelated Reader, image-block, schema-DDL, and
WebDAV concurrent-write lanes while item 4 was still active. Those candidate changes were removed and were
not included in the five-item closure.

## Consequence

The agreed queue no longer had an obvious end state, and uncommitted candidate work accumulated before the
next required phase commit. The user had to redirect the task back to the fixed list.

## Required Handling

- Keep one compact fixed-scope plan with only the agreed items, status, and commit reference.
- Do not implement or develop an unlisted debt item while a listed item remains open.
- Stage and commit each validated listed item before proceeding to the next one.
- Revert or explicitly park any out-of-scope candidate before resuming the fixed list.
- After a commit, report the intended next listed item only; a new priority requires user reprioritization.
