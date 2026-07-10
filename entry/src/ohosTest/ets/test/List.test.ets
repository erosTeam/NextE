import galleryDetailParserTest from './GalleryDetailParser.test'
import readProgressStateTest from './ReadProgressState.test'
import readerImagePrioritySchedulerTest from './ReaderImagePriorityScheduler.test'
import commentTranslationQueueSchedulerTest from './CommentTranslationQueueScheduler.test'
import commentTranslationMemoryCacheTest from './CommentTranslationMemoryCache.test'
import commentTranslationCacheEpochTest from './CommentTranslationCacheEpoch.test'
import imageResolveMemoryCacheTest from './ImageResolveMemoryCache.test'
import gallerySeedSchedulerTest from './GallerySeedScheduler.test'
import imageBlockThumbnailHashMemoryCacheTest from './ImageBlockThumbnailHashMemoryCache.test'
import coverColorResourceBoundsTest from './CoverColorResourceBounds.test'
import preloadedGalleryListMemoryCacheTest from './PreloadedGalleryListMemoryCache.test'

export default function testsuite(): void {
  galleryDetailParserTest()
  readProgressStateTest()
  readerImagePrioritySchedulerTest()
  commentTranslationQueueSchedulerTest()
  commentTranslationMemoryCacheTest()
  commentTranslationCacheEpochTest()
  imageResolveMemoryCacheTest()
  gallerySeedSchedulerTest()
  imageBlockThumbnailHashMemoryCacheTest()
  coverColorResourceBoundsTest()
  preloadedGalleryListMemoryCacheTest()
}
