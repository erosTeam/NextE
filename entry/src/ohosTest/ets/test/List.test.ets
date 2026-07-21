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
import recentGalleryDetailMemoryCacheTest from './RecentGalleryDetailMemoryCache.test'
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
import webDavManifestWriteGuardTest from './WebDavManifestWriteGuard.test'
import downloadQueueRestoreReconcilerTest from './DownloadQueueRestoreReconciler.test'
import downloadQueueTaskProjectionTest from './DownloadQueueTaskProjection.test'
import favoritesTagTranslationRaceTest from './FavoritesTagTranslationRace.test'
import readerSessionCacheStateTest from './ReaderSessionCacheState.test'
import basicDataSourceChangeNotificationTest from './BasicDataSourceChangeNotification.test'
import customProfilesPersistSchedulerTest from './CustomProfilesPersistScheduler.test'
import customProfileSyncSemanticsTest from './CustomProfileSyncSemantics.test'
import allThumbnailsTailAppendTest from './AllThumbnailsTailAppend.test'
import galleryListMutationTargetedUpdateTest from './GalleryListMutationTargetedUpdate.test'
import galleryResumeBatchTest from './GalleryResumeBatch.test'
import listTagTranslationMutationRaceTest from './ListTagTranslationMutationRace.test'
import readerImageLoadPresentationTest from './ReaderImageLoadPresentation.test'
import readerImageLoadPriorityTest from './ReaderImageLoadPriority.test'
import gallerySeedDetailRefreshGateTest from './GallerySeedDetailRefreshGate.test'
import readerImageSourceRequestGateTest from './ReaderImageSourceRequestGate.test'
import readerSessionRequestGateTest from './ReaderSessionRequestGate.test'
import readerThumbnailGeometryTest from './ReaderThumbnailGeometry.test'
import imageResolveSourceGateTest from './ImageResolveSourceGate.test'
import backupCipherMetadataGuardTest from './BackupCipherMetadataGuard.test'
import backupLocalDataStructureGuardTest from './BackupLocalDataStructureGuard.test'
import backupWebDavCredentialGroupTest from './BackupWebDavCredentialGroup.test'
import readerSuperResolutionBackendTest from './ReaderSuperResolutionBackend.test'
import readerSuperResolutionModelIntegrationTest from './ReaderSuperResolutionModelIntegration.test'
import comicTranslationPhase0Test from './ComicTranslationPhase0.test'
import comicTranslationProvidersTest from './ComicTranslationProviders.test'
import comicTranslationOrchestratorTest from './ComicTranslationOrchestrator.test'
import comicTranslationPersistentRepositoryTest from './ComicTranslationPersistentRepository.test'
import comicVisualTranslationContractTest from './ComicVisualTranslationContract.test'
import llmSourceProfileRepositoryTest from './LlmSourceProfileRepository.test'

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
  recentGalleryDetailMemoryCacheTest()
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
  webDavManifestWriteGuardTest()
  downloadQueueRestoreReconcilerTest()
  downloadQueueTaskProjectionTest()
  favoritesTagTranslationRaceTest()
  readerSessionCacheStateTest()
  basicDataSourceChangeNotificationTest()
  customProfilesPersistSchedulerTest()
  customProfileSyncSemanticsTest()
  allThumbnailsTailAppendTest()
  galleryListMutationTargetedUpdateTest()
  galleryResumeBatchTest()
  listTagTranslationMutationRaceTest()
  readerImageLoadPresentationTest()
  readerImageLoadPriorityTest()
  gallerySeedDetailRefreshGateTest()
  readerImageSourceRequestGateTest()
  readerSessionRequestGateTest()
  readerThumbnailGeometryTest()
  imageResolveSourceGateTest()
  backupCipherMetadataGuardTest()
  backupLocalDataStructureGuardTest()
  backupWebDavCredentialGroupTest()
  readerSuperResolutionBackendTest()
  readerSuperResolutionModelIntegrationTest()
  comicTranslationPhase0Test()
  comicTranslationProvidersTest()
  comicTranslationOrchestratorTest()
  comicTranslationPersistentRepositoryTest()
  comicVisualTranslationContractTest()
  llmSourceProfileRepositoryTest()
}
