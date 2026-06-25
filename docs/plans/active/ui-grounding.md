# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: reader original image display

Status: active
Reference implementation: `../eros_fe/lib/pages/image_view/view/view_image.dart` long-press current image path into `showImageSheet`, `../eros_fe/lib/pages/image_view/view/view_widget.dart` `showSaveActionSheet` / `showShareActionSheet`, and `../eros_fe/lib/network/request.dart` / `api.dart` showpage parsing of `originImageUrl`.
Surface type: Reader bottom toolbar current-page image source action.
Primary information: the current reader page remains the primary surface; original image display is an explicit per-page source switch backed by the parsed `/fullimg` URL.
Primary action: tap the Reader toolbar original badge to resolve and display the current page's original image; save/share use whatever source is currently displayed.
Reuse or deviation: reuse NextE `ImageResolveService`, `CachedImageFileService`, existing Reader chrome buttons, and the existing single/double/vertical image renderers; deviate from eros_fe's save/share action sheet by adding an in-reader view toggle because this lane is about viewing the original, not only exporting it.
Verification: reader original-image contract, image-page parser contract, current-image share/save contracts, i18n duplicate check, V1 decorator inventory, UI grounding contract, signed HarmonyOS build, and X7 emulator user path with screenshot plus hilog evidence containing `original_mode_on` / `display_original` and `fullimg true`.

## Active: local block rules

Status: active
Reference implementation: `../eros_fe/lib/common/controller/block_controller.dart`, `../eros_fe/lib/pages/setting/block/blockers_page.dart`, `feature/settings/src/main/ets/pages/SearchSettingsPage.ets`, and `feature/gallery/src/main/ets/components/GalleryCommentsCard.ets`.
Surface type: EH settings entry, local block rules settings page, retained gallery-list/search/favorites filtering, gallery-detail comment preview, and full comments page.
Primary information: local block rules hide galleries by title/uploader and comments by author/text or low score; raw comment data remains available for reply-reference resolution.
Primary action: add a local block rule from the single title-bar `+` entry, edit/enable/disable/remove existing rules in their buckets, choose whether blocked comments are hidden or collapsed, or enable score-threshold filtering for comments.
Reuse or deviation: reuse eros_fe's four rule buckets plus low-score threshold, NextE `SecondaryListScaffold` / `GroupedListSection` / `ConciseListRow` settings chrome, existing per-comment cards, and the retained-list VM `setData()` refresh path used by tag translation/favcat metadata updates; deviate by storing rules in AppStorageV2-backed preferences instead of FE profile JSON and by showing blocked comments as a compact collapsed card when the user chooses that display mode.
Verification: local block contract covering title/uploader/comment-author/comment-text/score/regex/disabled rules, UI grounding contract, V1 decorator inventory, i18n duplicate check, signed HarmonyOS build, and emulator user paths for the single add entry retaining the last selected type, adding title/uploader rules, re-filtering already-loaded Home rows, persistence after restart, comment/commentator filtering, hide-vs-collapse display mode, score-threshold filtering after vote-state changes, edit/delete cleanup, and no real-device interaction.

## Active: Toplist hidden My Tags setting

Status: active
Reference implementation: `feature/settings/src/main/ets/pages/EhSettingsPage.ets` existing HDS settings rows, `shared/src/main/ets/components/ConciseListRow.ets`, and `shared/src/main/ets/network/EhApiService.ets` existing `UserTagStore.anyHidden()` local list filtering.
Surface type: EH settings page switch plus Toplist gallery-list fetch path.
Primary information: Toplist can hide galleries carrying tags the user already marked hidden in My Tags; the setting defaults on so rankings do not ignore the user's local blocked-tag preference.
Primary action: toggle the EH Settings switch to apply or stop applying My Tags hidden-tag filtering to Toplist; Advanced Search `disableTagFilter/f_sft` remains a separate search-only server parameter.
Reuse or deviation: reuse the existing `GroupedListSection` / `ConciseListRow` switch row and existing `filterHidden()` logic; deviate only by adding a dedicated Toplist-local state field instead of reusing Search Filter state.
Verification: Toplist hidden-filter contract, gallery paging contract, UI grounding contract, V1 decorator inventory, i18n duplicate check, and signed HarmonyOS build.

## Active: async tag translation visible refresh

Status: active
Reference implementation: `shared/src/main/ets/utils/BasicDataSource.ets` `setData()` reload contract, `shared/src/main/ets/components/GalleryCard.ets` / `GalleryWaterfallCard.ets` tag chip render path, and `feature/gallery/src/main/ets/components/GalleryTagsCard.ets` detail tag member render path.
Surface type: gallery list/search/favorites cards and gallery detail tag chips that receive translated tag text after the first raw render.
Primary information: raw EH tag text may appear briefly, but the same visible card/chip must update to the localized `translat` value when async tag translation finishes.
Primary action: no new user action; existing card tap/tag tap/long press behavior remains unchanged while render identity changes only to refresh translated text.
Reuse or deviation: reuse the existing `BasicDataSource.setData()` reload path and existing card/chip components; deviate from pure `gid` / namespace-only `ForEach` keys because async translation changes display text without changing gallery identity.
Verification: tag translation contract, page cache contract, UI grounding contract, V1 decorator inventory, emulator screenshot evidence for list/detail translated tags, and signed HarmonyOS build.

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

## Active: comment translation

Status: active
Reference implementation: `../eros_n/lib/pages/gallery/comments_page.dart`, `../eros_n/lib/pages/gallery/comment_translation_provider.dart`, `../eros_n/lib/utils/translation/translate_helper.dart`, and `../eros_n/lib/pages/setting/translation_setting_page.dart`.
Surface type: full gallery comments page comment rows plus a Settings translation page.
Primary information: the comment remains the primary object; translation is an optional per-comment alternate text backed by a local cache, with the original text still available.
Primary action: tapping the translate footer icon translates or toggles a comment; settings let the user enable translation, auto-translate full comments, choose Google-only fallback behavior, and enter an OpenAI-compatible API URL/key/model.
Reuse or deviation: reuse NextE `GalleryCommentsCard` footer actions, `SecondaryListScaffold`, `GroupedListSection`, `ConciseListRow`, V2 settings holders, and `LocalDataStore`; deviate from eros_n by skipping model-list fetching and complex bilingual style previews in the first closure.
Verification: comment translation contract, UI grounding contract, V1 decorator inventory, i18n duplicate check, and signed HarmonyOS build.

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
Reuse or deviation: reuse Next2V's white top-level reply-card surface, `SPACE_SM - 2` reply spacing on both preview and full comments surfaces, and V2Next's shared large-card radii (`RADIUS_MD = 22`, `RADIUS_CARD = 24`); keep narrow grid tiles on a compact `GALLERY_GRID_CARD_RADIUS = 16`, keep the detail header cover on its dedicated inset radius, keep the Waterfall category corner badge attached to the cover's true top-right corner like Grid/eros_fe instead of manually shifting it inward, remove the old outer grouped card because it produced card-inside-card chrome, invert quote colors so quoted replies sit on a secondary gray block with `COMMENT_QUOTE_RADIUS = 8` inside the white comment card, keep score badges on the dark-aware secondary surface instead of separator chrome, emphasize only resolved `@user` reply mentions with the same link/accent color while leaving unresolved text plain, and retire the old edit half-modal by reusing the reply composer context preview for edits.
Verification: gallery comment card layout contract, V2Next card radius contract, full-comments entry contract, reply-reference contract including resolved mention emphasis, badge/vote/compose contracts, V1 decorator inventory, UI grounding contract, and signed HarmonyOS build.

## Active: retained subtab settled selection timing

Status: active
Reference implementation: `shared/src/main/ets/components/RetainedSubtabHost.ets`, `shared/src/main/ets/components/SubTabBar.ets`, and the V2Next retained-tab visual-index pattern used by Home/Toplist/Favorites.
Surface type: retained Home source, Toplist period, and Favorites favcat Swiper-backed SubTab surfaces.
Primary information: during a horizontal swipe, the SubTab indicator should track gesture progress without prematurely snapping to the destination tab or rebuilding the selected-key surface.
Primary action: swiping or tapping a subtab changes the retained page; selection state is committed only after the Swiper settles.
Reuse or deviation: reuse Next2V's split between high-frequency visual state and discrete selection state: `visualIndex` drives only the indicator/highlight, while SubTabBar recenters from a discrete `selectedIndex` using native `ListScroller.scrollToIndex(..., ScrollAlign.CENTER)` instead of hand-computed `xOffset`; deviate from the old `onChange` path by not publishing `selectedKey`, `activeKey`, or integer `visualIndex` from `onChange` because ArkUI can fire it before the transition visually finishes.
Verification: retained-tab framework contract, retained subtab preference contract, UI grounding contract, V1 decorator inventory, diff check, and signed HarmonyOS build.

## Active: gallery list adaptive cover slot

Status: active
Reference implementation: `../eros_fe/lib/pages/item/gallery_item.dart` `_CoverImage`, `shared/src/main/ets/components/GalleryCard.ets`, and `shared/src/main/ets/components/EhThumbnail.ets`.
Surface type: LIST-mode gallery card cover in non-fixed row-height mode.
Primary information: the cover image remains the left-side visual anchor; the fit decision compares parsed image dimensions against the actual cover container ratio, not a guessed row height.
Primary action: tapping the row still opens gallery detail; this lane only corrects cover fill/background presentation for adaptive list rows.
Reuse or deviation: reuse the existing measured list width and `EhThumbnail` gradient/blur letterbox background; deviate from the old precomputed `LIST_CARD_COVER_ASPECT` slot by measuring the stretched cover slot height after the right column lays out.
Verification: list responsive cover contract, list height mode contract, cover presentation contract, UI grounding contract, V1 decorator inventory, and signed HarmonyOS build.

## Active: gallery list tag chip radius token

Status: active
Reference implementation: `shared/src/main/ets/components/GalleryCard.ets`, `shared/src/main/ets/components/GalleryWaterfallCard.ets`, and `shared/src/main/ets/theme/ThemeConstants.ets`.
Surface type: ordinary gallery tag chips in LIST and WATERFALL browsing cards.
Primary information: tag chips remain compact tag labels; only their corner radius is tuned.
Primary action: tapping a tag still publishes the existing exact-tag search.
Reuse or deviation: reuse the existing tag chip renderers and introduce one narrow token, `LIST_TAG_RADIUS = 6`, instead of reusing card/badge/detail-chip radii.
Verification: UI grounding contract, V1 decorator inventory, and signed HarmonyOS build.

## Active: gallery cover wall mode

Status: active
Reference implementation: `../eros_fe/lib/pages/tab/view/list/waterfall_flow.dart`, `../eros_fe/lib/pages/item/gallery_item_flow.dart`, and NextE `shared/src/main/ets/components/GalleryWaterfallCard.ets`.
Surface type: gallery browsing list mode for Home, Search, and Favorites.
Primary information: the cover image is the entire card, with only the existing category/translated corner badge exposed over the image.
Primary action: tapping a cover opens the same gallery detail route; refresh, load-more, footer retry, and scroll-title linkage remain the existing WaterFlow behavior.
Reuse or deviation: reuse `PullRefreshWaterFlowScaffold`, native `FlowItem`, the bounded source-ratio cover policy, and the shared `GalleryCategoryCornerBadge`; deviate from Waterfall by using `GALLERY_COVER_WALL_MIN_W = 120` and omitting title, rating, page/favorite overlay, meta, and tag chips.
Verification: gallery cover wall mode contract, gallery grid mode contract, gallery waterflow contract, settings layout entry contract, i18n duplicate check, UI grounding contract, V1 decorator inventory, and signed HarmonyOS build.

## Active: gallery torrent sheet

Status: active
Reference implementation: `../eros_fe/lib/pages/gallery/view/torrent_dialog.dart` `showTorrentDialog()` / `TorrentItem`, and NextE `feature/gallery/src/main/ets/pages/GalleryTorrentsPage.ets`.
Surface type: gallery detail torrent list opened as a half-modal sheet, with the legacy pushed page kept as a fallback route.
Primary information: each torrent row should show seeds, peers, downloads, size, filename, posted time, and uploader without the metric row collapsing into one visual string.
Primary action: tapping the filename shares/opens the `.torrent` URL; tapping the right action shares the magnet link; closing the sheet returns to the same gallery detail scroll context.
Reuse or deviation: reuse NextE `AppModalScaffold`, `SecondaryListScaffold`, existing torrent parser/network/share helpers, and one shared torrent content component; deviate from the old pushed-only page because eros_fe presents torrent as a dialog instead of a navigation destination.
Verification: UI grounding contract, V1 decorator inventory, signed HarmonyOS build, and sheet screenshot covering loading, one long filename row, and multiple torrent rows.

## Active: gallery detail action chips

Status: active
Reference implementation: NextE `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` existing `relationsRow()` action cluster, and `shared/src/main/ets/components/GalleryWaterfallCard.ets` horizontal chip-strip scrolling.
Surface type: gallery detail auxiliary action row below the info bar.
Primary information: the row exposes secondary actions, not gallery metadata; each action should read as a tappable control with an icon and label.
Primary action: similar search, torrents, rating, archiver, and gallery download keep their existing actions while becoming compact chip targets; parent-gallery navigation moves to the existing title-bar menu.
Reuse or deviation: reuse the existing detail section card, title-bar menu, native horizontal `Scroll`, and the detail page's smart-grip hand-edge state; deviate only from tiny text links by using local capsule `Button` chips with theme-colored icon/text, and place the chip row on a start-based rail so short rows animate left/right with `translate` instead of jumping through centered alignment.
Verification: UI grounding contract, detail header visual contract, V1 decorator inventory, signed HarmonyOS build, and detail screenshot on a narrow viewport with all available actions.
