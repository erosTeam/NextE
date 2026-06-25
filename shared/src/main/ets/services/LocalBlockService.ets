import { EhGallery } from '../model/EhGallery'
import { EhGalleryComment } from '../model/EhGalleryComment'
import { GalleryList } from '../model/GalleryList'
import {
  LOCAL_BLOCK_TYPE_COMMENT,
  LOCAL_BLOCK_TYPE_COMMENTATOR,
  LOCAL_BLOCK_TYPE_TITLE,
  LOCAL_BLOCK_TYPE_UPLOADER,
  LocalBlockRule,
  LocalBlockState,
  connectLocalBlock,
} from '../state/LocalBlockState'

export class LocalBlockService {
  static matchText(text: string, blockType: string): boolean {
    if (text.length === 0) {
      return false
    }
    const rules: LocalBlockRule[] = connectLocalBlock().rules
    for (let i = 0; i < rules.length; i++) {
      const rule: LocalBlockRule = rules[i]
      if (rule.blockType !== blockType || !rule.enabled) {
        continue
      }
      const ruleText: string = rule.ruleText.trim().replace(/\(\?i\)/g, '')
      if (ruleText.length === 0) {
        continue
      }
      if (rule.enableRegex) {
        try {
          if (new RegExp(ruleText).test(text)) {
            return true
          }
        } catch (_error) {
          continue
        }
      } else if (text.indexOf(ruleText) >= 0) {
        return true
      }
    }
    return false
  }

  static isGalleryBlocked(gallery: EhGallery): boolean {
    return LocalBlockService.matchText(gallery.englishTitle, LOCAL_BLOCK_TYPE_TITLE) ||
      LocalBlockService.matchText(gallery.japaneseTitle, LOCAL_BLOCK_TYPE_TITLE) ||
      LocalBlockService.matchText(gallery.uploader, LOCAL_BLOCK_TYPE_UPLOADER)
  }

  static filterGalleryList(list: GalleryList): GalleryList {
    list.gallerys = list.gallerys.filter((gallery: EhGallery) => !LocalBlockService.isGalleryBlocked(gallery))
    return list
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
      LocalBlockService.matchText(comment.author, LOCAL_BLOCK_TYPE_COMMENTATOR)
  }

  static filterComments(comments: EhGalleryComment[]): EhGalleryComment[] {
    return comments.filter((comment: EhGalleryComment) => !LocalBlockService.isCommentBlocked(comment))
  }
}
