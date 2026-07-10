import { describe, expect, it } from '@ohos/hypium'
import { ImageBlockThumbnailHashMemoryCache } from 'shared'

export default function imageBlockThumbnailHashMemoryCacheTest(): void {
  describe('ImageBlockThumbnailHashMemoryCache', () => {
    it('keeps a bounded LRU working set without caching empty values', 0, (done: Function) => {
      const cache: ImageBlockThumbnailHashMemoryCache = new ImageBlockThumbnailHashMemoryCache(2)
      cache.put('first', '0000000000000001')
      cache.put('second', '0000000000000002')
      expect(cache.get('first')).assertEqual('0000000000000001')
      cache.put('third', '0000000000000003')
      expect(cache.size()).assertEqual(2)
      expect(cache.get('second')).assertEqual('')
      expect(cache.get('first')).assertEqual('0000000000000001')
      expect(cache.get('third')).assertEqual('0000000000000003')

      cache.put('', '0000000000000004')
      cache.put('empty', '')
      expect(cache.size()).assertEqual(2)
      expect(cache.get('empty')).assertEqual('')
      done()
    })
  })
}
