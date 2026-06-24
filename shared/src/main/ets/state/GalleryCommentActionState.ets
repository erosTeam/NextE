import { AppStorageV2 } from '@kit.ArkUI'

const GALLERY_COMMENT_ACTION_KEY: string = 'v2:galleryCommentAction'

export const GALLERY_COMMENT_ACTION_AUTHOR: string = 'author'
export const GALLERY_COMMENT_ACTION_VOTE: string = 'vote'
export const GALLERY_COMMENT_ACTION_REPLY: string = 'reply'
export const GALLERY_COMMENT_ACTION_EDIT: string = 'edit'
export const GALLERY_COMMENT_ACTION_TRANSLATE: string = 'translate'
export const GALLERY_COMMENT_ACTION_TOGGLE_TRANSLATION: string = 'toggleTranslation'
export const GALLERY_COMMENT_ACTION_AUTO_TRANSLATE: string = 'autoTranslate'
export const GALLERY_COMMENT_ACTION_RENDER_STATE: string = 'renderState'

@ObservedV2
export class GalleryCommentActionState {
  @Trace version: number = 0
  @Trace scopeId: string = ''
  @Trace action: string = ''
  @Trace commentId: string = ''
  @Trace author: string = ''
  @Trace vote: number = 0
  @Trace sourceText: string = ''
  @Trace translationText: string = ''
  @Trace translationShown: boolean = false
  @Trace translationLoading: boolean = false
  @Trace score: string = ''

  publish(scopeId: string, action: string, commentId: string, author: string, vote: number, sourceText: string): void {
    this.scopeId = scopeId
    this.action = action
    this.commentId = commentId
    this.author = author
    this.vote = vote
    this.sourceText = sourceText
    this.version = this.version + 1
  }

  requestAuthor(scopeId: string, author: string): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_AUTHOR, '', author, 0, '')
  }

  requestVote(scopeId: string, commentId: string, vote: number): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_VOTE, commentId, '', vote, '')
  }

  requestReply(scopeId: string, commentId: string): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_REPLY, commentId, '', 0, '')
  }

  requestEdit(scopeId: string, commentId: string): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_EDIT, commentId, '', 0, '')
  }

  requestTranslate(scopeId: string, commentId: string, sourceText: string): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_TRANSLATE, commentId, '', 0, sourceText)
  }

  requestToggleTranslation(scopeId: string, commentId: string): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_TOGGLE_TRANSLATION, commentId, '', 0, '')
  }

  requestAutoTranslate(scopeId: string, commentId: string, sourceText: string): void {
    this.publish(scopeId, GALLERY_COMMENT_ACTION_AUTO_TRANSLATE, commentId, '', 0, sourceText)
  }

  requestRenderState(
    scopeId: string,
    commentId: string,
    translationText: string,
    translationShown: boolean,
    translationLoading: boolean,
    score: string,
    vote: number,
  ): void {
    this.scopeId = scopeId
    this.action = GALLERY_COMMENT_ACTION_RENDER_STATE
    this.commentId = commentId
    this.author = ''
    this.vote = vote
    this.sourceText = ''
    this.translationText = translationText
    this.translationShown = translationShown
    this.translationLoading = translationLoading
    this.score = score
    this.version = this.version + 1
  }
}

export function connectGalleryCommentAction(): GalleryCommentActionState {
  return AppStorageV2.connect(
    GalleryCommentActionState,
    GALLERY_COMMENT_ACTION_KEY,
    () => new GalleryCommentActionState(),
  )!
}
