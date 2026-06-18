import { EhGalleryComment } from './EhGalleryComment'
import { EhGalleryImage } from './EhGalleryImage'
import { EhGallery } from './EhGallery'

/**
 * Typed params pushed onto the NavPathStack by name. Hand-written classes (ArkTS route
 * params must be inferable objects, not ad-hoc literals).
 */

/** Params for the 'GalleryDetail' destination. */
export class GalleryDetailParams {
  gid: string = ''
  token: string = ''
  // Optional thumb/title to render the header instantly before the detail fetch lands.
  thumbUrl: string = ''
  title: string = ''
  // List-row opens carry fileCount so the detail VM can SKIP the gdata enrich (eros_fe's filecount-absent
  // gate); sparse opens (deep link / URL paste) leave it '' → the VM enriches via /api.php gdata first.
  fileCount: string = ''
  // Parsed cover dimensions from the source list/search/favorites row. Carrying these into the seed lets
  // the detail header paint the same real-ratio cover immediately instead of changing fit mode after the
  // detail HTML fetch returns.
  imgWidth: number = 0
  imgHeight: number = 0

  constructor(
    gid: string = '',
    token: string = '',
    thumbUrl: string = '',
    title: string = '',
    fileCount: string = '',
    imgWidth: number = 0,
    imgHeight: number = 0,
  ) {
    this.gid = gid
    this.token = token
    this.thumbUrl = thumbUrl
    this.title = title
    this.fileCount = fileCount
    this.imgWidth = imgWidth
    this.imgHeight = imgHeight
  }
}

/** Params for the 'GalleryInfo' destination (full read-only metadata sheet). */
export class GalleryInfoParams {
  gallery: EhGallery = new EhGallery()
  isEx: boolean = false
  title: string = ''

  constructor(gallery: EhGallery = new EhGallery(), isEx: boolean = false, title: string = '') {
    this.gallery = gallery
    this.isEx = isEx
    this.title = title
  }
}

/** Params for the 'GalleryTorrents' destination. */
export class GalleryTorrentsParams {
  gid: string = ''
  token: string = ''
  isEx: boolean = false
  title: string = ''
  torrentCount: string = ''

  constructor(
    gid: string = '',
    token: string = '',
    isEx: boolean = false,
    title: string = '',
    torrentCount: string = '',
  ) {
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.title = title
    this.torrentCount = torrentCount
  }
}

/** Params for the 'Reader' destination. */
export class ReaderParams {
  gid: string = ''
  token: string = ''
  index: number = 0 // initial page index
  fileCount: number = 0
  title: string = '' // shown in the reader's top bar (exit affordance + context)
  seedImages: EhGalleryImage[] = [] // already-loaded preview entries, preserving absolute page + /s/ URL
  seedLoadedPages: number = 0
  seedPerPage: number = 0
  seedPreviewPages: number[] = [] // exact loaded preview-page numbers when the seed is sparse
  seedImagePageUrl: string = '' // exact tapped /s/ image-page URL; resolved first for the initial page

  constructor(
    gid: string = '',
    token: string = '',
    index: number = 0,
    fileCount: number = 0,
    title: string = '',
    seedImages: EhGalleryImage[] = [],
    seedLoadedPages: number = 0,
    seedPerPage: number = 0,
    seedPreviewPages: number[] = [],
    seedImagePageUrl: string = '',
  ) {
    this.gid = gid
    this.token = token
    this.index = index
    this.fileCount = fileCount
    this.title = title
    this.seedImages = seedImages
    this.seedLoadedPages = seedLoadedPages
    this.seedPerPage = seedPerPage
    this.seedPreviewPages = seedPreviewPages
    this.seedImagePageUrl = seedImagePageUrl
  }
}

/** Params for the image-page deep-link failure destination. */
export class ImagePageRouteErrorParams {
  url: string = ''

  constructor(url: string = '') {
    this.url = url
  }
}

/** Params for the 'GalleryComments' destination (full comment list — a peek lives on the detail). */
export class GalleryCommentsParams {
  comments: EhGalleryComment[] = []
  title: string = ''

  constructor(comments: EhGalleryComment[] = [], title: string = '') {
    this.comments = comments
    this.title = title
  }
}

/**
 * Params for the 'AllThumbnails' destination (the separate, paged preview grid — the detail only
 * shows the first-page peek). Seeded with the already-loaded first page so it paints instantly,
 * then pages the rest via getPreviewImages.
 */
export class AllThumbnailsParams {
  gid: string = ''
  token: string = ''
  isEx: boolean = false
  fileCount: number = 0
  previewPageCount: number = 1
  title: string = ''
  firstPage: EhGalleryImage[] = []

  constructor(
    gid: string = '',
    token: string = '',
    isEx: boolean = false,
    fileCount: number = 0,
    previewPageCount: number = 1,
    title: string = '',
    firstPage: EhGalleryImage[] = [],
  ) {
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.fileCount = fileCount
    this.previewPageCount = previewPageCount
    this.title = title
    this.firstPage = firstPage
  }
}
