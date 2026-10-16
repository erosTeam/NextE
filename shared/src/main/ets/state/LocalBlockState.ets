import { AppStorageV2 } from '@kit.ArkUI'

export const LOCAL_BLOCK_TYPE_TITLE: string = 'title'
export const LOCAL_BLOCK_TYPE_UPLOADER: string = 'uploader'
export const LOCAL_BLOCK_TYPE_COMMENTATOR: string = 'commentator'
export const LOCAL_BLOCK_TYPE_COMMENT: string = 'comment'
export const LOCAL_BLOCK_COMMENT_DISPLAY_HIDE: string = 'hide'
export const LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE: string = 'collapse'
// Stable identities live in the existing rule text behind a typed prefix instead of a new block type or
// column: an older client normalizes unknown block types to 'title' (see LocalBlockSettings.normalizeType),
// which would turn a nameless rule into a title rule. A prefixed value stays inert there because no title
// contains this literal, and it keeps the RDB schema, backup shape and older clients compatible.
export const LOCAL_BLOCK_MEMBER_ID_PREFIX: string = '#uid:'
export const LOCAL_BLOCK_COMMENT_ID_PREFIX: string = '#cid:'

@ObservedV2
export class LocalBlockRule {
  @Trace id: string = ''
  @Trace blockType: string = LOCAL_BLOCK_TYPE_TITLE
  @Trace ruleText: string = ''
  @Trace enabled: boolean = true
  @Trace enableRegex: boolean = false
}

@ObservedV2
export class LocalBlockState {
  @Trace filterCommentsByScore: boolean = false
  @Trace scoreFilteringThreshold: number = -20
  @Trace commentDisplayMode: string = LOCAL_BLOCK_COMMENT_DISPLAY_HIDE
  @Trace rules: LocalBlockRule[] = []
  @Trace version: number = 0
}

const LOCAL_BLOCK_STATE_KEY: string = 'v2_localBlock'

export function connectLocalBlock(): LocalBlockState {
  return AppStorageV2.connect(
    LocalBlockState,
    LOCAL_BLOCK_STATE_KEY,
    () => new LocalBlockState(),
  )!
}
