export const IMAGE_BLOCK_ALGORITHM_DCT64_V1: string = 'dct64-v1'
export const IMAGE_BLOCK_SCOPE_WHOLE: string = 'whole'
export const IMAGE_BLOCK_SOURCE_LOCAL: string = 'local'
export const IMAGE_BLOCK_SOURCE_SUBSCRIPTION: string = 'subscription'
export const IMAGE_BLOCK_DEFAULT_THRESHOLD: number = 8
export const IMAGE_BLOCK_MAX_THRESHOLD: number = 12
export const IMAGE_BLOCK_FEED_KIND: string = 'nexte-image-block-feed'
export const IMAGE_BLOCK_MANIFEST_KIND: string = 'nexte-image-block-manifest'
export const IMAGE_BLOCK_DEFAULT_MANIFEST_URL: string =
  'https://raw.githubusercontent.com/erosTeam/nexte-image-block-rules/main/dist/manifest.json'

export class ImageBlockRule {
  id: string = ''
  hash: string = ''
  threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD
  label: string = ''
  scope: string = IMAGE_BLOCK_SCOPE_WHOLE
  feedId: string = ''
  sourceType: string = IMAGE_BLOCK_SOURCE_LOCAL
  sourceUrl: string = ''
  sourcePage: number = 0
  enabled: boolean = true
  updatedAt: number = 0
  deletedAt: number = 0

  copy(): ImageBlockRule {
    const rule: ImageBlockRule = new ImageBlockRule()
    rule.id = this.id
    rule.hash = this.hash
    rule.threshold = this.threshold
    rule.label = this.label
    rule.scope = this.scope
    rule.feedId = this.feedId
    rule.sourceType = this.sourceType
    rule.sourceUrl = this.sourceUrl
    rule.sourcePage = this.sourcePage
    rule.enabled = this.enabled
    rule.updatedAt = this.updatedAt
    rule.deletedAt = this.deletedAt
    return rule
  }
}

export class ImageBlockFeedItem {
  hash: string = ''
  threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD
  label: string = ''
  scope: string = IMAGE_BLOCK_SCOPE_WHOLE
}

export class ImageBlockFeed {
  schema: number = 1
  kind: string = IMAGE_BLOCK_FEED_KIND
  id: string = ''
  title: string = ''
  url: string = ''
  algorithm: string = IMAGE_BLOCK_ALGORITHM_DCT64_V1
  defaultThreshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD
  updatedAt: number = 0
  sha256: string = ''
  count: number = 0
  enabled: boolean = true
  items: ImageBlockFeedItem[] = []
}

export class ImageBlockManifest {
  schema: number = 1
  kind: string = IMAGE_BLOCK_MANIFEST_KIND
  updatedAt: number = 0
  feeds: ImageBlockFeed[] = []
}

export class ImageBlockDecision {
  blocked: boolean = false
  hash: string = ''
  ruleId: string = ''
  feedId: string = ''
  sourceType: string = ''
  label: string = ''
  threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD
  distance: number = -1
}
