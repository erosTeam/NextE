import { describe, expect, it } from '@ohos/hypium'
import { EhGallery, GalleryDetailResult, GallerySeedDetailRefreshGate } from 'shared'

function detail(gid: string): GalleryDetailResult {
  return new GalleryDetailResult(new EhGallery(gid, 'token-' + gid), [])
}

export default function gallerySeedDetailRefreshGateTest(): void {
  describe('Gallery seed detail refresh gate', () => {
    it('joins the same gallery quality refresh without starting another detail request', 0, async (done: Function) => {
      const gate: GallerySeedDetailRefreshGate = new GallerySeedDetailRefreshGate()
      let starts: number = 0
      let release: (value: GalleryDetailResult) => void = (_value: GalleryDetailResult): void => {}
      const first: Promise<GalleryDetailResult> = gate.joinOrStart(
        'one:token-one:resample:eh',
        (): Promise<GalleryDetailResult> => {
          starts++
          return new Promise<GalleryDetailResult>((resolve: (value: GalleryDetailResult) => void): void => {
            release = resolve
          })
        },
      )
      const second: Promise<GalleryDetailResult> = gate.joinOrStart(
        'one:token-one:resample:eh',
        (): Promise<GalleryDetailResult> => {
          starts++
          return Promise.resolve(detail('unexpected'))
        },
      )

      expect(starts).assertEqual(1)
      release(detail('one'))
      expect((await first).gallery.gid).assertEqual('one')
      expect((await second).gallery.gid).assertEqual('one')
      done()
    })

    it('keeps separate image-quality refreshes independent', 0, async (done: Function) => {
      const gate: GallerySeedDetailRefreshGate = new GallerySeedDetailRefreshGate()
      let starts: number = 0
      const resample: Promise<GalleryDetailResult> = gate.joinOrStart(
        'one:token-one:resample:eh',
        (): Promise<GalleryDetailResult> => {
          starts++
          return Promise.resolve(detail('resample'))
        },
      )
      const original: Promise<GalleryDetailResult> = gate.joinOrStart(
        'one:token-one:original:eh',
        (): Promise<GalleryDetailResult> => {
          starts++
          return Promise.resolve(detail('original'))
        },
      )

      expect(starts).assertEqual(2)
      expect((await resample).gallery.gid).assertEqual('resample')
      expect((await original).gallery.gid).assertEqual('original')
      done()
    })

    it('releases a failed detail refresh so a later retry can start', 0, async (done: Function) => {
      const gate: GallerySeedDetailRefreshGate = new GallerySeedDetailRefreshGate()
      let starts: number = 0
      try {
        await gate.joinOrStart('one:token-one:resample:eh', (): Promise<GalleryDetailResult> => {
          starts++
          return Promise.reject(new Error('expected'))
        })
      } catch (_error) {
      }
      await gate.joinOrStart('one:token-one:resample:eh', (): Promise<GalleryDetailResult> => {
        starts++
        return Promise.resolve(detail('retry'))
      })
      expect(starts).assertEqual(2)
      done()
    })
  })
}
