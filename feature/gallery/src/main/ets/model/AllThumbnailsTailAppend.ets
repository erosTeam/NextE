import { BasicDataSource, EhGalleryImage } from 'shared'

/**
 * Fast path for the ordinary forward-thumbnail page: keep the existing LazyForEach rows intact
 * when the server page is strictly after the current tail. Sparse jumps and overlaps deliberately
 * decline this path so the view model can retain its complete merge/sort fallback.
 */
export class AllThumbnailsTailAppend {
  static appendIfStrictTail(
    dataSource: BasicDataSource<EhGalleryImage>,
    incoming: EhGalleryImage[],
  ): boolean {
    const current: EhGalleryImage[] = dataSource.getAll()
    if (!AllThumbnailsTailAppend.isStrictTail(current, incoming)) {
      return false
    }
    const copies: EhGalleryImage[] = []
    incoming.forEach((image: EhGalleryImage) => {
      copies.push(image.copy())
    })
    dataSource.appendData(copies)
    return true
  }

  private static isStrictTail(current: EhGalleryImage[], incoming: EhGalleryImage[]): boolean {
    if (current.length === 0 || incoming.length === 0) {
      return false
    }
    let previous: number = current[0].page
    for (let i: number = 1; i < current.length; i++) {
      const page: number = current[i].page
      if (page <= previous) {
        return false
      }
      previous = page
    }
    for (let i: number = 0; i < incoming.length; i++) {
      const page: number = incoming[i].page
      if (page <= previous) {
        return false
      }
      previous = page
    }
    return true
  }
}
