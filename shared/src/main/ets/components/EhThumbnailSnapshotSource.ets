/** Current main-image success plus native content-ready evidence, not a decode timestamp. */
export class EhImageContentSource {
  readonly url: string
  readonly reloadToken: number
  readonly width: number
  readonly height: number
  private current: () => boolean

  constructor(url: string, reloadToken: number, width: number, height: number, current: () => boolean) {
    this.url = url
    this.reloadToken = reloadToken
    this.width = width
    this.height = height
    this.current = current
  }

  isCurrent(): boolean {
    return this.current()
  }
}

/** A live eligibility handle for the existing cropped thumbnail node; owns no pixels. */
export class EhThumbnailSnapshotSource {
  readonly url: string
  readonly imageKey: string
  readonly thumbWidth: number
  readonly thumbHeight: number
  readonly offsetX: number
  readonly spriteWidth: number
  readonly spriteHeight: number
  private current: () => boolean

  constructor(url: string, imageKey: string, thumbWidth: number, thumbHeight: number,
    offsetX: number, spriteWidth: number, spriteHeight: number, current: () => boolean) {
    this.url = url
    this.imageKey = imageKey
    this.thumbWidth = thumbWidth
    this.thumbHeight = thumbHeight
    this.offsetX = offsetX
    this.spriteWidth = spriteWidth
    this.spriteHeight = spriteHeight
    this.current = current
  }

  isCurrent(): boolean {
    return this.current()
  }
}
