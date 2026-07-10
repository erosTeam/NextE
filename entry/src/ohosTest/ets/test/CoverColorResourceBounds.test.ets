import { describe, expect, it } from '@ohos/hypium'
import { CoverColorMemoryCache, CoverColorQueueScheduler, CoverColorQueueTask } from 'shared'

export default function coverColorResourceBoundsTest(): void {
  describe('CoverColorResourceBounds', () => {
    it('keeps cached colors bounded while retaining a cached extraction failure', 0, (done: Function) => {
      const cache: CoverColorMemoryCache = new CoverColorMemoryCache(2)
      cache.put('first', 0xff010203)
      cache.put('failed', 0)
      expect(cache.get('first')).assertEqual(0xff010203)
      cache.put('third', 0xff040506)
      expect(cache.size()).assertEqual(2)
      expect(cache.get('failed') === undefined).assertEqual(true)
      expect(cache.get('first')).assertEqual(0xff010203)
      expect(cache.get('third')).assertEqual(0xff040506)
      done()
    })

    it('runs the newest decoration first and drops stale pending work', 0, (done: Function) => {
      const starts: string[] = []
      const dropped: string[] = []
      const scheduler: CoverColorQueueScheduler = new CoverColorQueueScheduler(1, 2)
      const first: CoverColorQueueTask = new CoverColorQueueTask('first', () => starts.push('first'))
      const second: CoverColorQueueTask = new CoverColorQueueTask(
        'second',
        () => starts.push('second'),
        () => dropped.push('second'),
      )
      const third: CoverColorQueueTask = new CoverColorQueueTask('third', () => starts.push('third'))
      const fourth: CoverColorQueueTask = new CoverColorQueueTask('fourth', () => starts.push('fourth'))
      scheduler.schedule(first)
      scheduler.schedule(second)
      scheduler.schedule(third)
      scheduler.schedule(fourth)
      expect(starts.join(',')).assertEqual('first')
      expect(dropped.join(',')).assertEqual('second')
      expect(scheduler.activeCount()).assertEqual(1)
      expect(scheduler.pendingCount()).assertEqual(2)
      scheduler.complete(first)
      expect(starts.join(',')).assertEqual('first,fourth')
      scheduler.complete(fourth)
      expect(starts.join(',')).assertEqual('first,fourth,third')
      scheduler.complete(third)
      expect(scheduler.activeCount()).assertEqual(0)
      expect(scheduler.pendingCount()).assertEqual(0)
      done()
    })
  })
}
