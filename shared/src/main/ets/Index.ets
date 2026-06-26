// NextE shared library public surface.
// Feature modules and entry import ONLY from this barrel ('shared'), never deep paths.

// theme
export { ThemeConstants } from './theme/ThemeConstants'

// constants
export { StorageKeys } from './constants/StorageKeys'
export { EhConstants } from './constants/EhConstants'
export { InternalQaRoutes } from './constants/InternalQaRoutes'

// model
export { SimpleTag } from './model/SimpleTag'
export { EhTagSuggestion } from './model/EhTagSuggestion'
export { TagGroup } from './model/TagGroup'
export { EhGallery } from './model/EhGallery'
export {
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
} from './model/DownloadGalleryTask'
export { ViewedGallery } from './model/ViewedGallery'
export { Favcat } from './model/Favcat'
export { EhMytags, EhUsertag, EhMytagSet } from './model/EhMytags'
export { EhGalleryComment } from './model/EhGalleryComment'
export { EhGalleryImage } from './model/EhGalleryImage'
export { EhGalleryTorrent, EhGalleryTorrentList } from './model/EhGalleryTorrent'
export {
  EhGalleryArchiverItem,
  EhGalleryArchiverQuote,
  EhGalleryArchiverSubmitResult,
} from './model/EhGalleryArchiver'
export { GalleryList } from './model/GalleryList'
export {
  GalleryDetailParams,
  GalleryInfoParams,
  GalleryTorrentsParams,
  GalleryArchiverParams,
  GalleryWebParams,
  GalleryEditTagsParams,
  ReaderParams,
  ImagePageRouteErrorParams,
  GalleryCommentsParams,
  AllThumbnailsParams,
  MyTagsPageParams,
} from './model/RouteParams'

// components
export {
  EhThumbnail,
  THUMBNAIL_VISUAL_AUTO,
  THUMBNAIL_VISUAL_LOADING,
  THUMBNAIL_VISUAL_ERROR,
} from './components/EhThumbnail'
export { EhSpriteThumbnail } from './components/EhSpriteThumbnail'
export { PreviewThumbTile } from './components/PreviewThumbTile'
export { RatingStars } from './components/RatingStars'
export {
  immersiveTitleBarOpts,
  immersiveTitleBar,
  immersiveMaterialType,
} from './components/ImmersiveTitleBar'
export { EhWebView } from './components/EhWebView'
export { GalleryCard } from './components/GalleryCard'
export { PageLoadingState, PageErrorState, CardEmptyState } from './components/PageState'
export { LoadingFooter } from './components/LoadingFooter'
export { PullRefresh, PullRefreshController } from './components/PullRefresh'
export { PullRefreshListScaffold } from './components/PullRefreshListScaffold'
export { PullRefreshGridScaffold } from './components/PullRefreshGridScaffold'
export { PullRefreshWaterFlowScaffold } from './components/PullRefreshWaterFlowScaffold'
export { GalleryGridCard } from './components/GalleryGridCard'
export { GalleryWaterfallCard } from './components/GalleryWaterfallCard'
export { GalleryCoverWallCard } from './components/GalleryCoverWallCard'
export { GalleryCategoryCornerBadge } from './components/GalleryCategoryCornerBadge'
export { GallerySimpleCard } from './components/GallerySimpleCard'
export { SecondaryListScaffold } from './components/SecondaryListScaffold'
export { GroupedListSection } from './components/GroupedListSection'
export { ConciseListRow } from './components/ConciseListRow'
export { SettingsCheckedMenuItem } from './components/SettingsCheckedMenuItem'
export { SectionHeader } from './components/SectionHeader'
export { AppSearchField } from './components/AppSearchField'
export { AppModalScaffold } from './components/AppModalScaffold'
export { appSheetOptions } from './components/AppSheetOptions'
export { AppColorPicker } from './components/AppColorPicker'
export { HdsCapsuleBarButton } from './components/HdsCapsuleBarButton'

// parser
export { HtmlSelectorUtils } from './parser/HtmlSelectorUtils'
export { EhGalleryListParser } from './parser/EhGalleryListParser'
export { EhFavcatListParser } from './parser/EhFavcatListParser'
export { EhMytagsParser } from './parser/EhMytagsParser'
export { EhUconfigParser } from './parser/EhUconfigParser'
export {
  EhProfile,
  EhProfileSettings,
  EhRadioOption,
  EhUconfigToggleItem,
  EhUconfigCategory,
} from './model/EhProfileSettings'
export { EhCommentParser } from './parser/EhCommentParser'
export { EhGalleryDetailParser } from './parser/EhGalleryDetailParser'
export { EhGalleryImageParser } from './parser/EhGalleryImageParser'
export { EhGalleryTorrentParser } from './parser/EhGalleryTorrentParser'
export { EhGalleryArchiverParser } from './parser/EhGalleryArchiverParser'
export { EhImagePageParser, ImagePageResult } from './parser/EhImagePageParser'
export { EhGalleryFavoriteParser, GalleryFavoriteInfo } from './parser/EhGalleryFavoriteParser'

// services
export { ImageResolveService } from './services/ImageResolveService'
export {
  CachedImageFileService,
  CachedImageFileResult,
  CachedImageProgress,
} from './services/CachedImageFileService'
export { ImagePageRouteService, ImagePageRouteTarget } from './services/ImagePageRouteService'
export { TagTranslationService, TagTranslationStatus, TagTranslationInfo } from './services/TagTranslationService'
export { CommentTranslationService } from './services/CommentTranslationService'
export { LocalBlockService } from './services/LocalBlockService'
export { EhPageCacheService } from './services/EhPageCacheService'
export { CacheStat } from './services/CacheStat'
export { BackupService } from './backup/BackupService'
export {
  BackupAppMetadata,
  BackupExportOptions,
  BackupEnvelopeV1,
  BackupParseResult,
  BackupPreview,
  BackupRestoreResult,
  BACKUP_FILE_SUFFIX,
  MAX_BACKUP_BYTES,
} from './backup/BackupTypes'
export { MyTagsTargetService, MyTagsTargetResolveResult } from './services/MyTagsTargetService'
export { CoverColorService } from './services/CoverColorService'
export { MotionHandStateService, MotionHandEdge } from './services/MotionHandStateService'

// settings/state
export {
  COMMENT_TRANSLATION_DISPLAY_BILINGUAL,
  COMMENT_TRANSLATION_DISPLAY_REPLACE,
  CommentTranslationSettingsState,
  connectCommentTranslationSettings,
} from './state/CommentTranslationSettingsState'
export {
  CommentTranslationSettings,
  CommentTranslationSettingsSnapshot,
} from './settings/CommentTranslationSettings'
export {
  LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE,
  LOCAL_BLOCK_COMMENT_DISPLAY_HIDE,
  LOCAL_BLOCK_TYPE_COMMENT,
  LOCAL_BLOCK_TYPE_COMMENTATOR,
  LOCAL_BLOCK_TYPE_TITLE,
  LOCAL_BLOCK_TYPE_UPLOADER,
  LocalBlockRule,
  LocalBlockState,
  connectLocalBlock,
} from './state/LocalBlockState'
export { LocalBlockSettings } from './settings/LocalBlockSettings'

// network
export { EhCookieStore } from './network/EhCookieStore'
export { EhHttpClient, EhTextResponse } from './network/EhHttpClient'
export {
  EhApiService,
  GalleryListQuery,
  FavoritesQuery,
  GalleryDetailResult,
  GalleryCommentWrite,
  MyTagsAddUpdate,
  MyTagsDeleteUpdate,
  MyTagsTagsetUpdate,
} from './network/EhApiService'
export {
  EhApiPhpService,
  GalleryRatingResult,
  CommentVoteResult,
  TagGalleryResult,
  SetUserTagResult,
} from './network/EhApiPhpService'
export { EhError, EhErrorKind } from './network/EhError'
export { EhErrorClassifier } from './network/EhErrorClassifier'

// i18n
export { AppStrings } from './i18n/AppStrings'
export { EhErrorText } from './i18n/EhErrorText'

// utils
export { FavcatSlotResolver, FavcatSlotResolveResult } from './utils/FavcatSlotResolver'

// diagnostics
export { DiagnosticLogger, DiagnosticLogLevel } from './diagnostics/DiagnosticLogger'
export { DiagnosticsLogFileSink, DiagnosticsLogFileInfo } from './diagnostics/DiagnosticsLogFileSink'
export { DiagnosticsStore } from './diagnostics/DiagnosticsStore'
export { DiagnosticsSettings, DiagnosticsSettingsSnapshot } from './settings/DiagnosticsSettings'
export { DiagnosticsFileExport, DiagnosticsExportFile } from './settings/DiagnosticsFileExport'

// utils
export { ReaderImageTransformCoordinator } from './utils/ReaderImageTransformCoordinator'
export {
  ActionFollowTouchTracker,
  ActionFollowTouchState,
  ActionFollowTouchUpdate,
} from './utils/ActionFollowTouchTracker'

// state holders (AppStorageV2)
export { NavStackHolder, connectNavStack } from './state/NavStackHolder'
export {
  PendingEhUrlState,
  connectPendingEhUrl,
  publishPendingEhUrl,
} from './state/PendingEhUrlState'
export { SiteModeState, connectSiteMode } from './state/SiteModeState'
export { UserTagStore } from './state/UserTagStore'
export { UserTagSignal, connectUserTagSignal } from './state/UserTagSignal'
export { ListMode, ListModeState, connectListMode } from './state/ListModeState'
export { GalleryTitleState, connectGalleryTitle } from './state/GalleryTitleState'
export { ReadMode, ReadColumnMode, ReadModeState, connectReadMode } from './state/ReadModeState'
export {
  DownloadOriginalMode,
  DownloadSettingsState,
  connectDownloadSettings,
} from './state/DownloadSettingsState'
export {
  AutoLockTimeout,
  SecuritySettingsState,
  connectSecuritySettings,
} from './state/SecuritySettingsState'
export {
  DownloadViewType,
  DownloadViewState,
  connectDownloadView,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
} from './state/DownloadViewState'
export { DownloadQueueState, connectDownloadQueue } from './state/DownloadQueueState'
export { ThumbnailModeState, connectThumbnailMode } from './state/ThumbnailModeState'
export { CoverBackgroundState, connectCoverBackground } from './state/CoverBackgroundState'
export { ActionAlignmentState, connectActionAlignment } from './state/ActionAlignmentState'
export { ActionHandEdgeState, connectActionHandEdge } from './state/ActionHandEdgeState'
export { SearchHistoryState, connectSearchHistory } from './state/SearchHistoryState'
export { LocalFavState, connectLocalFav } from './state/LocalFavState'
export {
  GalleryFavoriteMutationState,
  connectGalleryFavoriteMutation,
} from './state/GalleryFavoriteMutationState'
export {
  GalleryRatingMutationState,
  connectGalleryRatingMutation,
} from './state/GalleryRatingMutationState'
export {
  CommentVoteMutationState,
  connectCommentVoteMutation,
} from './state/CommentVoteMutationState'
export {
  GALLERY_COMMENT_ACTION_AUTHOR,
  GALLERY_COMMENT_ACTION_AUTO_TRANSLATE,
  GALLERY_COMMENT_ACTION_EDIT,
  GALLERY_COMMENT_ACTION_REPLY,
  GALLERY_COMMENT_ACTION_RENDER_STATE,
  GALLERY_COMMENT_ACTION_TOGGLE_TRANSLATION,
  GALLERY_COMMENT_ACTION_TRANSLATE,
  GALLERY_COMMENT_ACTION_VOTE,
  GalleryCommentActionState,
  connectGalleryCommentAction,
} from './state/GalleryCommentActionState'
export {
  RemoteFavoriteSlotCacheState,
  connectRemoteFavoriteSlotCache,
} from './state/RemoteFavoriteSlotCacheState'
export {
  GalleryReadProgressState,
  ReadProgressEntry,
  connectGalleryReadProgress,
} from './state/GalleryReadProgressState'
export { ViewedHistoryState, connectViewedHistory } from './state/ViewedHistoryState'
export {
  LayoutSafeAreaState,
  connectLayoutSafeArea,
  LayoutSafeAreaBridge,
} from './state/LayoutSafeAreaState'
export { SearchActionState, connectSearchAction } from './state/SearchActionState'
export { AppColorFavoritesState, connectAppColorFavorites } from './state/AppColorFavoritesState'
export { HomeTabAutoHideState, connectHomeTabAutoHide } from './state/HomeTabAutoHideState'
export { DiagnosticsState, connectDiagnostics } from './state/DiagnosticsState'
export {
  TagTranslationSettingsState,
  connectTagTranslationSettings,
  TAG_INTRO_IMAGE_DISABLE,
  TAG_INTRO_IMAGE_NON_H,
  TAG_INTRO_IMAGE_R18,
  TAG_INTRO_IMAGE_R18G,
  TAG_TRANSLATION_UPDATE_EVERY_START,
  TAG_TRANSLATION_UPDATE_MANUAL,
} from './state/TagTranslationSettingsState'
export { SearchPageParams } from './state/SearchPageParams'
export {
  SearchFilterState,
  connectSearchFilter,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
  SEARCH_SCOPE_FAVORITE,
} from './state/SearchFilterState'
export { AuthState, connectAuth } from './state/AuthState'
export { AccountListState, connectAccountList } from './state/AccountListState'
export {
  HomeSourceState,
  HomeSourceBridge,
  connectHomeSource,
  SELECTOR_BAR_HEIGHT,
  TabVisualIndexState,
  connectHomeSourceVisualIndex,
  connectToplistVisualIndex,
} from './state/HomeSourceState'
export { SubTabBar } from './components/SubTabBar'
export { TabItem } from './model/TabItem'
export { RetainedSubtabHost, ActiveKeyState } from './components/RetainedSubtabHost'
export {
  FavSelectionState,
  connectFavSelection,
  FavSelectionBridge,
  connectFavcatVisualIndex,
} from './state/FavSelectionState'

// settings
export { SettingsBootstrap } from './settings/SettingsBootstrap'
export { ThemeSettings } from './settings/ThemeSettings'
export { LanguageSettings } from './settings/LanguageSettings'
export { ThemeColorSettings, ThemeColorOption } from './settings/ThemeColorSettings'
export {
  ImmersiveMaterialSettings,
  ImmersiveMaterialOption,
  ImmersiveMaterialEffect,
} from './settings/ImmersiveMaterialSettings'
export {
  ImmersiveMaterialSettingsState,
  connectImmersiveMaterialSettings,
} from './state/ImmersiveMaterialSettingsState'
export {
  ThemeDisplayState,
  connectThemeDisplay,
  LanguageState,
  connectLanguageState,
  ThemeColorState,
  connectThemeColor,
} from './state/AppearanceState'
export { CookieJarSettings } from './settings/CookieJarSettings'
export { AccountListSettings } from './settings/AccountListSettings'
export { SiteModeSettings } from './settings/SiteModeSettings'
export { ListModeSettings } from './settings/ListModeSettings'
export { GalleryTitleSettings } from './settings/GalleryTitleSettings'
export { ReadModeSettings } from './settings/ReadModeSettings'
export { ReadButtonStyleSettings, ReadButtonStyleOption } from './settings/ReadButtonStyleSettings'
export {
  READ_BUTTON_STYLE_FILLED,
  READ_BUTTON_STYLE_HDS,
  ReadButtonStyleState,
  connectReadButtonStyle,
} from './state/ReadButtonStyleState'
export { ThumbnailModeSettings } from './settings/ThumbnailModeSettings'
export { CoverBackgroundSettings } from './settings/CoverBackgroundSettings'
export {
  ActionAlignmentSettings,
  ActionAlignmentMode,
  ActionAlignmentOption,
} from './settings/ActionAlignmentSettings'
export { SearchHistorySettings } from './settings/SearchHistorySettings'
export { SearchFilterSettings, SearchFilterSnapshot } from './settings/SearchFilterSettings'
export { FavcatListSettings } from './settings/FavcatListSettings'
export { LocalFavSettings } from './settings/LocalFavSettings'
export { GalleryReadProgressSettings } from './settings/GalleryReadProgressSettings'
export { ViewedHistorySettings } from './settings/ViewedHistorySettings'
export { DownloadSettings } from './settings/DownloadSettings'
export { DownloadQueueSettings } from './settings/DownloadQueueSettings'
export { SecuritySettings } from './settings/SecuritySettings'
export { SubtabSelectionSettings } from './settings/SubtabSelectionSettings'
export { AppColorFavoritesSettings } from './settings/AppColorFavoritesSettings'
export { HomeTabSettings } from './settings/HomeTabSettings'
export { ToplistFilterSettings } from './settings/ToplistFilterSettings'
export { TagTranslationSettings } from './settings/TagTranslationSettings'
export { ToplistFilterState, connectToplistFilter } from './state/ToplistFilterState'

// utils
export { EhUrlRouter, GalleryRef, ImagePageRef } from './utils/EhUrlRouter'
export { BasicDataSource } from './utils/BasicDataSource'
export { ShareUtil } from './utils/ShareUtil'
export { ImageSaveUtil } from './utils/ImageSaveUtil'
export { ResponsiveGrid } from './utils/ResponsiveGrid'
export { RootRefreshRegistry } from './utils/RootRefreshRegistry'
export { galleryWaterfallColumnCount, clampColumnWidth } from './utils/GalleryColumns'
