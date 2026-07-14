import { describe, expect, it } from '@ohos/hypium'
import { AllThumbnailsTailAppend } from 'gallery'
import { BasicDataSource, EhGalleryImage } from 'shared'

class RecordingDataChangeListener implements DataChangeListener {
  addStarts: number[] = []
  addCounts: number[] = []
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
        this.addStarts.push(add.index)
        this.addCounts.push(add.count !== undefined ? add.count : 1)
      }
    }
  }
}

function image(page: number, marker: string = ''): EhGalleryImage {
  const item: EhGalleryImage = new EhGalleryImage(page)
  item.imgkey = marker.length > 0 ? marker : `key-${page}`
  return item
}

export default function allThumbnailsTailAppendTest(): void {
  describe('AllThumbnailsTailAppend', () => {
    it('adds a normal forward preview page without reloading existing grid rows', 0, (done: Function) => {
      const dataSource: BasicDataSource<EhGalleryImage> = new BasicDataSource<EhGalleryImage>()
      dataSource.setData([image(1), image(2)])
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      dataSource.registerDataChangeListener(listener)
      const incoming: EhGalleryImage[] = [image(3, 'before-copy'), image(4)]

      expect(AllThumbnailsTailAppend.appendIfStrictTail(dataSource, incoming)).assertEqual(true)
      incoming[0].imgkey = 'after-copy'

      expect(dataSource.totalCount()).assertEqual(4)
      expect(dataSource.getData(2).page).assertEqual(3)
      expect(dataSource.getData(2).imgkey).assertEqual('before-copy')
      expect(listener.addStarts.length).assertEqual(1)
      expect(listener.addStarts[0]).assertEqual(2)
      expect(listener.addCounts[0]).assertEqual(2)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })

    it('declines overlapping or out-of-order pages for the complete merge fallback', 0, (done: Function) => {
      const dataSource: BasicDataSource<EhGalleryImage> = new BasicDataSource<EhGalleryImage>()
      dataSource.setData([image(1), image(2)])
      const listener: RecordingDataChangeListener = new RecordingDataChangeListener()
      dataSource.registerDataChangeListener(listener)

      expect(AllThumbnailsTailAppend.appendIfStrictTail(dataSource, [image(2), image(3)])).assertEqual(false)
      expect(AllThumbnailsTailAppend.appendIfStrictTail(dataSource, [image(4), image(3)])).assertEqual(false)

      expect(dataSource.totalCount()).assertEqual(2)
      expect(listener.addStarts.length).assertEqual(0)
      expect(listener.reloadCount).assertEqual(0)
      done()
    })
  })
}
