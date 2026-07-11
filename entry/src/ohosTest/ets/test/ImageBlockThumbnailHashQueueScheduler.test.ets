import { describe, expect, it } from '@ohos/hypium'
import {
  ImageBlockThumbnailHashQueueScheduler,
  ImageBlockThumbnailHashQueueTask,
} from 'shared'

export default function imageBlockThumbnailHashQueueSchedulerTest(): void {
  describe('ImageBlockThumbnailHashQueueScheduler', () => {
    it('bounds waiting hashes and runs the newest visible thumbnail first', 0, (done: Function) => {
      const starts: string[] = []
      const dropped: string[] = []
      const scheduler: ImageBlockThumbnailHashQueueScheduler =
        new ImageBlockThumbnailHashQueueScheduler(1, 2)
      const active: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'active',
        () => starts.push('active'),
      )
      const stale: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'stale',
        () => starts.push('stale'),
        () => dropped.push('stale'),
      )
      const previous: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'previous',
        () => starts.push('previous'),
      )
      const newest: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'newest',
        () => starts.push('newest'),
      )

      scheduler.schedule(active)
      scheduler.schedule(stale)
      scheduler.schedule(previous)
      scheduler.schedule(newest)

      expect(starts.join(',')).assertEqual('active')
      expect(dropped.join(',')).assertEqual('stale')
      expect(stale.discarded).assertEqual(true)
      expect(scheduler.activeCount()).assertEqual(1)
      expect(scheduler.pendingCount()).assertEqual(2)

      scheduler.complete(active)
      expect(starts.join(',')).assertEqual('active,newest')
      scheduler.complete(newest)
      expect(starts.join(',')).assertEqual('active,newest,previous')
      scheduler.complete(previous)
      expect(scheduler.activeCount()).assertEqual(0)
      expect(scheduler.pendingCount()).assertEqual(0)
      done()
    })

    it('promotes another visible request for the same waiting thumbnail', 0, (done: Function) => {
      const starts: string[] = []
      const scheduler: ImageBlockThumbnailHashQueueScheduler =
        new ImageBlockThumbnailHashQueueScheduler(1, 3)
      const active: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'active',
        () => starts.push('active'),
      )
      const returning: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'returning',
        () => starts.push('returning'),
      )
      const newer: ImageBlockThumbnailHashQueueTask = new ImageBlockThumbnailHashQueueTask(
        'newer',
        () => starts.push('newer'),
      )

      scheduler.schedule(active)
      scheduler.schedule(returning)
      scheduler.schedule(newer)
      scheduler.promote(returning)
      scheduler.complete(active)

      expect(starts.join(',')).assertEqual('active,returning')
      scheduler.complete(returning)
      expect(starts.join(',')).assertEqual('active,returning,newer')
      done()
    })
  })
}
