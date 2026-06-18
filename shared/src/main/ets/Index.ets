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
export { TagGroup } from './model/TagGroup'
export { EhGallery } from './model/EhGallery'
export { DownloadGalleryTask, DownloadGalleryTaskStatus } from './model/DownloadGalleryTask'
export { ViewedGallery } from './model/ViewedGallery'
export { Favcat } from './model/Favcat'
export { EhMytags, EhUsertag, EhMytagSet } from './model/EhMytags'
export { EhGalleryComment } from './model/EhGalleryComment'
export { EhGalleryImage } from './model/EhGalleryImage'
export { EhGalleryTorrent, EhGalleryTorrentList } from './model/EhGalleryTorrent'
export { GalleryList } from './model/GalleryList'
export {
  GalleryDetailParams,
  GalleryInfoParams,
  GalleryTorrentsParams,
  ReaderParams,
  ImagePageRouteErrorParams,
  GalleryCommentsParams,
  AllThumbnailsParams,
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
export { GalleryGridCard } from './components/GalleryGridCard'
export { GallerySimpleCard } from './components/GallerySimpleCard'
export { SecondaryListScaffold } from './components/SecondaryListScaffold'
export { GroupedListSection } from './components/GroupedListSection'
export { ConciseListRow } from './components/ConciseListRow'
export { SectionHeader } from './components/SectionHeader'
export { AppSearchField } from './components/AppSearchField'

// parser
export { HtmlSelectorUtils } from './parser/HtmlSelectorUtils'
export { EhGalleryListParser } from './parser/EhGalleryListParser'
export { EhFavcatListParser } from './parser/EhFavcatListParser'
export { EhMytagsParser } from './parser/EhMytagsParser'
export { EhCommentParser } from './parser/EhCommentParser'
export { EhGalleryDetailParser } from './parser/EhGalleryDetailParser'
export { EhGalleryImageParser } from './parser/EhGalleryImageParser'
export { EhGalleryTorrentParser } from './parser/EhGalleryTorrentParser'
export { EhImagePageParser, ImagePageResult } from './parser/EhImagePageParser'

// services
export { ImageResolveService } from './services/ImageResolveService'
export { ImagePageRouteService, ImagePageRouteTarget } from './services/ImagePageRouteService'

// network
export { EhCookieStore } from './network/EhCookieStore'
export { EhHttpClient, EhTextResponse } from './network/EhHttpClient'
export {
  EhApiService,
  GalleryListQuery,
  FavoritesQuery,
  GalleryDetailResult,
} from './network/EhApiService'
export { EhApiPhpService } from './network/EhApiPhpService'
export { EhError, EhErrorKind } from './network/EhError'
export { EhErrorClassifier } from './network/EhErrorClassifier'

// i18n
export { AppStrings } from './i18n/AppStrings'
export { EhErrorText } from './i18n/EhErrorText'

// diagnostics
export { DiagnosticLogger } from './diagnostics/DiagnosticLogger'

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
export { ReadMode, ReadColumnMode, ReadModeState, connectReadMode } from './state/ReadModeState'
export {
  DownloadOriginalMode,
  DownloadSettingsState,
  connectDownloadSettings,
} from './state/DownloadSettingsState'
export {
  DownloadViewType,
  DownloadViewState,
  connectDownloadView,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
} from './state/DownloadViewState'
export { DownloadQueueState, connectDownloadQueue } from './state/DownloadQueueState'
export { ThumbnailModeState, connectThumbnailMode } from './state/ThumbnailModeState'
export { SearchHistoryState, connectSearchHistory } from './state/SearchHistoryState'
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
export { SearchPageParams } from './state/SearchPageParams'
export { SearchFilterState, connectSearchFilter } from './state/SearchFilterState'
export { AuthState, connectAuth } from './state/AuthState'
export {
  HomeSourceState,
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
export { CookieJarSettings } from './settings/CookieJarSettings'
export { SiteModeSettings } from './settings/SiteModeSettings'
export { ListModeSettings } from './settings/ListModeSettings'
export { ReadModeSettings } from './settings/ReadModeSettings'
export { ThumbnailModeSettings } from './settings/ThumbnailModeSettings'
export { SearchHistorySettings } from './settings/SearchHistorySettings'
export { SearchFilterSettings, SearchFilterSnapshot } from './settings/SearchFilterSettings'
export { GalleryReadProgressSettings } from './settings/GalleryReadProgressSettings'
export { ViewedHistorySettings } from './settings/ViewedHistorySettings'
export { DownloadSettings } from './settings/DownloadSettings'
export { DownloadQueueSettings } from './settings/DownloadQueueSettings'

// utils
export { EhUrlRouter, GalleryRef, ImagePageRef } from './utils/EhUrlRouter'
export { BasicDataSource } from './utils/BasicDataSource'
export { ShareUtil } from './utils/ShareUtil'
export { ResponsiveGrid } from './utils/ResponsiveGrid'
