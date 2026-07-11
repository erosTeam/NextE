import { describe, expect, it } from '@ohos/hypium'
import { GalleryReadProgressState, ReadColumnMode, ReadProgressEntry } from 'shared'

export default function readProgressStateTest(): void {
  describe('GalleryReadProgressState', () => {
    it('keeps the newest local mutation durable and records a column-only choice', 0, (done: Function) => {
      const state: GalleryReadProgressState = new GalleryReadProgressState()
      state.setColumnMode('fixture-progress', ReadColumnMode.EVEN_LEFT, 100)
      let entries = state.snapshot()

      expect(entries.length).assertEqual(1)
      expect(entries[0].i).assertEqual(0)
      expect(entries[0].c).assertEqual(ReadColumnMode.EVEN_LEFT)
      expect(entries[0].t).assertEqual(100)

      state.setIndex('fixture-progress', 7, 100)
      entries = state.snapshot()
      expect(entries[0].i).assertEqual(7)
      expect(entries[0].t).assertEqual(101)
      const newestLocalMutation: ReadProgressEntry[] = entries

      const persisted: ReadProgressEntry | null = state.adoptPersistedTimestamp('fixture-progress', 9001)
      expect(persisted === null).assertEqual(false)
      if (persisted !== null) {
        expect(persisted.i).assertEqual(7)
        expect(persisted.c).assertEqual(ReadColumnMode.EVEN_LEFT)
        expect(persisted.t).assertEqual(9001)
      }
      entries = state.snapshot()
      expect(entries[0].t).assertEqual(9001)

      const refreshed: GalleryReadProgressState = new GalleryReadProgressState()
      refreshed.replaceAll([
        new ReadProgressEntry('fixture-progress', 3, 100, ReadColumnMode.ODD_LEFT),
      ])
      refreshed.mergeNewest(newestLocalMutation)
      expect(refreshed.getIndex('fixture-progress')).assertEqual(7)
      expect(refreshed.snapshot()[0].t).assertEqual(101)
      done()
    })
  })
}
