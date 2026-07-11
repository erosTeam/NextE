import { describe, expect, it } from '@ohos/hypium'
import { CustomProfilesPersistScheduler } from 'shared'

function waitFor(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(() => {
      resolve()
    }, ms)
  })
}

export default function customProfilesPersistSchedulerTest(): void {
  describe('CustomProfilesPersistScheduler', () => {
    it('makes a later profile snapshot durable after an active write', 0, async (done: Function) => {
      const scheduler: CustomProfilesPersistScheduler = new CustomProfilesPersistScheduler()
      const writes: string[] = []
      let releaseFirst: () => void = (): void => {}
      scheduler.enqueue((): Promise<void> => {
        writes.push('before')
        return new Promise<void>((resolve: () => void): void => {
          releaseFirst = resolve
        })
      })
      const finalWrite: Promise<void> = scheduler.enqueue((): Promise<void> => {
        writes.push('after')
        return Promise.resolve()
      })

      await waitFor(10)
      expect(writes.length).assertEqual(1)
      expect(writes[0]).assertEqual('before')
      releaseFirst()
      await finalWrite

      expect(writes.length).assertEqual(2)
      expect(writes[1]).assertEqual('after')
      done()
    })

    it('keeps later profile writes runnable after a failure', 0, async (done: Function) => {
      const scheduler: CustomProfilesPersistScheduler = new CustomProfilesPersistScheduler()
      let failed: boolean = false
      await scheduler.enqueue((): Promise<void> => Promise.reject(new Error('expected'))).catch((): void => {
        failed = true
      })
      let wrote: boolean = false
      await scheduler.enqueue((): Promise<void> => {
        wrote = true
        return Promise.resolve()
      })

      expect(failed).assertEqual(true)
      expect(wrote).assertEqual(true)
      done()
    })
  })
}
