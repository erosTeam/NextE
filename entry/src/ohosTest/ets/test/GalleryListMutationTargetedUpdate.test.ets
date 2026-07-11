import { describe, expect, it } from '@ohos/hypium'
import { GalleryListViewModel } from 'home'
import { SearchViewModel } from 'search'
import { FavoritesViewModel } from 'user'
import { EhGallery } from 'shared'

class RecordingDataChangeListener implements DataChangeListener {
  changedIndexes: number[] = []
  deletedIndexes: number[] = []
  reloadCount: number = 0

  onDataReloaded(): void {
    this.reloadCount = this.reloadCount + 1
  }
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(index: number): void {
    this.deletedIndexes.push(index)
  }
  onDataChanged(_index: number): void {}
  onDataChange(index: number): void {
    this.changedIndexes.push(index)
  }
  onDatasetChange(_dataOperations: DataOperation[]): void {}
}

function gallery(gid: string): EhGallery {
  const item: EhGallery = new EhGallery(gid, 'token-' + gid)
  item.englishTitle = 'title-' + gid
  return item
}

export default function galleryListMutationTargetedUpdateTest(): void {
  describe('Gallery list mutation updates', () => {
    it('updates Home rows in place for favorite and rating mutations', 0, (done: Function) => {
      const vm: GalleryListViewModel = new GalleryListViewModel()
      vm.dataSource.setData([gallery('one'), gallery('two')])
      vm.itemCount = 2
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      vm.dataSource.registerDataChangeListener(listener)

      vm.applyFavoriteMutation('one', '2', 'Folder Two')
      vm.applyRatingMutation('two', 4.5, 4.2, '17', 'irb')

      expect(vm.dataSource.totalCount()).assertEqual(2)
      expect(vm.itemCount).assertEqual(2)
      expect(vm.dataSource.getData(0).favcat).assertEqual('2')
      expect(vm.dataSource.getData(0).favTitle).assertEqual('Folder Two')
      expect(vm.dataSource.getData(1).ratingFallBack).assertEqual(4.5)
      expect(vm.dataSource.getData(1).rating).assertEqual(4.2)
      expect(vm.dataSource.getData(1).ratingCount).assertEqual('17')
      expect(vm.dataSource.getData(1).colorRating).assertEqual('irb')
      expect(vm.dataSource.getData(1).isRated).assertEqual(true)
      expect(listener.changedIndexes.length).assertEqual(2)
      expect(listener.changedIndexes[0]).assertEqual(0)
      expect(listener.changedIndexes[1]).assertEqual(1)
      expect(listener.deletedIndexes.length).assertEqual(0)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })

    it('removes only the affected favorite-scope search row and keeps subsequent updates targeted', 0, (done: Function) => {
      const vm: SearchViewModel = new SearchViewModel()
      vm.seedFavoriteScope('a')
      vm.dataSource.setData([gallery('one'), gallery('two')])
      vm.itemCount = 2
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      vm.dataSource.registerDataChangeListener(listener)

      vm.applyFavoriteMutation('one', '', '')
      vm.applyRatingMutation('two', 3.5, 3.3, '9', 'irg')

      expect(vm.dataSource.totalCount()).assertEqual(1)
      expect(vm.itemCount).assertEqual(1)
      expect(vm.dataSource.getData(0).gid).assertEqual('two')
      expect(vm.dataSource.getData(0).rating).assertEqual(3.3)
      expect(listener.deletedIndexes.length).assertEqual(1)
      expect(listener.deletedIndexes[0]).assertEqual(0)
      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(0)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })

    it('removes only the affected Favorites row and updates retained ratings in place', 0, (done: Function) => {
      const vm: FavoritesViewModel = new FavoritesViewModel()
      vm.configure('0', false)
      vm.dataSource.setData([gallery('one'), gallery('two')])
      vm.itemCount = 2
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      vm.dataSource.registerDataChangeListener(listener)

      vm.applyFavoriteMutation('one', '1', 'Folder One')
      vm.applyRatingMutation('two', 2.5, 2.2, '4', 'irr')

      expect(vm.dataSource.totalCount()).assertEqual(1)
      expect(vm.itemCount).assertEqual(1)
      expect(vm.dataSource.getData(0).gid).assertEqual('two')
      expect(vm.dataSource.getData(0).ratingFallBack).assertEqual(2.5)
      expect(vm.dataSource.getData(0).colorRating).assertEqual('irr')
      expect(listener.deletedIndexes.length).assertEqual(1)
      expect(listener.deletedIndexes[0]).assertEqual(0)
      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(0)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })
  })
}
