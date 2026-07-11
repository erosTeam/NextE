import { describe, expect, it } from '@ohos/hypium'
import { BasicDataSource } from 'shared'

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

export default function basicDataSourceChangeNotificationTest(): void {
  describe('BasicDataSource item updates', () => {
    it('notifies only a valid changed index without reloading the data source', 0, (done: Function) => {
      const dataSource: BasicDataSource<number> = new BasicDataSource<number>()
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      dataSource.setData([10, 20, 30])
      dataSource.registerDataChangeListener(listener)

      dataSource.notifyDataChanged(1)
      dataSource.notifyDataChanged(-1)
      dataSource.notifyDataChanged(3)

      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(1)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })

    it('replaces and removes one item without a full data-source reload', 0, (done: Function) => {
      const dataSource: BasicDataSource<number> = new BasicDataSource<number>()
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      dataSource.setData([10, 20, 30])
      dataSource.registerDataChangeListener(listener)

      expect(dataSource.replaceDataAt(1, 25)).assertEqual(true)
      expect(dataSource.removeDataAt(0)).assertEqual(true)
      expect(dataSource.replaceDataAt(2, 99)).assertEqual(false)
      expect(dataSource.removeDataAt(-1)).assertEqual(false)

      expect(dataSource.totalCount()).assertEqual(2)
      expect(dataSource.getData(0)).assertEqual(25)
      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(1)
      expect(listener.deletedIndexes.length).assertEqual(1)
      expect(listener.deletedIndexes[0]).assertEqual(0)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })
  })
}
