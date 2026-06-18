# Project current state and next plan

- **status**: ACTIVE
- **owner**: controller / project lead
- **updated**: 2026-06-18 08:03:05 +0800
- **purpose**: single scheduling snapshot after the Mac migration and the latest list responsive-cover gate.

This document is a planning control surface, not an acceptance archive. Existing active plans remain queues. Historical PASS logs, worker summaries, and old screenshots are useful evidence, but they do not equal current controller acceptance.

## Standing constraints

```text
- State Management V2 only. No V1 decorators in entry/, feature/, or shared/.
- Do not delete, move, overwrite, or clean untracked/ignored docs, plans, harness state, screenshots, fixtures, local profiles, or worktrees.
- Do not push, merge, tag, or delete worktrees without explicit controller/user authorization.
- Do not treat historical Linux paths as local Mac paths.
- Do not treat source-only checks such as borderRadius/clip as visual acceptance.
- Screenshots and device evidence must be deliverable to controller/user, not only left as local paths.
- On macOS, do not use dev.sh for normal build/signing. Use official DevEco/Hvigor and build-profile signing.
- hdc commands must run outside the Codex sandbox, serially, with the current target explicitly selected.
```

## Current machine and migration delta

Current local machine facts:

```text
host:             macOS
home:             /Users/honjow
primary repo:     /Users/honjow/git/NextE
worktree root:    /Users/honjow/git/NextE-wt
eros_fe ref:      /Users/honjow/git/eros_fe
V2Next ref:       /Users/honjow/git/V2Next
harmony skills:   /Users/honjow/git/harmony-next.skills
DevEco Studio:    /Applications/DevEco-Studio.app
```

Migration consequences:

```text
- Old Linux-path evidence may appear in historical docs, but it is not a local path on this Mac.
- Local responsive QA should prefer the Mate X7 foldable emulator and Mate Pad Mini emulator when available.
- hdc port identity must be verified each session; do not infer device identity from port alone.
- hdc must not be run inside the Codex sandbox. Sandbox HDC failures can masquerade as device/server failures.
- macOS signing/build should use the official DevEco/Hvigor build-profile flow, not Linux helper scripts.
- Local signing material is represented by ignored build-profile.local.json5 installed into build-profile.json5 with skip-worktree protection.
```

## Repository snapshot

Controller checkout at the start of this snapshot update:

```text
repo:   /Users/honjow/git/NextE
branch: main
base:   7b99bf5 docs(project): record false 404 smoke status
```

Current controller checkout status:

```text
Clean and in sync with origin/main at this snapshot.
```

Control-plane/project assets, screenshots, harness state, worktrees, local profiles, and old WIP remain
protected. Do not clean or discard them.

Known worktrees:

```text
/Users/honjow/git/NextE-wt/auth-cookie-login        agent/claude/auth-cookie-login      ahead 2, behind 12, preserved historical WIP
/Users/honjow/git/NextE-wt/auth-cookie-login-rebase agent/codex/auth-cookie-login-rebase 58e48ba, merged to origin/main
/Users/honjow/git/NextE-wt/device-lease             agent/codex/device-lease            behind main, clean
/Users/honjow/git/NextE-wt/detail-visual-reqa       agent/codex/detail-visual-reqa      0652a05, merged to origin/main
/Users/honjow/git/NextE-wt/list-responsive-cover    agent/codex/list-responsive-cover   11069a5, merged to origin/main
/Users/honjow/git/NextE-wt/logic-subtab-loading     agent/claude/logic-subtab-loading   behind main, clean
/Users/honjow/git/NextE-wt/mac-harness-signing      agent/codex/mac-harness-signing     4ab2367, merged to origin/main
/Users/honjow/git/NextE-wt/subtab-never-loaded-flash agent/codex/subtab-never-loaded-flash b3d9e5d, merged to origin/main
/Users/honjow/git/NextE-wt/ui-detail-preview-audit  agent/codex/ui-detail-preview-audit behind main, clean
```

Do not reuse old worktrees for new product lanes. Rebase/review old lanes only when that lane is explicitly resumed.

## Active queues

### 1. List responsive cover hard gate

Status: **merged and pushed to origin/main; controller acceptance still active**

Location:

```text
worktree: /Users/honjow/git/NextE-wt/list-responsive-cover
branch:   agent/codex/list-responsive-cover
commit:   11069a5 fix(list): make gallery card covers pane-responsive
```

Why it is first-priority:

```text
- It is the freshest user-reported hard product issue.
- It affects top-level gallery list usability on Mate X7 fold/unfold.
- The root cause was architectural: GalleryCard cached startup display size at module scope.
- It crosses Home/Search/Favorites list surfaces.
- It must be resolved before treating lower-priority visual polish as stable on foldables.
```

Candidate state:

```text
- GalleryCard no longer reads display.getDefaultDisplaySync() or caches _coverW.
- PullRefreshListScaffold measures current list content width via onAreaChange.
- Home/Search/Favorites pass measured listContentWidth to GalleryCard.
- Width semantics mirror eros_fe:
  narrow pane: contentWidth / 3
  wide pane:  0.7 * kFixedHeight = 142.8vp
  fixed row:  kFixedHeight = 204vp
- New deterministic gate: scripts/test_list_responsive_cover_contract.mjs.
- Signed HAP build, Mate X7 emulator validation, and Mate Pad Mini cold-start validation were completed in the worktree.
```

Current evidence:

```text
/private/tmp/nexte_list_responsive_cover_evidence/nexte_inner_cold.jpeg
/private/tmp/nexte_list_responsive_cover_evidence/nexte_outer_cold.jpeg
/private/tmp/nexte_list_responsive_cover_evidence/nexte_outer_to_inner.jpeg
/private/tmp/nexte_list_responsive_cover_evidence/nexte_inner_to_outer_pid_verified.jpeg
/private/tmp/nexte_list_responsive_cover_evidence/nexte_mate_pad_mini_cold.jpeg
```

Refreshed merge-readiness evidence from 2026-06-18, using the harmony-next skill's device-side
DisplayManagerService fold controls (`-p` folded/outer, `-y` expanded/inner, `-a` state dump);
all hdc commands were run outside the Codex sandbox:

```text
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_outer_cold.png
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_outer_cold_layout.json
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_inner_cold.png
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_inner_cold_layout.json
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_outer_to_inner.png
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_outer_to_inner_layout.json
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_inner_to_outer.png
/private/tmp/nexte_lane_a_fold_evidence/nexte_lane_a_inner_to_outer_layout.json
```

Observed state evidence:

```text
Outer/folded:  PhysicalFoldStatus=FOLDED, DisplayFoldStatus=FOLDED, display 1080 x 2444.
Inner/expanded: PhysicalFoldStatus=EXPAND, DisplayFoldStatus=EXPAND, display 2210 x 2416.
Inner -> outer same-process pid stayed 9633.
Outer -> inner same-process pid stayed 9874.
```

Current merge status:

```text
Merged to main and pushed:
11069a5 fix(list): make gallery card covers pane-responsive

Controller still needs to review the diff and Mate X7 evidence before marking the active queue accepted.
If rejected, follow-up fixes stay inside a new responsive/list lane and must not mix with auth or detail visual work.
```

### 2. Mac harness/build-signing normalization

Status: **merged and pushed to origin/main**

Location:

```text
worktree: /Users/honjow/git/NextE-wt/mac-harness-signing
branch:   agent/codex/mac-harness-signing
commit:   4ab2367 chore(mac): use official hvigor signing in harness
```

Why it matters:

```text
- Future Mac workers must not use Linux-only dev.sh for normal build/signing.
- build-profile.json5 already defines signingConfigs on this machine through the local-profile flow.
- Harness/pre-commit paths must not fall back to stale /home/gamer locations.
```

Candidate state:

```text
- .harness/config.json buildCmd uses scripts/build_hvigor_signed.sh.
- scripts/build_hvigor_signed.sh uses official hvigorw assembleHap debug flow and refuses missing signingConfigs.
- .harness/hooks/pre-commit fails clearly if harness-verify is not installed in PATH instead of probing old Linux paths.
- README, CLAUDE, and docs/loop document macOS official build/signing flow and label dev.sh as Linux legacy.
- New deterministic gate: scripts/test_mac_harness_signing_contract.mjs.
```

Validation already run:

```text
- node scripts/test_mac_harness_signing_contract.mjs
- node scripts/test_v1_decorator_inventory_contract.mjs
- node scripts/test_version_consistency.mjs
- node scripts/test_secret_safety.mjs
- node scripts/test_i18n_parity.mjs
- git diff --check
- bash scripts/build_hvigor_signed.sh
```

Current merge status:

```text
Merged to main and pushed:
4ab2367 chore(mac): use official hvigor signing in harness

This is tooling/control-plane only; it was not mixed with auth or visual product patches.
```

### 3. Gate V2 subtab/search reload terminal-copy gate

Status: **merged and pushed to origin/main; controller acceptance still active**

Location:

```text
worktree: /Users/honjow/git/NextE-wt/subtab-never-loaded-flash
branch:   agent/codex/subtab-never-loaded-flash
commit:   b3d9e5d fix(search): keep reload footer in loading state
```

Why it matters:

```text
- The reopened visual/navigation contract says never-loaded or reloading selector surfaces must not flash
  terminal empty/no-more copy before loading.
- Home and Favorites already had loaded/loadedOnce gates and page-level loading footers.
- Search/filter reload preserved old rows but its footer only watched isLoadingMore, so a page-level
  search/filter reload with old rows could flash "没有更多了" while the replacement request was in flight.
```

Candidate state:

```text
- GallerySearchPage LoadingFooter now counts vm.isLoadingMore || vm.isLoading.
- scripts/test_selector_reload_preserves_content_contract.mjs now asserts Search footer page-level loading.
- No auth-cookie-login, detail preview, list-responsive-cover, or harness changes are mixed into this lane.
```

Validation already run:

```text
- node scripts/test_selector_reload_preserves_content_contract.mjs
- node scripts/test_retained_tab_contract.mjs
- node scripts/test_v1_decorator_inventory_contract.mjs
- git diff --check
- official DevEco/Hvigor build:
  env JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home ... hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

Build note:

```text
The first Hvigor run reached ArkTS compile but failed at PackageHap because Java runtime was not located.
The rerun with DevEco Studio's bundled JBR completed PackageHap and SignHap successfully.
No dev.sh command was used.
```

Required next acceptance action:

```text
Controller reviews the narrow Search footer diff, contracts, and the current reachable device re-QA evidence.
Do not mark the full V2 queue accepted until Search/filter and Favorites logged-in cases are reachable.
```

Current reachable device re-QA from 2026-06-18:

```text
Target: 127.0.0.1:5555 Mate X7 emulator; every hdc command ran outside the Codex sandbox.

Home:
  - default list loaded with real rows, no terminal empty/no-more copy.
  - default -> popular subtab switch captured immediately and after settle.
  - settled popular layout has rows and no "没有数据/没有更多了".

Toplist:
  - all period loaded with real rows, no terminal empty/no-more copy.
  - all -> year period switch captured immediately and after settle.
  - settled year layout has rows and no "没有数据/没有更多了".

Contracts:
  - node scripts/test_selector_reload_preserves_content_contract.mjs PASS
  - node scripts/test_retained_tab_contract.mjs PASS
  - node scripts/test_v1_decorator_inventory_contract.mjs PASS, 0 file(s)

Evidence:
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_home.png
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_home_layout.json
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_home_hot_immediate.png
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_home_hot_after.png
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_home_hot_layout.json
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_toplist.png
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_toplist_layout.json
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_toplist_year_immediate.png
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_toplist_year_after.png
  - /private/tmp/nexte_lane_continuation_probe/nexte_req_toplist_year_layout.json

Still open:
  - Search/filter visual re-QA remains blocked by the system Xiaoyi IME first-run privacy page.
  - Favorites favcat/order re-QA still needs a safe logged-in app state; the current run could not
    prove one, and Codex did not request or type cookies.
```

### 4. Detail visual re-QA preview-grid comfort gate

Status: **merged and pushed to origin/main; controller acceptance still active**

Location:

```text
worktree: /Users/honjow/git/NextE-wt/detail-visual-reqa
branch:   agent/codex/detail-visual-reqa
commit:   0652a05 fix(gallery): restore comfortable preview grid width
```

Why it matters:

```text
- Current source failed the existing responsive-grid contract before any code change.
- The failure reproduced the reopened visual concern: a 420vp-class detail preview pane resolved to 4
  too-narrow columns instead of the expected comfortable 3 columns.
- Root cause was token drift: ThemeConstants.PREVIEW_THUMB_MIN_W had fallen to 90vp while the contract
  and historical correction require 105vp.
```

Candidate state:

```text
- ThemeConstants.PREVIEW_THUMB_MIN_W is restored from 90vp to 105vp.
- No hardcoded column count was introduced; ResponsiveGrid still derives columns from pane width.
- No list-card, auth-cookie-login, Search footer, or harness changes are mixed into this lane.
```

Validation already run:

```text
- node scripts/test_responsive_grid_contract.mjs
- node scripts/test_thumbnail_mode_contract.mjs
- node scripts/test_cover_presentation_contract.mjs
- node scripts/test_detail_header_visual_contract.mjs
- node scripts/test_tag_chip_contract.mjs
- node scripts/test_v1_decorator_inventory_contract.mjs
- git diff --check
- official DevEco/Hvigor signed build with DevEco JBR:
  env JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home ... hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

Device evidence status:

```text
CORRECTED. The earlier `Connect server failed` diagnosis was an operator/tooling mistake: hdc had been
run inside the Codex sandbox. After switching to sandbox-external hdc, the current target was verified:
127.0.0.1:5555 TCP Connected, boot=true.

The signed HAP already installed on the target was launched through a public gallery deep link:
https://e-hentai.org/g/3989982/16600a66e8/

Current deliverable evidence:
/private/tmp/nexte_lane_d_detail_visual_evidence/nexte_lane_d_detail.png
/private/tmp/nexte_lane_d_detail_visual_evidence/nexte_lane_d_detail_layout.json
/private/tmp/nexte_lane_d_detail_visual_evidence/nexte_lane_d_allthumbs.png
/private/tmp/nexte_lane_d_detail_visual_evidence/nexte_lane_d_allthumbs_layout.json
```

Required next acceptance action:

```text
Merged to main and pushed:
0652a05 fix(gallery): restore comfortable preview grid width

Controller still needs to review the current detail page and AllThumbnails screenshots, plus the narrow token
diff and deterministic contracts. If rejected, return exact visual objections and keep follow-up fixes inside a
detail visual lane.
```

### 5. Gallery visual/controller work order

Status: **ACTIVE queue, not globally accepted**

Source:

```text
docs/plans/active/controller-work-order-gallery-visual.md
docs/plans/active/gallery-visual-navigation-regression-contract.md
```

Current active meaning:

```text
- Gate V1 detail thumbnail/cover presentation remains a visual acceptance queue.
- Gate V2 subtab never-loaded empty/no-more flash remains a P0 behavior queue.
- Gate V3 re-audits prior visual/navigation claims.
- gallery-visual-navigation-regression-contract.md explicitly says prior PASS/archive claims are invalid unless re-backed by current controller evidence.
```

Important boundary:

```text
Do not fold list-responsive-cover into Gate V1. Gate V1 is detail-page thumbnail/header/preview surfaces. List-page GalleryCard responsive sizing is its own hard gate.
```

### 6. Cookie login function gate

Status: **merged and pushed to origin/main; real-cookie success verification remains user/manual**

Source:

```text
docs/plans/active/cookie-login-function-gate.md
original worktree: /Users/honjow/git/NextE-wt/auth-cookie-login
merged worktree:   /Users/honjow/git/NextE-wt/auth-cookie-login-rebase
merged commit:     58e48ba fix(auth): sync logout state before persistence cleanup
```

Old preserved WIP files in the original worktree:

```text
feature/settings/src/main/ets/pages/SettingsPage.ets
scripts/test_cookie_import_contract.mjs
shared/src/main/ets/settings/CookieJarSettings.ets
```

Boundary:

```text
- Do not touch or clean the old WIP from visual/layout lanes.
- Do not request or print cookies.
- Do not reintroduce bundled/session auto-login.
- Route/UI/empty-input behavior was emulator-verified. Real successful import remains USER_MANUAL_REQUIRED.
- Auth completion unlocks follow-up ExHentai/Sad Panda/donor/permission matrix, but controller must not receive cookie values.
```

### 6a. False-404 / auth matrix follow-up

Status: **PARTIAL logged-out smoke complete; full matrix still active**

Current Mac smoke evidence:

```text
Target: 127.0.0.1:5555 Mate X7 emulator, hdc run outside the Codex sandbox.
Deep link: https://e-hentai.org/g/1/0000000000/
Displayed result: "无法解析此页面,应用可能需要更新。" + retry.
Important negative result: no user-facing "404" was shown for this logged-out invalid public-gallery case.

Evidence:
/private/tmp/nexte_lane_f_false_404_evidence/nexte_lane_f_false_404.png
/private/tmp/nexte_lane_f_false_404_evidence/nexte_lane_f_false_404_layout.json
```

Limitations:

```text
- This proves only the displayed text for one logged-out non-auth case.
- Bounded hilog tail did not capture a useful NextE classifier line, so do not over-claim log coverage.
- True HTTP 404, ExHentai/Sad Panda, donor/permission, MaybeHidden, and logged-in auth matrix cases remain active.
- Full matrix depends on a safe user-driven login state. Codex must not request, receive, type, log, or screenshot raw cookie values.
```

### 7. Older clean worktrees

Status: **not active by default**

```text
logic-subtab-loading: clean but behind current main; do not assume accepted.
ui-detail-preview-audit: clean but behind current main; do not assume accepted.
device-lease: clean but behind current main; device-lease guidance exists, but current local emulator QA changes scheduling assumptions.
```

## Main risks

1. **Acceptance drift**

Historical PASS entries are mixed with reopened active audit language. The controller must treat active plan items as queues until current evidence closes each item.

2. **Visual evidence weakness**

Contracts can reject obvious regressions, but loaded/loading/error/light/dark and fold/unfold visual behavior still need device screenshots or video.

3. **Lane contamination**

auth-cookie-login, list-responsive-cover, detail visual re-QA, and subtab behavior can touch overlapping shared UI/settings files. Worktrees must stay isolated until reviewed.

4. **Mac migration tooling drift**

Paths, build helpers, hdc targets, and harness hooks may still reflect the old desktop. On macOS, use official DevEco/Hvigor flow and verify local tool paths before claiming build/device gates. hdc must be run outside the Codex sandbox; sandbox failures should not be recorded as emulator/HDC server defects.

5. **Signing and secret safety**

Local build profiles can contain signing material. Do not print profile contents, commit them, or rely on `.gitignore` as package-safety proof.

6. **Foldable/tablet layout semantics**

Phone-only assumptions such as startup shortest-side sizing are invalid on Mate X7 inner/outer screens and tablet panes. Current pane/container metrics must drive responsive UI.

7. **State Management V1 regression**

Any ArkTS/UI/state lane must run `node scripts/test_v1_decorator_inventory_contract.mjs` and report 0.

## Recommended lane split

### Lane A — list-responsive-cover acceptance

Goal:

```text
Accept or reject the current responsive list-card candidate.
```

Scope:

```text
- GalleryCard list cover sizing only.
- PullRefreshListScaffold measured-width plumbing.
- Home/Search/Favorites GalleryCard call sites.
- Deterministic list-responsive-cover contract.
- Mate X7 outer/inner cold start + same-process fold/unfold evidence.
```

Out of scope:

```text
- auth-cookie-login
- detail preview/header re-QA
- false-404/auth matrix
- destructive EH writes
- broad visual redesign
```

First action:

```text
Controller reviews the existing worktree and evidence, then either authorizes local merge or returns exact visual/source objections.
```

### Lane B — Mac harness/build-signing normalization

Goal:

```text
Make Mac-native validation commands explicit and reliable for all future workers.
```

Scope:

```text
- Document official Hvigor/DevEco signing/build command shape.
- Verify harness/pre-commit paths do not point to the old desktop.
- Keep local build-profile secrets ignored and skip-worktree protected.
```

First action:

```text
Controller reviews the existing worktree and decides whether this should merge immediately after Lane A.
```

Out of scope:

```text
- product code changes
- auth UI
- visual fixes
```

### Lane C — Gate V2 subtab never-loaded flash / stale-body behavior

Goal:

```text
Reproduce and gate the current subtab empty/no-more flash issue under the reopened controller rules.
```

Scope:

```text
- Home source, Toplist period, Favorites favcat/order, Search/filter if reachable.
- Deterministic loaded-state contract.
- Device video/screenshots.
```

Dependency:

```text
Can start after Lane A is accepted or explicitly parked, to avoid confusing list-card responsive changes with loading-state visual changes.
If Lane B is accepted first, use its normalized Mac build flow for device verification.
```

### Lane D — Gate V1/V3 detail visual re-QA

Goal:

```text
Produce a current accepted/rejected matrix for detail header cover, preview grid, horizontal preview, all-thumbnails, long-title/action states, and tag chips.
```

Scope:

```text
- Current source and current device screenshots only.
- No source-only acceptance.
- Each subitem marked ACCEPTED / OPEN / OUT_OF_SCOPE.
```

Dependency:

```text
Run after the responsive list gate is no longer the freshest blocking layout issue.
```

### Lane E — auth-cookie-login

Goal:

```text
Complete the safe manual Cookie import/login path without leaking secrets.
```

Scope:

```text
- Settings/account import UI.
- CookieJarSettings/EhCookieStore/AuthState.
- Redaction and secret-safety contracts.
```

Dependency:

```text
Separate from visual lanes. Needed before full logged-in/ExHentai/permission matrix can be accepted.
```

### Lane F — false-404/auth matrix follow-up

Goal:

```text
Re-verify truthful error classification under logged-in and ExHentai cases.
```

Dependency:

```text
Requires auth lane or user-driven login state. Do not ask for cookies in chat.
```

First action:

```text
If the controller supplies a safe already-logged-in app state, run the full ExHentai/Sad Panda/donor/permission
matrix with screenshot/layout/log evidence. Without that state, continue the non-auth visual/navigation re-QA
queues instead of blocking the whole project.
```

## Post-stabilization eros_fe feature lanes

The queues above are stabilization and acceptance work. They do not replace the product roadmap. After the current hard gates are accepted or explicitly parked, NextE still needs feature-depth development against eros_fe. These lanes should get their own active plans before implementation; do not mix them into visual/regression fixes.

### Feature Lane 1 — Auth foundation completion

Purpose:

```text
Complete the login foundation that unlocks authenticated parity work.
```

Scope:

```text
- Manual Cookie import UI and validation.
- WebView login path preservation.
- Complete cookie jar persistence through CookieJarSettings/EhCookieStore/AuthState.
- ExHentai igneous detection and site-switch gating.
- Secret-safety and HAP/package leakage gates.
```

Why first:

```text
Many eros_fe parity gaps cannot be honestly accepted while the app is logged out:
favorites, My Tags, ExHentai/Sad Panda, donor/permission states, favorite notes, usertag colors, and auth-specific false-404 cases.
```

### Feature Lane 2 — Search parity depth

Purpose:

```text
Move Search from a basic keyword/results page toward eros_fe's search workflow.
```

Candidate scope:

```text
- Tag autocomplete / tagsuggest with debounce on the last token.
- Local tag-translation-backed suggestions when the translation DB exists.
- QuickSearch saved-query state, list page, add/remove/clear affordances.
- Search type scoping: gallery / watched / favorites.
- Gallery URL paste detection and jump-to-gallery affordance.
- Image search route and upload flow, lower priority behind tagsuggest/QuickSearch.
```

Acceptance shape:

```text
Each subfeature needs eros_fe source grounding, deterministic contracts, and device evidence.
Do not fold all search parity into one broad patch.
```

### Feature Lane 3 — Favorites parity architecture

Purpose:

```text
Turn Favorites from a thin single-list surface into the eros_fe-style favorites workspace.
```

Candidate scope:

```text
- Per-favcat tab/page architecture with independent scroll and pagination state.
- Synthetic local favorites slot `l` with offline persistence.
- Favorites search mode with favorite-specific scope flags.
- Full favcat selector page with counts and colored hearts.
- Jump-to-page/date navigation and previous/next cursor support.
- Sort-order action in title bar, persisted and available in all layouts.
```

Dependency:

```text
Requires auth foundation for remote favorites. Local favorites can be designed separately but must not hide remote gaps.
```

### Feature Lane 4 — My Tags / usertag management parity

Purpose:

```text
Port the usertag/tagset management subsystem, not just the current read-only viewer.
```

Candidate scope:

```text
- Two-level structure: tagset list page -> usertag detail/manage page.
- Parse and render fillColor/borderColor/textColor/defaultColor correctly.
- Watch/hide/color/weight edit dialog via setusertag.
- Add/delete usertag with tagsuggest search.
- Create/rename/delete tagset with canDelete gating.
- Wire usertags into gallery tag coloring and hidden/watched tag behavior.
```

Risk:

```text
This lane includes destructive EH writes. Real submit actions need explicit authorization and non-destructive preview/cancel QA first.
```

### Feature Lane 5 — Download, archive, and offline reading

Purpose:

```text
Implement eros_fe's offline consumption path on HarmonyOS.
```

Candidate scope:

```text
- Download queue with pause/resume/delete and concurrency state.
- Per-image token handling and 509 retry through ImageResolveService.
- Archive request/poll/download flow.
- Offline reader source from downloaded files or archives.
- Storage/export UX using HarmonyOS-safe file APIs.
```

Risk:

```text
HarmonyOS background download behavior and cookie/token carrying need a spike before committing to the final implementation path.
```

### Feature Lane 6 — Comments, rating, and write operations

Purpose:

```text
Complete interaction surfaces that eros_fe supports but NextE currently treats as read-only or shallow.
```

Candidate scope:

```text
- Comment parser completeness: memberId, vote, canEdit, canVote, scoreDetails, local time, links.
- Full comments page and poster/uploader navigation.
- Gallery rating submit flow.
- Favorite add/remove/move with note editing.
- Tag edit/add actions.
```

Safety:

```text
All write operations are non-idempotent. Default QA is open-dialog/cancel or controlled test content only; real submits require explicit authorization.
```

### Feature Lane 7 — Sync and long-tail advanced features

Purpose:

```text
Cover eros_fe long-tail workflows after the core authenticated product is stable.
```

Candidate scope:

```text
- WebDAV sync for history/read progress/QuickSearch/custom groups.
- Custom profile/tab groups.
- Torrent/search-by-image/similar-search flows.
- Image blocking / pHash / QR-based filtering.
- EPUB export and update/about polish.
```

Default priority:

```text
Defer until the core authenticated browse/search/favorites/mytags/download lanes have acceptance evidence.
```

## First-stage dispatch recommendation

Start with **non-auth visual/navigation re-QA** until a safe user-driven login state exists, then resume
**Lane F: false-404/auth matrix follow-up**.

Rationale:

```text
- Lanes A-D have already been merged and pushed to origin/main with contracts, official signed builds, and device evidence where reachable.
- Lanes A-E have already been merged and pushed to origin/main with contracts, official signed builds, and device evidence where reachable.
- A safe manual Cookie import path now exists, but Codex cannot verify real successful import without a user-owned cookie.
- The latest run confirmed no safe logged-in state and the system IME privacy page blocks Search text entry.
- The next useful automatic proof is therefore more non-auth visual/navigation re-QA.
- Truthful error/auth matrix re-QA resumes after the user manually establishes login state.
- Do not request or print cookies; controller only needs screenshots/status from manual login import, never cookie values.
```

Concrete first-stage checklist:

```text
1. Continue non-auth visual/navigation re-QA that does not require text entry or login.
2. If user manually imports real cookies, collect only redacted app status/screenshots.
3. Re-run false-404/auth cases:
   - true HTTP 404
   - parse failure with HTTP 200
   - ExHentai/Sad Panda
   - donor/permission/member-only cases if reachable
4. Keep destructive EH writes out of scope.
5. Required gates before any follow-up merge:
   - error-classification contract
   - cookie import/roundtrip/secret-safety contracts
   - V1 decorator inventory
   - official DevEco/Hvigor signed build
   - device screenshots/log summaries with raw cookies redacted
```

## Authorization needed from user/controller

```text
- No authorization is needed for Codex to continue non-auth re-QA and commit/push control-plane docs under
  the current "完全授权" / continuous-progress instruction.
- User/controller action is still needed only to create a safe logged-in app state for full auth/ExHentai/Favorites
  matrix re-QA. Codex will not request, receive, type, log, or screenshot raw cookie values.
- If controller wants tablet-specific acceptance, specify whether Mate Pad Mini/tablet re-QA should preempt
  the remaining detail visual queue.
```
