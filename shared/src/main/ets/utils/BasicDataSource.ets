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
  private contentVersion: number = 0
  private keyResolver: ((item: T) => string) | null = null

  constructor(keyResolver: ((item: T) => string) | null = null) {
    this.keyResolver = keyResolver
  }

  /** Override when a data source can provide the same stable key used by its LazyForEach. */
  protected keyForData(item: T): string {
    if (this.keyResolver === null) {
      return ''
    }
    return this.keyResolver(item)
  }

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): T {
    return this.items[index]
  }

  getAll(): T[] {
    return this.items
  }

  /** Increments whenever a row set or one of its row references changes. */
  contentRevision(): number {
    return this.contentVersion
  }

  /** Replace the whole list (refresh / first page). */
  setData(items: T[]): void {
    this.items = items
    this.contentVersion = this.contentVersion + 1
    this.notifyDatasetChange([{ type: DataOperationType.RELOAD }])
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
    this.contentVersion = this.contentVersion + 1
    this.notifyAdded(start, items)
  }

  /** Prepend a page as real LazyForEach inserts, so List can preserve visible content position. */
  prependData(items: T[]): void {
    if (items.length === 0) {
      return
    }
    for (let i: number = items.length - 1; i >= 0; i--) {
      this.items.splice(0, 0, items[i])
    }
    this.contentVersion = this.contentVersion + 1
    this.notifyAdded(0, items)
  }

  /** Refresh one existing LazyForEach item without reloading the full data source. */
  notifyDataChanged(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return
    }
    const operation: DataChangeOperation = {
      type: DataOperationType.CHANGE,
      index: index,
    }
    const key: string = this.keyForData(this.items[index])
    if (key.length > 0) {
      operation.key = key
    }
    this.notifyDatasetChange([operation])
  }

  /** Replace one existing row and refresh only that LazyForEach item. */
  replaceDataAt(index: number, item: T): boolean {
    if (index < 0 || index >= this.items.length) {
      return false
    }
    this.items[index] = item
    this.contentVersion = this.contentVersion + 1
    this.notifyDataChanged(index)
    return true
  }

  /** Remove one row and let LazyForEach preserve the rest of the list in place. */
  removeDataAt(index: number): boolean {
    if (index < 0 || index >= this.items.length) {
      return false
    }
    this.items.splice(index, 1)
    this.contentVersion = this.contentVersion + 1
    this.notifyDatasetChange([{
      type: DataOperationType.DELETE,
      index: index,
      count: 1,
    }])
    return true
  }

  clear(): void {
    this.items = []
    this.contentVersion = this.contentVersion + 1
    this.notifyDatasetChange([{ type: DataOperationType.RELOAD }])
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

  private notifyAdded(index: number, items: T[]): void {
    const operation: DataAddOperation = {
      type: DataOperationType.ADD,
      index: index,
      count: items.length,
    }
    const keys: string[] = this.keysForData(items)
    if (keys.length === items.length) {
      operation.key = keys
    }
    this.notifyDatasetChange([operation])
  }

  private keysForData(items: T[]): string[] {
    const keys: string[] = []
    for (let i: number = 0; i < items.length; i++) {
      const key: string = this.keyForData(items[i])
      if (key.length === 0) {
        return []
      }
      keys.push(key)
    }
    return keys
  }

  private notifyDatasetChange(operations: DataOperation[]): void {
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDatasetChange(operations)
    })
  }
}
