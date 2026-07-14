import { describe, expect, it } from '@ohos/hypium'
import { BasicDataSource } from 'shared'

class RecordingDataChangeListener implements DataChangeListener {
  addedIndexes: number[] = []
  addedCounts: number[] = []
  addedKeys: string[] = []
  changedIndexes: number[] = []
  changedKeys: string[] = []
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
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}
  onDatasetChange(dataOperations: DataOperation[]): void {
    for (let i: number = 0; i < dataOperations.length; i++) {
      const operation: DataOperation = dataOperations[i]
      if (operation.type === DataOperationType.RELOAD) {
        this.reloadCount = this.reloadCount + 1
      } else if (operation.type === DataOperationType.ADD) {
        const add: DataAddOperation = operation as DataAddOperation
        this.addedIndexes.push(add.index)
        this.addedCounts.push(add.count !== undefined ? add.count : 1)
        if (add.key !== undefined) {
          for (let j: number = 0; j < add.key.length; j++) {
            this.addedKeys.push(add.key[j])
          }
        }
      } else if (operation.type === DataOperationType.CHANGE) {
        const change: DataChangeOperation = operation as DataChangeOperation
        this.changedIndexes.push(change.index)
        if (change.key !== undefined) {
          this.changedKeys.push(change.key)
        }
      } else if (operation.type === DataOperationType.DELETE) {
        this.deletedIndexes.push((operation as DataDeleteOperation).index)
      }
    }
  }
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
      const beforeMutationRevision: number = dataSource.contentRevision()

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
      expect(dataSource.contentRevision() > beforeMutationRevision).assertEqual(true)
      done()
    })

    it('notifies one counted batch for an appended page without reloading', 0, (done: Function) => {
      const dataSource: BasicDataSource<number> = new BasicDataSource<number>(
        (item: number): string => `number_${item}`,
      )
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      dataSource.setData([10, 20, 30])
      dataSource.registerDataChangeListener(listener)

      dataSource.appendData([40, 50, 60])

      expect(dataSource.totalCount()).assertEqual(6)
      expect(listener.addedIndexes.length).assertEqual(1)
      expect(listener.addedIndexes[0]).assertEqual(3)
      expect(listener.addedCounts.length).assertEqual(1)
      expect(listener.addedCounts[0]).assertEqual(3)
      expect(listener.addedKeys.length).assertEqual(3)
      expect(listener.addedKeys[0]).assertEqual('number_40')
      expect(listener.addedKeys[2]).assertEqual('number_60')
      expect(listener.reloadCount).assertEqual(0)
      done()
    })

    it('supplies the replacement key when row identity changes', 0, (done: Function) => {
      const dataSource: BasicDataSource<number> = new BasicDataSource<number>(
        (item: number): string => `number_${item}`,
      )
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      dataSource.setData([10, 20])
      dataSource.registerDataChangeListener(listener)

      expect(dataSource.replaceDataAt(1, 25)).assertEqual(true)

      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(1)
      expect(listener.changedKeys.length).assertEqual(1)
      expect(listener.changedKeys[0]).assertEqual('number_25')
      done()
    })
  })
}
