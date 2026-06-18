import { HtmlSelectorUtils } from './HtmlSelectorUtils'
import { EhGalleryTorrent, EhGalleryTorrentList } from '../model/EhGalleryTorrent'

/** Parser for /gallerytorrents.php. Ported from eros_fe common/parser/torrent_parser.dart. */
export class EhGalleryTorrentParser {
  private static readonly RE_FORM: RegExp = /<form\b[\s\S]*?<\/form>/g
  private static readonly RE_LINK: RegExp = /<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/i
  private static readonly RE_HASH: RegExp = /([0-9a-f]{40})/i
  private static readonly RE_TOKEN: RegExp = /\/(?:get|torrent)\/(\d+)\//i

  static parse(html: string): EhGalleryTorrentList {
    const result: EhGalleryTorrentList = new EhGalleryTorrentList()
    let m: RegExpExecArray | null = EhGalleryTorrentParser.RE_FORM.exec(html)
    while (m !== null) {
      const form: string = m[0]
      const torrent: EhGalleryTorrent | null = EhGalleryTorrentParser.parseForm(form)
      if (torrent !== null) {
        result.torrents.push(torrent)
        if (result.torrentToken.length === 0) {
          result.torrentToken = EhGalleryTorrentParser.extractToken(form)
        }
      }
      m = EhGalleryTorrentParser.RE_FORM.exec(html)
    }
    return result
  }

  private static parseForm(form: string): EhGalleryTorrent | null {
    const link: RegExpMatchArray | null = form.match(EhGalleryTorrentParser.RE_LINK)
    if (link === null || link[1] === undefined || link[2] === undefined) {
      return null
    }
    const href: string = link[1]
    const hash: string = HtmlSelectorUtils.group1(href, EhGalleryTorrentParser.RE_HASH)
    if (hash.length === 0) {
      return null
    }

    const t: EhGalleryTorrent = new EhGalleryTorrent()
    t.hash = hash.toLowerCase()
    t.name = EhGalleryTorrentParser.cleanText(link[2])
    t.posted = EhGalleryTorrentParser.labelValue(form, 'Posted')
    t.sizeText = EhGalleryTorrentParser.labelValue(form, 'Size')
    t.seeds = EhGalleryTorrentParser.labelValue(form, 'Seeds')
    t.peers = EhGalleryTorrentParser.labelValue(form, 'Peers')
    t.downloads = EhGalleryTorrentParser.labelValue(form, 'Downloads')
    t.uploader = EhGalleryTorrentParser.labelValue(form, 'Uploader')
    return t
  }

  private static extractToken(form: string): string {
    return HtmlSelectorUtils.group1(form, EhGalleryTorrentParser.RE_TOKEN)
  }

  private static labelValue(html: string, label: string): string {
    if (label === 'Uploader') {
      const uploader: string = HtmlSelectorUtils.group1(
        html,
        /Uploader:\s*(?:<\/span>)?\s*([^<]*)/i,
      )
      return EhGalleryTorrentParser.cleanText(uploader)
    }
    const text: string = EhGalleryTorrentParser.cleanText(html)
    const needle: string = `${label}:`
    const start: number = text.indexOf(needle)
    if (start < 0) {
      return ''
    }
    const valueStart: number = start + needle.length
    const end: number = EhGalleryTorrentParser.nextLabelIndex(text, valueStart)
    return text.substring(valueStart, end >= 0 ? end : text.length).trim()
  }

  private static nextLabelIndex(text: string, from: number): number {
    const labels: string[] = ['Posted:', 'Size:', 'Seeds:', 'Peers:', 'Downloads:', 'Uploader:']
    let next: number = -1
    for (let i: number = 0; i < labels.length; i++) {
      const idx: number = text.indexOf(labels[i], from)
      if (idx >= 0 && (next < 0 || idx < next)) {
        next = idx
      }
    }
    return next
  }

  private static cleanText(raw: string): string {
    let s: string = raw.replace(/<[^>]+>/g, '')
    s = HtmlSelectorUtils.htmlUnescape(s)
    return s.replace(/\s+/g, ' ').trim()
  }
}
