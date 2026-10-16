import { EhGallery } from '../model/EhGallery'
import { EhGalleryComment } from '../model/EhGalleryComment'
import { GalleryList } from '../model/GalleryList'
import { LocalBlockSettings } from '../settings/LocalBlockSettings'
import {
  LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE,
  LOCAL_BLOCK_COMMENT_ID_PREFIX,
  LOCAL_BLOCK_MEMBER_ID_PREFIX,
  LOCAL_BLOCK_TYPE_COMMENT,
  LOCAL_BLOCK_TYPE_COMMENTATOR,
  LOCAL_BLOCK_TYPE_TITLE,
  LOCAL_BLOCK_TYPE_UPLOADER,
  LocalBlockRule,
  LocalBlockState,
  connectLocalBlock,
} from '../state/LocalBlockState'

export class LocalBlockService {
  private static normalized(text: string): string {
    return text
      .replace(/[\u200B-\u200F\uFEFF]/g, '')
      .trim()
  }

  /**
   * Identity rules reuse `commentator`/`comment` with a typed prefix so no new block type or column is
   * needed. The prefix is only reserved for those two types: other types keep plain text matching, so a
   * rule the user retypes into another bucket still works instead of becoming inert.
   */
  private static identityPrefixFor(blockType: string): string {
    if (blockType === LOCAL_BLOCK_TYPE_COMMENTATOR) {
      return LOCAL_BLOCK_MEMBER_ID_PREFIX
    }
    if (blockType === LOCAL_BLOCK_TYPE_COMMENT) {
      return LOCAL_BLOCK_COMMENT_ID_PREFIX
    }
    return ''
  }

  static isIdentityRule(rule: LocalBlockRule): boolean {
    const prefix: string = LocalBlockService.identityPrefixFor(rule.blockType)
    const text: string = LocalBlockService.normalized(rule.ruleText)
    return !rule.enableRegex && prefix.length > 0 && text.startsWith(prefix) &&
      /^[1-9]\d*$/.test(text.substring(prefix.length).trim())
  }

  static matchText(text: string, blockType: string): boolean {
    const normalizedText: string = LocalBlockService.normalized(text)
    if (normalizedText.length === 0) {
      return false
    }
    const rules: LocalBlockRule[] = connectLocalBlock().rules
    for (let i = 0; i < rules.length; i++) {
      const rule: LocalBlockRule = rules[i]
      if (rule.blockType !== blockType || !rule.enabled) {
        continue
      }
      const rawRuleText: string = LocalBlockService.normalized(rule.ruleText)
      // An identity rule is compared against its own field, not against visible comment text.
      if (LocalBlockService.isIdentityRule(rule)) {
        continue
      }
      const caseInsensitive: boolean = rule.enableRegex && rawRuleText.indexOf('(?i)') >= 0
      const ruleText: string = rule.enableRegex ? rawRuleText.replace(/\(\?i\)/g, '') : rawRuleText
      if (ruleText.length === 0) {
        continue
      }
      if (rule.enableRegex) {
        try {
          if (new RegExp(ruleText, caseInsensitive ? 'i' : '').test(normalizedText)) {
            return true
          }
        } catch (_error) {
          continue
        }
      } else {
        const plainText: string = blockType === LOCAL_BLOCK_TYPE_COMMENT
          ? LocalBlockSettings.cleanText(normalizedText) : normalizedText
        if (plainText.toLowerCase().indexOf(ruleText.toLowerCase()) >= 0) {
          return true
        }
      }
    }
    return false
  }

  /**
   * Matches one exact identity (comment id or member id) against enabled identity rules of the given
   * type. An empty identity never matches: uploader comments and any shape without a member id must stay
   * visible instead of being swept up by an id rule.
   */
  static matchIdentity(identity: string, blockType: string): boolean {
    const target: string = LocalBlockService.normalized(identity)
    if (target.length === 0) {
      return false
    }
    const prefix: string = LocalBlockService.identityPrefixFor(blockType)
    if (prefix.length === 0) {
      return false
    }
    const rules: LocalBlockRule[] = connectLocalBlock().rules
    for (let i = 0; i < rules.length; i++) {
      const rule: LocalBlockRule = rules[i]
      if (rule.blockType !== blockType || !rule.enabled) {
        continue
      }
      const ruleText: string = LocalBlockService.normalized(rule.ruleText)
      if (!LocalBlockService.isIdentityRule(rule)) {
        continue
      }
      if (ruleText.substring(prefix.length).trim() === target) {
        return true
      }
    }
    return false
  }

  static isGalleryBlocked(gallery: EhGallery): boolean {
    return LocalBlockService.matchText(gallery.englishTitle, LOCAL_BLOCK_TYPE_TITLE) ||
      LocalBlockService.matchText(gallery.japaneseTitle, LOCAL_BLOCK_TYPE_TITLE) ||
      LocalBlockService.matchText(gallery.uploader, LOCAL_BLOCK_TYPE_UPLOADER) ||
      LocalBlockService.matchText(gallery.title(), LOCAL_BLOCK_TYPE_UPLOADER)
  }

  static filterGalleryList(list: GalleryList): GalleryList {
    list.gallerys = list.gallerys.filter((gallery: EhGallery) => !LocalBlockService.isGalleryBlocked(gallery))
    return list
  }

  static filterGalleries(galleries: EhGallery[]): EhGallery[] {
    return galleries.filter((gallery: EhGallery) => !LocalBlockService.isGalleryBlocked(gallery))
  }

  static isCommentBlocked(comment: EhGalleryComment): boolean {
    const state: LocalBlockState = connectLocalBlock()
    if (state.filterCommentsByScore && comment.score.trim().length > 0) {
      const score: number = Number.parseInt(comment.score.trim(), 10)
      if (!Number.isNaN(score) && score <= state.scoreFilteringThreshold) {
        return true
      }
    }
    return LocalBlockService.matchText(comment.contentText, LOCAL_BLOCK_TYPE_COMMENT) ||
      LocalBlockService.matchText(comment.author, LOCAL_BLOCK_TYPE_COMMENTATOR) ||
      LocalBlockService.matchIdentity(comment.commentId, LOCAL_BLOCK_TYPE_COMMENT) ||
      LocalBlockService.matchIdentity(comment.memberId, LOCAL_BLOCK_TYPE_COMMENTATOR)
  }

  static filterComments(comments: EhGalleryComment[]): EhGalleryComment[] {
    if (connectLocalBlock().commentDisplayMode === LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE) {
      return comments
    }
    return comments.filter((comment: EhGalleryComment) => !LocalBlockService.isCommentBlocked(comment))
  }

  static shouldCollapseBlockedComments(): boolean {
    return connectLocalBlock().commentDisplayMode === LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE
  }
}
