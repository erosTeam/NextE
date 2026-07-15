/** Stable Reader source identity. Online preview metadata and local image assets are not interchangeable. */
export class ReaderSourceKind {
  static readonly ONLINE: string = 'online'
  static readonly GALLERY_DOWNLOAD: string = 'galleryDownload'
  static readonly ARCHIVE: string = 'archive'
}

/** Quality of the bytes currently displayed by a local Reader session. */
export class ReaderSourceVariant {
  static readonly RESAMPLED: string = 'resampled'
  static readonly ORIGINAL: string = 'original'
  static readonly UNKNOWN: string = 'unknown'
}

export class ReaderSourceDescriptor {
  kind: string = ReaderSourceKind.ONLINE
  variant: string = ReaderSourceVariant.UNKNOWN
  sourceKey: string = ''
  resolution: string = ''

  constructor(
    kind: string = ReaderSourceKind.ONLINE,
    variant: string = ReaderSourceVariant.UNKNOWN,
    sourceKey: string = '',
    resolution: string = '',
  ) {
    this.kind = kind
    this.variant = variant
    this.sourceKey = sourceKey
    this.resolution = resolution
  }

  isLocal(): boolean {
    return this.kind === ReaderSourceKind.GALLERY_DOWNLOAD || this.kind === ReaderSourceKind.ARCHIVE
  }
}
