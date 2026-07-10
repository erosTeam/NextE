import { EhGalleryComment } from '../model/EhGalleryComment'

class CommentReferenceSnapshotEntry {
  source: EhGalleryComment[]
  sorted: EhGalleryComment[]

  constructor(source: EhGalleryComment[], sorted: EhGalleryComment[]) {
    this.source = source
    this.sorted = sorted
  }
}

/**
 * Bounded identity cache for the read-only comment order used when resolving reply mentions. A full
 * comments page gives every visible card the same source array, so sharing its already-sorted snapshot
 * avoids repeated O(n log n) copies. Entries are keyed by array identity: a refresh supplies a new array,
 * while vote/translation updates keep the same comment-id ordering. Consumers must not mutate `sorted`.
 */
export class CommentReferenceSnapshotCache {
  private readonly maxEntries: number
  private entries: CommentReferenceSnapshotEntry[] = []

  constructor(maxEntries: number = 4) {
    this.maxEntries = maxEntries > 0 ? Math.floor(maxEntries) : 1
  }

  get(source: EhGalleryComment[]): EhGalleryComment[] | null {
    for (let i: number = 0; i < this.entries.length; i++) {
      const entry: CommentReferenceSnapshotEntry = this.entries[i]
      if (entry.source === source) {
        this.entries.splice(i, 1)
        this.entries.push(entry)
        return entry.sorted
      }
    }
    return null
  }

  put(source: EhGalleryComment[], sorted: EhGalleryComment[]): void {
    for (let i: number = 0; i < this.entries.length; i++) {
      if (this.entries[i].source === source) {
        this.entries.splice(i, 1)
        break
      }
    }
    this.entries.push(new CommentReferenceSnapshotEntry(source, sorted))
    while (this.entries.length > this.maxEntries) {
      this.entries.shift()
    }
  }

  size(): number {
    return this.entries.length
  }
}
