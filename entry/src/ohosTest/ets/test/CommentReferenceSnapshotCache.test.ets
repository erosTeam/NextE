import { describe, expect, it } from '@ohos/hypium'
import { CommentReferenceSnapshotCache, EhGalleryComment } from 'shared'

function source(commentId: string): EhGalleryComment[] {
  const comment: EhGalleryComment = new EhGalleryComment()
  comment.commentId = commentId
  return [comment]
}

export default function commentReferenceSnapshotCacheTest(): void {
  describe('CommentReferenceSnapshotCache', () => {
    it('shares an active source snapshot and evicts the least recently used source', 0, (done: Function) => {
      const cache: CommentReferenceSnapshotCache = new CommentReferenceSnapshotCache(2)
      const first: EhGalleryComment[] = source('1')
      const second: EhGalleryComment[] = source('2')
      const third: EhGalleryComment[] = source('3')
      const firstSorted: EhGalleryComment[] = first.slice()
      const secondSorted: EhGalleryComment[] = second.slice()
      const thirdSorted: EhGalleryComment[] = third.slice()

      cache.put(first, firstSorted)
      cache.put(second, secondSorted)
      expect(cache.get(first) === firstSorted).assertEqual(true)
      cache.put(third, thirdSorted)

      expect(cache.size()).assertEqual(2)
      expect(cache.get(second) === null).assertEqual(true)
      expect(cache.get(first) === firstSorted).assertEqual(true)
      expect(cache.get(third) === thirdSorted).assertEqual(true)
      done()
    })
  })
}
