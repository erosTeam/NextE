/**
 * One page of a gallery. Server-known fields come from the detail/preview parse (page,
 * imgkey, the /s/ image-page URL, preview thumb); runtime fields (the resolved full-image
 * URL, origin URL, loaded flag) are filled by ImageResolveService as the reader advances.
 * Split kept explicit so reader prefetch can carry just the serializable server fields.
 */
export class EhGalleryImage {
  page: number = 0 // 1-based page number
  imgkey: string = '' // key for the /s/ image page
  sUrl: string = '' // https://<host>/s/{imgkey}/{gid}-{page}
  thumbUrl: string = '' // preview thumbnail — a SPRITE SHEET shared by a whole preview page

  // EH packs ~20 previews per page into one sprite image; each preview is the sub-rectangle
  // (thumbOffsetX, 0, thumbWidth, thumbHeight). spriteWidth/Height are the full sheet extent
  // (derived across the page's previews) so the renderer can crop+scale the right sub-rect.
  // All 0 → no sprite info parsed (render the whole image).
  thumbWidth: number = 0
  thumbHeight: number = 0
  thumbOffsetX: number = 0
  spriteWidth: number = 0
  spriteHeight: number = 0

  // resolved by the reader (M2 reader / ImageResolveService)
  imageUrl: string = '' // direct full-image URL (one-shot per-IP token)
  originImageUrl: string = '' // "download original" URL when available
  showKey: string = '' // per-gallery key enabling the fast /api.php showpage path
  reloadKey: string = '' // nl('xxx') source id — append ?nl= to re-source a broken/509 image (换源)

  constructor(page: number = 0) {
    this.page = page
  }

  copy(): EhGalleryImage {
    const i: EhGalleryImage = new EhGalleryImage(this.page)
    i.imgkey = this.imgkey
    i.sUrl = this.sUrl
    i.thumbUrl = this.thumbUrl
    i.thumbWidth = this.thumbWidth
    i.thumbHeight = this.thumbHeight
    i.thumbOffsetX = this.thumbOffsetX
    i.spriteWidth = this.spriteWidth
    i.spriteHeight = this.spriteHeight
    i.imageUrl = this.imageUrl
    i.originImageUrl = this.originImageUrl
    i.showKey = this.showKey
    i.reloadKey = this.reloadKey
    return i
  }
}
