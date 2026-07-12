# Current Mac/Codex handoff

Last updated: 2026-06-21 after local main sync.

This file is the current-site handoff for Codex/Claude/local agents after the Hermes migration from the old desktop to the Mac. It summarizes durable context that is otherwise split across memory, active plans, and controller chat. It is **not** a completion claim and does not override active plan gates.

## Read order

1. `AGENTS.md`
2. `docs/agent-guides/always-loaded-rules.md`
3. `docs/agent-guides/harmonyos-default.md`
4. This file
5. Relevant active plans under `docs/plans/active/`

## Machine and path facts

Current machine:

```text
macOS host, user home: /Users/honjow
primary git root: /Users/honjow/git
```

Do not assume old Linux paths are local. Historical `/home/gamer/...` paths usually refer to the old desktop over SSH:

```text
gamer@itx.local:/home/gamer/git
```

Current local project roots:

```text
NextE:                  /Users/honjow/git/NextE
NextE worktrees:         /Users/honjow/git/NextE-wt
Product reference:       /Users/honjow/git/eros_fe
Harmony architecture ref:/Users/honjow/git/V2Next
Harmony docs/skills:     /Users/honjow/git/harmony-next.skills
```

Reference roles:

```text
eros_fe = product/UX semantics source of truth for EH behavior.
V2Next  = HarmonyOS/HDS/navigation/state architecture reference.
```

For tab/state/navigation questions, check both roles explicitly. Do not let V2Next override EH product semantics, and do not let eros_fe's Flutter implementation override the target HarmonyOS architecture without adaptation.

## Local DevEco / device facts

Known local coding-agent CLIs:

```text
Codex:      /opt/homebrew/bin/codex, observed `codex-cli 0.140.0`
ClaudeCode: /Users/honjow/.local/bin/claude, observed `2.1.179 (Claude Code)`
OpenCode:   not found in PATH at this handoff
```

Verify versions again before relying on exact CLI behavior, but do not assume Claude is missing on the Mac.

Known local tools:

```text
DevEco Studio: /Applications/DevEco-Studio.app
DevEco helper: /Users/honjow/.local/bin/deveco
hdc:           /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
```

Observed targets at this handoff:

```text
127.0.0.1:5555       TCP Connected localhost
127.0.0.1:5557       TCP Connected localhost
192.168.50.200:12345 TCP Offline   localhost
```

User-created emulator intent:

```text
Mate X7 foldable emulator: primary responsive-layout QA target.
Mate Pad Mini emulator: planned ordinary tablet QA target.
```

The `127.0.0.1:5555` / `127.0.0.1:5557` mapping must be verified before naming either one folded or unfolded. Do not assume from port alone.

Responsive-layout QA should prefer local emulators over always requiring a physical device:

1. Mate X7 folded/outer-screen cold start.
2. Mate X7 unfolded/inner-screen cold start.
3. Folded -> unfolded transition in the same running app process.
4. Unfolded -> folded transition in the same running app process.
5. Mate Pad Mini cold start after the emulator exists.

Fold/unfold control must follow the harmony-next skill's device-side DisplayManager path; do not guess or declare the CLI unavailable before checking it:

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
TARGET="127.0.0.1:<port>"

"$HDC" -t "$TARGET" shell hidumper -s DisplayManagerService -a '-a'  # current fold/display state
"$HDC" -t "$TARGET" shell hidumper -s DisplayManagerService -a '-p'  # folded / outer screen
"$HDC" -t "$TARGET" shell hidumper -s DisplayManagerService -a '-y'  # expanded / inner screen
"$HDC" -t "$TARGET" shell hidumper -s DisplayManagerService -a '-z'  # half-folded
```

Current verified meanings on the Mate X7 emulator:

```text
Folded:  PhysicalFoldStatus=FOLDED, DisplayFoldStatus=FOLDED, Display width x height = 1080 x 2444.
Expanded: PhysicalFoldStatus=EXPAND, DisplayFoldStatus=EXPAND, Display width x height = 2210 x 2416.
```

Every hdc command above must run outside the Codex sandbox.

Use physical-device QA for hardware/performance/permission/account-state cases that emulators cannot faithfully cover.

### Physical-device target boundary

There is no default physical-device target. For any agent-controlled device action, use only the target
explicitly named by the user or the current task plan. Never infer a target from a historical handoff,
lease script, artifact, or another task's evidence.

## Build profile / secret boundary

The migrated Mac uses the safe local build-profile pattern:

```text
Tracked/public: build-profile.json5
Ignored/local:  build-profile.local.json5
Installer:      scripts/setup-local-build-profile.sh
Protection:     repo hooks / skip-worktree setup
```

Do not commit signing secrets or local profile contents. Do not treat `.gitignore` as a package-safety guarantee; packaged HAP resources must be scanned separately when auth/cookie work changes.

## Current repository state snapshot

Controller checkout at the latest local-main hygiene pass:

```text
repo:   /Users/honjow/git/NextE
branch: main
base:   a8af7f1 docs(dispatch): close merged waterfall lane
status: clean tree, in sync with origin/main
```

Control-plane documents, harness state, screenshots, fixtures, and worktrees are project assets. Do not delete, move, or call them disposable without explicit path-level user authorization.

Known high-risk worktrees:

```text
/Users/honjow/git/NextE-wt/auth-cookie-login        agent/claude/auth-cookie-login
/Users/honjow/git/NextE-wt/auth-cookie-login-rebase agent/codex/auth-cookie-login-rebase merged at 58e48ba
/Users/honjow/git/NextE-wt/device-lease             agent/codex/device-lease
/Users/honjow/git/NextE-wt/detail-visual-reqa       agent/codex/detail-visual-reqa      merged at 0652a05
/Users/honjow/git/NextE-wt/list-responsive-cover    agent/codex/list-responsive-cover   merged at 11069a5
/Users/honjow/git/NextE-wt/logic-subtab-loading     agent/claude/logic-subtab-loading
/Users/honjow/git/NextE-wt/mac-harness-signing      agent/codex/mac-harness-signing     merged at 4ab2367
/Users/honjow/git/NextE-wt/subtab-never-loaded-flash agent/codex/subtab-never-loaded-flash merged at b3d9e5d
/Users/honjow/git/NextE-wt/ui-detail-preview-audit  agent/codex/ui-detail-preview-audit
```

Full local inventory is large; use `git worktree list` before reusing any old path.

Current lane warnings:

```text
auth-cookie-login (old Claude worktree):
  - ahead of origin/main by 2 commits
  - behind origin/main by 303 commits at the 2026-06-21 hygiene pass
  - has uncommitted WIP in:
    feature/settings/src/main/ets/pages/SettingsPage.ets
    scripts/test_cookie_import_contract.mjs
    shared/src/main/ets/settings/CookieJarSettings.ets
  - preserved as historical WIP; do not reuse for new work or clean it.

auth-cookie-login-rebase:
  - created from current origin/main to avoid mutating the old WIP worktree.
  - merged/pushed to main at 58e48ba after contracts, official signed build, and emulator route/UI QA.
  - real successful cookie import remains USER_MANUAL_REQUIRED because Codex must not request or enter real cookie values.

other old lanes:
  - behind current main
  - do not assume they are active or accepted.
  - do not clean, delete, or move without explicit path-level authorization.

additional dirty WIP observed during the 2026-06-21 hygiene pass:
  - download-gallery-runner: download runner/resources/settings WIP plus an untracked runner contract.
  - reader-auto-page-turn: reader/settings/resources WIP plus an untracked auto-page contract.
  - reader-baseline-recovery: ReaderPage WIP.
  - reader-core-incident-recovery: ReaderPage/loading-progress contract WIP.
  - reader-gesture-recovery: ReaderPage/progress/gesture contracts WIP.
  - reader-image-cache: untracked ReaderImageCacheService.ets prototype only; not wired or verified.
  - reader-thumbnail-strip: ReaderPage WIP plus untracked thumbnail-strip contract.
  - search-quicksearch: quick-search resources/state/page WIP plus untracked contracts/settings.

recently merged/pushed lanes:
  - a8af7f1 dispatch state cleanup after local main rebase/sync
  - 8e6e931 retained sub-tab preference
  - 53740b0 Waterfall full-width reserve / chrome avoidance
  - f4d2d5b AllThumbnails first real thumbnail stays normal grid cell
  - 11069a5 list-responsive-cover
  - 4ab2367 macOS official Hvigor signing/harness
  - b3d9e5d Search reload footer loading state
  - 0652a05 detail preview grid comfort width
  - 58e48ba manual Cookie login/import path and logout-state sync
  - 38a04b4 auth-cookie merge-status control-plane docs
  - 7b99bf5 false-404 logged-out smoke control-plane docs
```

At this handoff there are no live tmux worker sessions and no Hermes background processes.

## Active plan state

Planning note:

```text
Use the user's latest explicit request plus docs/plans/active/product-bug-intake.md.
```

Important state:

```text
This handoff is machine/device context, not the live feature queue.
Another active session owns download / archiver / offline Reader work; this thread should avoid those files
unless explicitly redirected.
cookie-login-function-gate.md:
  Manual Cookie login/import candidate is merged at 58e48ba.
  User/manual real-cookie success verification remains open; do not ask for cookie values.
```

Latest false-404 smoke:

```text
2026-06-18, after auth-cookie-login-rebase merge:
  Target: 127.0.0.1:5555 Mate X7 emulator, hdc run outside the Codex sandbox.
  Deep link: https://e-hentai.org/g/1/0000000000/
  Result: UI displayed "无法解析此页面,应用可能需要更新。" + retry, not a 404 message.
  Evidence:
    /private/tmp/nexte_lane_f_false_404_evidence/nexte_lane_f_false_404.png
    /private/tmp/nexte_lane_f_false_404_evidence/nexte_lane_f_false_404_layout.json
  Limitation: bounded hilog tail did not capture a useful NextE classifier line. This is one logged-out
  non-auth smoke only; ExHentai/Sad Panda/donor/permission/auth matrix still requires a safe user-driven
  login state and must not involve Codex receiving or typing raw cookies.
```

Latest Gate V2 reachable subtab re-QA smoke:

```text
2026-06-18, Mate X7 emulator target 127.0.0.1:5555, hdc run outside the Codex sandbox.
  Home default list loaded with content, no terminal empty/no-more copy.
  Home default -> popular subtab switch: immediate and settled screenshots captured; settled layout has
  gallery rows and no "没有数据/没有更多了" text.
  Toplist all -> year period switch: immediate and settled screenshots captured; settled layout has
  gallery rows and no "没有数据/没有更多了" text.
  Search landing and Favorites follow-up are still blocked by the system Xiaoyi IME first-run privacy
  page staying in the foreground. Codex clicked no "同意" button and typed no text.

Evidence directory:
  /private/tmp/nexte_lane_continuation_probe/
Important files:
  nexte_req_home.png
  nexte_req_home_layout.json
  nexte_req_home_hot_immediate.png
  nexte_req_home_hot_after.png
  nexte_req_home_hot_layout.json
  nexte_req_toplist.png
  nexte_req_toplist_layout.json
  nexte_req_toplist_year_immediate.png
  nexte_req_toplist_year_after.png
  nexte_req_toplist_year_layout.json
  nexte_req_search_landing.png
  nexte_req_search_landing_layout.json
```

Do not archive active plans or convert plan items into a new batch. Existing headings are queued gates until current controller evidence proves them solved/blocked/out of scope.

## Latest user-reported hard issue: list page responsive sizing

This is the freshest product issue and should be treated as a hard gate before resuming lower-priority polish.

User observation:

```text
List-page covers look sized as a proportion of container/display width.
On wide/folded-unfolded screens the list row becomes too tall.
When the app starts on the inner screen and then folds to the outer screen, cover width stays large.
When starting on the outer screen and unfolding, dimensions likewise do not react correctly.
This is not how eros_fe designs the list item.
```

Verified NextE source chain:

```text
shared/src/main/ets/components/GalleryCard.ets
  lines 15-23: module-level `_coverW` cache.
  lines 18-20: reads display.getDefaultDisplaySync() once and stores px2vp(shortSide) / 3.
  line 29: row min height derives from cardCoverWidth() / COVER_ASPECT.
  line 121: EhThumbnail thumbWidth uses cardCoverWidth().
```

Why this is wrong:

```text
1. Module-level `_coverW` is startup/display-state cache. It will not recompute on fold/unfold or window/pane resize.
2. It uses global display size instead of the actual list/container width.
3. It applies phone `shortSide / 3` semantics universally, including wide/foldable/tablet layouts.
```

Verified eros_fe reference:

```text
/Users/honjow/git/eros_fe/lib/pages/item/gallery_item.dart
  line 20:  kFixedHeight = 204.0
  lines 75-76: fixedHeightOfListItems ? kFixedHeight : null
  lines 233-235: coverImageWidth = isPhone ? mediaQueryShortestSide / 3 : 0.7 * kFixedHeight
  lines 240-241: fixed-height mode coverImageHeight = kFixedHeight
```

Product semantics to preserve:

```text
Phone/narrow: cover width may follow shortest/container side / 3.
Wide/non-phone: cover width should be bounded around eros_fe's fixed rhythm (~0.7 * 204 = 142.8vp), not grow with the screen.
Fixed-height list mode should keep row rhythm around kFixedHeight semantics instead of expanding indefinitely on wide screens.
Fold/unfold within the same app process must recompute from current pane/window/container metrics.
```

Likely target area:

```text
shared/src/main/ets/components/GalleryCard.ets
shared/src/main/ets/components/PullRefreshListScaffold.ets
feature/home/src/main/ets/components/GalleryListBody.ets
Search/Favorites/Toplist consumers if they bypass GalleryListBody or need measured-width plumbing.
```

Known good local patterns:

```text
shared/src/main/ets/components/PullRefreshGridScaffold.ets uses onAreaChange + measuredWidth + ResponsiveGrid.
feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets also measures width reactively.
```

Implementation direction for a worker:

```text
- Do not patch with a one-off maxWidth only.
- Remove startup-sized module cache from list-card sizing.
- Measure the current list content/pane width reactively, probably at scaffold/list-body boundary.
- Pass sizing context into GalleryCard or a shared list-card sizing utility.
- Record a source check that rejects module-level `_coverW` / display.getDefaultDisplaySync based list-card sizing, then prove it with folded/unfolded device evidence.
- Preserve existing fixed/adaptive list-height setting semantics.
- Preserve current cover image presentation constraints: real image ratio, rounded visible image content, no blanket fill/crop rewrite.
```

Minimum acceptance gates for this issue:

```text
- source review for no startup display cache in GalleryCard sizing.
- source review for phone/narrow vs wide/non-phone width semantics.
- `node scripts/test_v1_decorator_inventory_contract.mjs` reports 0.
- project harness/pre-commit gates relevant to severe-impact boundaries.
- build succeeds.
- Mate X7 folded cold-start screenshot.
- Mate X7 unfolded cold-start screenshot.
- Mate X7 folded -> unfolded same-process screenshot/video.
- Mate X7 unfolded -> folded same-process screenshot/video.
- Mate Pad Mini tablet screenshot when available.
```

Screenshots should be delivered to the controller/user, not only kept as local paths.

## Planning Pointer

For planning context, use:

```text
docs/plans/active/product-bug-intake.md
```

Current coordination note:

```text
Download / archiver / offline Reader work is owned by another active session unless the user explicitly
hands it back to this thread.
Recovered EhViewer / JHenTai comparison candidates live in
docs/plans/active/ehviewer-jhentai-feature-comparison.md.
```

Historical worker note:

```text
The old list-card responsive-sizing worker suggestion is no longer a current recommendation.
Do not choose work from this handoff.
```

## Agent execution rules for the next phase

- New product/layout work should use a fresh worktree and fresh local Codex/Claude session.
- Controller/worker must not delete untracked docs, plans, screenshots, harness state, or worktree artifacts.
- Do not use State Management V1 decorators.
- Do not add `Text('›')` or hand-written arrow glyphs as UI icons; use project icon/HDS/Symbol mechanisms.
- Do not claim visual acceptance from source contracts alone.
- Do not claim emulator target identity until verified from DevEco/hdc/device info.
- Do not push, merge, tag, or delete worktrees unless explicitly authorized by the controller/user.
- When current evidence conflicts with old docs, current source/device evidence wins; update the relevant active plan rather than relying on chat memory.
