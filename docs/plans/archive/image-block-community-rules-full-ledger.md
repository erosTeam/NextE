# ARCHIVED: Image Block Community Rules Full Ledger

> Historical implementation and device evidence. Current protocol and follow-ups live in
> `docs/plans/active/image-block-community-rules.md`.

Status: foundation and Reader/settings integration landed on main; remaining items are follow-up lanes.

## JHenTai Integration Notes

JHenTai's useful pattern is not QR auto-detection; it is the split between local rules and a built-in/community
provider. NextE should keep the same separation:

- App runtime only sees safe pHash match fields.
- Rules repository keeps reviewer-only `sourceUrl` / `sourcePage` / `note` for PR review and CI recomputation.
- UI later calls a contribution helper to generate one JSONL line; it does not write directly to `erosTeam/main`.
- QR-code matching, crop/region matching, HDS floating controls, and full rule-management UI remain separate lanes.

## Goal

Build NextE image blocking around community-maintained pHash rules for repeated scanlator ad pages/images.
QR-code auto blocking remains deferred because it has higher false-positive risk.

## External Rules Repository

Repository:

```text
erosTeam/nexte-image-block-rules
```

Local path:

```text
/Users/honjow/git/nexte-image-block-rules
```

Remote:

```text
git@github-3003h:erosTeam/nexte-image-block-rules.git
```

Published state:

- Initial rules commit: `ac04b29 chore: bootstrap image block rules`
- Published merge commit: `b6bd857` on `origin/main`
- First real seed rule: `f086185 data: add first scanlator ad phash rule`
- Validation command: `node tools/rules.mjs validate`
- App-draft review command: `node tools/rules.mjs import-jsonl --feed zh-scanlator-ads --file <draft.jsonl>`
- Importer smoke command: `node tools/test_import_jsonl.mjs`
- App-side sample review uses the rules-repo fixture; the former source-shape drift contract is retired.
- Raw GitHub check on 2026-06-29: `dist/manifest.json` exposes feed `zh-scanlator-ads` with count `1` and SHA-256
  `5bc6849243594b7886105fd30c58a88acf6658987b714ce8d5099beef618f2b1`; the feed contains reviewed pHash
  `ce9e181d354a3cd5`, threshold `8`, label `scanlator-ad`, scope `whole`.

## Rules Repository Shape

Source rules are JSON Lines under `rules/*.jsonl` and may include reviewer-only fields:

```json
{"hash":"0123456789abcdef","threshold":8,"label":"scanlator-ad","scope":"whole","sourceUrl":"https://example.com/review-gallery","sourcePage":1,"note":"full-page ad"}
```

Generated client files live under `dist/`:

```text
dist/manifest.json
dist/<feed>.json
dist/review-report.md
```

Client feed items contain only safe matching fields:

```json
{"hash":"0123456789abcdef","threshold":8,"label":"scanlator-ad","scope":"whole"}
```

The app should subscribe to:

```text
https://raw.githubusercontent.com/erosTeam/nexte-image-block-rules/main/dist/manifest.json
```

Maintainer workflow for app-copied drafts:

```bash
node tools/rules.mjs import-jsonl --feed zh-scanlator-ads --file /path/to/app-draft.jsonl
node tools/rules.mjs import-jsonl --feed zh-scanlator-ads --file /path/to/app-draft.jsonl --apply
```

The first command is a dry run. It reports new rows, existing duplicate hashes, duplicate incoming hashes, and invalid
rows. App-copied drafts require both `sourceUrl` and `sourcePage`. `--apply` appends only valid, non-duplicate rows
and rebuilds `dist/`; it refuses drafts with invalid rows. CI also runs `node tools/test_import_jsonl.mjs` so duplicate
detection, unsafe URL rejection, missing/invalid page rejection, invalid apply refusal, and clean apply/rebuild behavior
stay covered.

## Client Contract

- `schema=1`
- manifest kind: `nexte-image-block-manifest`
- feed kind: `nexte-image-block-feed`
- algorithm: `dct64-v1`
- hash: 16 lowercase hex characters
- threshold: integer clamped to `0..12`
- first-version scope: `whole`
- per-feed item cap: `10000`
- update failure keeps the last valid feed
- local whitelist is applied before subscription rules

## App Foundation Slice

Implemented in this branch:

1. `PHashService`
   - Normalizes 64-bit hex pHash values.
   - Computes hex Hamming distance without `BigInt`.
   - Clamps thresholds to the shared `0..12` range.
   - Computes `dct64-v1` from local image files in TaskPool using a 32x32 RGBA downsample and 8x8 DCT.

2. `ImageBlockFeedParser`
   - Parses manifest and feed JSON.
   - Rejects unsupported schema, kind, algorithm, scope, and malformed hashes.

3. `ImageBlockService`
   - Takes an image hash, enabled rules, and whitelist.
   - Returns a block decision with matched rule id/feed id/source, threshold, and distance.

4. `ImageBlockRuntimeService`
   - Takes a local image file path or `file://` URI.
   - Skips pHash computation when no local/subscription rules are enabled.
   - Reuses cached pHash values when the file path and byte size match.
   - Computes missing `dct64-v1` hashes and returns the same block decision model.
   - Creates local rules from a user-marked image file for the later "mark this page as ad" UI.
   - Can add a local image file's pHash to the whitelist so later UI can offer a false-positive escape path.
   - Accepts a reviewer source URL plus page number so manual rules are not anonymous hashes.

5. `ImageBlockRepository`
   - Stores subscription metadata, rules, and whitelist in RDB.
   - Supports replacing one subscription feed, loading enabled rules, loading/replacing whitelist, adding local rules,
     and caching file pHash values.
   - Supports adding/removing one whitelist hash without replacing the whole whitelist.
   - Treats each subscription as a provider; disabling a subscription excludes its rules without deleting the feed.

6. `LocalDataStore`
   - Schema version `13`.
   - Tables: `image_block_subscriptions`, `image_block_rules`, `image_block_whitelist`,
     `image_block_hash_cache`.
   - `image_block_rules` includes optional `source_url` and `source_page` metadata for local manual rules.

7. `ImageBlockSubscriptionService`
   - Fetches manifest/feed JSON through cookie-free HTTPS requests.
   - Verifies feed SHA-256 before replacing local subscription rows.
   - Keeps the last valid local feed when one feed update fails.

8. `ImageBlockContributionService`
   - Builds the source-repo JSONL line from an app-computed pHash plus reviewer `sourceUrl` / `sourcePage` / `note`.
   - Can also build the JSONL line from a saved local `ImageBlockRule`, preserving `source_page` as structured
     reviewer metadata instead of hiding it inside `note`.
   - Can concatenate multiple saved local rules into JSONL for a later assisted submission or PR flow.
   - Can build a submit-ready batch summary from local rules, recording total, included, skipped, missing-source,
     duplicate, and invalid counts so UI can explain why a manual mark is or is not ready for review.
   - Can build a non-submitting GitHub issue package from the same batch: title, review body, `issues/new` URL, JSONL,
     included/total/skipped counts, and a URL-length fallback. This is service-only preparation for a later UI action;
     it does not open GitHub, call OAuth, fork, commit, or create a PR.
   - Requires `sourceUrl` and a positive `sourcePage` for copied app drafts so future PR review is traceable.
   - Rejects credential-bearing or temporary EH image URLs containing cookies, `showkey`, `nl=`, tokens,
     sessions, or `fullimg.php`.

9. Reader minimal integration
   - `ReaderSpreadImageLayer`, `ReaderImagePage`, and `ReaderVerticalImage` call
     `ImageBlockRuntimeService.decisionForFile()` after `CachedImageFileService` returns a local file and before
     rendering the `displayUri`.
   - Cached hits and newly loaded files both go through the same decision path.
   - A blocked page is treated as loaded for Reader progress/preload accounting, but the local cache file is kept.
   - The blocked placeholder can allow the current image as a false positive by adding the image file's pHash to the
     local whitelist, then re-running the page decision.
   - Current presentation is the blocked cached image in the same contained Reader image surface, visibly blurred until
     unreadable without becoming a black canvas, with a large central warning icon, hidden-image message, hint, page
     number, and a single whitelist escape action. HDS floating controls, PR submission, and richer management actions
     are explicitly deferred.
   - QR-code scanning is not part of this lane.

10. Settings subscription entry
   - `EhSettingsPage` routes to `ImageBlockSettingsPage` under the EH settings group.
   - The page refreshes the default erosTeam community manifest, lists installed subscription providers, and toggles
     provider enablement through `ImageBlockRepository.setSubscriptionEnabled()`.
   - The page also lists the local rules produced by Reader-side manual marking and can delete mistaken local rules.
   - Local rows show a readable label/page, short pHash, threshold, and the public gallery review URL when present.
   - When local rules exist, the page can copy a sanitized JSONL contribution draft from submit-ready manual rules.
     The draft path reuses `ImageBlockContributionService.buildSubmissionBatchFromRules()`, skips duplicate/missing-source
     rows, and writes plain text to the system pasteboard. It does not submit a PR, open GitHub, or require OAuth.
   - The contribution row shows `ready/total` and summarizes skipped-rule reasons such as missing source, duplicate hash,
     or invalid hash, so local manual rules are understandable before a future PR flow exists.
   - The page lists false-positive allowlist hashes created from the Reader blocked placeholder and can remove them.
   - This is intentionally not a PR submission, QR flow, or rule-table editor.

11. Reader local rule mark action
   - Reader image components report the loaded local cache file path to the parent page.
   - The bottom toolbar `eye_slash` action calls `ImageBlockRuntimeService.addLocalRuleForFile()` for the current page.
   - The icon-only toolbar action carries the accessible label `reader_image_block_mark` (`屏蔽当前图片` /
     `Block current image` / `現在の画像をブロック`) so screen readers and QA automation can target it without
     coordinate guessing.
   - The manual rule stores `https://e-hentai.org/g/<gid>/<token>/` plus the image page number instead of a
     temporary `/s/`, `fullimg`, `showkey`, or cookie-bearing URL.
   - After adding the rule, Reader bumps a local image key version so the cached current page immediately re-runs the
     pHash decision and shows `ReaderImageBlockedOverlay`.
   - This provides the first manual-rule QA path without adding a full management UI; cleanup is handled from
     `ImageBlockSettingsPage`.

12. Image-block QA routes
   - Mutating seed routes are retired. QA helpers must not insert sample local rules, delete user rules, replace
     subscription feeds, or write `qa-*` rows into `image_block_user_rules`.
   - `nexte://qa/image-block-reader-open` opens the reviewed Reader page without mutating image-block state.
   - `nexte://qa/image-block-settings-open` opens Image blocks settings without mutating image-block state.
   - The old `scripts/qa_image_block_seeded_reader.mjs` helper was removed because its default path depended on hidden
     seed routes that wrote into the real user-rule sync table.

## App Contribution Flow

Phase 1: assisted submission

- App computes pHash.
- User confirms a stable review `sourceUrl`, `sourcePage`, and note.
- App generates a JSONL snippet through `ImageBlockContributionService`; current settings UI can copy submit-ready local
  rules as JSONL to the system pasteboard.
- The same service can now build a non-submitting GitHub issue package for a future action, while keeping the accepted
  UI path copy-only. Single-rule packages target `rule_submission.yml` and prefill `hash`, `source_url`,
  `source_page`, `note`, and `feed`; multi-rule packages keep JSONL in the issue body because issue forms are not a
  good batch-edit surface.
- Maintainers import copied JSONL through `tools/rules.mjs import-jsonl`, starting with a dry run and applying only after
  invalid rows are zero.
- Wiring an in-app action that opens GitHub remains a separate follow-up after the copy-only path is accepted.

Phase 2: one-tap PR

- Optional GitHub OAuth.
- App forks `erosTeam/nexte-image-block-rules` to the user account.
- App creates a branch, appends to `rules/zh-scanlator-ads.jsonl`, and opens a PR.
- App never writes directly to the `erosTeam` main repository.

Submission safety:

- Do not upload full images by default.
- Do not auto-submit without user confirmation.
- Keep `sourceUrl`, `sourcePage`, and `note` in source rules only; generated `dist/` feeds strip them before clients
  download rules.
- Reject `sourceUrl` values containing cookies, tokens, `showkey`, `nl=`, `igneous`,
  `ipb_pass_hash`, or EH temporary image links.

## Validation Samples

Durable fixture:

```text
docs/fixtures/image-block-public-samples.json
```

The fixture records only stable gallery review URLs, page numbers, public search expectations, and pHash metadata. It
does not store original image URLs, `/s/` links, `fullimg.php`, `showkey`, `nl=`, cookies, or image bytes.

Public EH search checks on 2026-06-29:

- `other:advertisement`, `other:advertisements`, and `other:advertising` returned no hits, so current sample discovery
  must not describe these as real EH namespace tags.
- Public `curl` re-checks on 2026-06-29 confirmed all three `other:` variants still return `No hits found`.
- Title search `advertisement` returned three public candidate galleries:
  - `https://e-hentai.org/g/3049882/d7e740a39e/` - 6 pages; title-search candidate; no visible advertisement
    namespace tag; promoted as the first scanlator-ad seed rule.
  - `https://e-hentai.org/g/1757442/f27210be8c/` - 39 pages; title-search candidate; visible `other:artbook`
    tag only, not an advertisement namespace tag; lower priority because it is a general advertisement/artbook sample.
  - `https://e-hentai.org/g/1284740/ed8b71498d/` - 6 pages; title-search candidate; visible `other:missing cover`
    tag only, not an advertisement namespace tag; useful secondary manual-rule smoke.
- Title search `advertisements` returned `https://e-hentai.org/g/1284740/ed8b71498d/` as the single public short
  candidate. Use it as the second manual-rule smoke sample after the already seeded `3049882` gallery.
- Title search `advertising` returned five public candidates, but live gallery tag checks still did not expose an
  advertisement namespace tag:
  - `https://e-hentai.org/g/3917158/2db060bc4c/` - 3 pages; shortest additional advertising-title sample.
  - `https://e-hentai.org/g/2991483/416674eea1/` - 7 pages; additional short advertising-title sample.
  - `https://e-hentai.org/g/2652400/31b1601675/` - 25 pages; longer, lower-priority sample.
  - `https://e-hentai.org/g/1678170/58f56e1fb3/` - 40 pages; general advertising-materials sample.
  - `https://e-hentai.org/g/3636516/df5d90e12e/` - search result only; unauthenticated gallery fetch did not expose
    stable title/page metadata, so do not use it as a first validation sample.

Current conclusion: there are useful public title-search samples, but no verified EH `other:advertisement` /
`other:advertising` namespace tag to subscribe to. Manual-rule validation should therefore start from stable gallery
review URLs and a reviewed page number, then promote only verified pHashes into the community feed.

Manual-rule validation path:

1. Open a stable gallery URL, not a temporary `/s/`, `fullimg.php`, `showkey`, or `nl=` image URL.
2. Enter Reader and load the candidate ad page.
3. Tap the Reader `eye_slash` action to create a local pHash rule with the gallery URL plus page number.
4. Confirm the page immediately re-renders into the blocked placeholder.
5. Open Settings -> EH -> Image blocks and confirm the local row shows label/page, short pHash, threshold, and source URL.
6. Run the edge-case settings QA route to confirm missing review sources and duplicate pHashes are visible as skipped
   reasons instead of silently disappearing from the contribution draft.
7. Delete the local row to verify cleanup, or keep it and use `ImageBlockContributionService.buildSubmissionBatchFromRules()`
   for a later PR/submission UI.

Static validation:

- Rules-repo fixture review checks this plan, the app default rules manifest URL, and
  the local sibling `nexte-image-block-rules` repository when present.
- The same script verifies the rules repository generated feed strips reviewer-only `sourceUrl` / `sourcePage` / `note`,
  while source JSONL keeps the stable gallery review URL and page evidence.
- The same script writes an app-shaped temporary JSONL draft with `sourceUrl` plus `sourcePage` and runs
  `node tools/rules.mjs import-jsonl --feed zh-scanlator-ads --file <draft>` as a dry run, requiring
  `new=1 duplicateExisting=0 duplicateIncoming=0 invalid=0`.
- `scripts/test_image_block_foundation_contract.mjs` locks the hidden seeded Reader route, confirms it is not exposed in
  `module.json5`, and verifies the device QA script keeps the signed HAP path, lockscreen guard, seeded pHash/source URL,
  direct Reader URI, seeded settings URI, via-detail option, settings/copy-draft modes, install-failure guard, and
  placeholder success status. The lockscreen guard keys on `ScreenLockRootComponent`; normal `com.ohos.sceneboard`
  status-bar layout is not treated as a lockscreen.
- This static check does not replace Reader/device QA; it prevents sample, manifest, pHash, and review-source drift
  while 197 remains unavailable.

Emulator validation on `127.0.0.1:5555` with a signed HAP:

- Opened `https://e-hentai.org/g/3049882/d7e740a39e/` through the app deep-link route.
- Entered Reader and loaded page 1.
- Tapped the Reader `eye_slash` manual-block action.
- Reader immediately showed the blocked placeholder for page 1.
- After app restart, Settings -> EH -> Image blocks showed one manual block rule, row `scanlator-ad / P1`, short pHash
  `ce9e...3cd5`, threshold `T8`, and source gallery URL metadata.
- Local artifacts: `.hvigor/outputs/image-block-emulator-smoke/reader_3049882_after_mark.jpeg` and
  `.hvigor/outputs/image-block-emulator-smoke/image_block_after_manual_rule.jpeg`.
- Local-rule deletion source path is locked by `scripts/test_image_block_foundation_contract.mjs`: delete requires a
  confirmation dialog, guards duplicate taps, tombstones through `ImageBlockRepository.removeLocalRule()`, reloads the
  visible local-rule list, and shows success feedback.
- False-positive allowlist cleanup is locked by the same contract: Settings loads `ImageBlockRepository.loadWhitelist()`,
  deletes through `ImageBlockRepository.removeWhitelistHash()`, guards duplicate taps, reloads the visible allowlist, and
  shows success/failure feedback.
- Seeded Reader QA now passes on `127.0.0.1:5555` with a signed HAP:
  - Direct Reader route: `scripts/qa_image_block_seeded_reader.mjs --target 127.0.0.1:5555 --artifact-dir
    .hvigor/outputs/image-block-seeded-reader-emulator-direct` returned `reader_block_placeholder_visible` for
    `nexte://qa/image-block-seed-reader`.
  - Detail route: the same script with `--via-detail` returned `reader_block_placeholder_visible` for
    `nexte://qa/image-block-seed`; read-button click evidence was `x=936,y=2264`.
  - The direct-route screenshot shows the original black blocked placeholder, warning icon, `图片已隐藏`, page `P1`, and
    `允许此图`. Artifacts:
    `.hvigor/outputs/image-block-seeded-reader-emulator-direct/summary.json`,
    `.hvigor/outputs/image-block-seeded-reader-emulator-direct/reader_wait_0.jpeg`,
    `.hvigor/outputs/image-block-seeded-reader-emulator-via-detail/summary.json`, and
    `.hvigor/outputs/image-block-seeded-reader-emulator-via-detail/reader_wait_0.jpeg`.
  - Allowlist route: the same direct Reader route with `--allow-and-verify` first found the blocked placeholder, tapped
    `允许此图`, and returned `reader_allowlist_image_visible`. This caught and fixed the false-positive escape tap being
    intercepted by the Reader tap overlay; `ReaderTapOverlay` is now suppressed while the current page is showing a
    blocked placeholder. Artifacts:
    `.hvigor/outputs/image-block-allowlist-emulator-fixed/summary.json`,
    `.hvigor/outputs/image-block-allowlist-emulator-fixed/reader_wait_0.jpeg`, and
    `.hvigor/outputs/image-block-allowlist-emulator-fixed/allow_wait_0.jpeg`.
- Seeded settings QA on the local emulator is currently blocked by emulator storage, not by product logic:
  `scripts/qa_image_block_seeded_reader.mjs --target 127.0.0.1:5555 --settings` now returns
  `blocked_install_failed` when `hdc install` prints `install failed due to insufficient disk memory`, instead of
  continuing against an older installed HAP. Local artifact:
  `.hvigor/outputs/image-block-settings-emulator-draft-install-guard/summary.json`.
- Live deletion QA is still pending: on 2026-06-29, `127.0.0.1:5555` had been overwritten by the parallel Download HAP
  and no longer exposed the Image blocks route; `192.168.50.197:12345` stayed on `ScreenLockRootComponent` after
  Power plus swipe. Local artifacts: `.hvigor/outputs/image-block-197-manual-rule-followup/wake_after_power.jpeg`,
  `.hvigor/outputs/image-block-197-manual-rule-followup/after_swipe.jpeg`, and matching layout JSON files.
- Live allowlist overlay QA is covered on the local emulator but still pending on 197: on 2026-06-29, the latest 197
  read-only probe still reported `ScreenLockRootComponent`. Local artifact:
  `.hvigor/outputs/image-block-allow-197-probe/layout.json`.
- Follow-up 197 probe after this settings-management slice is still blocked by the lockscreen: target
  `192.168.50.197:12345` was connected and boot completed, but both the initial layout and a layout captured after one
  standard upward swipe still contained `ScreenLockRootComponent`. Local artifacts:
  `.hvigor/outputs/image-block-manual-197-probe/layout.json` and
  `.hvigor/outputs/image-block-manual-197-probe/layout_after_swipe.json`.
- Latest 197 read-only probe after the sample-contract slice is unchanged: target `192.168.50.197:12345` is connected
  and boot completed, but the foreground layout is still `com.ohos.sceneboard` / `ScreenLockRootComponent`. Local
  artifact: `.hvigor/outputs/image-block-197-probe-latest/layout.json`.
- Seeded Reader signed-build QA on 197 is also blocked before install: `scripts/qa_image_block_seeded_reader.mjs`
  acquired the 197 lease, captured preflight layout/screenshot, detected `ScreenLockRootComponent`, wrote
  `blocked_screen_locked`, and exited without installing the signed HAP. Local artifacts:
  `.hvigor/outputs/image-block-seeded-reader-197-latest/summary.json`,
  `.hvigor/outputs/image-block-seeded-reader-197-latest/preflight.json`, and
  `.hvigor/outputs/image-block-seeded-reader-197-latest/preflight.jpeg`.
- A follow-up 197 wake plus upward swipe returned `WakeupDevice is called` / `No Error`, but the next seeded Reader QA
  run still detected `ScreenLockRootComponent` and again exited before install. Local artifacts:
  `.hvigor/outputs/image-block-seeded-reader-197-after-wake/summary.json`,
  `.hvigor/outputs/image-block-seeded-reader-197-after-wake/preflight.json`, and
  `.hvigor/outputs/image-block-seeded-reader-197-after-wake/preflight.jpeg`.
- After narrowing the script lock guard to `ScreenLockRootComponent` only, 197 is still blocked before install:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345` used the direct Reader QA URI, acquired the
  lease, captured preflight evidence containing `ScreenLockRootComponent`, wrote `blocked_screen_locked`, and exited
  before installing. Local artifacts:
  `.hvigor/outputs/image-block-seeded-reader-197-direct-fixed/summary.json`,
  `.hvigor/outputs/image-block-seeded-reader-197-direct-fixed/preflight.json`, and
  `.hvigor/outputs/image-block-seeded-reader-197-direct-fixed/preflight.jpeg`.
- Follow-up 197 allowlist verification after the Reader tap-overlay fix is also blocked before install:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --allow-and-verify` acquired the 197 lease,
  captured `ScreenLockRootComponent`, wrote `blocked_screen_locked`, and exited before installing the signed HAP. Local
  artifacts:
  `.hvigor/outputs/image-block-allowlist-197-after-reader-tap-fix/summary.json`,
  `.hvigor/outputs/image-block-allowlist-197-after-reader-tap-fix/preflight.json`, and
  `.hvigor/outputs/image-block-allowlist-197-after-reader-tap-fix/preflight.jpeg`.
- Seeded settings signed-build QA passed on 197 while the device was unlocked:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --settings` acquired the 197 lease, installed
  the signed HAP, opened `nexte://qa/image-block-settings`, and returned `settings_manual_rule_draft_visible`. The
  screenshot shows Image blocks settings with community provider count `1/1 / 1`, manual block rule count `1`, community
  draft count `1`, local row `scanlator-ad / P1`, short pHash `ce9e...3cd5`, threshold `T8`, and stable source gallery
  URL. Local artifacts:
  `.hvigor/outputs/image-block-settings-197-draft/summary.json`,
  `.hvigor/outputs/image-block-settings-197-draft/settings_wait_0.json`, and
  `.hvigor/outputs/image-block-settings-197-draft/settings_wait_0.jpeg`.
- Copy-draft click QA on 197 is still pending: a follow-up `--settings --copy-draft` run reacquired the 197 lease, but
  the device had returned to `ScreenLockRootComponent`, wrote `blocked_screen_locked`, and exited before install. Local
  artifact: `.hvigor/outputs/image-block-settings-197-draft-copy/summary.json`.
- Latest copy-draft retry on 197 is unchanged: `scripts/qa_image_block_seeded_reader.mjs --target
  192.168.50.197:12345 --settings --copy-draft` acquired the 197 lease, found `ScreenLockRootComponent` during
  preflight, wrote `blocked_screen_locked`, and exited before install. Local artifact:
  `.hvigor/outputs/image-block-settings-197-draft-copy-retry/summary.json`.
- Latest Reader allowlist retry on 197 is also blocked by the same preflight lockscreen:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --allow-and-verify` acquired the 197 lease,
  found `ScreenLockRootComponent`, wrote `blocked_screen_locked`, and exited before install. Local artifact:
  `.hvigor/outputs/image-block-allowlist-197-retry-after-copy/summary.json`.
- Latest settings-edge retry on 197 after the manual-rule wording cleanup is still blocked before install:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --settings-edge --copy-draft` acquired the
  197 lease, found `ScreenLockRootComponent`, wrote `blocked_screen_locked`, and exited before installing the signed HAP.
  Local artifacts:
  `.hvigor/outputs/image-block-settings-edge-197-manual-labels/summary.json`,
  `.hvigor/outputs/image-block-settings-edge-197-manual-labels/preflight.json`, and
  `.hvigor/outputs/image-block-settings-edge-197-manual-labels/preflight.jpeg`.
- 197 unlock note: a normal `uitest uiInput swipe 630 2500 630 500 1000` plus `power-shell wakeup` did not leave the
  lockscreen. The working path was `power-shell timeout -o 600000`, `power-shell wakeup`, then the documented
  high-velocity `uitest uiInput swipe 630 2580 630 260 40000`. After that, layout evidence reported
  `ScreenLockRootComponent=false`. Local artifacts:
  `.hvigor/outputs/image-block-197-unlock-manual/after_fast.json` and
  `.hvigor/outputs/image-block-197-unlock-manual/after_fast.jpeg`.
  This path is now available in `scripts/qa_image_block_seeded_reader.mjs --wake-unlock`, with audit artifacts
  `wake-keep-awake.json`, `wake-unlock.json`, and `wake-unlock-result.json`.
- Seeded settings-edge copy-draft QA then passed on 197 with the signed HAP:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --settings-edge --copy-draft` acquired its
  own 197 lease, installed the signed build, opened `nexte://qa/image-block-settings-edge`, verified the contribution
  draft row, clicked `复制社区规则草稿`, and returned `settings_contribution_draft_clicked`. The post-click capture returned
  to the lockscreen before the toast was visible, so `toastVisible=false`; the click itself is still recorded in
  `draft-click.json` and the script status. Local artifacts:
  `.hvigor/outputs/image-block-settings-edge-197-after-unlock/summary.json`,
  `.hvigor/outputs/image-block-settings-edge-197-after-unlock/after_start.json`,
  `.hvigor/outputs/image-block-settings-edge-197-after-unlock/draft-click.json`, and
  `.hvigor/outputs/image-block-settings-edge-197-after-unlock/draft_wait_0.json`.
- The self-contained 197 path now passes with `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --settings-edge --copy-draft`
  first captured `preflight` as `ScreenLockRootComponent`, then ran the scripted wake/unlock sequence, recaptured
  `preflight_after_wake_unlock` as the NextE Image blocks page, installed the signed HAP, clicked `复制社区规则草稿`, and
  returned `settings_contribution_draft_clicked`. The 197 visible PNG screenshot stayed on the Image blocks page after
  the click; `toastVisible=false` only means the toast was not present in that one-second layout capture. Local artifacts:
  `.hvigor/outputs/image-block-settings-edge-197-wake-unlock-script/summary.json`,
  `.hvigor/outputs/image-block-settings-edge-197-wake-unlock-script/wake-unlock.json`,
  `.hvigor/outputs/image-block-settings-edge-197-wake-unlock-script/wake-unlock-result.json`,
  `.hvigor/outputs/image-block-settings-edge-197-wake-unlock-script/preflight_after_wake_unlock.json`, and
  `.hvigor/outputs/image-block-settings-edge-197-wake-unlock-script/draft_wait_0.png`.
- Structured sourcePage copy-draft QA passed on 197 with the signed HAP:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --settings-edge --copy-draft
  --artifact-dir .hvigor/outputs/image-block-settings-edge-sourcepage-197` installed the signed build, opened the
  seeded Image blocks settings route, verified the contribution draft row, clicked `复制社区规则草稿`, and returned
  `settings_contribution_draft_clicked`. This run pairs with the static app-shaped JSONL dry-run in
  the rules-repo fixture path, which now feeds `sourceUrl` plus `sourcePage` to the rules repo
  importer and requires `new=1 duplicateExisting=0 duplicateIncoming=0 invalid=0`. Local artifacts:
  `.hvigor/outputs/image-block-settings-edge-sourcepage-197/summary.json`,
  `.hvigor/outputs/image-block-settings-edge-sourcepage-197/draft_wait_0.json`, and
  `.hvigor/outputs/image-block-settings-edge-sourcepage-197/draft_wait_0.png`.
- 197 visible UI note: `snapshot_display` returned black frames on this target even when layout showed the NextE
  settings page. For UI evidence, use `uitest screenCap -p` after keeping the display awake. The captured settings page
  shows `本地手动屏蔽`, `复制社区规则草稿`, `1/3`, `缺少来源`, `重复`, all three local rule rows, and the allowlist section.
  Local artifacts:
  `.hvigor/outputs/image-block-settings-edge-197-after-unlock/visible_screenCap.json` and
  `.hvigor/outputs/image-block-settings-edge-197-after-unlock/visible_screenCap.png`.
- Seeded direct Reader QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock` installed the signed build,
  opened `nexte://qa/image-block-seed-reader`, and returned `reader_block_placeholder_visible`. The PNG evidence shows
  the centered `图片已隐藏` placeholder, explanatory copy, `P1`, and `允许此图` action without black-frame capture or
  navigation-bar overlap. Local artifacts:
  `.hvigor/outputs/image-block-seeded-reader-197-wake-unlock-direct/summary.json`,
  `.hvigor/outputs/image-block-seeded-reader-197-wake-unlock-direct/after_start.json`, and
  `.hvigor/outputs/image-block-seeded-reader-197-wake-unlock-direct/after_start.png`.
- Visible blurred blocked-placeholder QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --artifact-dir
  .hvigor/outputs/image-block-blur80-visible-native-button-197` installed the signed build, opened the seeded
  direct Reader route, and returned `reader_block_placeholder_visible`. The PNG evidence shows the blocked image is
  only used as a visible blurred Reader image surface, not a full-screen cover background or black canvas; the content
  is unreadable while the central warning icon, `图片已隐藏`, `P1`, and the native default text button `允许此图` remain
  readable and tappable. Local artifacts:
  `.hvigor/outputs/image-block-blur80-visible-native-button-197/summary.json`,
  `.hvigor/outputs/image-block-blur80-visible-native-button-197/after_start.json`, and
  `.hvigor/outputs/image-block-blur80-visible-native-button-197/after_start.png`.
- Seeded Reader allowlist QA also passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --allow-and-verify` tapped the
  visible `允许此图` action at `(630,1583)` and returned `reader_allowlist_image_visible`. The PNG evidence shows the
  original page image rendered again after allowlisting. Local artifacts:
  `.hvigor/outputs/image-block-allowlist-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-allowlist-197-wake-unlock/allow-click.json`,
  `.hvigor/outputs/image-block-allowlist-197-wake-unlock/allow_wait_0.json`, and
  `.hvigor/outputs/image-block-allowlist-197-wake-unlock/allow_wait_0.png`.
- Seeded Reader allowlist settings/deletion QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --allow-and-verify
  --verify-settings-after-allow --delete-whitelist --artifact-dir
  .hvigor/outputs/image-block-allowlist-delete-197-wake-unlock` tapped `允许此图`, reopened the non-seeding Image blocks
  settings route, clicked the visible allowlist trash action at `(1130,1865)`, confirmed the native `删除` dialog at
  `(898,1417)`, and returned `reader_allowlist_deleted`. The before/after screenshots show `误杀放行图片 = 1` with the
  `已放行图片 / pHash ce9e...3cd5` row, then `误杀放行图片 = 0` after deletion while `本地手动屏蔽 = 1` and the
  `scanlator-ad / P1` local rule remain. This validates the allowlist cleanup path without deleting the underlying
  local block rule. Local artifacts:
  `.hvigor/outputs/image-block-allowlist-delete-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-allowlist-delete-197-wake-unlock/allow_settings_wait_0.png`,
  `.hvigor/outputs/image-block-allowlist-delete-197-wake-unlock/whitelist-delete-click.json`,
  `.hvigor/outputs/image-block-allowlist-delete-197-wake-unlock/whitelist-delete-confirm-click.json`,
  `.hvigor/outputs/image-block-allowlist-delete-197-wake-unlock/whitelist_delete_alert.png`, and
  `.hvigor/outputs/image-block-allowlist-delete-197-wake-unlock/whitelist_delete_wait_0.png`.
- Follow-up allowlist delete -> Reader re-block QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --allow-and-verify
  --verify-settings-after-allow --delete-whitelist --verify-block-after-whitelist-delete --artifact-dir
  .hvigor/outputs/image-block-allowlist-delete-reblock-197-wake-unlock` first proved the allowlist escape restored the
  original image, then deleted the allowlist row from settings, reopened `nexte://qa/image-block-seed-reader`, and
  returned `reader_block_after_whitelist_delete_visible`. The final screenshot shows the same page hidden again with
  `图片已隐藏`, `P1`, and `允许此图`, proving allowlist cleanup restores the pHash block decision rather than only removing
  settings UI state. Local artifacts:
  `.hvigor/outputs/image-block-allowlist-delete-reblock-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-allowlist-delete-reblock-197-wake-unlock/allow_wait_0.png`,
  `.hvigor/outputs/image-block-allowlist-delete-reblock-197-wake-unlock/whitelist_delete_wait_0.png`,
  `.hvigor/outputs/image-block-allowlist-delete-reblock-197-wake-unlock/block-after-whitelist-aa-start.txt`, and
  `.hvigor/outputs/image-block-allowlist-delete-reblock-197-wake-unlock/block_after_whitelist_wait_0.png`.
- Manual-mark QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --manual-mark
  --verify-settings-after-mark --artifact-dir .hvigor/outputs/image-block-manual-mark-settings-197-wake-unlock-toolbar-center`
  opened the non-seeded manual Reader route, clicked the Reader bottom toolbar's `eye_slash` manual-block action at
  `(266,2505)`, returned `reader_manual_mark_settings_visible`, and verified both the immediate `图片已隐藏` Reader
  placeholder and the non-seeding Image blocks settings reopen. The settings capture shows `本地手动屏蔽 = 1`,
  `复制社区规则草稿 = 1/1`, and the `scanlator-ad / P1` local rule with pHash `ce9e...3cd5` plus the stable gallery
  review URL. Local artifacts:
  `.hvigor/outputs/image-block-manual-mark-settings-197-wake-unlock-toolbar-center/summary.json`,
  `.hvigor/outputs/image-block-manual-mark-settings-197-wake-unlock-toolbar-center/manual-mark-click.json`,
  `.hvigor/outputs/image-block-manual-mark-settings-197-wake-unlock-toolbar-center/manual_mark_wait_0.png`, and
  `.hvigor/outputs/image-block-manual-mark-settings-197-wake-unlock-toolbar-center/manual_settings_wait_0.png`.
- Manual local-rule deletion QA also passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --manual-mark
  --verify-settings-after-mark --delete-local-rule --artifact-dir .hvigor/outputs/image-block-manual-delete-197-wake-unlock`
  created the same non-seeded manual rule, reopened Image blocks settings, clicked the visible local-rule trash action
  at `(1130,1393)`, confirmed the native `删除` dialog at `(898,1447)`, and returned
  `reader_manual_mark_rule_deleted`. The final settings screenshot shows `本地手动屏蔽 = 0`, `误杀放行图片 = 0`, and no
  `复制社区规则草稿`, `scanlator-ad / P1`, or `ce9e...3cd5` row. Local artifacts:
  `.hvigor/outputs/image-block-manual-delete-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-manual-delete-197-wake-unlock/local-rule-delete-click.json`,
  `.hvigor/outputs/image-block-manual-delete-197-wake-unlock/local-rule-delete-confirm-click.json`,
  `.hvigor/outputs/image-block-manual-delete-197-wake-unlock/local_rule_delete_alert.png`, and
  `.hvigor/outputs/image-block-manual-delete-197-wake-unlock/local_rule_delete_wait_0.png`.
- Follow-up manual local-rule delete -> Reader restore QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --manual-mark
  --verify-settings-after-mark --delete-local-rule --verify-image-after-local-rule-delete --artifact-dir
  .hvigor/outputs/image-block-manual-delete-unblock-197-wake-unlock-final` created a non-seeded manual rule, deleted it
  from the non-seeding Image blocks settings route, reopened `nexte://qa/image-block-reader-open`, and returned
  `reader_image_after_local_rule_delete_visible`. The final Reader layout contains a real image node and no `图片屏蔽`,
  `本地手动屏蔽`, `误杀放行图片`, `图片已隐藏`, or `允许此图` text, proving local-rule cleanup restores the Reader decision
  rather than only removing the settings row. Local artifacts:
  `.hvigor/outputs/image-block-manual-delete-unblock-197-wake-unlock-final/summary.json`,
  `.hvigor/outputs/image-block-manual-delete-unblock-197-wake-unlock-final/local_rule_delete_wait_0.png`,
  `.hvigor/outputs/image-block-manual-delete-unblock-197-wake-unlock-final/image-after-local-rule-aa-start.txt`, and
  `.hvigor/outputs/image-block-manual-delete-unblock-197-wake-unlock-final/image_after_local_rule_wait_0.png`.
- Subscription-provider Reader QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --subscription
  --verify-settings-after-subscription --artifact-dir
  .hvigor/outputs/image-block-subscription-reader-settings-197-wake-unlock` opened the subscription-seeded Reader route
  and returned `reader_subscription_settings_visible`. The Reader screenshot shows `图片已隐藏`, `P1`, and `允许此图`;
  the follow-up non-seeding Image blocks settings screenshot shows the enabled `Chinese scanlator ads` provider,
  `1/1 / 1`, `本地手动屏蔽 = 0`, and `误杀放行图片 = 0`, proving subscription storage/provider enablement can drive the
  Reader block decision without a local rule or allowlist row. Local artifacts:
  `.hvigor/outputs/image-block-subscription-reader-settings-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-subscription-reader-settings-197-wake-unlock/after_start.png`,
  `.hvigor/outputs/image-block-subscription-reader-settings-197-wake-unlock/subscription-settings-aa-start.txt`, and
  `.hvigor/outputs/image-block-subscription-reader-settings-197-wake-unlock/subscription_settings_wait_0.png`.
- Real community refresh QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --settings-refresh
  --artifact-dir .hvigor/outputs/image-block-settings-refresh-197-wake-unlock` opened
  `nexte://qa/image-block-settings-refresh`, verified the provider reset state (`Chinese scanlator ads`, `0 条规则`,
  `1/1 / 0`, local rules `0`, allowlist `0`), clicked the real `更新社区规则` row, and returned
  `settings_subscription_update_visible` after the UI changed to `1 条规则` and `1/1 / 1`. Local artifacts:
  `.hvigor/outputs/image-block-settings-refresh-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-settings-refresh-197-wake-unlock/after_start.png`,
  `.hvigor/outputs/image-block-settings-refresh-197-wake-unlock/settings-refresh-click.json`, and
  `.hvigor/outputs/image-block-settings-refresh-197-wake-unlock/settings_refresh_wait_0.png`.
- Real community refresh -> Reader block QA passed on 197 with the signed HAP and `--wake-unlock`:
  `scripts/qa_image_block_seeded_reader.mjs --target 192.168.50.197:12345 --wake-unlock --settings-refresh
  --verify-block-after-settings-refresh --artifact-dir
  .hvigor/outputs/image-block-settings-refresh-reader-197-wake-unlock` first proved the visible provider update from
  `1/1 / 0` to `1/1 / 1`, then opened `nexte://qa/image-block-reader-open` without seeding or cleaning rules and
  returned `reader_block_after_settings_refresh_visible`. This proves the live GitHub feed update reaches
  `ImageBlockRuntimeService` decisions, not just the settings counters. Local artifacts:
  `.hvigor/outputs/image-block-settings-refresh-reader-197-wake-unlock/summary.json`,
  `.hvigor/outputs/image-block-settings-refresh-reader-197-wake-unlock/settings_refresh_wait_0.png`,
  `.hvigor/outputs/image-block-settings-refresh-reader-197-wake-unlock/block-after-settings-refresh-aa-start.txt`, and
  `.hvigor/outputs/image-block-settings-refresh-reader-197-wake-unlock/block_after_settings_refresh_wait_0.png`.
- Seeded settings-edge copy-draft QA passed on local emulator `127.0.0.1:5557` with the signed HAP:
  `scripts/qa_image_block_seeded_reader.mjs --target 127.0.0.1:5557 --settings-edge --copy-draft` installed the signed
  build, opened `nexte://qa/image-block-settings-edge`, verified the updated `本地手动屏蔽` / `复制社区规则草稿` wording,
  showed `1/3` submit-ready rules plus missing-source and duplicate skipped reasons, clicked the community-draft row,
  and returned `settings_contribution_draft_clicked` with `toastVisible=true`. Local artifacts:
  `.hvigor/outputs/image-block-settings-edge-5557-manual-labels/summary.json`,
  `.hvigor/outputs/image-block-settings-edge-5557-manual-labels/settings_wait_0.json`,
  `.hvigor/outputs/image-block-settings-edge-5557-manual-labels/settings_wait_0.jpeg`,
  `.hvigor/outputs/image-block-settings-edge-5557-manual-labels/draft_wait_0.json`, and
  `.hvigor/outputs/image-block-settings-edge-5557-manual-labels/draft_wait_0.jpeg`.
- After switching the QA script to `uitest screenCap`, the same 5557 path passed again and produced PNG screenshots:
  `.hvigor/outputs/image-block-settings-edge-5557-screencap-pass/summary.json` and
  `.hvigor/outputs/image-block-settings-edge-5557-screencap-pass/draft_wait_0.png`.

## Follow-ups / Reference

These are not a scheduling queue. Use the user's latest request and `product-bug-intake.md` for planning.

1. Image-block sample verification on real galleries containing external scanlator-ad pages.
   - Current seeded community sample: `https://e-hentai.org/g/3049882/d7e740a39e/`, page 1, pHash
     `ce9e181d354a3cd5`.
   - 197 device note: settings/manual-rule UI, copy-draft click, Reader placeholder, Reader allowlist,
     allowlist settings visibility/deletion, the non-seeded manual-mark-to-settings path, local manual-rule
     deletion, manual delete -> Reader restore, subscription provider -> Reader block, real community refresh, and
     real community refresh -> Reader block now have signed-build passes with `--wake-unlock`.
   - Additional sample candidates should prefer gallery titles/tags that explicitly indicate advertisement/external
     pages, but current public checks found title-search candidates rather than a stable advertisement namespace tag.
     Promote only stable, reviewable gallery URLs plus reviewed page pHashes into the rules repository.
2. Seeded Reader QA path exists; rerun it only when image-block behavior changes.
   - Static precursor added: `docs/fixtures/image-block-public-samples.json` plus
     rules-repo fixture review keeps the seed gallery, seed pHash, manifest URL, and rules-repo dist
     output aligned before the device path is re-run.
   - Device precursor added: `scripts/qa_image_block_seeded_reader.mjs` uses the hidden seed routes and signed HAP,
     passes on the local emulator, and exits before install if 197 is still on the lockscreen.
3. Home EventPane / HentaiVerse reminder.
4. Add Reader touch-region ratios and a visual touch-area guide.
5. Add No Image Mode as a privacy/bandwidth toggle.
6. Park super-resolution, Archive Bot, and download-heavy JHenTai ideas for later lanes.

## Deferred

- Blur/HDS floating-control presentation for blocked pages.
- Local rule submission / one-tap PR UI.
- QR-code auto blocking.
- Region/crop matching.
- Signed feed metadata.
- BK-tree/hash index.
- Backend submission service, voting, and bot moderation.
