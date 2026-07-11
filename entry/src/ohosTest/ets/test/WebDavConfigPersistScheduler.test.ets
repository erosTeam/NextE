import { describe, expect, it } from '@ohos/hypium'
import { WebDavConfigPersistScheduler } from 'shared'

function waitFor(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(() => {
      resolve()
    }, ms)
  })
}

export default function webDavConfigPersistSchedulerTest(): void {
  describe('WebDavConfigPersistScheduler', () => {
    it('persists only the newest rapid configuration edit', 0, async (done: Function) => {
      const scheduler: WebDavConfigPersistScheduler = new WebDavConfigPersistScheduler(1000)
      const writes: string[] = []
      scheduler.schedule((): Promise<void> => {
        writes.push('1')
        return Promise.resolve()
      })
      scheduler.schedule((): Promise<void> => {
        writes.push('10')
        return Promise.resolve()
      })
      scheduler.schedule((): Promise<void> => {
        writes.push('100')
        return Promise.resolve()
      })

      await scheduler.flush()
      expect(writes.length).assertEqual(1)
      expect(writes[0]).assertEqual('100')
      done()
    })

    it('makes the newest configuration write final after an active write', 0, async (done: Function) => {
      const scheduler: WebDavConfigPersistScheduler = new WebDavConfigPersistScheduler(1)
      const writes: string[] = []
      let releaseFirst: () => void = (): void => {}
      let firstWriteStarted: boolean = false
      scheduler.schedule((): Promise<void> => {
        writes.push('1')
        firstWriteStarted = true
        return new Promise<void>((resolve: () => void): void => {
          releaseFirst = resolve
        })
      })
      await waitFor(20)
      expect(firstWriteStarted).assertEqual(true)

      scheduler.schedule((): Promise<void> => {
        writes.push('100')
        return Promise.resolve()
      })
      const completion: Promise<void> = scheduler.flush()
      releaseFirst()
      await completion

      expect(writes.length).assertEqual(2)
      expect(writes[0]).assertEqual('1')
      expect(writes[1]).assertEqual('100')
      done()
    })
  })
}
