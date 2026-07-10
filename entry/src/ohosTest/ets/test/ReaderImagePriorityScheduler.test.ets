import { describe, expect, it } from '@ohos/hypium'
import {
  EH_IMAGE_PRIORITY_HIGH,
  EH_IMAGE_PRIORITY_LOW,
  ReaderImagePriorityScheduler,
  ReaderImagePriorityTask,
} from 'shared'

export default function readerImagePrioritySchedulerTest(): void {
  describe('ReaderImagePriorityScheduler', () => {
    it('starts visible images ahead of queued warmers and promotes the same queued task', 0, (done: Function) => {
      const starts: string[] = []
      const scheduler: ReaderImagePriorityScheduler = new ReaderImagePriorityScheduler()
      const lowA: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'low-a',
        EH_IMAGE_PRIORITY_LOW,
        () => starts.push('low-a'),
      )
      const lowB: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'low-b',
        EH_IMAGE_PRIORITY_LOW,
        () => starts.push('low-b'),
      )
      const high: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'high',
        EH_IMAGE_PRIORITY_HIGH,
        () => starts.push('high'),
      )

      scheduler.schedule(lowA)
      scheduler.schedule(lowB)
      scheduler.schedule(high)
      expect(starts.join(',')).assertEqual('low-a,high')
      scheduler.complete(lowA)
      expect(starts.join(',')).assertEqual('low-a,high,low-b')

      const promotionStarts: string[] = []
      const promotionScheduler: ReaderImagePriorityScheduler = new ReaderImagePriorityScheduler()
      const activeLow: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'active-low',
        EH_IMAGE_PRIORITY_LOW,
        () => promotionStarts.push('active-low'),
      )
      const queuedLow: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'queued-low',
        EH_IMAGE_PRIORITY_LOW,
        () => promotionStarts.push('queued-low'),
      )
      promotionScheduler.schedule(activeLow)
      promotionScheduler.schedule(queuedLow)
      promotionScheduler.promote(queuedLow, EH_IMAGE_PRIORITY_HIGH)
      expect(promotionStarts.join(',')).assertEqual('active-low,queued-low')
      expect(queuedLow.started).assertEqual(true)
      expect(queuedLow.priority).assertEqual(EH_IMAGE_PRIORITY_HIGH)

      const cancellationStarts: string[] = []
      const cancellationScheduler: ReaderImagePriorityScheduler = new ReaderImagePriorityScheduler()
      const activeWarm: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'active-warm',
        EH_IMAGE_PRIORITY_LOW,
        () => cancellationStarts.push('active-warm'),
      )
      const staleWarm: ReaderImagePriorityTask = new ReaderImagePriorityTask(
        'stale-warm',
        EH_IMAGE_PRIORITY_LOW,
        () => cancellationStarts.push('stale-warm'),
      )
      cancellationScheduler.schedule(activeWarm)
      cancellationScheduler.schedule(staleWarm)
      expect(cancellationScheduler.cancel(staleWarm)).assertEqual(true)
      cancellationScheduler.complete(activeWarm)
      expect(cancellationStarts.join(',')).assertEqual('active-warm')
      expect(staleWarm.started).assertEqual(false)
      done()
    })
  })
}
