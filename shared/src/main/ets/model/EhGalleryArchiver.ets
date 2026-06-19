/** One selectable archive quote from /archiver.php. This is read-only until an explicit download lane. */
export class EhGalleryArchiverItem {
  dltype: string = ''
  resolution: string = ''
  sizeText: string = ''
  priceText: string = ''

  copy(): EhGalleryArchiverItem {
    const out: EhGalleryArchiverItem = new EhGalleryArchiverItem()
    out.dltype = this.dltype
    out.resolution = this.resolution
    out.sizeText = this.sizeText
    out.priceText = this.priceText
    return out
  }
}

/** Parsed archiver quote page: account balance plus local download and H@H options. */
export class EhGalleryArchiverQuote {
  gp: string = ''
  credits: string = ''
  downloadItems: EhGalleryArchiverItem[] = []
  hathItems: EhGalleryArchiverItem[] = []

  copy(): EhGalleryArchiverQuote {
    const out: EhGalleryArchiverQuote = new EhGalleryArchiverQuote()
    out.gp = this.gp
    out.credits = this.credits
    out.downloadItems = this.downloadItems.map((it: EhGalleryArchiverItem) => it.copy())
    out.hathItems = this.hathItems.map((it: EhGalleryArchiverItem) => it.copy())
    return out
  }
}
