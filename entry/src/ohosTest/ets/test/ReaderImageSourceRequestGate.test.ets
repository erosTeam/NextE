import { describe, expect, it } from '@ohos/hypium'
import { EhGalleryImage } from 'shared'
import { ReaderImageSourceRequestGate } from 'reader'

function image(page: number, sUrl: string): EhGalleryImage {
  const value: EhGalleryImage = new EhGalleryImage(page)
  value.sUrl = sUrl
  return value
}

export default function readerImageSourceRequestGateTest(): void {
  describe('Reader image source request gate', () => {
    it('drops an old normal resolve after the user switches to the original source', 0, (done: Function) => {
      const gate: ReaderImageSourceRequestGate = new ReaderImageSourceRequestGate()
      const live: EhGalleryImage = image(7, 'https://e-hentai.org/s/key/7-1')
      const normal = gate.begin(live, 'page-7-fit', 'reader:7:resampled', false)
      normal.image.imageUrl = 'https://old-host.example/resampled.jpg'
      normal.image.reloadKey = 'old-reload'

      const original = gate.begin(live, 'page-7-orig', 'reader:7:original', true)
      original.image.originImageUrl = 'https://new-host.example/original.jpg'
      original.image.reloadKey = 'new-reload'

      expect(gate.commitResolvedImage(
        normal,
        live,
        'page-7-orig',
        'reader:7:original',
        true,
      )).assertEqual(false)
      expect(live.imageUrl).assertEqual('')
      expect(gate.commitResolvedImage(
        original,
        live,
        'page-7-orig',
        'reader:7:original',
        true,
      )).assertEqual(true)
      expect(live.originImageUrl).assertEqual('https://new-host.example/original.jpg')
      expect(live.reloadKey).assertEqual('new-reload')
      done()
    })

    it('invalidates a disappearing page so a late failure or result has no owner', 0, (done: Function) => {
      const gate: ReaderImageSourceRequestGate = new ReaderImageSourceRequestGate()
      const live: EhGalleryImage = image(3, 'https://e-hentai.org/s/key/3-1')
      const request = gate.begin(live, 'page-3-fit', 'reader:3:resampled', false)
      gate.invalidate()
      expect(gate.isCurrent(request, 'page-3-fit', 'reader:3:resampled', false)).assertEqual(false)
      done()
    })
  })
}
