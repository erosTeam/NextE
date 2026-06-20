import { Favcat } from '../model/Favcat'
import { HtmlSelectorUtils } from './HtmlSelectorUtils'

export class GalleryFavoriteInfo {
  favcats: Favcat[] = []
  selectFavcat: string = ''
  favNote: string = ''
}

/**
 * Parses /gallerypopups.php?act=addfav. This popup is the authoritative source for the user's
 * real favorite-folder names and the current gallery's note/selected slot.
 */
export class EhGalleryFavoriteParser {
  private static readonly RE_FAV_ROW: RegExp =
    /<div[^>]*>\s*<div[^>]*>\s*(<input[^>]*>)\s*<\/div>\s*<div[^>]*>[\s\S]*?<\/div>\s*<div[^>]*>([\s\S]*?)<\/div>\s*<\/div>/g
  private static readonly RE_VALUE: RegExp = /\bvalue="([^"]*)"/
  private static readonly RE_TEXTAREA: RegExp = /<textarea[^>]*>([\s\S]*?)<\/textarea>/

  static parse(html: string): GalleryFavoriteInfo {
    const info: GalleryFavoriteInfo = new GalleryFavoriteInfo()
    let m: RegExpExecArray | null = EhGalleryFavoriteParser.RE_FAV_ROW.exec(html)
    while (m !== null) {
      const input: string = m[1] !== undefined ? m[1] : ''
      const value: string = HtmlSelectorUtils.group1(input, EhGalleryFavoriteParser.RE_VALUE).trim()
      if (EhGalleryFavoriteParser.isRemoteSlot(value)) {
        const titleHtml: string = m[2] !== undefined ? m[2] : ''
        const title: string = HtmlSelectorUtils.htmlUnescape(
          titleHtml.replace(/<[^>]*>/g, '').trim(),
        )
        if (title.length > 0) {
          info.favcats.push(new Favcat(value, title, 0))
          if (/\bchecked\b/.test(input)) {
            info.selectFavcat = value
          }
        }
      }
      m = EhGalleryFavoriteParser.RE_FAV_ROW.exec(html)
    }
    info.favcats = info.favcats.slice(0, 10)
    info.favNote = HtmlSelectorUtils.htmlUnescape(
      HtmlSelectorUtils.group1(html, EhGalleryFavoriteParser.RE_TEXTAREA).trim(),
    )
    return info
  }

  private static isRemoteSlot(favId: string): boolean {
    const n: number = Number.parseInt(favId, 10)
    return `${n}` === favId && n >= 0 && n <= 9
  }
}
