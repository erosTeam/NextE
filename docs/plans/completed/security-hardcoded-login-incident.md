# Security incident — hardcoded/bundled login session risk

- **status**: remediated / gate-backed / monitor normal login path
- **created**: 2026-06-16
- **source**: user report: hardcoded login information may be committed/leaked
- **scope owner**: controller; Claude self-report is not acceptable evidence

## Current verified facts

Verified without printing secret values:

1. `git remote -v` is empty at the time of this inspection, so this local repo has no configured remote push target.
2. `entry/src/main/resources/rawfile/legacy bundled credential rawfile` exists locally and contains an EH auth cookie header shape:
   - `ipb_member_id` value length 7
   - `ipb_pass_hash` value length 32
   - `igneous` value length 17
   - file size 96 bytes
   - file sha256 `6b8cf59cf3cbc411c739a964cd5b8a3ef5f3682b967a2780373123f26f9310c1`
3. The same rawfile is present in build intermediates:
   - `entry/build/default/intermediates/res/default/resources/rawfile/legacy bundled credential rawfile`
   - same sha256 as source rawfile
4. The current local HAP artifacts contain the credential rawfile (verified with `unzip -l`, without reading values):
   - `entry/build/default/outputs/default/entry-default-signed.hap` contains `resources/rawfile/legacy bundled credential rawfile` (96 bytes)
   - `entry/build/default/outputs/default/entry-default-unsigned.hap` contains `resources/rawfile/legacy bundled credential rawfile` (96 bytes)
   - This directly explains fresh-device installs opening already logged in: the HAP ships the rawfile, startup reads it, then saves the auth bundle to Preferences.
5. `.gitignore` currently ignores:
   - `.env.local`
   - `scripts/dev.env`
   - `entry/src/main/resources/rawfile/legacy bundled credential rawfile`
   - `entry/build/`
   - `*.hap`
6. Full local git-history audit at 2026-06-16 after the user confirmed the HAP has not left the local-device boundary:
   - `git remote -v`: no configured remote.
   - Scope scanned: all refs + reflog commits (`git rev-list --all --reflog`) — 31 commits / 720 reachable-or-reflog objects.
   - Also checked dangling/unreachable objects with `git fsck --full --unreachable --dangling`: 0 unreachable objects.
   - Result: no tracked `entry/src/main/resources/rawfile/legacy bundled credential rawfile` filename in history.
   - Result: no tracked HAP/package artifact in history.
   - Result: no historical blob matching the current 96-byte rawfile sha256.
   - Result: no secret-bearing EH session rawfile verified in git history.
   - Expected non-secret hits found: cookie field names in runtime code/docs and synthetic cookie fixture values in `scripts/test_cookiejar_contract.mjs`; these are not the live session rawfile and do not authenticate.
7. Follow-up binary-safe local history/object scan at `2026-06-16 16:08:08 +0800`:
   - scanned 724 all-ref/reflog/unreachable/dangling objects, 311 blobs.
   - `filename_legacy bundled credential_hits=0`.
   - `package_or_signing_artifact_hits=0`.
   - `secret_pattern_hits_after_allowlist=0`.
   - allowlisted non-secret hits only: synthetic fixture values in `scripts/test_cookiejar_contract.mjs`, cookie field-name documentation in `docs/eh-integration-contract.md`.
8. `git ls-files` and tree search found no tracked `legacy bundled credential rawfile` path and no tracked HAP output at this inspection.
9. The risky code path **was committed from the initial commit `6edd5cb`**:
   - `shared/src/main/ets/settings/CookieJarSettings.ets:114-134` reads `legacy rawfile read`, parses it, and saves it into app Preferences.
   - `shared/src/main/ets/settings/SettingsBootstrap.ets:27-29` calls `CookieJarSettings.legacy startup injector(context)` on every startup after restore when no login exists.
10. Therefore the credential file itself is **not verified as committed**, but a local ignored cookie file can be bundled into a HAP and auto-injected into login state. Shipping or sharing that HAP leaks the session.
11. Committed docs also reveal account-adjacent operational details, e.g. `docs/m3-plan.md` mentions booting logged-in and a member ID. This is not enough to authenticate, but should be scrubbed from public history before publish.
12. Remediation completed after explicit path-level authorization:
   - quarantined the four exact local secret/package artifacts to `/home/gamer/.nexte-secret-quarantine/20260616-160432/` with redacted `manifest.txt` metadata only.
   - removed app-startup legacy bundled credential injection from `CookieJarSettings.ets` and `SettingsBootstrap.ets`.
   - added `scripts/test_secret_safety_contract.mjs`, wired into `.harness/config.json`, and listed in `docs/loop.md`.
   - rebuilt debug unsigned HAP successfully with `bash dev.sh --build-only` after exporting Harmony command-line-tools PATH.
   - verified new `entry/build/default/outputs/default/entry-default-unsigned.hap` does **not** package `resources/rawfile/legacy bundled credential rawfile`.

## Impact

P0. Treat the cookie values as compromised if any HAP/apk/artifact built from this workspace has been shared outside the local device/controller environment.

Risks:

- A signed/unsigned HAP built with `entry/src/main/resources/rawfile/legacy bundled credential rawfile` contains live EH session cookies.
- App startup auto-persists those cookies to Preferences, so a build can silently run as that account.
- Future workers can unknowingly keep validating with the user's/test account and hide login regressions.
- If HAP or build directory is ever pushed, uploaded, or sent, credentials leak.
- If the branch is published as-is, the auto-injection mechanism advertises a dangerous pattern even if the ignored secret file is absent.

## Immediate freeze rules

Resolved freeze rules (historical):

- Do not push, publish, upload, or send any old pre-remediation HAP from this workspace.
- Do not run release packaging from this workspace without `secret-safety` + package-content verification.
- Do not let Claude continue feature work unless it reads this incident and `docs/plans/active/gallery-visual-navigation-regression-contract.md`.
- Do not print cookie values, account password, raw `.env.local`, raw `legacy bundled credential rawfile`, or raw HAP contents.
- Do not delete ignored/untracked secret files without explicit path-level authorization from the user; preserve evidence with redaction.

A local `.git/hooks/pre-push` fuse may block pushing while this incident is unresolved.

## Required remediation

### R1 — Remove committed auto-injection code path

Remove production/runtime code that reads bundled `legacy bundled credential rawfile` and auto-injects cookies:

- Delete or hard-disable `CookieJarSettings.legacy startup injector`.
- Remove the unconditional call in `SettingsBootstrap.loadAll`.
- Do not replace it with another bundled/rawfile/session shortcut.

Allowed replacement pattern:

- App login comes only from in-app WebView login and persisted Preferences created by the app.
- Test automation can inject credentials only through a local, non-packaged, explicit dev harness outside app resources, with logs redacted and with a build-time hard gate proving no cookie rawfile is packaged.

### R2 — Delete local packaged secret artifacts after user explicitly authorizes exact paths

Candidate paths to remove/quarantine after explicit authorization:

- `entry/src/main/resources/rawfile/legacy bundled credential rawfile`
- `entry/build/default/intermediates/res/default/resources/rawfile/legacy bundled credential rawfile`
- `entry/build/default/outputs/default/entry-default-signed.hap`
- `entry/build/default/outputs/default/entry-default-unsigned.hap`
- any other `entry/build/**` artifact containing the rawfile

Do not run blanket `rm -rf` or `git clean`.

### R3 — Add deterministic secret gates

Add a project-local gate that fails if any of these are true:

- tracked tree contains `legacy bundled credential rawfile`, `.env.local`, `scripts/dev.env`, HAP, signing material, or cookie fixture paths;
- source code calls `legacy rawfile read` or `legacy startup injector` from app startup;
- resources contain `entry/src/main/resources/rawfile/legacy bundled credential rawfile` at build/test time;
- staged diff contains `ipb_pass_hash=`, `ipb_member_id=`, `igneous=`, `sk=`, `Cookie:`, password-like values, or HAP/signing artifacts.

Wire the gate into `.harness/hooks/pre-commit` / project loop before accepting remediation.

### R4 — Scrub docs before public publish

At minimum, redact committed docs that expose:

- concrete member IDs;
- “authenticated account state” claims tied to auth validation;
- instructions that normalize bundled cookie rawfile injection.

If this repository will be made public or pushed to a remote after the incident, rewrite local history before first push so the public history never contains the unsafe pattern or account-adjacent details.

### R5 — Rotate/revoke session

If the HAP or cookie file has ever left the local machine/device boundary, rotate/revoke the EH session:

- Log out / invalidate sessions from EH where possible.
- Re-login to get new `ipb_pass_hash` / `igneous` values.
- Remove old local cookie files and app Preferences on test devices.

## Verification checklist

- [x] `git remote -v` checked before any push: no configured remote at inspection time.
- [x] `git ls-files` contains no secret/resource/HAP paths, covered by `secret-safety`.
- [x] `git grep` / source search shows no app-startup `legacy startup injector` / `legacy rawfile read` path.
- [x] Secret gate passes on clean tree after quarantine and build.
- [x] Build output checked: no packaged `rawfile/legacy bundled credential rawfile` in new debug unsigned HAP.
- [x] Device app still supports normal WebView login and persisted Preferences. Re-device-verified 2026-06-17: after fresh restart, Favorites page remained logged in and loaded real favorite categories/list (`/tmp/sec_fav_loggedin.jpeg`; no secrets printed).
- [x] Logs show auth restore paths without raw cookie values. Re-device-verified 2026-06-17: `/tmp/jscrash.log` contains `cookie_jar_restored | login=true` and `bootstrap_loaded | cookie jar restored`; raw cookie pattern counts for `ipb_member_id`, `ipb_pass_hash`, `igneous`, `sk`, and `Cookie:` were all 0 in the inspected log.
- [x] User explicitly authorized quarantine of exact local secret artifacts before removal.
- [x] Public push path prepared as single-root `public-safe-main` commit `1d7c283` and independently bundle-clone verified.
- [x] Local `.git/hooks/pre-push` blocks pushing old `main` by default and permits only sanitized `public-safe-main` unless explicitly bypassed.

## Status log

- 2026-06-16 — Created after user reported hardcoded login info. Verified the raw cookie file is ignored/untracked but packaged locally; verified committed auto-injection code path from initial commit. No secret values printed.
- 2026-06-16 — User confirmed HAP has not leaked beyond installing on a new device. Ran full local history scan across all refs + reflogs + dangling/unreachable objects. No tracked live session rawfile, no HAP/package artifact, and no secret-bearing EH session rawfile verified in git history. Added result above without printing secret values.
- 2026-06-16 — Removed the app-startup legacy bundled credential injection code path from `CookieJarSettings.ets` and `SettingsBootstrap.ets`; added `scripts/test_secret_safety_contract.mjs`; wired it into `.harness/config.json` and `docs/loop.md`. Current gate result: source-code injection path is gone, V1 and cookie contracts pass.
- 2026-06-16 16:08:08 +0800 — User authorized quarantine of the four exact local artifacts. Quarantined them to `/home/gamer/.nexte-secret-quarantine/20260616-160432/`; reran `test_secret_safety_contract`, V1 inventory, cookie contract, `bash dev.sh --build-only`, package listing, and `.harness/hooks/pre-commit`. All security/build/harness gates passed; new unsigned HAP does not contain `resources/rawfile/legacy bundled credential rawfile`.
- 2026-06-16 16:22:17 +0800 — Re-checked the same four exact paths after context handoff. The rawfile source/intermediate paths were absent; two existing HAPs under `entry/build/default/outputs/default/` were quarantined to `/home/gamer/.nexte-secret-quarantine/20260616-162217-+0800/`. Rebuilt with `hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon` → BUILD SUCCESSFUL; new `entry-default-unsigned.hap` package listing shows `NO_CREDENTIAL_RAWFILE`. `node scripts/test_secret_safety_contract.mjs`, V1 inventory, cookie contract, and `.harness/hooks/pre-commit` all pass; harness reports 9 gates including `secret-safety`.
- 2026-06-16 17:29:49 +0800 — Prepared non-destructive public-safe push path: `public-safe-main` is a one-commit orphan branch (`1d7c283`, no parents) built in `/home/gamer/git/NextE-public-safe-20260616-171841`. It removes the legacy bundled credential injection path, scrubs public docs of legacy bundled credential/account-specific markers, removes the legacy rawfile ignore, and adds a stricter `secret-safety` gate. Verified in the public-safe worktree: `test_secret_safety_contract` PASS, `.harness/hooks/pre-commit` PASS, `bash dev.sh --build-only` BUILD SUCCESSFUL, HAP listing `NO_CREDENTIAL_RAWFILE`. Created `/tmp/nexte-public-safe-main-20260616-172747.bundle`, cloned it to `/tmp/nexte-public-safe-clone-20260616-172747`, and verified standalone history count=1, no forbidden paths, no unsafe markers outside the gate script, no non-allowlisted secret patterns, and harness PASS. Installed a local `.git/hooks/pre-push` fuse that blocks pushing old `main` and permits only `public-safe-main` by default.
- 2026-06-16 17:33:00 +0800 — Simulated the intended remote workflow: initialized throwaway bare remote `/tmp/nexte-public-remote-20260616-173238.git`, pushed `public-safe-main` to remote `main`, cloned fresh to `/tmp/nexte-public-remote-clone-20260616-173238`, confirmed clone branch `main`, history count=1, commit `1d7c283`; ran `node scripts/test_secret_safety_contract.mjs` and `.harness/hooks/pre-commit` before build (PASS), built with `bash dev.sh --build-only` using Harmony command-line-tools PATH (BUILD SUCCESSFUL), verified generated `entry-default-unsigned.hap` reports `NO_CREDENTIAL_RAWFILE`, and reran secret/harness gates after build (PASS). Remote pull + local compile path is verified safe for `public-safe-main -> main`.
- 2026-06-17 05:23 +0800 — Controller closed the final device/log verification items after fresh evidence, not Claude self-report: `/tmp/sec_fav_loggedin.jpeg` shows a restarted app still logged into Favorites with real categories/list loaded; `/tmp/jscrash.log` contains `cookie_jar_restored | login=true` and `bootstrap_loaded | cookie jar restored`; redacted raw-cookie pattern scan of that log found 0 matches for `ipb_member_id`, `ipb_pass_hash`, `igneous`, `sk`, and `Cookie:`. No secret values printed.
