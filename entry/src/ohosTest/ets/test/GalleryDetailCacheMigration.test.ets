import { describe, expect, it } from '@ohos/hypium'
import { EhPageCacheService, GalleryDetailResult } from 'shared'

const LEGACY_DETAIL_PAYLOAD: string = '{"gallery":{"gid":"1","token":"token"},"images":[' +
  '{"page":1,"imgkey":"key","sUrl":"https://e-hentai.org/s/key/1-1",' +
  '"thumbUrl":"https://thumb.test/one.jpg","thumbWidth":100,"thumbHeight":200},' +
  '{"page":2,"imgkey":"key2","sUrl":"https://e-hentai.org/s/key2/1-2",' +
  '"thumbUrl":"https://thumb.test/two.jpg","thumbWidth":0,"thumbHeight":200}' +
  '],"comments":[],"previewPageCount":1}'

const EXPLICIT_FALSE_DETAIL_PAYLOAD: string = '{"gallery":{"gid":"1","token":"token"},"images":[' +
  '{"page":1,"imgkey":"key","sUrl":"https://e-hentai.org/s/key/1-1",' +
  '"thumbUrl":"https://thumb.test/one.jpg","thumbWidth":100,"thumbHeight":200,' +
  '"previewGeometryWholePage":false}' +
  '],"comments":[],"previewPageCount":1}'

export default function galleryDetailCacheMigrationTest(): void {
  describe('Gallery detail cache preview-geometry migration', () => {
    it('restores only an absent legacy parser attestation with the parser rule', 0, () => {
      const restored: GalleryDetailResult = EhPageCacheService.decodeGalleryDetailPayload(LEGACY_DETAIL_PAYLOAD)
      expect(restored.images[0].previewGeometryWholePage).assertEqual(true)
      expect(restored.images[1].previewGeometryWholePage).assertEqual(false)
    })

    it('preserves an explicit false attestation', 0, () => {
      const restored: GalleryDetailResult = EhPageCacheService.decodeGalleryDetailPayload(EXPLICIT_FALSE_DETAIL_PAYLOAD)
      expect(restored.images[0].previewGeometryWholePage).assertEqual(false)
    })
  })
}
