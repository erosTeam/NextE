import { common } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { BackupChecksum } from '../backup/BackupChecksum'
import {
  IMAGE_BLOCK_DEFAULT_MANIFEST_URL,
  ImageBlockFeed,
  ImageBlockManifest,
} from '../model/ImageBlockRule'
import { ImageBlockRepository } from '../storage/ImageBlockRepository'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ImageBlockFeedParser } from './ImageBlockFeedParser'

const CONNECT_TIMEOUT_MS: number = 10000
const READ_TIMEOUT_MS: number = 20000
const MAX_MANIFEST_CHARS: number = 256 * 1024
const MAX_FEED_CHARS: number = 2 * 1024 * 1024

export class ImageBlockSubscriptionUpdateResult {
  manifestUrl: string = ''
  feedCount: number = 0
  updatedFeedCount: number = 0
  updatedRuleCount: number = 0
  failedFeedCount: number = 0
}

export class ImageBlockSubscriptionService {
  static async updateDefault(context: common.UIAbilityContext): Promise<ImageBlockSubscriptionUpdateResult> {
    return ImageBlockSubscriptionService.updateFromManifest(context, IMAGE_BLOCK_DEFAULT_MANIFEST_URL)
  }

  static async updateFromManifest(
    context: common.UIAbilityContext,
    manifestUrl: string,
  ): Promise<ImageBlockSubscriptionUpdateResult> {
    const result: ImageBlockSubscriptionUpdateResult = new ImageBlockSubscriptionUpdateResult()
    result.manifestUrl = manifestUrl
    const manifestText: string = await ImageBlockSubscriptionService.fetchText(manifestUrl, MAX_MANIFEST_CHARS)
    const manifest: ImageBlockManifest = ImageBlockFeedParser.parseManifest(manifestText)
    result.feedCount = manifest.feeds.length

    for (let i: number = 0; i < manifest.feeds.length; i++) {
      const feedRef: ImageBlockFeed = manifest.feeds[i]
      try {
        const feedText: string = await ImageBlockSubscriptionService.fetchText(feedRef.url, MAX_FEED_CHARS)
        if (feedRef.sha256.length > 0) {
          const actualHash: string = await BackupChecksum.hashText(feedText)
          if (actualHash !== feedRef.sha256) {
            throw new Error('Image block feed checksum mismatch')
          }
        }
        const feed: ImageBlockFeed = ImageBlockFeedParser.parseFeed(feedText, feedRef.url)
        feed.sha256 = feedRef.sha256
        if (feed.title.length === 0) {
          feed.title = feedRef.title
        }
        await ImageBlockRepository.replaceSubscription(context, feed)
        result.updatedFeedCount++
        result.updatedRuleCount += feed.items.length
      } catch (error) {
        const e: Error = error as Error
        result.failedFeedCount++
        DiagnosticLogger.warn('image-block-subscription', 'feed_update_failed', `${feedRef.id}: ${e.message}`)
      }
    }
    return result
  }

  private static async fetchText(url: string, maxChars: number): Promise<string> {
    if (url.indexOf('https://') !== 0) {
      throw new Error('Image block subscriptions require HTTPS')
    }
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'Accept': 'application/json,text/plain,*/*',
        'User-Agent': 'NextE image-block-rules',
      }
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code}`)
      }
      if (body.length > maxChars) {
        throw new Error('Image block subscription response is too large')
      }
      return body
    } finally {
      req.destroy()
    }
  }
}
