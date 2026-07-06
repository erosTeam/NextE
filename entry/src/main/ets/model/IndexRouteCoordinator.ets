export type IndexDestinationFamily =
  'galleryDetail' |
  'galleryInfo' |
  'galleryTorrents' |
  'galleryArchiver' |
  'galleryWeb' |
  'galleryEditTags' |
  'search' |
  'reader' |
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
  'downloadSettings' |
  'searchSettings' |
  'localBlockSettings' |
  'imageBlockSettings' |
  'tagTranslationSettings' |
  'translationSettings' |
  'syncSettings' |
  'webDavSyncSettings' |
  'advancedSettings' |
  'securitySettings' |
  'about' |
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
    'GalleryEditTags': 'galleryEditTags',
    'Search': 'search',
    'Reader': 'reader',
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
    'DownloadSettings': 'downloadSettings',
    'SearchSettings': 'searchSettings',
    'LocalBlockSettings': 'localBlockSettings',
    'ImageBlockSettings': 'imageBlockSettings',
    'TagTranslationSettings': 'tagTranslationSettings',
    'TranslationSettings': 'translationSettings',
    'SyncSettings': 'syncSettings',
    'WebDavSyncSettings': 'webDavSyncSettings',
    'AdvancedSettings': 'advancedSettings',
    'SecuritySettings': 'securitySettings',
    'About': 'about',
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
