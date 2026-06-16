/**
 * One gallery comment (from the detail page comment list). `postedTime` is the raw EH
 * "DD Mon YYYY, HH:MM" string; `contentText` is the comment body with tags stripped to plain
 * text (br → newline, entities decoded) for read-only display. `score` is the signed community
 * score (e.g. "+15"/"-3"; empty for the uploader comment, which carries no score). `isUploader`
 * marks the gallery uploader's own comment (the `Uploader Comment` block, usually comment_0).
 */
export class EhGalleryComment {
  commentId: string = ''
  author: string = ''
  postedTime: string = ''
  contentText: string = ''
  score: string = ''
  isUploader: boolean = false
}
