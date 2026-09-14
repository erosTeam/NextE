import { describe, expect, it } from '@ohos/hypium'
import {
  NextEReaderBackend,
  ReaderParams,
  connectNextEReaderBackendSelection,
  connectReaderOverlayNavigation,
} from 'shared'
import { NextEProductionReaderRequest } from 'reader'

export default function readerBackendSelectionTest(): void {
  describe('Reader backend replacement rehearsal', (): void => {
    it('fails closed and snapshots the backend at overlay admission', 0, (done: Function): void => {
      const selection = connectNextEReaderBackendSelection()
      const overlay = connectReaderOverlayNavigation()
      overlay.reset()

      expect(selection.selectForRehearsal(NextEReaderBackend.SHARED, false))
        .assertEqual(NextEReaderBackend.LEGACY)

      selection.selectForRehearsal(NextEReaderBackend.SHARED, true)
      overlay.open(new ReaderParams('123', 'token', 4, 10))
      selection.selectForRehearsal(NextEReaderBackend.LEGACY, true)
      overlay.presentPendingReader()
      expect(overlay.stack.getAllPathName().join(','))
        .assertEqual('ReaderOverlayBackdrop,ReaderShared')

      overlay.reset()
      overlay.open(new ReaderParams('123', 'token', 4, 10))
      overlay.presentPendingReader()
      expect(overlay.stack.getAllPathName().join(','))
        .assertEqual('ReaderOverlayBackdrop,Reader')
      overlay.reset()
      done()
    })

    it('keeps production requests free of Lab overrides', 0, (done: Function): void => {
      const request = new NextEProductionReaderRequest(new ReaderParams('456', 'token-2', 7, 12))
      expect(request.work).assertEqual('456')
      expect(request.unit).assertEqual('token-2')
      expect(request.pageIndex).assertEqual(7)
      expect(request.progressReadWrite).assertTrue()
      expect(request.preferencesReadWrite).assertTrue()
      expect(request.productionSources).assertTrue()
      expect(request.failurePage).assertEqual(-1)
      expect(request.thumbnailFailurePage).assertEqual(-1)
      expect(request.entryLayoutOverride === null).assertTrue()
      expect(request.entryDirectionOverride === null).assertTrue()
      expect(request.shareProbe).assertEqual('')
      expect(request.informationProbe).assertEqual('')
      expect(request.originalVariantProbe).assertEqual('')
      done()
    })
  })
}
