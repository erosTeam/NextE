import { describe, expect, it } from '@ohos/hypium'
import { GallerySeedQueueTask, GallerySeedScheduler } from 'shared'

export default function gallerySeedSchedulerTest(): void {
  describe('GallerySeedScheduler', () => {
    it('enforces one global image limit and drops paused gallery work before it starts', 0, (done: Function) => {
      const starts: string[] = []
      const scheduler: GallerySeedScheduler = new GallerySeedScheduler()
      const first: GallerySeedQueueTask = new GallerySeedQueueTask(
        'first',
        'gallery-a',
        () => starts.push('first'),
      )
      const second: GallerySeedQueueTask = new GallerySeedQueueTask(
        'second',
        'gallery-b',
        () => starts.push('second'),
      )
      const third: GallerySeedQueueTask = new GallerySeedQueueTask(
        'third',
        'gallery-c',
        () => starts.push('third'),
      )
      scheduler.schedule(first, 2)
      scheduler.schedule(second, 2)
      scheduler.schedule(third, 2)
      expect(starts.join(',')).assertEqual('first,second')
      scheduler.complete(first, 2)
      expect(starts.join(',')).assertEqual('first,second,third')

      const cappedStarts: string[] = []
      const capped: GallerySeedScheduler = new GallerySeedScheduler()
      const capA: GallerySeedQueueTask = new GallerySeedQueueTask('cap-a', 'a', () => cappedStarts.push('a'))
      const capB: GallerySeedQueueTask = new GallerySeedQueueTask('cap-b', 'b', () => cappedStarts.push('b'))
      const capC: GallerySeedQueueTask = new GallerySeedQueueTask('cap-c', 'c', () => cappedStarts.push('c'))
      const capD: GallerySeedQueueTask = new GallerySeedQueueTask('cap-d', 'd', () => cappedStarts.push('d'))
      capped.schedule(capA, 2)
      capped.schedule(capB, 2)
      capped.schedule(capC, 2)
      capped.schedule(capD, 1)
      capped.complete(capA, 1)
      expect(cappedStarts.join(',')).assertEqual('a,b')
      capped.complete(capB, 1)
      expect(cappedStarts.join(',')).assertEqual('a,b,c')

      const cancelled: string[] = []
      const pauseScheduler: GallerySeedScheduler = new GallerySeedScheduler()
      const active: GallerySeedQueueTask = new GallerySeedQueueTask(
        'active',
        'active-gallery',
        () => cancelled.push('active-start'),
      )
      const paused: GallerySeedQueueTask = new GallerySeedQueueTask(
        'paused',
        'paused-gallery',
        () => cancelled.push('paused-start'),
        () => cancelled.push('paused-cancel'),
      )
      pauseScheduler.schedule(active, 1)
      pauseScheduler.schedule(paused, 1)
      expect(pauseScheduler.cancelQueued('paused-gallery')).assertEqual(1)
      pauseScheduler.complete(active, 1)
      expect(cancelled.join(',')).assertEqual('active-start,paused-cancel')
      done()
    })
  })
}
