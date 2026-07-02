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

  /** Append a page; use the same DataChangeListener family as reload (V2Next pattern). */
  appendData(items: T[]): void {
    if (items.length === 0) {
      return
    }
    const start: number = this.items.length
    this.items = this.items.concat(items)
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
