import { describe, expect, it } from '@ohos/hypium'
import { DownloadGalleryTask, GalleryResumeAllGate, GalleryResumeBatch } from 'shared'

function task(gid: string): DownloadGalleryTask {
  const value: DownloadGalleryTask = new DownloadGalleryTask()
  value.gid = gid
  value.token = 'token-' + gid
  return value
}

export default function galleryResumeBatchTest(): void {
  describe('GalleryResumeBatch', () => {
    it('starts up to the configured number of recoveries before an earlier gallery completes', 0, async (done: Function) => {
      const starts: string[] = []
      const errors: string[] = []
      let releaseFirst: () => void = (): void => {}
      const completion: Promise<void> = GalleryResumeBatch.start(
        [task('first'), task('second')],
        2,
        (pending: DownloadGalleryTask): Promise<void> => {
          starts.push(pending.gid)
          if (pending.gid === 'first') {
            return new Promise<void>((resolve: () => void): void => {
              releaseFirst = resolve
            })
          }
          return Promise.resolve()
        },
        (failed: DownloadGalleryTask, error: Error): void => {
          errors.push(failed.gid + ':' + error.message)
        },
      )

      expect(starts.join(',')).assertEqual('first,second')
      releaseFirst()
      await completion
      expect(errors.length).assertEqual(0)
      done()
    })

    it('keeps later recoveries running when one start fails', 0, async (done: Function) => {
      const starts: string[] = []
      const errors: string[] = []
      await GalleryResumeBatch.start(
        [task('broken'), task('healthy')],
        1,
        (pending: DownloadGalleryTask): Promise<void> => {
          starts.push(pending.gid)
          return pending.gid === 'broken'
            ? Promise.reject(new Error('expected'))
            : Promise.resolve()
        },
        (failed: DownloadGalleryTask, error: Error): void => {
          errors.push(failed.gid + ':' + error.message)
        },
      )

      expect(starts.join(',')).assertEqual('broken,healthy')
      expect(errors.length).assertEqual(1)
      expect(errors[0]).assertEqual('broken:expected')
      done()
    })

    it('does not start another recovery until a bounded worker becomes available', 0, async (done: Function) => {
      const starts: string[] = []
      let releaseFirst: () => void = (): void => {}
      const completion: Promise<void> = GalleryResumeBatch.start(
        [task('first'), task('second')],
        1,
        (pending: DownloadGalleryTask): Promise<void> => {
          starts.push(pending.gid)
          if (pending.gid === 'first') {
            return new Promise<void>((resolve: () => void): void => {
              releaseFirst = resolve
            })
          }
          return Promise.resolve()
        },
        (_failed: DownloadGalleryTask, _error: Error): void => {},
      )

      expect(starts.join(',')).assertEqual('first')
      releaseFirst()
      await completion
      expect(starts.join(',')).assertEqual('first,second')
      done()
    })

    it('joins repeated resume-all requests until the active batch settles', 0, async (done: Function) => {
      const gate: GalleryResumeAllGate = new GalleryResumeAllGate()
      let starts: number = 0
      let release: () => void = (): void => {}
      const first: Promise<void> = gate.joinOrStart((): Promise<void> => {
        starts++
        return new Promise<void>((resolve: () => void): void => {
          release = resolve
        })
      })
      const second: Promise<void> = gate.joinOrStart((): Promise<void> => {
        starts++
        return Promise.resolve()
      })

      expect(starts).assertEqual(1)
      release()
      await first
      await second
      await gate.joinOrStart((): Promise<void> => {
        starts++
        return Promise.resolve()
      })
      expect(starts).assertEqual(2)
      done()
    })

    it('releases a failed resume-all batch for a later retry', 0, async (done: Function) => {
      const gate: GalleryResumeAllGate = new GalleryResumeAllGate()
      let starts: number = 0
      try {
        await gate.joinOrStart((): Promise<void> => {
          starts++
          return Promise.reject(new Error('expected'))
        })
      } catch (_error) {
      }
      await gate.joinOrStart((): Promise<void> => {
        starts++
        return Promise.resolve()
      })
      expect(starts).assertEqual(2)
      done()
    })
  })
}
