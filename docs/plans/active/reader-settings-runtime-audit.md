# Reader settings runtime audit

Scope: NextE shared reader only. OPEN. Baseline c94b43fa; host base4f7bd4a2, core0fd19c3. Installed HAP75a38669a321b10ce95cdebce05c8bc684fa9e20dfd1aaef545c4f16f8f6fec9. The same candidate now has continuous device197 evidence for uncached thumbnail waiting, waiting-time navigation, original indicator dismissal, and local single/double live settings with right-slot entry and companion fade. This does not accept all settings or other hosts. Frozen source/HAP/protocols: `.hvigor/outputs/reader-retained-entry-20260925/`.

## Ownership and confirmed fault

ReaderSettingsPage writes ReadModeSettings. The footer writes through ReaderPreferenceSink. Initial session policy used NextEReaderInitialPolicy.resolve, but the host omitted the reverse live subscription for mode, doublePageEnabled and spreadLayoutMode. Saving a preference therefore did not update the existing session. The new host monitor maps those three fields through the existing resolver and session.setPolicy; it preserves other policy fields and ignores equal updates. It does not reopen the reader.

24 settings rows were traced, counting paged/continuous settings separately and excluding the model-management navigation action. Three missed live layout propagation, twenty have a runtime consumer, one selects the backend for the next entry. A runtime consumer is not device acceptance.

| # | Setting | Runtime consumer | Evidence |
|---|---|---|---|
|1|Reading mode/direction|Host resolver → session.setPolicy|RTL applied within same session: fast rightward12→13 and leftward13→12. LTR restore confirmed. Axis/continuous modes pending|
|2|Double-page enabled|Host resolver → session.setPolicy|75a38669: first-spread ON/OFF and matching footer, complete920-frame route without prior blank; source3 OFF also preserves anchor; remaining anchors untested|
|3|Spread arrangement|Host resolver → session.setPolicy|75a38669: equal then merged updates current spread without reentry; source3 anchor retained|
|4|Page-turn animation|ReaderSurface command animation policy|Source wired; not individually device accepted|
|5|Paged tap layout|ReaderTapPolicy + preview revision|Source wired; not individually device accepted|
|6|Paged tap inversion|ReaderTapPolicy + preview revision|Source wired; not individually device accepted|
|7|Continuous tap layout|ReaderTapPolicy + preview revision|Source wired; not individually device accepted|
|8|Continuous tap inversion|ReaderTapPolicy + preview revision|Source wired; not individually device accepted|
|9|Paged crop enabled|ReaderCropPolicy → setCropEnabled/refreshCrop|Source wired; not individually device accepted|
|10|Paged crop strength|ReaderCropPolicy → refreshCrop|Source wired; not individually device accepted|
|11|Continuous crop enabled|ReaderCropPolicy → setCropEnabled/refreshCrop|Source wired; not individually device accepted|
|12|Continuous crop strength|ReaderCropPolicy → refreshCrop|Source wired; not individually device accepted|
|13|Background|Observed host value → canvas/chrome parameters|Source wired; not individually device accepted|
|14|Scaling quality|Observed host value → imageInterpolation|Source wired; not individually device accepted|
|15|Page number|Observed host value → reader chrome|Source wired; not individually device accepted|
|16|Fullscreen|Host preference monitor → system-bar owner|Source wired; not individually device accepted|
|17|Keep screen on|Host monitor → keep-screen-on owner|Source wired; not individually device accepted|
|18|Image enhancement enabled|ReaderVariantPolicy → variant update|Source wired; not individually device accepted|
|19|Enhancement model|Variant identity + provider configuration|Source wired; per-unit temporary choice can override global|
|20|Maximum source height|Variant policy + provider configuration|Source wired; not individually device accepted|
|21|Automatic turn interval|ReaderAutoReadPolicy → onAutoReadInputsChanged|Source wired; not individually device accepted|
|22|Volume keys|Host preference monitor → input binding|Source wired; not individually device accepted|
|23|Preload depth|onPreloadDepthChanged → paged/continuous preload|Source wired; not individually device accepted|
|24|Reader implementation|Next-entry route selection|Intentional next-entry effect; no mid-session backend replacement|

## Current visual counterevidence

The full local HAP7570ea6 recording actually starts at downloaded EX Machi detail, not Anne detail as the old manifest description claimed. All921 decoded frames were reviewed. First entry uses double-page ON; first toggle turns it OFF, but the spread/footer remain double through dismissal (frames528–589). Reentry shows single. Second toggle turns ON, but the single image remains through dismissal (frames834–889). Thus both toggle directions fail live in that candidate. This corrects the action names in the old manifest; the footage is retained unchanged.

Local entry frames420–444 remove the visible thumbnail and show loading against black before originals appear. Frames662–668 briefly remove the already visible second image. Geometry-keyed native Image recreation has been withdrawn. Current candidate retains native nodes and revalidates the same completion against the final layout. This requires new matching continuous evidence before acceptance.

## Native completion receipt

In the c658 local run, 05:06:05.449 reproduced the exact sibling-size update that rejected the native completion projection. At 05:06:05.450 the retained completion was successfully reported against current geometry, without recreating Image or requesting another onComplete. This closes that observed receipt-loss mechanism only; it does not accept layout-switch continuity or online paths.

## Current candidate boundaries

Prior HAP e1ea47a951284b59e150f40c9ecf546ece5f1b71a2deb4f8ffc6899a3a1527d8; source, signed HAP and continuous route manifests are frozen under `.hvigor/outputs/reader-position-container-20260925/`. The online Anne/Nadia entry runs completed original loading before the flight ended; they do not accept waiting feedback or waiting-time input. Nadia had a previous P8 reading record. A 400ms entry tap did not turn during flight. Later far-slider evidence is recorded below; it does not cover uncached thumbnail entry.

Direction validation: `live-direction-roundtrip` first section proves immediate RTL and fast12→13→12 without reentry. Its restore section is rejected: a redundant center tap hid already-visible chrome, so following coordinates turned pages. `restore-direction-and-original-gate` records the corrected route and restores LTR in the same session. No product change is justified by that automation error.

Online e1ea far-seek: full308 frames reviewed. Normal slider10→90 showed a loading bar; fast6000px/s swipe selected91 while loading (05:33:56.008), before original native completion05:33:57.481. First original frames197–199 still overlapped the decoding bar until the05:33:57.510 presentation receipt. Therefore overlay lifecycle is not accepted. Current candidate b39376b5 hides only the matching original's decoding indicator at its real native completion; post-frame presentation guards and native Image instances remain unchanged. It also monitors the snapshot parameter rather than unsupported nested topology path for external input-lock reporting. Signed build passed; installed197. Fresh local874 frames and online751 frames reviewed: local scope above preserved; online page45→46 loading then first original frame619 without stale indicator. Entry handoff remains OPEN. Binding: `.hvigor/outputs/reader-decoded-feedback-20260925/`.


## Current entry black-frame cause and candidate
Core126fc08 made pager transparency conditional on entry.pending(); geometry cancellation therefore reinstated an opaque pager above the loading thumbnail. Host4f7bd4a2 additionally retired the thumbnail on every cancellation, even while the same original was still loading. Both are regressions in this repair lane, not legacy omissions. Root-to-Reader forward handoff also mounted a second Image. The candidate uses the existing Reader preview from OPENING through waiting/reveal, preserving one node; root still owns reverse/close. Existing canvas owns the background; pager stays transparent in ReaderSurface (standalone pager default unchanged). The host retires a cancelled preview only for changed navigation/missing page/terminal state, using current snapshots separately from native-visible progress. Four executed state tests cover cancellation versus navigation/terminal retirement; they are not visual acceptance. No new timer or native image key.

Device197 was explicitly released by the user for continued testing after the rejected system-Photos replay. No app data/cache was cleared. Candidate75 ordinary Oniisama gid4210490 thumbnail1 entry: all400 frames reviewed; flight55–80, thumbnail+loading81–235 continuously, original236 onward without stale indicator. The decoded-aspect-mismatch cancellation occurred in this run, with no black handoff. Far thumbnail29: all334 frames reviewed; flight53–74, thumbnail+loading75–137; next selected page30 before decoding, old thumbnail retired, original221 without indicator, previous29 and return retained. These are distinct uncached waiting/input observations.

Same75 local EX Machi route: all920 frames reviewed. First entry412–449 retained visible preview; live double ON513–529 and matching footer after sheet dismissal; second thumbnail flight620–640 lands right, left companion fades645–652; fast6000px/s next/previous preserves images; live double OFF821–830 and footer after dismissal; return888–907 preserved. Only this first-spread route is accepted.

Page-counter diagnostic60e1c508 changed only two log lines. Complete466-frame cached1→2→1 route reviewed. Initial interpretation of stale TextController state was not supported: Swiper ends06:21:59.902, snapshot changes59.909, value monitor receives1/36 at59.919. Legacy also commits its page number from onChange. Visible image reaches near-final position before the native spring animation's end; the recording alone did not establish a lost text update. No text behavior patch was made; diagnostic lines were removed and candidate75 reinstalled with independent install-final artifacts. Do not reuse the initial stale-text claim as an established cause.

Default entry/spread follow-up on75: all238 frames of download-default-entry-spread-gate reviewed; native navigation slide81–102 remains present, original103 has no stale loading indicator. All458 spread-live-roundtrip frames reviewed: equal selection updates current spread; fast next to source3/4, merged selection237–246 changes geometry in the same session, OFF354–366 preserves source3 and footer, system return417–438. Settings restored to merged, double OFF. This closes the three missing live layout subscriptions for observed direction, double, and spread paths; it does not validate every mode or all24 rows.

The thumbnail-to-loading black-frame repair and its affected local/default/spread regression routes are accepted for these197 paths. Full reader replacement, rotation, flight reversal, continuous-mode parity, and untested settings remain outside this bounded acceptance. Next action is source/evidence checkpoint and device postflight; do not recreate components or change unrelated settings based on those untested entries.
