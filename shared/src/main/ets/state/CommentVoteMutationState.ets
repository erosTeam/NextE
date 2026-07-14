import { AppStorageV2 } from '@kit.ArkUI'

const COMMENT_VOTE_MUTATION_KEY: string = 'v2_commentVoteMutation'

@ObservedV2
export class CommentVoteMutationState {
  @Trace version: number = 0
  @Trace gid: string = ''
  @Trace commentId: string = ''
  @Trace score: string = ''
  @Trace vote: number = 0

  publish(gid: string, commentId: string, score: string, vote: number): void {
    this.gid = gid
    this.commentId = commentId
    this.score = score
    this.vote = vote
    this.version = this.version + 1
  }
}

export function connectCommentVoteMutation(): CommentVoteMutationState {
  return AppStorageV2.connect(
    CommentVoteMutationState,
    COMMENT_VOTE_MUTATION_KEY,
    () => new CommentVoteMutationState(),
  )!
}
