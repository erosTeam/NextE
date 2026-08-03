import { common } from '@kit.AbilityKit'
import {
  COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  CommentTranslationService,
} from './CommentTranslationService'

/**
 * Title-facing boundary over the shared short-text translation pipeline.
 *
 * Gallery titles intentionally reuse the existing provider, target-locale, cache, queue, and fallback
 * behavior used by manual comment translation. Keeping this boundary title-named prevents the gallery
 * feature from depending on comment UI semantics and leaves room for a title-specific prompt later.
 */
export class GalleryTitleTranslationService {
  static translate(context: common.UIAbilityContext, sourceText: string): Promise<string> {
    return CommentTranslationService.translate(
      context,
      sourceText,
      false,
      COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
    )
  }
}
