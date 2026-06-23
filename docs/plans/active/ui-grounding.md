# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: gallery waterfall tag strip and root gallery title

Status: active
Reference implementation: `shared/src/main/ets/components/GalleryWaterfallCard.ets` existing tag chips/colors/search action, `feature/gallery/src/main/ets/components/GalleryTagsCard.ets` odd/even image distribution, and `entry/src/main/ets/pages/Index.ets` localized HDS tab title resources.
Surface type: Waterfall-mode gallery card tag strip plus the root Gallery tab title bar.
Primary information: tag chips remain visible in a fixed two-line area and start from the left; the root gallery tab title reads the localized gallery label instead of the site name.
Primary action: tapping a tag still publishes the raw EH exact tag search; horizontal drag scrolls the two-line tag strip without handing the gesture to the outer tab Swiper.
Reuse or deviation: reuse the existing `GalleryWaterfallCard` chip color/user-tag lookup and native horizontal scroll surface; deviate from the previous two-chip-column List because it forced top and bottom tags to share column widths.
Verification: gallery waterflow contract, gallery-list parser contract, favorites load-more contract, home title actions contract, UI grounding contract, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: gallery detail read button HDS style

Status: active
Reference implementation: `../V2Next/feature/detail/src/main/ets/components/HdsMiniBarButton.ets` and `../V2Next/feature/detail/src/main/ets/pages/TopicDetailPage.ets` reply/resume FAB hosts.
Surface type: gallery detail page-level floating Read / Resume action plus its Layout settings selector.
Primary information: the existing Read / Resume label remains the button content; the optional new style changes material only, not the reader entry behavior.
Primary action: tapping the floating button opens Reader at the current resume index; secondary action is choosing Filled or HDS material in `LayoutSettingsPage`.
Reuse or deviation: reuse V2Next HDS `HdsTabs` floating material parameters (`barWidth`, `barHeight`, `activityPadding`, `barBottomMargin`, `systemMaterialEffect`) and NextE's existing translate-based smart-edge animation; deviate only by making the HDS bar a capsule instead of V2Next's circle.
Verification: read-button-style contract, existing gallery detail FAB/header contracts, UI grounding contract, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: gallery detail bottom preview entry position

Status: active
Reference implementation: `feature/gallery/src/main/ets/components/GalleryPreviewGrid.ets` entry split and `feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets` existing image-page scroll helpers.
Surface type: gallery detail preview section entry into the all-thumbnails grid.
Primary information: the top/header entry opens all thumbnails from the beginning; the bottom grid entry opens near the last thumbnail already visible on the detail page.
Primary action: tapping a thumbnail in all thumbnails still opens Reader at that image page.
Reuse or deviation: reuse `AllThumbnailsParams` and the existing `visibleIndexForImagePage` / `loadImagePage` path; only add an optional initial image page for the bottom grid entry.
Verification: all-thumbnails page jump contract, thumbnail mode contract, UI grounding contract, V1 decorator inventory, diff check, and signed HarmonyOS build.
