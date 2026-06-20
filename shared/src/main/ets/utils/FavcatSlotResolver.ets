import { EhGallery } from '../model/EhGallery'
import { Favcat } from '../model/Favcat'
import { FavSelectionState } from '../state/FavSelectionState'

export class FavcatSlotResolveResult {
  rows: EhGallery[] = []
  changed: boolean = false
}

/**
 * EH favorites rows sometimes carry only the favorite-folder title, not the numeric favcat slot.
 * Resolve title -> slot only from real account metadata; placeholder `Favorites N / 0` rows are not
 * evidence and must never color already-rendered cards.
 */
export class FavcatSlotResolver {
  static realTitleMap(favcats: Favcat[]): Map<string, string> {
    const byTitle: Map<string, string> = new Map<string, string>()
    favcats.forEach((f: Favcat) => {
      if (!FavSelectionState.isPlaceholderFavcat(f) && f.favTitle.length > 0) {
        byTitle.set(f.favTitle, f.favId)
      }
    })
    return byTitle
  }

  static applyInPlace(gallerys: EhGallery[], favcats: Favcat[]): void {
    if (favcats.length === 0) {
      return
    }
    const byTitle: Map<string, string> = FavcatSlotResolver.realTitleMap(favcats)
    if (byTitle.size === 0) {
      return
    }
    gallerys.forEach((g: EhGallery) => {
      if (g.favcat.length === 0 && g.favTitle.length > 0) {
        const hit: string | undefined = byTitle.get(g.favTitle)
        if (hit !== undefined) {
          g.favcat = hit
        }
      }
    })
  }

  static resolvedCopies(rows: EhGallery[], favcats: Favcat[]): FavcatSlotResolveResult {
    const result: FavcatSlotResolveResult = new FavcatSlotResolveResult()
    if (rows.length === 0 || favcats.length === 0) {
      result.rows = rows
      return result
    }
    const byTitle: Map<string, string> = FavcatSlotResolver.realTitleMap(favcats)
    if (byTitle.size === 0) {
      result.rows = rows
      return result
    }
    const nextRows: EhGallery[] = []
    rows.forEach((g: EhGallery) => {
      if (g.favcat.length === 0 && g.favTitle.length > 0) {
        const hit: string | undefined = byTitle.get(g.favTitle)
        if (hit !== undefined) {
          const next: EhGallery = g.copy()
          next.favcat = hit
          nextRows.push(next)
          result.changed = true
          return
        }
      }
      nextRows.push(g)
    })
    result.rows = nextRows
    return result
  }
}
