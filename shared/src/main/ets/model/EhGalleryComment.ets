/**
 * One gallery comment (from the detail page comment list). `postedTime` is the EH UTC timestamp
 * converted to device-local `yyyy-MM-dd HH:mm`. `contentText` is the comment body with tags
 * stripped to plain text (br → newline, entities decoded) for filtering, translation, and fallback
 * display. `contentLinks` and `contentSpans` preserve anchor hrefs and supported inline HTML style
 * ranges without exposing raw URLs as extra visible text. `score` is the signed community score
 * (e.g. "+15"/"-3"; empty for the uploader comment, which carries no score). `vote` is the current
 * user's vote state (-1/0/+1); canEdit/canVote/scoreDetails/memberId are parser-owned metadata for
 * the full comments page and later guarded write-op lanes.
 */
@ObservedV2
export class EhGalleryCommentLink {
  @Trace start: number = 0
  @Trace end: number = 0
  @Trace url: string = ''
}

@ObservedV2
export class EhGalleryCommentTextSpan {
  @Trace start: number = 0
  @Trace end: number = 0
  @Trace url: string = ''
  @Trace bold: boolean = false
  @Trace italic: boolean = false
  @Trace underline: boolean = false
  @Trace strike: boolean = false
  @Trace color: string = ''
}

@ObservedV2
export class EhGalleryComment {
  @Trace commentId: string = ''
  @Trace memberId: string = ''
  @Trace author: string = ''
  @Trace postedTime: string = ''
  @Trace contentText: string = ''
  @Trace contentLinks: EhGalleryCommentLink[] = []
  @Trace contentSpans: EhGalleryCommentTextSpan[] = []
  @Trace score: string = ''
  @Trace vote: number = 0
  @Trace canEdit: boolean = false
  @Trace canVote: boolean = false
  @Trace scoreDetails: string[] = []
  @Trace isUploader: boolean = false
  @Trace translationText: string = ''
  @Trace translationSpans: EhGalleryCommentTextSpan[] = []
  @Trace translationShown: boolean = false
  @Trace translationLoading: boolean = false
  @Trace translationAutoStarted: boolean = false
}
