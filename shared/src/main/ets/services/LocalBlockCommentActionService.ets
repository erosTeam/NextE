import { common } from '@kit.AbilityKit'
import { EhGalleryComment } from '../model/EhGalleryComment'
import { LocalBlockSettings } from '../settings/LocalBlockSettings'
import {
  LOCAL_BLOCK_COMMENT_ID_PREFIX,
  LOCAL_BLOCK_MEMBER_ID_PREFIX,
  LOCAL_BLOCK_TYPE_COMMENT,
  LOCAL_BLOCK_TYPE_COMMENTATOR,
} from '../state/LocalBlockState'

/** Which identity a comment-author block used, so the caller can report the actual match basis. */
export const COMMENT_AUTHOR_BLOCK_BY_MEMBER_ID: string = 'member-id'
export const COMMENT_AUTHOR_BLOCK_BY_NAME: string = 'name'

/**
 * Actions the comment-row block menu publishes. They live here rather than in each UI file so the card that
 * raises an action and the page that handles it cannot drift apart.
 */
export const COMMENT_BLOCK_ACTION_AUTHOR: string = 'author'
export const COMMENT_BLOCK_ACTION_THIS: string = 'this'
export const COMMENT_BLOCK_ACTION_CONTENT: string = 'content'

/**
 * Turns a comment-row action (block author / block this comment / block selected words) into ordinary local
 * block rules. Rules go through LocalBlockSettings so the version bump, durable write queue, sync request and
 * every mounted comment surface refresh exactly as a hand-added rule does.
 *
 * Each method reports the outcome the user actually experienced (which identity was used, whether the row had
 * a writable id), not whether a new row happened to be inserted: re-blocking an already blocked comment is a
 * success, so duplicates are silently kept single instead of surfacing as a failure.
 */
export class LocalBlockCommentActionService {
  private static identityText(prefix: string, value: string): string {
    return `${prefix}${value.trim()}`
  }

  private static async addRule(
    context: common.UIAbilityContext,
    blockType: string,
    ruleText: string,
  ): Promise<void> {
    await LocalBlockSettings.ensureLiteralRules(context, blockType, [ruleText])
  }

  /**
   * Blocks the comment author by member id, which survives a nickname change. A comment shape without a
   * numeric member id falls back to the author name so the action is still useful; the return value tells the
   * caller which one was used.
   */
  static async blockCommentAuthor(
    context: common.UIAbilityContext,
    comment: EhGalleryComment,
  ): Promise<string> {
    const memberId: string = comment.memberId.trim()
    if (/^[1-9]\d*$/.test(memberId)) {
      await LocalBlockCommentActionService.addRule(
        context,
        LOCAL_BLOCK_TYPE_COMMENTATOR,
        LocalBlockCommentActionService.identityText(LOCAL_BLOCK_MEMBER_ID_PREFIX, memberId),
      )
      return COMMENT_AUTHOR_BLOCK_BY_MEMBER_ID
    }
    if (comment.author.trim().length === 0) {
      return ''
    }
    await LocalBlockCommentActionService.addRule(
      context,
      LOCAL_BLOCK_TYPE_COMMENTATOR,
      comment.author,
    )
    return COMMENT_AUTHOR_BLOCK_BY_NAME
  }

  /**
   * Blocks exactly one comment row by comment id, leaving the author's other comments visible. Returns false
   * when the row carries no stable id (the uploader comment and a not-yet-persisted row both report 0).
   */
  static async blockComment(
    context: common.UIAbilityContext,
    comment: EhGalleryComment,
  ): Promise<boolean> {
    const commentId: string = comment.commentId.trim()
    if (!/^[1-9]\d*$/.test(commentId)) {
      return false
    }
    await LocalBlockCommentActionService.addRule(
      context,
      LOCAL_BLOCK_TYPE_COMMENT,
      LocalBlockCommentActionService.identityText(LOCAL_BLOCK_COMMENT_ID_PREFIX, commentId),
    )
    return true
  }

  /**
   * Each supplied phrase becomes one literal rule; phrases match independently. Adjacent tokens have
   * already been combined by the panel. Returns the distinct phrase count after the atomic durable write.
   */
  static async blockCommentWords(
    context: common.UIAbilityContext,
    words: string[],
  ): Promise<number> {
    return LocalBlockSettings.ensureLiteralRules(context, LOCAL_BLOCK_TYPE_COMMENT, words)
  }
}
