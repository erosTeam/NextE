# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: pull-refresh edge-drag ownership

Status: active
Reference implementation: `../V2Next/shared/src/main/ets/components/PullRefreshListScaffold.ets` and `../V2Next/shared/src/main/ets/components/SecondaryListScaffold.ets` both use `EdgeEffect.None`; HarmonyOS offline docs say child scroll nodes should disable edge effect when custom nested/edge scrolling owns the movement.
Surface type: shared List/Grid/WaterFlow scaffolds that sit under custom `PullRefresh`, plus the plain secondary list scaffold default.
Primary information: list content should move once during an edge pull, with the custom refresh indicator and content offset remaining the only visible pull feedback.
Primary action: drag down at the top to refresh or drag up at the bottom for manual load-more where supported; normal list scrolling remains unchanged.
Reuse or deviation: reuse V2Next's no-native-edge-effect scaffold policy for pull-refresh surfaces; keep `alwaysEnabled` only as a local opt-in for non-refresh sparse-content lists such as Settings pages and Search suggestions.
Verification: scroll edge-effect ownership contract, search tag-suggestion contract, V1 decorator inventory, UI grounding contract, and signed HarmonyOS build.

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

## Active: favorites retained favcat preference

Status: active
Reference implementation: `entry/src/main/ets/components/FavcatBar.ets`, `feature/user/src/main/ets/pages/FavoritesPage.ets`, `feature/user/src/main/ets/pages/FavoriteSelectorPage.ets`, and `shared/src/main/ets/components/RetainedSubtabHost.ets`.
Surface type: Favorites favcat sub-tabs plus the full-screen favorite-category selector.
Primary information: the selected favcat is a stable key where `a` means all favorites, `0..9` are remote EH favorite slots, and `l` is the local-only slot.
Primary action: tapping either the pinned sub-tab chip or the selector row switches the retained Favorites page and persists the same stable key for the next app launch.
Reuse or deviation: reuse the existing `SubtabSelectionSettings.setFavoritesFavcat` preference writer for every selection path; deviate from the old selector-only direct V2 mutation because it updated memory without writing `subtab.favoritesFavcat`.
Verification: retained subtab preference contract, favorites selector contract, V1 decorator inventory, UI grounding contract, and signed HarmonyOS build.

## Active: gallery detail comment cards

Status: active
Reference implementation: `../V2Next/shared/src/main/ets/components/ReplyCard.ets`, `../V2Next/feature/detail/src/main/ets/components/HotRepliesPanel.ets`, and `feature/gallery/src/main/ets/components/GalleryCommentsCard.ets`.
Surface type: gallery detail comments preview and full comments page comment list.
Primary information: each comment is the primary object and should read as its own white card; the detail preview still exposes only the first two comments as one close-knit group.
Primary action: tapping a preview comment or the comments header opens the full comments page; full comments keep author, vote, reply, and edit actions, with reply and own-comment edit sharing the same bottom composer surface.
Reuse or deviation: reuse Next2V's white top-level reply-card surface, `SPACE_SM - 2` reply spacing on both preview and full comments surfaces, and V2Next's shared large-card radii (`RADIUS_MD = 22`, `RADIUS_CARD = 24`); keep narrow grid tiles on a compact `GALLERY_GRID_CARD_RADIUS = 16`, keep the detail header cover on its dedicated inset radius, keep the Waterfall category corner badge attached to the cover's true top-right corner like Grid/eros_fe instead of manually shifting it inward, remove the old outer grouped card because it produced card-inside-card chrome, invert quote colors so quoted replies sit on a secondary gray block with `COMMENT_QUOTE_RADIUS = 8` inside the white comment card, keep score badges on the dark-aware secondary surface instead of separator chrome, and retire the old edit half-modal by reusing the reply composer context preview for edits.
Verification: gallery comment card layout contract, V2Next card radius contract, full-comments entry contract, reply-reference contract, badge/vote/compose contracts, V1 decorator inventory, UI grounding contract, and signed HarmonyOS build.
