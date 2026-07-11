import { describe, expect, it } from '@ohos/hypium'
import { ImageResolveSourceGate } from 'shared'

export default function imageResolveSourceGateTest(): void {
  describe('Image resolve source gate', () => {
    it('prevents an older normal resolve from owning memory after a source reload starts', 0, (done: Function) => {
      const gate: ImageResolveSourceGate = new ImageResolveSourceGate()
      const normalEpoch: number = gate.begin('https://e-hentai.org/s/key/1-1', false)
      const reloadEpoch: number = gate.begin('https://e-hentai.org/s/key/1-1', true)
      expect(normalEpoch).assertEqual(0)
      expect(reloadEpoch).assertEqual(1)
      expect(gate.isCurrent('https://e-hentai.org/s/key/1-1', normalEpoch)).assertEqual(false)
      expect(gate.isCurrent('https://e-hentai.org/s/key/1-1', reloadEpoch)).assertEqual(true)
      done()
    })

    it('keeps only the latest consecutive source reload current', 0, (done: Function) => {
      const gate: ImageResolveSourceGate = new ImageResolveSourceGate()
      const first: number = gate.begin('https://e-hentai.org/s/key/2-1', true)
      const second: number = gate.begin('https://e-hentai.org/s/key/2-1', true)
      expect(gate.isCurrent('https://e-hentai.org/s/key/2-1', first)).assertEqual(false)
      expect(gate.isCurrent('https://e-hentai.org/s/key/2-1', second)).assertEqual(true)
      done()
    })
  })
}
