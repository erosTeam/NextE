import { EhGallery } from './EhGallery'

/**
 * One viewed-history entry (eros_fe records a stripped GalleryProvider). A lean summary projection of
 * EhGallery — just what a history row needs to render and re-open; the heavy images/comments/tags are
 * intentionally NOT carried (eros_fe strips galleryImages/galleryComment before storing). `time` is the
 * last-view epoch millis, used for newest-first ordering.
 */
export class ViewedGallery {
  gid: string = ''
  token: string = ''
  title: string = '' // englishTitle
  titleJp: string = '' // japaneseTitle
  thumbUrl: string = ''
  category: string = ''
  uploader: string = ''
  postTime: string = ''
  rating: number = 0
  ratingFallBack: number = 0
  colorRating: string = ''
  fileCount: string = ''
  translated: string = ''
  expunged: boolean = false
  time: number = 0

  static fromGallery(g: EhGallery, time: number): ViewedGallery {
    const v: ViewedGallery = new ViewedGallery()
    v.gid = g.gid
    v.token = g.token
    v.title = g.englishTitle
    v.titleJp = g.japaneseTitle
    v.thumbUrl = g.thumbUrl
    v.category = g.category
    v.uploader = g.uploader
    v.postTime = g.postTime
    v.rating = g.rating
    v.ratingFallBack = g.ratingFallBack
    v.colorRating = g.colorRating
    v.fileCount = g.fileCount
    v.translated = g.translated
    v.expunged = g.expunged
    v.time = time
    return v
  }

  copy(): ViewedGallery {
    const v: ViewedGallery = new ViewedGallery()
    v.gid = this.gid
    v.token = this.token
    v.title = this.title
    v.titleJp = this.titleJp
    v.thumbUrl = this.thumbUrl
    v.category = this.category
    v.uploader = this.uploader
    v.postTime = this.postTime
    v.rating = this.rating
    v.ratingFallBack = this.ratingFallBack
    v.colorRating = this.colorRating
    v.fileCount = this.fileCount
    v.translated = this.translated
    v.expunged = this.expunged
    v.time = this.time
    return v
  }
}
