# Downloads Intake

Status: domain intake ledger.

Purpose:

- Preserve full evidence and handling notes for this domain.
- This file is an evidence ledger, not a priority queue. Start from the user's latest request and use `../product-bug-intake.md` for intake writing rules.
- When an item is implemented, update its Status/commit/evidence here so it does not remain an unhandled queue item.

## Items

### Export Progress Dialog Can Be Hidden While Export Keeps Running

Type: downloaded gallery export / modal lifecycle

Priority suggestion: P1 / task-state correctness

Status: implemented candidate / needs device QA

Source:

- User report, 2026-07-15: pressing Back hides the in-progress export dialog, but the export continues
  in the background, making it appear cancelled even though no cancellation occurred.

Root cause and implementation:

- `DownloadQueuePage` configured its `CustomDialogController` with `autoCancel: false`. ArkUI defines
  that option as outside-mask cancellation only; Back is an interactive dismissal reported through
  `onWillDismiss` with `DismissReason.PRESS_BACK`.
- The export service has no cancellation path and all three export flows already close the dialog from
  `finally` after the export settles. The dialog now intercepts interactive dismissal by not invoking
  `DismissDialogAction.dismiss()`, while `finishExport()` retains programmatic close ownership.

Acceptance path:

- Start an export from a completed Gallery or Archiver task, press Back while the loading dialog is
  visible, and verify the dialog remains visible. After success or failure, verify it closes normally
  and the existing share/error continuation runs once.

### Interrupted Downloads Become Directory-Unavailable Errors After Cold Start

Type: download queue recovery / lifecycle

Priority suggestion: P1 / core download continuity

Status: implemented candidate / needs interrupted-task device QA

Source:

- User report, 2026-07-10: exiting the app while a download is active and reopening it changes the
  task to failed with `Download directory unavailable`.

Root cause and implementation:

- The public Download root is intentionally process-local. Cold-start queue restore ran from
  `SettingsBootstrap.loadAll(...)`, before the main content and foreground Ability lifecycle were
  both ready, so `DocumentViewPicker.save(DOWNLOAD)` could fail and the per-task executor then
  persisted that transient storage failure as a terminal task error.
- Automatic resume now starts from `EntryAbility` only after both `loadContent(...)` succeeds and
  `onForeground()` has run, independent of which callback arrives first.
- `runPendingResume(...)` now resolves Download storage once before starting any restored worker. If
  storage is temporarily unavailable, it logs `pending_resume_storage_deferred` and leaves restored
  queued/ready/partial states intact instead of rewriting every task to `ERROR`. Its in-flight guard
  resets when the attempt settles, so a later foreground transition can retry deferred work without
  creating duplicate workers while the previous attempt is still active.
- Manual starts and retries retain the existing explicit directory-error behavior.

Evidence:

- Download workbench, gallery queue, RDB, settings, prepare, first-file, archiver protected-submit,
  backup, V1 inventory contracts, and `git diff --check` pass.
- Official signed Hvigor build succeeds.
- Mate X7 emulator `127.0.0.1:5555`: updated signed HAP installs and cold-starts successfully. Existing
  device logs confirm the old pre-content phase attempted download metadata writes before the runtime
  Download root existed. The device had no safely reusable active task, so the exact interrupted-task
  restart path remains pending manual/device acceptance.

### Download Gallery Task Rows Are Hard To Read

Type: UX / information architecture cleanup

Priority suggestion: P2 / small cleanup behind online reading work

Status: implemented / needs controller acceptance

Source:

- User feedback that the Downloads tab and task rows felt like a settings shell, and that the download
  item hierarchy was too shallow: cover, title, page count, progress/status, and remove action were
  compressed into one row while the remove button consumed too much visual weight.

Implementation:

- `0e0f6ac fix(ui): ground torrent and download surfaces` moved the Gallery / Archiver selector into
  the HDS title-bar `bottomBuilder` and removed settings controls from the scrolling queue body.
- `4e1c314 fix(download): clarify gallery task cards` replaces gallery task `ConciseListRow`s with
  dedicated task cards: cover slot, two-line title, metadata row, progress bar, prominent status text,
  and a low-weight trash icon action.
- `049170c fix(download): focus gallery task progress` keeps seed/download progress focused in the
  task subtitle, so page/category/uploader metadata does not crowd the important preparation or
  downloaded-count state.
- Pending commit `fix(download): focus queue workbench` removes the settings-like queue summary rows
  from the Download tab, so the pinned Gallery / Archiver segmented control is followed directly by
  task cards or the per-queue empty state.
- Scope stays UI/IA-only. This does not implement a deeper download executor, archive submission,
  retry/backoff, resumability, or offline reader integration.

Evidence:

- UI validation: signed build plus device-path evidence; no source-shape UI contract.
- Gates: `scripts/check_i18n_duplicates.py`, `scripts/test_v1_decorator_inventory_contract.mjs`,
  `git diff --check`, official signed Hvigor build.
- Mate X7 emulator target `127.0.0.1:5555`, hdc outside sandbox, official signed HAP installed:
  Gallery download tab showed two real gallery tasks with cover/title/meta/progress/status rows, and
  Archiver tab showed the pinned segmented control plus empty queue state without settings rows.
  Evidence directory: `/private/tmp/nexte_download_workbench_ia_evidence/`, especially
  `download_initial.png`, `download_initial_layout.json`, `download_archiver.png`,
  `download_archiver_layout.json`.
- Current follow-up evidence, 2026-06-19: Android FE target `fa967a75` opened the real Downloads tab
  with `su` and showed the `画廊 / 归档` split plus gallery task rows. NextE Mate X7 emulator target
  `127.0.0.1:5555` installed the official signed HAP and showed the Download tab with a real task row
  whose subtitle foregrounds `部分完成 · 已下载 1/51`; metadata remains on the row metadata line.
  Evidence directories: `.hvigor/outputs/download-seed-progress-fe-comparison/` and
  `.hvigor/outputs/download-seed-progress-nexte-evidence/`.
- Current follow-up evidence, 2026-06-20: Android FE target `fa967a75`, launched with `adb su`, showed
  the Downloads tab as a task workbench with top `画廊 / 归档` segmented control and task cards directly
  below it. Evidence: `.hvigor/outputs/download-ia-current-fe/download_tab3.png`.
- Current NextE evidence, 2026-06-20: Mate X7 emulator target `127.0.0.1:5555`, official signed HAP,
  shows the Download tab with top `画廊 / 归档` segmented control followed directly by a real gallery task
  card (`部分完成 · 已下载 1/51`), and the Archiver segment followed directly by `暂无归档下载`. Layout checks
  confirm no `活跃任务`, `已完成任务`, `画廊下载队列`, `归档下载队列`, or `下载设置` summary rows. Evidence:
  `.hvigor/outputs/download-ia-current-nexte/download.png`,
  `.hvigor/outputs/download-ia-current-nexte/download.json`,
  `.hvigor/outputs/download-ia-current-nexte/archiver.png`,
  `.hvigor/outputs/download-ia-current-nexte/archiver.json`.

Remaining acceptance:

- Needs controller/user acceptance of the task-card visual hierarchy and action weight on screenshots.
  Deeper executor/offline/archive behavior remains explicitly out of scope.
