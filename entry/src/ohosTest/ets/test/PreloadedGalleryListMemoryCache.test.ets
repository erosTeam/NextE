import { describe, expect, it } from '@ohos/hypium'
import { GalleryList, PreloadedGalleryListMemoryCache } from 'shared'

function list(nextGid: string): GalleryList {
  const out: GalleryList = new GalleryList()
  out.nextGid = nextGid
  return out
}

export default function preloadedGalleryListMemoryCacheTest(): void {
  describe('PreloadedGalleryListMemoryCache', () => {
    it('bounds unused startup preloads and isolates staged snapshots', 0, (done: Function) => {
      const isolated: PreloadedGalleryListMemoryCache = new PreloadedGalleryListMemoryCache(1)
      const source: GalleryList = list('source')
      isolated.put('source', source)
      source.nextGid = 'caller-mutated'
      const staged: GalleryList | null = isolated.take('source')
      expect(staged === null ? '' : staged.nextGid).assertEqual('source')

      const cache: PreloadedGalleryListMemoryCache = new PreloadedGalleryListMemoryCache(2)
      cache.put('first', list('first'))
      cache.put('second', list('second'))
      cache.put('first', list('first-refreshed'))
      cache.put('third', list('third'))
      expect(cache.size()).assertEqual(2)
      expect(cache.take('second') === null).assertEqual(true)
      const first: GalleryList | null = cache.take('first')
      expect(first === null ? '' : first.nextGid).assertEqual('first-refreshed')
      if (first !== null) {
        first.nextGid = 'consumer-mutated'
      }
      const third: GalleryList | null = cache.take('third')
      expect(third === null ? '' : third.nextGid).assertEqual('third')
      expect(cache.size()).assertEqual(0)
      done()
    })
  })
}
