import { describe, expect, it } from '@ohos/hypium'
import {
  EhGallery,
  EhGalleryComment,
  EhGalleryImage,
  GalleryDetailResult,
  RecentGalleryDetailMemoryCache,
} from 'shared'

function detail(gid: string): GalleryDetailResult {
  const gallery: EhGallery = new EhGallery(gid, 'token')
  gallery.englishTitle = gid
  const image: EhGalleryImage = new EhGalleryImage(0)
  image.thumbUrl = gid
  const comment: EhGalleryComment = new EhGalleryComment()
  comment.contentText = gid
  return new GalleryDetailResult(gallery, [image], [comment], 2)
}

export default function recentGalleryDetailMemoryCacheTest(): void {
  describe('RecentGalleryDetailMemoryCache', () => {
    it('keeps recent detail snapshots reusable, bounded, and isolated', 0, (done: Function) => {
      const cache: RecentGalleryDetailMemoryCache = new RecentGalleryDetailMemoryCache(2)
      const source: GalleryDetailResult = detail('first')
      cache.put('first', source)
      source.gallery.englishTitle = 'source-mutated'
      source.images[0].thumbUrl = 'source-mutated'
      source.comments[0].contentText = 'source-mutated'

      const first: GalleryDetailResult | null = cache.get('first')
      expect(first === null ? '' : first.gallery.englishTitle).assertEqual('first')
      expect(first === null ? '' : first.images[0].thumbUrl).assertEqual('first')
      expect(first === null ? '' : first.comments[0].contentText).assertEqual('first')
      if (first !== null) {
        first.gallery.englishTitle = 'consumer-mutated'
      }
      const reused: GalleryDetailResult | null = cache.get('first')
      expect(reused === null ? '' : reused.gallery.englishTitle).assertEqual('first')

      cache.put('second', detail('second'))
      cache.get('first')
      cache.put('third', detail('third'))
      expect(cache.size()).assertEqual(2)
      expect(cache.get('second') === null).assertEqual(true)
      expect(cache.get('first') === null).assertEqual(false)
      expect(cache.get('third') === null).assertEqual(false)
      done()
    })
  })
}
