# EhViewer / JHenTai Feature Research

Status: recovered source-backed research note, not a direct implementation queue.

Current scheduling lives in [Current Dispatch State](current-dispatch-state.md). This file records what was
actually found in EhViewer/JHenTai and how it compares with current NextE. Before implementation, re-open the
exact source path and current NextE code.

## What Was Missing

The earlier comparison was not preserved as a complete document. It existed only as scattered chat context plus
some notes inside [Image Block Community Rules](image-block-community-rules.md). This file is the repaired
research record.

## Good Candidates

### Home EventPane / HentaiVerse Reminder

Source evidence:

- EhViewer parses the homepage/news `#eventpane` HTML in
  `/private/tmp/EhViewer-NekoInverter-EhViewer/app/src/main/java/com/hippo/ehviewer/client/parser/EventPaneParser.kt`.
- EhViewer startup checks news and shows a dialog, with a setting to hide HV monster events, in
  `/private/tmp/EhViewer-NekoInverter-EhViewer/app/src/main/java/com/hippo/ehviewer/EhApplication.kt`.
- JHenTai has a cleaner split: `EHSpiderParser.newsPage2Event()` extracts `dawnInfo` and `hvUrl`, then
  `ScheduleService.checkEHEvent()` shows separate Dawn and HV snackbars. User settings are
  `showDawnInfo` and `showHVInfo`.

NextE status:

- No current NextE EventPane/HV implementation was found in `entry/`, `feature/`, or `shared/`.

Recommendation:

- Worth doing. First slice should parse `#eventpane` into structured `dawnInfo` / `hvUrl` and show a compact
  Home notice or toast/snackbar only when data exists.
- Skip background polling and push notifications for now.

### Reader Touch Region Guide / Adjustable Center Region

Source evidence:

- JHenTai builds three Reader tap regions in `lib/src/pages/read/read_page.dart`: left, center, right.
- The center region width is user-adjustable through `gestureRegionWidthRatio` in
  `lib/src/pages/setting/read/setting_read_page.dart`.
- Desktop help also documents keyboard shortcuts in the Reader top menu.

NextE status:

- Reader already has volume-key plumbing and Reader settings strings for volume keys.
- The missing/unclear part is a visible tap-region guide and richer region presets, not basic key paging.

Recommendation:

- Worth doing as a small Reader-settings lane: preview the tap zones, expose a center-region ratio or presets,
  and keep the implementation shared by horizontal/vertical Reader surfaces.
- Do not rewrite the pager for this.

### Privacy Lock / Recent-Task Privacy

Source evidence:

- EhViewer has app-level screenshot/recent-task protection via `FLAG_SECURE` in
  `/private/tmp/EhViewer-NekoInverter-EhViewer/app/src/main/java/com/hippo/ehviewer/ui/EhActivity.kt`.
- EhViewer has pattern unlock plus biometric unlock in `SecurityScene.kt`, backed by `LockPatternView` and
  `BiometricPrompt`.
- EhViewer settings expose pattern protection, secure screenshots/recent-apps, and clear search history in
  `privacy_settings.xml`.

NextE status:

- NextE already has a Security settings surface with `最近任务中模糊处理` and `自动锁定` strings/page.
- Need device/API verification before claiming actual recent-task privacy behavior works.

Recommendation:

- Worth doing only as native Harmony behavior, not by porting Android lock-pattern UI.
- First slice: verify/implement the existing recent-task blur and auto-lock settings end to end.
- Pattern/PIN/biometric app lock is a later lane after Harmony API confirmation.

### No Image Mode

Source evidence:

- This is a comparison-derived privacy/bandwidth idea rather than a confirmed EhViewer/JHenTai source feature
  in the checked snippets.

NextE status:

- No obvious NextE setting for list/detail image suppression was found.

Recommendation:

- Maybe worth doing after EventPane/privacy. Smallest useful slice is list/detail thumbnail suppression behind
  one setting. Reader suppression is separate because it changes the primary use flow.

## Already Covered Or Lower Priority

### Image Blocking / Community pHash Rules

- NextE already has a pHash/community-rule foundation, settings UI, Reader integration, local rules, allowlist,
  source URL/source page metadata, and contribution draft flow.
- The remaining useful ideas are presentation and scale: blurred blocked thumbnails/pages with a center icon,
  HDS floating controls later, and possibly hash indexing if rule count grows.
- QR auto-blocking remains parked because false positives are likely.

### Local Block Rules

Source evidence:

- JHenTai has grouped local block rules for gallery and comment targets in
  `lib/src/service/local_block_rule_service.dart`, including attributes like title, tag, uploader, gid,
  comment user, score, and content.

NextE status:

- NextE already has local block settings for title/uploader/commentator/comment plus score/comment display.

Possible gap:

- JHenTai-style tag/gid blocking and grouped multi-condition rules are more powerful, but also more management
  UI. Do not do this unless a real user path needs it.

### Reader Volume Keys / Keyboard / Mouse

- NextE already has Reader volume-key settings and ReaderPage volume-key consumer logs.
- JHenTai has richer desktop support: keyboard listener, mouse-wheel speed setting, and mouse back/forward
  button helpers.
- On Harmony phone/tablet this is lower priority; revisit only for keyboard/mouse device support.

### Archive Bot / Super Resolution

- JHenTai has Archive Bot and super-resolution services/settings.
- Both are expensive lanes and either download-adjacent or model/backend-heavy.
- Park while another session owns download work.

## Current Priority From This Research

1. Home EventPane / HentaiVerse reminder.
2. Reader touch-region guide / adjustable region.
3. Verify and finish recent-task privacy / auto-lock.
4. No Image Mode.
5. Image-block presentation polish.
