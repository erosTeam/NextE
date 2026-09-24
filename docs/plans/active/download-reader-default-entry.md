# Download reader default navigation (OPEN)

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

Scoped default-navigation behavior observed; overall Reader FAIL: both entries still visibly show loading → very low-detail image → full-detail image. No claim that preload/blur is fixed, no fault-owner attribution from the pixels alone. Next action is a bounded image-leaf geometry/URI-kind diagnostic, independent of navigation.
