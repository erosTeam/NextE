# Reader image preprocessing — issue #12

Status: completed for the scoped preprocessing repair; bounded runtime paths accepted
Reviewed: 2026-10-09
Scope: the user's request to repair NextE shared-reader super-resolution, automatic translation and related image preprocessing. No commit, push, release, global translation enablement or user-data migration.

## Grounding

- Reference: current Legacy `ReaderPage.scheduleSuperResolutionPrefetch`, `ReaderComicTranslationAutoPolicy`, and the existing explicit session translation confirmation.
- Main information: processed image readiness is independent of off-screen native presentation.
- Actions: retain current-page translation/variant actions and the current-session automatic translation switch.
- Closed local path: bounded source warming → image-block decision → optional crop/SR preparation; explicitly enabled translation settles the current page then prepares at most its next source.
- Harmony expression: existing V2 state, ReaderAsset file leases, TaskPool crop work, host-owned processing providers; no extra image nodes, timers or decoded resource window.

## Source cause and impact

- Shared `ReaderSurface` selects variants for current displayed frames. NextE's old preload bridge prepared only raw files; the shared host's auto-translation poll also required a displayed next-page frame and expired after about two seconds.
- NextE adapter/preload provider now obtains a retained file for local, cached and online sources. The same image-block decision precedes processing. Navigation/window cancellation, background/close and settings changes retire or refresh demand.
- SR uses its existing background priority and exact visible-request cache identity. The service already joins/promotes matching foreground work.
- Translation source acquisition no longer requires a decoded frame. Undisplayed catalog pages have zero dimensions; the provider now reads header dimensions from its retained original-file information capability before the strict runtime preflight. It does not mutate the catalog page or mount an off-screen image. One provider queue serializes actual runtime calls, joins matching foreground/prefetch requests and drops cancelled queued work. Runtime repository results remain page-owned; stale callers cannot publish them.
- Crop detection now uses a file-content identity, so warm and displayed asset instances reuse bounds while changed bytes or crop strength cannot reuse stale geometry. The original Legacy `detect(path, identity, strength)` API remains available.
- Direct: NextE shared-reader adapter/providers/page and crop source. Indirect: NextE `ReaderPageCropService` gains an additive file-content entrypoint; legacy calls keep their existing API and semantics. Reader Kit source/API/pin and its two foreign UI WIPs are unchanged. NextN/Koma do not consume NextE feature/shared services and receive no implementation change.

## Validation and acceptance

The local SR, translation, crop and original/cache runtime harnesses passed, including serial model calls, foreground/prefetch joining, cancelled queued work, retained-file release, changing bytes/strength, and old/new SR owner isolation. Original/cache runtime: 10/10. Image-block and auto-read checks, thumbnail crop parity, mandatory V2 inventory (0 files / 617 scanned), and exact diff review passed.

Two source-proven defects were addressed: overlapping SR preloads shared an owner key; undisplayed translation passed width 0 instead of the file-header width 800. The targeted owner-isolation case now passes. The exact dimension case fails before its repair (0 versus 800) and passes afterwards; it was found during the real production-service route, then rebuilt and retested.

Final signed Release SHA-256: `29dcdcdf86081c665dee92907b0969aef16c450cef35720636a2a26accaf1865`. Build succeeded in 13 s 750 ms; checked protocol 31 returned `install bundle successfully` for that exact local HAP path. Version remains 1.3.5 / 40. Earlier candidate `98873377` supplied the SR observations below; the final incremental product change only adds translation file-header dimensions. Installed-code-path hash access was denied, so package binding uses the exact local HAP hash, positive installer receipt and bundle readback. No access change or retry was used.

### Bounded ordinary-device evidence

The human selected 197, resolved live to `192.168.50.197:12345`. Evidence identity: device197 / ALN-AL80 / not-applicable fold / portrait 1260×2720. Ordinary Settings confirmed the shared reader, preload 4, existing system SR backend and 2000px source-height limit. The ordinary completed-download entry used the existing Non-H gallery 4212986 (19 pages), with no Debug probe or state injection.

- SR / crop: while showing P15, P19 was admitted at background priority 1 (`keyHash32:11a73bbb`, source800×906). It was already a completed enhanced-cache hit while P17 was showing, then its first native P19 display reused that exact key and showed HD. Enhanced-file crop reads happened in the preloading phase. No separate processing-duration claim is made; the completion log line itself was not retained.
- Actual automatic translation: an initial approval review rejected the confirmation because upload/quota authority was missing. No action occurred. The human then explicitly approved this same Non-H book, current service and at most two pages. P13 used the existing Torii/DeepSeek/noto/zh-cn route and displayed a generated visual page. The missing future request exposed catalog dimensions0; the strict runtime rejects them before service access.
- Final package: with native P13 still current, P13 reused its retained result and P14 was prepared from an 800×1131 source header. Exactly one new Torii request/200 response occurred; `translated source=13` (zero-based P14) was logged at22:59:28.111 while the native terminal remained13/19. The future completion did not request P15. Across both packages the real provider requests were P13 and P14 only.
- OFF / cache / source / lifecycle: disabling auto, reopening its native opt-in dialog and cancelling proved OFF before navigating. P14 then reused its translated result without another Torii request and showed the native “显示原图” action. Switching to the source image, Home/background and EntryAbility return kept P14 readable. Closing returned to the ordinary host route.
- Preservation and cleanup: ordinary navigation restored13/19 before closing. Native readback restored paged crop=false and SR=false; continuous crop stayedfalse and page-number/fullscreen/keep-screen settings stayedtrue. The two original completed downloads remained present. The temporary screen-timeout override from protocol00 was removed; PowerManager readback returned the system120000ms timeout without the override. The target lease was released. No user data or generated translation cache was cleared.

### Limits and retained diagnostics

The existing `test_reader_save_source_contract.mjs` fails identically at unchanged HEAD6439f11a, expecting an obsolete `loadReaderFile(...100,undefined,forceReload)` source form. It was not rewritten to claim a pass. Source/saveURI and retained-cache ownership are covered by runtime harnesses and native source-image restoration; a new Gallery export was not performed. These observations establish preprocessing readiness and reuse for the named route, not general translation quality or every reading mode/provider/failure timing.

Protocol23 had an incorrect local receive directory, corrected by artifact-only recovery24. Protocol35 reached P15 after an extra chrome action; it did not request translation there, and terminal P14 evidence was recovered by36. Protocol37 was rejected at dry-run for a raw command in measurement; corrected37b used the documented postflight phase. These are protocol observations, not product defect claims. Observation16 retained an older package context label; observations17 onward explicitly bind their actual candidate, and31 onward bind29dcdcdf.

Project checked manifests: `.hvigor/outputs/reader-preprocessing-issue12-20261009/protocols`. Raw local evidence: `/private/tmp/nexte-reader-preprocessing-20261009/device197__ALN-AL80/not-applicable/portrait-1260x2720/preprocessing`. Source/test application receipt and build logs remain in that local staging root. Power cleanup follows the official [power-shell timeout documentation](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/tools/power-shell.md).

No remaining implementation action for the diagnosed preprocessing paths. No commit, push or distribution occurred. Reader Kit05542ecf and its two existing foreign UI WIPs remain unchanged by this repair; NextN/Koma source was not modified.
