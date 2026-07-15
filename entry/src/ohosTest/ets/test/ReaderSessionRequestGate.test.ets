import { describe, expect, it } from '@ohos/hypium'
import { ReaderSessionRequestGate } from 'reader'

export default function readerSessionRequestGateTest(): void {
  describe('Reader session request gate', () => {
    it('drops a preview result from a gallery replaced by another gallery', 0, (done: Function) => {
      const gate: ReaderSessionRequestGate = new ReaderSessionRequestGate()
      const oldRequest = gate.begin('gallery-a', 'token-a', false)
      const currentRequest = gate.begin('gallery-b', 'token-b', true)

      expect(gate.isCurrent(oldRequest)).assertEqual(false)
      expect(gate.isCurrent(currentRequest)).assertEqual(true)
      done()
    })

    it('drops an earlier request when the reader returns to a gallery after another session', 0, (done: Function) => {
      const gate: ReaderSessionRequestGate = new ReaderSessionRequestGate()
      const oldRequest = gate.begin('gallery-a', 'token-a', false)
      gate.begin('gallery-b', 'token-b', false)
      const currentRequest = gate.begin('gallery-a', 'token-a', false)

      expect(gate.isCurrent(oldRequest)).assertEqual(false)
      expect(gate.isCurrent(currentRequest)).assertEqual(true)
      done()
    })

    it('separates online and local sources for the same gallery identity', 0, (done: Function) => {
      const gate: ReaderSessionRequestGate = new ReaderSessionRequestGate()
      const onlineRequest = gate.begin('gallery-a', 'token-a', false, '')
      const localRequest = gate.begin('gallery-a', 'token-a', false, 'archive:gallery-a:completed')

      expect(gate.isCurrent(onlineRequest)).assertEqual(false)
      expect(gate.isCurrent(localRequest)).assertEqual(true)
      done()
    })
  })
}
