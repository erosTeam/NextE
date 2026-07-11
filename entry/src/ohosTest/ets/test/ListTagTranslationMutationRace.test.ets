import { describe, expect, it } from '@ohos/hypium'
import { SearchViewModel } from 'search'
import { FavoritesViewModel } from 'user'
import { connectTagTranslationSettings, EhGallery } from 'shared'

function gallery(gid: string): EhGallery {
  const item: EhGallery = new EhGallery(gid, 'token-' + gid)
  item.englishTitle = 'title-' + gid
  return item
}

export default function listTagTranslationMutationRaceTest(): void {
  describe('List tag translation mutation ownership', () => {
    it('does not let a stale Search translation erase a targeted rating update', 0, async (done: Function) => {
      const settings = connectTagTranslationSettings()
      const wasEnabled: boolean = settings.enabled
      settings.enabled = true
      try {
        const vm: SearchViewModel = new SearchViewModel()
        vm.dataSource.setData([gallery('one')])
        vm.itemCount = 1

        const pending: Promise<void> = vm.reapplyTagTranslation()
        vm.applyRatingMutation('one', 4.5, 4.2, '17', 'irb')
        await pending

        expect(vm.dataSource.totalCount()).assertEqual(1)
        expect(vm.dataSource.getData(0).ratingFallBack).assertEqual(4.5)
        expect(vm.dataSource.getData(0).rating).assertEqual(4.2)
        expect(vm.dataSource.getData(0).ratingCount).assertEqual('17')
        expect(vm.dataSource.getData(0).colorRating).assertEqual('irb')
        expect(vm.dataSource.getData(0).isRated).assertEqual(true)
      } finally {
        settings.enabled = wasEnabled
      }
      done()
    })

    it('does not let a stale Favorites translation erase a targeted favorite update', 0, async (done: Function) => {
      const settings = connectTagTranslationSettings()
      const wasEnabled: boolean = settings.enabled
      settings.enabled = true
      try {
        const vm: FavoritesViewModel = new FavoritesViewModel()
        vm.dataSource.setData([gallery('one')])
        vm.itemCount = 1

        const pending: Promise<void> = vm.reapplyTagTranslation()
        vm.applyFavoriteMutation('one', '2', 'Folder Two')
        await pending

        expect(vm.dataSource.totalCount()).assertEqual(1)
        expect(vm.dataSource.getData(0).favcat).assertEqual('2')
        expect(vm.dataSource.getData(0).favTitle).assertEqual('Folder Two')
      } finally {
        settings.enabled = wasEnabled
      }
      done()
    })
  })
}
