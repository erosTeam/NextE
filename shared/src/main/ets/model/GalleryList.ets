import { EhGallery } from './EhGallery'
import { Favcat } from './Favcat'

/**
 * Result of parsing one EH gallery-list page (eros_fe GalleryList). `gallerys` is the
 * page's rows; the cursor fields drive pagination. EH lists are cursor-based (next/prev
 * by full cursor token, not always a bare gid) with a legacy page index also available — the ViewModel uses `nextGid` for
 * forward paging and falls back to `maxPage`/`nextPage` for jump.
 */
export class GalleryList {
  gallerys: EhGallery[] = []
  nextGid: string = '' // cursor for the next (older) page: ?next=<cursor>
  prevGid: string = '' // cursor for the previous (newer) page: ?prev=<cursor>
  maxPage: number = 0
  nextPage: number = -1
  prevPage: number = -1
  // Only populated by getFavoritesList (the favcat selector bar on favorites.php); empty otherwise.
  favList: Favcat[] = []
  // Active favorites sort order parsed from the favorites.php response ('fs_f'/'fs_p'/''). EH's
  // inline_set is sticky-by-one-load, so the VM re-loads when this lags the requested order.
  favOrder: string = ''

  constructor(gallerys: EhGallery[] = []) {
    this.gallerys = gallerys
  }

  get isEmpty(): boolean {
    return this.gallerys.length === 0
  }

  copy(): GalleryList {
    const l: GalleryList = new GalleryList(this.gallerys.map((g: EhGallery) => g.copy()))
    l.nextGid = this.nextGid
    l.prevGid = this.prevGid
    l.maxPage = this.maxPage
    l.nextPage = this.nextPage
    l.prevPage = this.prevPage
    l.favList = this.favList
    l.favOrder = this.favOrder
    return l
  }
}
