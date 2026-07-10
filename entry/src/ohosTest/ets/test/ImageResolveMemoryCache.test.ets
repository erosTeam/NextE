import { describe, expect, it } from '@ohos/hypium'
import { ImagePageResult, ImageResolveMemoryCache } from 'shared'

function resolved(url: string): ImagePageResult {
  const result: ImagePageResult = new ImagePageResult()
  result.imageUrl = url
  result.originImageUrl = `${url}/original`
  result.reloadKey = `${url}-reload`
  return result
}

export default function imageResolveMemoryCacheTest(): void {
  describe('ImageResolveMemoryCache', () => {
    it('bounds page metadata and gallery keys with LRU eviction', 0, (done: Function) => {
      const cache: ImageResolveMemoryCache = new ImageResolveMemoryCache(2, 2)
      cache.putResolved('first', resolved('first-url'))
      cache.putResolved('second', resolved('second-url'))
      const firstHit: ImagePageResult | undefined = cache.getResolved('first')
      expect(firstHit === undefined ? '' : firstHit.imageUrl).assertEqual('first-url')
      if (firstHit !== undefined) {
        firstHit.imageUrl = 'caller-mutation'
      }
      cache.putResolved('third', resolved('third-url'))
      expect(cache.resolvedCount()).assertEqual(2)
      expect(cache.getResolved('second') === undefined).assertEqual(true)
      const preserved: ImagePageResult | undefined = cache.getResolved('first')
      expect(preserved === undefined ? '' : preserved.imageUrl).assertEqual('first-url')
      const thirdHit: ImagePageResult | undefined = cache.getResolved('third')
      expect(thirdHit === undefined ? '' : thirdHit.originImageUrl).assertEqual('third-url/original')

      cache.putShowKey('one', 'key-one')
      cache.putShowKey('two', 'key-two')
      expect(cache.getShowKey('one')).assertEqual('key-one')
      cache.putShowKey('three', 'key-three')
      expect(cache.showKeyCount()).assertEqual(2)
      expect(cache.getShowKey('two')).assertEqual('')
      expect(cache.getShowKey('one')).assertEqual('key-one')
      expect(cache.getShowKey('three')).assertEqual('key-three')
      done()
    })
  })
}
