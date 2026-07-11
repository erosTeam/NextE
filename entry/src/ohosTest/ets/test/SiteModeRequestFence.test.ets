import { describe, expect, it } from '@ohos/hypium'
import { SiteModeRequestFence, SiteModeSettings } from 'shared'

export default function siteModeRequestFenceTest(): void {
  describe('Site mode request fence', () => {
    it('accepts an Ex unlock only for the current choice and credentials', 0, (done: Function) => {
      expect(SiteModeRequestFence.canApplyExUnlock(
        true, 'member-a', 'hash-a', 'member-a', 'hash-a',
      )).assertEqual(true)
      expect(SiteModeRequestFence.canApplyExUnlock(
        false, 'member-a', 'hash-a', 'member-a', 'hash-a',
      )).assertEqual(false)
      expect(SiteModeRequestFence.canApplyExUnlock(
        true, 'member-a', 'hash-a', 'member-b', 'hash-b',
      )).assertEqual(false)
      expect(SiteModeRequestFence.canApplyExUnlock(
        true, 'member-a', 'hash-a', 'member-a', 'hash-b',
      )).assertEqual(false)
      expect(SiteModeRequestFence.canApplyExUnlock(
        true, '', '', '', '',
      )).assertEqual(false)
      done()
    })

    it('keeps ExHentai behind an authenticated real igneous', 0, (done: Function) => {
      expect(SiteModeSettings.shouldUseEx(true, true, 'fixture-igneous')).assertEqual(true)
      expect(SiteModeSettings.shouldUseEx(false, true, 'fixture-igneous')).assertEqual(false)
      expect(SiteModeSettings.shouldUseEx(true, false, 'fixture-igneous')).assertEqual(false)
      expect(SiteModeSettings.shouldUseEx(true, true, '')).assertEqual(false)
      expect(SiteModeSettings.shouldUseEx(true, true, 'mystery')).assertEqual(false)
      done()
    })
  })
}
