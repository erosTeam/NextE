/** One row from /gallerytorrents.php. Mirrors eros_fe GalleryTorrent's display fields. */
export class EhGalleryTorrent {
  hash: string = ''
  name: string = ''
  posted: string = ''
  sizeText: string = ''
  seeds: string = ''
  peers: string = ''
  downloads: string = ''
  uploader: string = ''

  copy(): EhGalleryTorrent {
    const t: EhGalleryTorrent = new EhGalleryTorrent()
    t.hash = this.hash
    t.name = this.name
    t.posted = this.posted
    t.sizeText = this.sizeText
    t.seeds = this.seeds
    t.peers = this.peers
    t.downloads = this.downloads
    t.uploader = this.uploader
    return t
  }
}

/** Parsed /gallerytorrents.php result: rows plus the ehtracker token used for .torrent links. */
export class EhGalleryTorrentList {
  torrents: EhGalleryTorrent[] = []
  torrentToken: string = ''

  copy(): EhGalleryTorrentList {
    const out: EhGalleryTorrentList = new EhGalleryTorrentList()
    out.torrents = this.torrents.map((t: EhGalleryTorrent) => t.copy())
    out.torrentToken = this.torrentToken
    return out
  }
}
