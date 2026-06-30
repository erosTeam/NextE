# EhViewer / JHenTai Feature Reference

Status: active reference, not a direct implementation queue.

Purpose:

- Preserve the feature comparison from the EhViewer / JHenTai research thread so it is not lost in
  dispatch churn.
- Use this file to choose candidate lanes, then verify current NextE code and the reference source before
  editing product code.
- Do not schedule download / archiver work from this file while another active session owns that lane.

## Selection Rule

Before saying "what to do next", check:

1. Current NextE implementation and settings entry.
2. Existing active/completed plan status.
3. Whether the item is user-visible without depending on the download lane.
4. Whether HarmonyOS has a native API or project primitive for the needed behavior.

If any of those are unknown, the next task is a code/source verification slice, not implementation.

## Strong Candidates

### Home EventPane / HentaiVerse Reminder

- Reference idea: EhViewer-style home event/HV reminder surface.
- Why it is distinct: this is not ordinary gallery browsing polish; it adds a timely home signal that the
  user can notice without opening a separate page.
- First NextE slice: verify whether current home parsing already sees event/HV data, then add one compact
  native Home pane only when real data exists.
- Non-scope: downloads, push notifications, background polling, or a large activity center.

### Reader Touch-Region Guide

- Reference idea: make tap/turn zones inspectable and support more touch-region layouts.
- Why it is distinct: it helps users understand Reader controls instead of silently relying on invisible
  hit areas.
- First NextE slice: inspect current Reader gesture/tap-zone model, then add a visual guide route or
  setting preview using the existing Reader settings primitives.
- Non-scope: Reader architecture rewrite, zoom/pager replacement, or unrelated chrome redesign.

### Privacy Lock / Recent-Task Privacy

- Reference idea: app lock plus recent-task hiding/blur.
- Why it is distinct: it is a privacy feature, not content filtering.
- Current note: Settings intake already records `最近任务中模糊处理` and `自动锁定`; reopen from there after
  checking HarmonyOS API support.
- First NextE slice: implement the smallest native setting-backed behavior that can be verified on device.
- Non-scope: account security, cookie migration, or custom authentication framework.

### No Image Mode

- Reference idea: privacy/bandwidth mode that avoids loading gallery images.
- Why it is distinct: it saves network and avoids exposing images in list/detail surfaces.
- First NextE slice: list/detail thumbnail suppression behind a setting; Reader behavior should be a
  separate decision because it changes the primary use flow.
- Non-scope: download/offline behavior.

## Image Blocking Follow-Ups

The pHash/community-rule foundation lives in
[image-block-community-rules.md](image-block-community-rules.md). Remaining ideas from the comparison:

- Blocked-page presentation: blur the image or thumbnail with a clear center icon; HDS floating controls can
  replace the old black overlay later.
- Community contribution: app generates a reviewable JSONL draft; repository/CI validates source URL,
  source page, hash, threshold, duplicates, and dist output.
- QR auto-blocking remains deferred because false positives are more likely than pHash matches.
- Region/crop matching and hash indexes are later scale lanes, not prerequisites for the current app UI.

## Parked

- Image search / search-by-image: lower expected use than Home event/HV and privacy features.
- Super-resolution, Archive Bot, and JHenTai download-heavy ideas: park while the download session owns
  download/offline work.
- Any feature that requires spending GP/Credits or mutating the EH account must stay behind an explicit
  confirmation and user authorization.
