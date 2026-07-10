import { describe, expect, it } from '@ohos/hypium'
import { CommentTranslationMemoryCache } from 'shared'

export default function commentTranslationMemoryCacheTest(): void {
  describe('CommentTranslationMemoryCache', () => {
    it('keeps a bounded LRU working set and removes expired entries', 0, (done: Function) => {
      const cache: CommentTranslationMemoryCache = new CommentTranslationMemoryCache(2)
      cache.put('first', 'one', 100, 0)
      cache.put('second', 'two', 100, 0)
      expect(cache.get('first', 1)).assertEqual('one')
      cache.put('third', 'three', 100, 1)
      expect(cache.get('second', 1)).assertEqual('')
      expect(cache.get('first', 1)).assertEqual('one')
      expect(cache.get('third', 1)).assertEqual('three')
      const expiryCache: CommentTranslationMemoryCache = new CommentTranslationMemoryCache(2)
      expiryCache.put('expired', 'gone', 2, 1)
      expect(expiryCache.get('expired', 2)).assertEqual('')
      expect(expiryCache.size(2)).assertEqual(0)
      done()
    })
  })
}
