# Image Block Community Rules Plan

Status: planning / external repository bootstrapped locally.

## Goal

Build NextE image blocking around pHash rules distributed through a public community rules repository.
The feature targets repeated scanlator ad pages/images. QR-code auto blocking remains deferred because it
has higher false-positive risk.

## External Rules Repository

Intended GitHub repository:

```text
erosTeam/nexte-image-block-rules
```

Local repository path:

```text
/Users/honjow/git/nexte-image-block-rules
```

Current local state:

- Initial local rules commit: `ac04b29 chore: bootstrap image block rules`
- Published merge commit: `b6bd857` on `origin/main`
- Git local identity matches NextE:
  - `user.name=3003h`
  - `user.email=148651245+3003h@users.noreply.github.com`
- Remote repository exists: `https://github.com/erosTeam/nexte-image-block-rules`
- Remote uses the same SSH host alias style as NextE:
  `git@github-3003h:erosTeam/nexte-image-block-rules.git`
- Remote initially had a `LICENSE` commit; local rules history was merged with
  `--allow-unrelated-histories` and pushed.

## Rules Repository Shape

Source files:

```text
rules/*.jsonl
```

Generated client subscription files:

```text
dist/manifest.json
dist/<feed>.json
dist/review-report.md
```

Tooling:

```text
node tools/rules.mjs validate
node tools/rules.mjs build
node tools/rules.mjs stats
node tools/rules.mjs find --hash <hex>
node tools/rules.mjs add --feed zh-scanlator-ads --hash <hex> --source-url <url> --note <text>
```

Source rules may include reviewer-only fields:

```json
{"hash":"0123456789abcdef","threshold":8,"label":"scanlator-ad","scope":"whole","sourceUrl":"https://example.com/review-only","note":"full-page ad"}
```

Generated client rules strip reviewer-only fields:

```json
{"hash":"0123456789abcdef","threshold":8,"label":"scanlator-ad","scope":"whole"}
```

## Subscription Contract

Manifest URL after remote exists:

```text
https://raw.githubusercontent.com/erosTeam/nexte-image-block-rules/main/dist/manifest.json
```

Manifest entries include feed id, title, URL, algorithm, default threshold, count, and SHA-256. Feed files
use `schema=1`, `kind=nexte-image-block-feed`, `algorithm=dct64-v1`, and `items`.

Hard client constraints:

- Feed data is data-only: no scripts, expressions, dynamic logic, cookies, gallery ids, or original image
  binaries.
- Clamp threshold to `0..12`.
- Cap feed size per source before import; start with 10,000 items.
- On update failure, keep the last valid feed.
- Apply local whitelist before subscription rules.

## App-Side Architecture

Non-UI first slice:

1. `PHashService`
   - Compute `dct64-v1` pHash from local cached reader image files.
   - Use TaskPool worker and small decoded bitmap, following the `CoverColorService` off-UI-thread pattern.

2. `ImageBlockRepository`
   - RDB tables for subscriptions, subscription rules, local rules, and whitelist.
   - Keep `rect_x/rect_y/rect_w/rect_h` fields reserved, but first implementation only matches whole image.

3. `ImageBlockService`
   - Input: local image path / page / resolved URL metadata.
   - Output: block decision with reason, rule id/feed id, distance, and threshold.
   - Does not own Reader UI.

4. State holder
   - AppStorageV2 holder only exposes small flags such as enabled/version.
   - Do not put the full rule list in UI state.

5. Backup/sync
   - Backup local rules, whitelist, subscription URLs, and enable flags.
   - Do not backup downloaded subscription rule payloads by default; refetch them from the feed.

## App Contribution Flow

Phase 1: assisted submission

- App computes pHash.
- User confirms `sourceUrl` and note.
- App generates a JSONL snippet and opens GitHub issue/PR flow.

Phase 2: one-tap PR

- Optional GitHub OAuth.
- App forks `erosTeam/nexte-image-block-rules` to the user account.
- App creates a branch, appends to `rules/zh-scanlator-ads.jsonl`, and opens a PR.
- App never writes directly to the `erosTeam` main repository.

Submission safety:

- Do not upload full images by default.
- Do not auto-submit without user confirmation.
- Strip or reject `sourceUrl` values containing cookies, tokens, `showkey`, `nl`, `igneous`,
  `ipb_pass_hash`, or EH temporary image links.

## Deferred

- QR-code auto blocking.
- Region/crop matching UI and matching logic.
- Signed feed metadata.
- BK-tree/hash index.
- Backend submission service, voting, bot moderation.
