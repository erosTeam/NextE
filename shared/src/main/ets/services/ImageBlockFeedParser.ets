import {
  IMAGE_BLOCK_ALGORITHM_DCT64_V1,
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_FEED_KIND,
  IMAGE_BLOCK_MANIFEST_KIND,
  IMAGE_BLOCK_SCOPE_WHOLE,
  ImageBlockFeed,
  ImageBlockFeedItem,
  ImageBlockManifest,
} from '../model/ImageBlockRule'
import { PHashService } from './PHashService'

const MAX_IMAGE_BLOCK_FEED_ITEMS: number = 10000

export class ImageBlockFeedParser {
  static parseManifest(rawText: string): ImageBlockManifest {
    const raw: ImageBlockManifest = JSON.parse(rawText) as ImageBlockManifest
    if (Math.floor(raw.schema) !== 1 || raw.kind !== IMAGE_BLOCK_MANIFEST_KIND) {
      throw new Error('Unsupported image block manifest')
    }
    if (!Array.isArray(raw.feeds)) {
      throw new Error('Image block manifest feeds must be an array')
    }
    const manifest: ImageBlockManifest = new ImageBlockManifest()
    manifest.schema = 1
    manifest.kind = IMAGE_BLOCK_MANIFEST_KIND
    manifest.updatedAt = ImageBlockFeedParser.safeNumber(raw.updatedAt)
    for (let i: number = 0; i < raw.feeds.length; i++) {
      const feed: ImageBlockFeed = ImageBlockFeedParser.normalizeManifestFeed(raw.feeds[i])
      if (feed.id.length > 0 && feed.url.length > 0) {
        manifest.feeds.push(feed)
      }
    }
    return manifest
  }

  static parseFeed(rawText: string, url: string = ''): ImageBlockFeed {
    const raw: ImageBlockFeed = JSON.parse(rawText) as ImageBlockFeed
    if (Math.floor(raw.schema) !== 1 || raw.kind !== IMAGE_BLOCK_FEED_KIND) {
      throw new Error('Unsupported image block feed')
    }
    if (raw.algorithm !== IMAGE_BLOCK_ALGORITHM_DCT64_V1) {
      throw new Error('Unsupported image block algorithm')
    }
    if (!Array.isArray(raw.items)) {
      throw new Error('Image block feed items must be an array')
    }
    if (raw.items.length > MAX_IMAGE_BLOCK_FEED_ITEMS) {
      throw new Error('Image block feed is too large')
    }

    const feed: ImageBlockFeed = new ImageBlockFeed()
    feed.id = ImageBlockFeedParser.requiredString(raw.id, 'feed id')
    feed.title = ImageBlockFeedParser.safeString(raw.title)
    feed.url = url
    feed.algorithm = IMAGE_BLOCK_ALGORITHM_DCT64_V1
    feed.defaultThreshold = PHashService.clampThreshold(
      ImageBlockFeedParser.safeNumber(raw.defaultThreshold, IMAGE_BLOCK_DEFAULT_THRESHOLD),
      IMAGE_BLOCK_DEFAULT_THRESHOLD,
    )
    feed.updatedAt = ImageBlockFeedParser.safeNumber(raw.updatedAt)

    for (let i: number = 0; i < raw.items.length; i++) {
      const item: ImageBlockFeedItem = ImageBlockFeedParser.normalizeFeedItem(raw.items[i], feed.defaultThreshold)
      feed.items.push(item)
    }
    feed.count = feed.items.length
    return feed
  }

  private static normalizeManifestFeed(raw: ImageBlockFeed): ImageBlockFeed {
    const feed: ImageBlockFeed = new ImageBlockFeed()
    feed.id = ImageBlockFeedParser.safeString(raw.id)
    feed.title = ImageBlockFeedParser.safeString(raw.title)
    feed.url = ImageBlockFeedParser.safeString(raw.url)
    feed.algorithm = ImageBlockFeedParser.safeString(raw.algorithm)
    if (feed.algorithm.length === 0) {
      feed.algorithm = IMAGE_BLOCK_ALGORITHM_DCT64_V1
    }
    if (feed.algorithm !== IMAGE_BLOCK_ALGORITHM_DCT64_V1) {
      throw new Error('Unsupported image block manifest algorithm')
    }
    feed.defaultThreshold = PHashService.clampThreshold(
      ImageBlockFeedParser.safeNumber(raw.defaultThreshold, IMAGE_BLOCK_DEFAULT_THRESHOLD),
      IMAGE_BLOCK_DEFAULT_THRESHOLD,
    )
    feed.count = Math.floor(ImageBlockFeedParser.safeNumber(raw.count))
    feed.sha256 = ImageBlockFeedParser.safeString(raw.sha256)
    return feed
  }

  private static normalizeFeedItem(raw: ImageBlockFeedItem, defaultThreshold: number): ImageBlockFeedItem {
    const item: ImageBlockFeedItem = new ImageBlockFeedItem()
    item.hash = PHashService.normalizeHex64(ImageBlockFeedParser.safeString(raw.hash))
    if (item.hash.length === 0) {
      throw new Error('Image block feed item hash must be 16 hex characters')
    }
    item.threshold = PHashService.clampThreshold(
      ImageBlockFeedParser.safeNumber(raw.threshold, defaultThreshold),
      defaultThreshold,
    )
    item.label = ImageBlockFeedParser.safeString(raw.label)
    if (item.label.length === 0) {
      item.label = 'scanlator-ad'
    }
    item.scope = ImageBlockFeedParser.safeString(raw.scope)
    if (item.scope.length === 0) {
      item.scope = IMAGE_BLOCK_SCOPE_WHOLE
    }
    if (item.scope !== IMAGE_BLOCK_SCOPE_WHOLE) {
      throw new Error('Only whole-image block rules are supported')
    }
    return item
  }

  private static requiredString(value: string, name: string): string {
    const out: string = ImageBlockFeedParser.safeString(value)
    if (out.length === 0) {
      throw new Error('Missing image block ' + name)
    }
    return out
  }

  private static safeString(value: string | null | undefined): string {
    if (typeof value !== 'string') {
      return ''
    }
    return value.trim()
  }

  private static safeNumber(value: number | null | undefined, fallback: number = 0): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return fallback
    }
    return value
  }
}
