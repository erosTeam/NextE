# Download reader default navigation and image allocation

User contract: a supplied thumbnail uses its scale transition; no thumbnail uses system default navigation. Loading may not approve entry animation.

## Proven owner and bad transition
DownloadQueuePage.openDownloadedTask/openArchiverTask both call open(params,true,true). ReaderOverlayNavigationState keeps animated=true but translates the third argument into route.liveSourceEntry for Shared/local. Index.downloadLiveSourceEntry forwards it; NextEReaderLabPage makes both destination backgrounds transparent until selected drawable reveal, and ReaderSurface suppresses its entire content via liveReaderVisible. Image completion thus controls the visibility of an already running default push. Other normal ReaderOverlayNavigationState.open callers use the default false and do not take this path.

A/B on the same archive page6: currentc76 reveal573ms into604ms push; reconstructed0681 reveal524ms into599ms push. This establishes the visibility gate, not that c76 introduced it or that reconstructed binary is the historical installed package. No authorship/approval inference from Git names.

## Narrow correction and prediction
Remove only the third argument at both Downloads calls. Preserve animated=true, source params, backend selection, local provider, archive preparation, progress, thumbnail entry, close/state-bar mechanisms and all unrelated WIP. No core changes. Prediction: download entry reports liveSourceEntry=false, ordinary destination content/background participates in the push without awaiting the selected drawable. No decoded readiness is fabricated. Loading may appear normally inside the entering reader.

## Acceptance
Build candidate, freeze source diff/core/HAP, install only197 via checked protocol. Ordinary downloaded archive entry from current stored page, continuous recording through push, Back and re-entry. Inspect all transition frames, logs and page identity. Failure: invisible destination until decoded, missing native animation, stale/wrong page, broken Back or entry-dependent status-bar change. This scope does not accept adjacent preload/blur or thumbnail timing; overall shared-reader result remains FAIL.

## Device result
Signed build passed. HAP `ff4a534062da0a022a4c93cdc4ffdec77a848b434a35a93922ad006befe3108b` installed197, host1e225b8a + preserved WIP + two caller changes, corec76b2b3. Ordinary archive page7 → Back → same page7 → Back recorded in `.hvigor/outputs/download-default-entry-20260925/default-entry/default-entry.mp4`. All235 native frames retained and reviewed in three contact sheets plus the route recording. Both entries show the default sliding destination before decode and both returns show the native pop. Logs show liveSourceEntry=false and push53.099→53.693 / 57.832→58.421.

Scoped default-navigation behavior observed; overall Reader FAIL: both entries still visibly show loading → very low-detail image → full-detail image. No claim that preload/blur is fixed, no fault-owner attribution from the pixels alone. The bounded image-leaf diagnostic below subsequently identified the independent allocation defect.

## Image allocation cause and correction
The archive-only diagnostic identified original image leaves mounted/completed at 1×1 while native Swiper cached children had not received their own layout. Resource preloading was present, but its image decode used the fake initial allocation. In the same ordinary archive 7→8→9→8 route, cached source7 completed at 1×1 and forward pages visibly changed from very low detail to clear. The local original was responsible; no blur modifier or thumbnail leaf was involved in this observed route.

Core 78bb2be3a2f8f695063895f7c45ccdcb2c2cee83 passes the measured native pager extent to cached page children and gives image leaves their fitted allocation before mounting. It refuses an original mount at 1×1; physical geometry/decoded readiness and entry guards remain intact. No provider, preload count, navigation, entry-animation, or selection changes. The after diagnostic showed cached original completion at 387.69×516.92 even before its own onArea callback; the matching fast route had no previous low-detail phase. Temporary leaf logs were removed before the final build.

## Final candidate and bounded device result
Host da08f1da + preserved WIP + core78bb2be; signed HAP SHA256 `09c73ee76b198c709a6a058b271d82efe73d9324a3158821c6b45f3a6965c166`. Build succeeded; 83 existing viewport/session/original/entry logic tests passed. Installed only device197 through checked protocol. Evidence root `.hvigor/outputs/reader-allocation-final-20260925/`, identity.txt binds source and HAP.

`final-full-exact/final-full-exact.mp4` contains all930 native frames over34.253s; all reviewed in12 sequential contact sheets. Ordinary archive page1, fast830px gestures at6000px/s:1→2→3→2; right/right/left taps:2→3→4→3; slider38→130→38; Back and ordinary re-entry38. Logs confirm zero-based selections1,2,1,2,3,2,37,129,37 and re-entry37. Foreground/viewport are NextE,1260×2720 portrait. Current tap inversion is NONE; earlier scripts assuming BOTH and far targets129/131 were rejected as route mismatches and retained separately.

Observed: adjacent pages remain clear through the tested fast gestures and taps, default push/pop visible, correct far destination and retained re-entry progress, no prior 1×1 low-detail phase. First entry and far jumps still show loading; page130 and return38 wait substantially for content. This does not claim zero loading, all-reader performance acceptance, other hosts, network images, or thumbnail latency. Thumbnail entry timing remains OPEN; next action is tracing its layout-gated root flight separately from decode and navigation.


## 2026-09-25 final audit disposition

Current regression: hoste5625bd0/corea433017/HAPbd4f95be on197, second-spread-default-final all592 frames reviewed. Task-body native push/pop preserved, original indicators retire per-image, double OFF retains source3. Thumbnail timing and part-specific entry/companion fade accepted for the named local and fresh online routes in reader-settings-runtime-audit.md; no all-gallery zero-loading claim.
