import { EhGalleryComment } from 'shared'

@ObservedV2
export class GalleryCommentRenderState {
  @Trace commentId: string = ''
  @Trace score: string = ''
  @Trace vote: number = 0
  @Trace translationText: string = ''
  @Trace translationShown: boolean = false
  @Trace translationLoading: boolean = false
  @Trace translationAutoStarted: boolean = false

  constructor(c?: EhGalleryComment) {
    if (c !== undefined) {
      this.applyComment(c)
    }
  }

  applyComment(c: EhGalleryComment): void {
    this.commentId = c.commentId
    this.score = c.score
    this.vote = c.vote
    this.translationText = c.translationText
    this.translationShown = c.translationShown
    this.translationLoading = c.translationLoading
    this.translationAutoStarted = c.translationAutoStarted
  }
}
