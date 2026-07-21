export type IndexDestinationFamily =
  'galleryDetail' |
  'galleryInfo' |
  'galleryTorrents' |
  'galleryArchiver' |
  'galleryWeb' |
  'search' |
  'ehLogin' |
  'ehCookieImport' |
  'ehPasswordLogin' |
  'myTags' |
  'history' |
  'favoriteSelector' |
  'tabManager' |
  'tabEdit' |
  'allThumbnails' |
  'galleryComments' |
  'ehSettings' |
  'ehProfileSettings' |
  'account' |
  'accountLogin' |
  'accountCookie' |
  'layoutSettings' |
  'columnDensity' |
  'thumbnailColumnDensity' |
  'cacheSettings' |
  'readerSettings' |
  'readerSuperResolutionModels' |
  'downloadSettings' |
  'searchSettings' |
  'localBlockSettings' |
  'imageBlockSettings' |
  'tagTranslationSettings' |
  'commentTranslationSettings' |
  'comicTranslationSettings' |
  'llmSourceManager' |
  'llmSourceDetail' |
  'syncSettings' |
  'webDavSyncSettings' |
  'advancedSettings' |
  'securitySettings' |
  'about' |
  'systemSymbolBrowser' |
  'imagePageRouteError' |
  'coverFallbackProbe' |
  'readerGestureProbe'

export class IndexRouteCoordinator {
  private static readonly DESTINATION_FAMILIES: Record<string, IndexDestinationFamily> = {
    'GalleryDetail': 'galleryDetail',
    'GalleryInfo': 'galleryInfo',
    'GalleryTorrents': 'galleryTorrents',
    'GalleryArchiver': 'galleryArchiver',
    'GalleryWeb': 'galleryWeb',
    'Search': 'search',
    'EhLogin': 'ehLogin',
    'EhCookieImport': 'ehCookieImport',
    'EhPasswordLogin': 'ehPasswordLogin',
    'MyTags': 'myTags',
    'History': 'history',
    'FavoriteSelector': 'favoriteSelector',
    'TabManager': 'tabManager',
    'TabEdit': 'tabEdit',
    'AllThumbnails': 'allThumbnails',
    'GalleryComments': 'galleryComments',
    'EhSettings': 'ehSettings',
    'EhProfileSettings': 'ehProfileSettings',
    'Account': 'account',
    'AccountLogin': 'accountLogin',
    'AccountCookie': 'accountCookie',
    'LayoutSettings': 'layoutSettings',
    'ColumnDensity': 'columnDensity',
    'ThumbnailColumnDensity': 'thumbnailColumnDensity',
    'CacheSettings': 'cacheSettings',
    'ReaderSettings': 'readerSettings',
    'ReaderSuperResolutionModels': 'readerSuperResolutionModels',
    'DownloadSettings': 'downloadSettings',
    'SearchSettings': 'searchSettings',
    'LocalBlockSettings': 'localBlockSettings',
    'ImageBlockSettings': 'imageBlockSettings',
    'TagTranslationSettings': 'tagTranslationSettings',
    'CommentTranslationSettings': 'commentTranslationSettings',
    'ComicTranslationSettings': 'comicTranslationSettings',
    'LlmSourceManager': 'llmSourceManager',
    'LlmSourceDetail': 'llmSourceDetail',
    'SyncSettings': 'syncSettings',
    'WebDavSyncSettings': 'webDavSyncSettings',
    'AdvancedSettings': 'advancedSettings',
    'SecuritySettings': 'securitySettings',
    'About': 'about',
    'SystemSymbolBrowser': 'systemSymbolBrowser',
    'ImagePageRouteError': 'imagePageRouteError',
    'CoverFallbackProbe': 'coverFallbackProbe',
    'ReaderGestureProbe': 'readerGestureProbe',
  }

  static family(name: string): IndexDestinationFamily | null {
    const family: IndexDestinationFamily | undefined =
      IndexRouteCoordinator.DESTINATION_FAMILIES[(name || '').trim()]
    return family ? family : null
  }
}
