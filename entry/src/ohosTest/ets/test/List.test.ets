import galleryDetailParserTest from './GalleryDetailParser.test'
import readProgressStateTest from './ReadProgressState.test'
import readerImagePrioritySchedulerTest from './ReaderImagePriorityScheduler.test'
import commentTranslationQueueSchedulerTest from './CommentTranslationQueueScheduler.test'
import commentTranslationMemoryCacheTest from './CommentTranslationMemoryCache.test'
import commentTranslationCacheEpochTest from './CommentTranslationCacheEpoch.test'
import commentReferenceSnapshotCacheTest from './CommentReferenceSnapshotCache.test'
import imageResolveMemoryCacheTest from './ImageResolveMemoryCache.test'
import gallerySeedSchedulerTest from './GallerySeedScheduler.test'
import imageBlockThumbnailHashMemoryCacheTest from './ImageBlockThumbnailHashMemoryCache.test'
import imageBlockThumbnailHashQueueSchedulerTest from './ImageBlockThumbnailHashQueueScheduler.test'
import coverColorResourceBoundsTest from './CoverColorResourceBounds.test'
import preloadedGalleryListMemoryCacheTest from './PreloadedGalleryListMemoryCache.test'
import userTagStoreInlineCacheTest from './UserTagStoreInlineCache.test'
import userTagRequestFenceTest from './UserTagRequestFence.test'
import cookieJarRefreshIdentityTest from './CookieJarRefreshIdentity.test'
import siteModeRequestFenceTest from './SiteModeRequestFence.test'
import ehProfileSettingsRequestFenceTest from './EhProfileSettingsRequestFence.test'
import userProfileRequestFenceTest from './UserProfileRequestFence.test'
import ehProfileSelectionCookieTest from './EhProfileSelectionCookie.test'
import diagnosticsLogFileSinkTest from './DiagnosticsLogFileSink.test'
import imageBlockPreviewCacheMaintenanceTest from './ImageBlockPreviewCacheMaintenance.test'
import cachedImageFileMaintenanceTest from './CachedImageFileMaintenance.test'
import searchFilterPersistSchedulerTest from './SearchFilterPersistScheduler.test'
import webDavConfigPersistSchedulerTest from './WebDavConfigPersistScheduler.test'
import downloadQueueTaskProjectionTest from './DownloadQueueTaskProjection.test'
import favoritesTagTranslationRaceTest from './FavoritesTagTranslationRace.test'
import readerSessionCacheStateTest from './ReaderSessionCacheState.test'
import basicDataSourceChangeNotificationTest from './BasicDataSourceChangeNotification.test'
import customProfilesPersistSchedulerTest from './CustomProfilesPersistScheduler.test'
import allThumbnailsTailAppendTest from './AllThumbnailsTailAppend.test'
import galleryListMutationTargetedUpdateTest from './GalleryListMutationTargetedUpdate.test'
import galleryResumeBatchTest from './GalleryResumeBatch.test'
import listTagTranslationMutationRaceTest from './ListTagTranslationMutationRace.test'
import readerImageLoadPresentationTest from './ReaderImageLoadPresentation.test'
import gallerySeedDetailRefreshGateTest from './GallerySeedDetailRefreshGate.test'

export default function testsuite(): void {
  galleryDetailParserTest()
  readProgressStateTest()
  readerImagePrioritySchedulerTest()
  commentTranslationQueueSchedulerTest()
  commentTranslationMemoryCacheTest()
  commentTranslationCacheEpochTest()
  commentReferenceSnapshotCacheTest()
  imageResolveMemoryCacheTest()
  gallerySeedSchedulerTest()
  imageBlockThumbnailHashMemoryCacheTest()
  imageBlockThumbnailHashQueueSchedulerTest()
  coverColorResourceBoundsTest()
  preloadedGalleryListMemoryCacheTest()
  userTagStoreInlineCacheTest()
  userTagRequestFenceTest()
  cookieJarRefreshIdentityTest()
  siteModeRequestFenceTest()
  ehProfileSettingsRequestFenceTest()
  userProfileRequestFenceTest()
  ehProfileSelectionCookieTest()
  diagnosticsLogFileSinkTest()
  imageBlockPreviewCacheMaintenanceTest()
  cachedImageFileMaintenanceTest()
  searchFilterPersistSchedulerTest()
  webDavConfigPersistSchedulerTest()
  downloadQueueTaskProjectionTest()
  favoritesTagTranslationRaceTest()
  readerSessionCacheStateTest()
  basicDataSourceChangeNotificationTest()
  customProfilesPersistSchedulerTest()
  allThumbnailsTailAppendTest()
  galleryListMutationTargetedUpdateTest()
  galleryResumeBatchTest()
  listTagTranslationMutationRaceTest()
  readerImageLoadPresentationTest()
  gallerySeedDetailRefreshGateTest()
}
