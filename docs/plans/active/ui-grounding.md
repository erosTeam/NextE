# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: gallery and thumbnail load-more retry footers

Status: active
Reference implementation: `shared/src/main/ets/components/LoadingFooter.ets`, `PullRefreshGridScaffold.ets`, `PullRefreshWaterFlowScaffold.ets`, gallery list mode footer wiring, and `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets`.
Surface type: gallery pagination footer across list/grid/waterfall and all-thumbnails bottom paging.
Primary information: existing rows stay visible; footer shows system spinner loading, tap-to-retry error, or no-more from the real page state.
Primary action: tapping retry after a load-more error retries the same cursor/page instead of marking the surface exhausted.
Reuse or deviation: reuse the existing LoadingFooter through optional scaffold footers; no custom thumbnail-only footer.
Verification: gallery paging contract, grid/thumbnail footer contracts, UI grounding contract, V1 decorator inventory, diff check, and signed HarmonyOS build.
