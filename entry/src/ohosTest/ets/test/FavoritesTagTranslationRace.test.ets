import { describe, expect, it } from '@ohos/hypium'
import { FavoritesViewModel } from 'user'
import { connectTagTranslationSettings, EhGallery } from 'shared'

function gallery(gid: string): EhGallery {
  const item: EhGallery = new EhGallery(gid, `token-${gid}`)
  item.englishTitle = `title-${gid}`
  return item
}

export default function favoritesTagTranslationRaceTest(): void {
  describe('Favorites tag translation ownership', () => {
    it('does not restore rows replaced while asynchronous translation is pending', 0, async (done: Function) => {
      const settings = connectTagTranslationSettings()
      const wasEnabled: boolean = settings.enabled
      settings.enabled = true
      try {
        const vm: FavoritesViewModel = new FavoritesViewModel()
        const stale: EhGallery = gallery('stale')
        const fresh: EhGallery = gallery('fresh')
        vm.dataSource.setData([stale])
        vm.itemCount = 1

        const pending: Promise<void> = vm.reapplyTagTranslation()
        vm.dataSource.setData([fresh])
        vm.itemCount = 1
        await pending

        expect(vm.dataSource.totalCount()).assertEqual(1)
        expect(vm.dataSource.getData(0).gid).assertEqual('fresh')
        expect(vm.itemCount).assertEqual(1)
      } finally {
        settings.enabled = wasEnabled
      }
      done()
    })
  })
}
