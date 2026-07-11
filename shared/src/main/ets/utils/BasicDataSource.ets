/**
 * Generic LazyForEach data source (V2Next pattern). Held as a STABLE reference on the
 * ViewModel and kept OUT of @Trace — LazyForEach subscribes to its DataChangeListeners
 * directly, so a @Trace array (re-rendered via ForEach) is the wrong tool for long lists.
 * The ViewModel mirrors `totalCount()` into a separate @Trace `itemCount` so @ComponentV2
 * build() re-evaluates the loading→list branch.
 */
export class BasicDataSource<T> implements IDataSource {
  private items: T[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): T {
    return this.items[index]
  }

  getAll(): T[] {
    return this.items
  }

  /** Replace the whole list (refresh / first page). */
  setData(items: T[]): void {
    this.items = items
    this.notifyReload()
  }

  /** Append a page; keep the backing array stable so long lists do not copy all old rows per page. */
  appendData(items: T[]): void {
    if (items.length === 0) {
      return
    }
    const start: number = this.items.length
    for (let i: number = 0; i < items.length; i++) {
      this.items.push(items[i])
    }
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataAdd(start)
    })
  }

  /** Prepend a page as real LazyForEach inserts, so List can preserve visible content position. */
  prependData(items: T[]): void {
    for (let i: number = items.length - 1; i >= 0; i--) {
      this.items.splice(0, 0, items[i])
      this.listeners.forEach((l: DataChangeListener) => {
        l.onDataAdd(0)
      })
    }
  }

  /** Refresh one existing LazyForEach item without reloading the full data source. */
  notifyDataChanged(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return
    }
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataChange(index)
    })
  }

  /** Replace one existing row and refresh only that LazyForEach item. */
  replaceDataAt(index: number, item: T): boolean {
    if (index < 0 || index >= this.items.length) {
      return false
    }
    this.items[index] = item
    this.notifyDataChanged(index)
    return true
  }

  /** Remove one row and let LazyForEach preserve the rest of the list in place. */
  removeDataAt(index: number): boolean {
    if (index < 0 || index >= this.items.length) {
      return false
    }
    this.items.splice(index, 1)
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataDelete(index)
    })
    return true
  }

  clear(): void {
    this.items = []
    this.notifyReload()
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener)
    if (idx >= 0) {
      this.listeners.splice(idx, 1)
    }
  }

  private notifyReload(): void {
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataReloaded()
    })
  }
}
